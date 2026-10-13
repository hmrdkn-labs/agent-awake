import XCTest
@testable import AgentAwakeCore

final class FakeSensor: StrainSensing {
    var value = Strain.normal
    func read() -> Strain { value }
}

final class FakeRelief: ReliefActing {
    var children: [AgentChild] = []
    var throttled: Set<Int32> = [], paused: Set<Int32> = [], killed: [Int32] = []
    func agentChildren(of agents: [String: Int32]) -> [AgentChild] {
        children.filter { agents[$0.session] != nil }.sorted { $0.footprint > $1.footprint }
    }
    func throttle(_ pid: Int32, _ on: Bool) -> Bool { if on { throttled.insert(pid) } else { throttled.remove(pid) }; return true }
    func pause(_ pid: Int32) -> Bool { paused.insert(pid); return true }
    func resume(_ pid: Int32) -> Bool { paused.remove(pid); return true }
    func terminate(_ pid: Int32) -> Bool { killed.append(pid); return true }
}

final class StrainGuardTests: XCTestCase {
    var t = 1000.0
    var cfg = Config()
    // Our own pid stands in for live processes, so ProcessList.isAlive keeps them tracked.
    let me = getpid()

    func make() -> (StrainGuard, Engine, FakeSensor, FakeRelief, FakeNotifier) {
        let n = FakeNotifier(), s = FakeSensor(), r = FakeRelief()
        let e = Engine(notifier: FakeNotifier(), power: FakePower(), probe: FakeProbe(), now: { self.t })
        let g = StrainGuard(engine: e, sensor: s, relief: r, notifier: n, config: { self.cfg }, now: { self.t })
        e.strainReport = g.report
        XCTAssertTrue(e.handle(Request(cmd: "begin", name: "claude:1", label: "Fix login", pid: 1)).ok)
        return (g, e, s, r, n)
    }

    func holding(_ e: Engine) -> Bool? { e.handle(Request(cmd: "strain")).holding }

    func testHoldsWhileHotAndReleasesWithOnePingEachWay() {
        let (g, e, s, _, n) = make()
        g.tick(); XCTAssertEqual(holding(e), false)
        s.value = Strain(thermal: .elevated)
        g.tick(); g.tick()
        XCTAssertEqual(holding(e), true)
        XCTAssertEqual(e.handle(Request(cmd: "strain")).strain?.reason, "Mac is running hot")
        s.value = .normal
        g.tick()
        XCTAssertEqual(holding(e), false)
        XCTAssertEqual(n.alerts.map(\.title), ["Mac is running hot: holding agents", "Back to normal"])
    }

    func testHoldCanBeTurnedOff() {
        let (g, e, s, _, _) = make()
        cfg.holdWhenStrained = false
        s.value = Strain(memory: .critical)
        g.tick()
        XCTAssertEqual(holding(e), false)
    }

    func testHeatThrottlesAgentWorkUntilItCools() {
        let (g, _, s, r, _) = make()
        r.children = [AgentChild(pid: me, name: "swift-build", footprint: 1 << 30, session: "claude:1")]
        s.value = Strain(thermal: .elevated)
        g.tick()
        XCTAssertEqual(r.throttled, [me])
        s.value = .normal
        g.tick()
        XCTAssertTrue(r.throttled.isEmpty)
    }

    func testCriticalMemoryPausesLargestThenResumesAfterACalmMinute() {
        let (g, _, s, r, n) = make()
        r.children = [AgentChild(pid: 9999, name: "small", footprint: 10 << 20, session: "claude:1"),
                      AgentChild(pid: me, name: "node", footprint: 3 << 30, session: "claude:1")]
        s.value = Strain(memory: .critical)
        g.tick()
        XCTAssertEqual(r.paused, [me])
        XCTAssertTrue(n.alerts.contains { $0.title == "Memory almost full: paused node" && $0.body.contains("Fix login") })
        t += 5; g.tick()
        XCTAssertEqual(r.paused, [me], "cooldown, and the small one isn't worth pausing")
        s.value = Strain(memory: .elevated)
        g.tick()
        t += StrainGuard.memoryCalm - 1; g.tick()
        XCTAssertEqual(r.paused, [me], "not before memory stayed below critical for a minute")
        t += 1; g.tick()
        XCTAssertTrue(r.paused.isEmpty, "memory warn can last for hours: don't wait for normal")
        XCTAssertEqual(n.alerts.last?.title, "Memory recovered"); XCTAssertEqual(n.alerts.last?.body, "Continued node.")
    }

    func testMemoryWarningAloneNeverHolds() {
        let (g, e, s, r, _) = make()
        r.children = [AgentChild(pid: me, name: "node", footprint: 3 << 30, session: "claude:1")]
        s.value = Strain(memory: .elevated)
        g.tick()
        XCTAssertEqual(holding(e), false)
        XCTAssertTrue(r.paused.isEmpty && r.throttled.isEmpty)
        XCTAssertEqual(e.handle(Request(cmd: "strain")).strain?.reason, "Memory is running low")
    }

    func testOverheatingPausesAllAgentWorkUntilItCools() {
        let (g, e, s, r, n) = make()
        r.children = [AgentChild(pid: me, name: "cargo", footprint: 2 << 30, session: "claude:1"),
                      AgentChild(pid: getppid(), name: "sh", footprint: 1 << 20, session: "claude:1")]
        s.value = Strain(thermal: .critical, batteryTemp: 51)
        g.tick()
        XCTAssertEqual(r.paused, [me, getppid()], "everything agents started, however small")
        XCTAssertEqual(holding(e), true)
        XCTAssertTrue(n.alerts.contains { $0.title == "Mac is overheating (battery 51 °C): paused agent work" })
        s.value = Strain(thermal: .elevated, batteryTemp: 47)
        g.tick()
        XCTAssertEqual(r.paused.count, 2, "still warm: stays paused")
        s.value = .normal
        g.tick()
        XCTAssertTrue(r.paused.isEmpty)
        XCTAssertTrue(n.alerts.last!.body.contains("Continued cargo, sh"))
    }

    func testKillModeEndsLargestOnlyAfterCooldown() {
        let (g, _, s, r, _) = make()
        cfg.memoryRelief = .kill
        r.children = [AgentChild(pid: 4242, name: "jest", footprint: 2 << 30, session: "claude:1")]
        s.value = Strain(memory: .critical)
        g.tick(); t += 10; g.tick()
        XCTAssertEqual(r.killed, [4242])
        t += StrainGuard.reliefCooldown; g.tick()
        XCTAssertEqual(r.killed, [4242, 4242], "still critical after the cooldown: acts again")
        XCTAssertTrue(r.paused.isEmpty)
    }

    func testReliefNoneOnlyHolds() {
        let (g, e, s, r, _) = make()
        cfg.memoryRelief = MemoryReliefNone
        r.children = [AgentChild(pid: me, name: "node", footprint: 3 << 30, session: "claude:1")]
        s.value = Strain(memory: .critical)
        g.tick()
        XCTAssertTrue(r.paused.isEmpty && r.killed.isEmpty)
        XCTAssertEqual(holding(e), true)
    }

    func testQuitContinuesEverything() {
        let (g, _, s, r, _) = make()
        r.children = [AgentChild(pid: me, name: "node", footprint: 3 << 30, session: "claude:1")]
        s.value = Strain(thermal: .critical, memory: .critical)
        g.tick()
        XCTAssertFalse(r.paused.isEmpty); XCTAssertFalse(r.throttled.isEmpty)
        g.releaseAll()
        XCTAssertTrue(r.paused.isEmpty); XCTAssertTrue(r.throttled.isEmpty)
    }
}

private let MemoryReliefNone = Config.MemoryRelief.none
