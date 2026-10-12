import XCTest
import Darwin
@testable import AgentAwakeCore

/// Real throwaway processes: the point is proving libproc and signals behave as LiveRelief assumes.
final class ReliefTests: XCTestCase {
    private var spawned: [Process] = []
    private let relief = LiveRelief(grace: 0.5)

    override func tearDown() {
        for p in spawned where p.isRunning {
            for pid in descendants(of: p.processIdentifier) + [p.processIdentifier] { kill(pid, SIGKILL) }
            p.waitUntilExit()
        }
        spawned = []
    }

    private func spawn(_ exe: String, _ args: [String]) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        spawned.append(p)
        return p
    }

    private func descendants(of pid: pid_t) -> [pid_t] {
        ProcessList.children(of: pid).flatMap { [$0] + descendants(of: $0) }
    }

    private func eventually(_ timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(20_000)
        }
        return condition()
    }

    /// A child holding ~96 MB: perl ships with macOS; python3 may be the Xcode shim.
    private var hog: (exe: String, script: String, name: String)? {
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") {
            return ("/usr/bin/perl", "-e '$x = \"a\" x (96 << 20); sleep 30'", "perl")
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") {
            return ("/usr/bin/python3", "-c 'b = bytearray(96 << 20); import time; time.sleep(30)'", "python3")
        }
        return nil
    }

    func testFindsDescendantsLargestFirstAndExcludesTheAgent() throws {
        let hog = try XCTUnwrap(hog, "no perl or python3 to allocate memory")
        // agent (sh) -> [ sh -> sleep ] and [ hog ]: two levels deep.
        let agent = try spawn("/bin/sh", ["-c", "/bin/sh -c '/bin/sleep 30; :' & \(hog.exe) \(hog.script) & wait"])
        let pid = agent.processIdentifier
        var kids: [AgentChild] = []
        XCTAssertTrue(eventually {
            kids = relief.agentChildren(of: ["s1": pid])
            return kids.contains { $0.name == "sleep" } && (kids.first { $0.name.hasPrefix(hog.name) }?.footprint ?? 0) > 64 << 20
        }, "children: \(kids)")
        XCTAssertFalse(kids.contains { $0.pid == pid }, "the agent itself is never a candidate")
        XCTAssertTrue(kids.first?.name.hasPrefix(hog.name) ?? false, "largest first: \(kids)")
        XCTAssertEqual(kids.map(\.footprint), kids.map(\.footprint).sorted(by: >))
        XCTAssertTrue(kids.allSatisfy { $0.footprint > 0 && $0.session == "s1" && $0.pid != getpid() })
        XCTAssertGreaterThanOrEqual(kids.count, 3, "inner sh, sleep, hog: \(kids)")
    }

    func testANestedAgentsChildrenBelongToItsOwnSession() throws {
        let outer = try spawn("/bin/sh", ["-c", "/bin/sh -c '/bin/sleep 30; :' & wait"])
        var inner: pid_t = 0
        XCTAssertTrue(eventually {
            inner = ProcessList.children(of: outer.processIdentifier).first ?? 0
            return inner != 0 && !ProcessList.children(of: inner).isEmpty
        })
        let kids = relief.agentChildren(of: ["outer": outer.processIdentifier, "inner": inner])
        XCTAssertFalse(kids.contains { $0.pid == inner || $0.pid == outer.processIdentifier })
        XCTAssertEqual(kids.map(\.session), ["inner"], "\(kids)")
    }

    func testPauseResumeThrottleAndTerminate() throws {
        let p = try spawn("/bin/sleep", ["30"])
        let pid = p.processIdentifier
        XCTAssertTrue(relief.pause(pid))
        XCTAssertTrue(eventually { ProcessList.isStopped(pid) }, "SIGSTOP should stop it")
        XCTAssertTrue(relief.resume(pid))
        XCTAssertTrue(eventually { !ProcessList.isStopped(pid) }, "SIGCONT should continue it")
        XCTAssertTrue(relief.throttle(pid, true))
        XCTAssertTrue(relief.throttle(pid, false))
        XCTAssertTrue(relief.pause(pid))
        XCTAssertTrue(relief.terminate(pid), "terminate must also wake a paused process")
        XCTAssertTrue(eventually { !p.isRunning })
        XCTAssertEqual(p.terminationReason, .uncaughtSignal)
        XCTAssertEqual(p.terminationStatus, SIGTERM)
        XCTAssertFalse(relief.terminate(pid), "gone: nothing to signal")
    }

    func testTerminateEscalatesToKillWhenTermIsIgnored() throws {
        // SIG_IGN survives exec, so this sleep ignores SIGTERM.
        let p = try spawn("/bin/sh", ["-c", "trap '' TERM; exec /bin/sleep 30"])
        XCTAssertTrue(eventually { ProcessList.name(of: p.processIdentifier) == "sleep" })
        let started = Date()
        XCTAssertTrue(relief.terminate(p.processIdentifier), "returns at once, kill happens later")
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.3)
        XCTAssertTrue(eventually(5) { !p.isRunning })
        XCTAssertEqual(p.terminationStatus, SIGKILL)
    }

    func testRefusesToActOnUnsafeTargets() {
        XCTAssertFalse(relief.throttle(0, true), "0 means the caller itself")
        XCTAssertFalse(relief.throttle(-1, true))
        XCTAssertFalse(relief.throttle(getpid(), true))
        XCTAssertFalse(relief.pause(1), "launchd")
        XCTAssertFalse(relief.terminate(1))
        XCTAssertEqual(relief.agentChildren(of: ["gone": 999_999]), [])
    }
}

final class StrainSensorTests: XCTestCase {
    private func sensor(thermal: UInt64?, state: ProcessInfo.ThermalState = .nominal, memory: Int32?) -> LiveStrainSensor {
        LiveStrainSensor(readers: .init(thermalPressure: { thermal }, thermalState: { state },
                                        memoryPressure: { memory }, swapUsed: { 42 }))
    }

    func testMapsThermalPressureAndMemoryPressure() {
        XCTAssertEqual(sensor(thermal: 0, memory: 1).read(), Strain(thermal: .normal, memory: .normal, swapUsed: 42))
        XCTAssertEqual(sensor(thermal: 1, memory: 2).read(), Strain(thermal: .normal, memory: .elevated, swapUsed: 42))
        XCTAssertEqual(sensor(thermal: 2, memory: 4).read(), Strain(thermal: .elevated, memory: .critical, swapUsed: 42))
        XCTAssertEqual(sensor(thermal: 3, memory: 1).read().thermal, .critical)
        XCTAssertEqual(sensor(thermal: 4, memory: 1).read().thermal, .critical)
    }

    func testFallsBackToThermalStateAndTreatsUnknownMemoryAsNormal() {
        XCTAssertEqual(sensor(thermal: nil, state: .fair, memory: nil).read().level, .normal)
        XCTAssertEqual(sensor(thermal: nil, state: .serious, memory: nil).read().thermal, .elevated)
        XCTAssertEqual(sensor(thermal: nil, state: .critical, memory: nil).read().thermal, .critical)
    }

    func testLiveReadOnThisMac() {
        let s = LiveStrainSensor()
        let start = Date()
        let strain = s.read()
        print("LiveStrainSensor: thermal=\(strain.thermal) memory=\(strain.memory) swapUsed=\(strain.swapUsed.map(String.init) ?? "nil") in \(Date().timeIntervalSince(start) * 1000) ms")
        XCTAssertNotNil(strain.swapUsed, "vm.swapusage is readable without root")
    }
}
