import XCTest
@testable import AgentAwakeCore

final class FakePower: PowerHolding { var held = false; func setHeld(_ h: Bool) { held = h } }
final class FakeNotifier: Notifier {
    var sent: [(String, String)] = []
    var alerts: [Alert] = []
    func send(_ a: Alert) { sent.append((a.title, a.body)); alerts.append(a) }
}
final class FakeProbe: ProcessProbe {
    var alive = true, busy = false
    func isAlive(_ pid: Int32) -> Bool { alive }
    func isBusy(_ pid: Int32, since: Double) -> Bool { busy }
}

final class EngineTests: XCTestCase {
    var t = 1000.0
    let probe = FakeProbe()
    func make() -> (Engine, FakePower, FakeNotifier) {
        let p = FakePower(), n = FakeNotifier()
        return (Engine(notifier: n, power: p, probe: probe, now: { self.t }), p, n)
    }

    func testNeedsYouPingsOnceHoldsForGraceThenReleasesSilently() {
        let (e, p, n) = make()
        _ = e.handle(Request(cmd: "begin", name: "a", label: "Fix bug", timeout: 60))
        _ = e.handle(Request(cmd: "wait", name: "a", message: "Allow Bash?"))
        _ = e.handle(Request(cmd: "wait", name: "a", message: "Allow Bash?"))
        XCTAssertEqual(n.alerts.count, 1, "duplicate needs-you reports ping once")
        XCTAssertEqual(n.alerts[0].level, .urgent); XCTAssertEqual(n.alerts[0].title, "Fix bug needs you")
        t += Engine.waitGrace - 1; e.tick()
        XCTAssertTrue(p.held, "the user gets the grace period to answer remotely")
        t += 1; e.tick()
        XCTAssertFalse(p.held); XCTAssertEqual(n.alerts.count, 1, "no second ping when the grace ends")
    }

    func testAnsweringReturnsToWorkWithItsTimeout() {
        let (e, _, _) = make()
        _ = e.handle(Request(cmd: "wait", name: "a"))
        _ = e.handle(Request(cmd: "beat", name: "a", timeout: 60))
        XCTAssertEqual(e.store.get("a")?.state, .working)
        XCTAssertEqual(e.store.get("a")?.timeout, 60)
    }

    func testDoneKinds() {
        let (e, _, n) = make()
        for k in [DoneKind.ended, .failed, .finished] {
            _ = e.handle(Request(cmd: "begin", name: k.rawValue))
            _ = e.handle(Request(cmd: "done", name: k.rawValue, kind: k))
        }
        XCTAssertEqual(n.alerts.map(\.level), [.urgent, .info], "ended is silent, failed is urgent")
    }

    func testQuietAgentWhoseProcessExitedEndsSilently() {
        let (e, p, n) = make()
        _ = e.handle(Request(cmd: "begin", name: "a", pid: 42, timeout: 60))
        probe.alive = false
        t += 60; e.tick()
        XCTAssertFalse(p.held); XCTAssertTrue(n.sent.isEmpty)
    }

    func testQuietAgentRunningALongToolStaysAwakeUntilCap() {
        let (e, p, n) = make()
        _ = e.handle(Request(cmd: "begin", name: "a", pid: 42, timeout: 60))
        probe.busy = true
        t += 3600; e.tick()
        XCTAssertTrue(p.held, "a 1h build is not stuck"); XCTAssertTrue(n.sent.isEmpty)
        t += Engine.busyCap; e.tick()
        XCTAssertFalse(p.held); XCTAssertTrue(n.sent[0].0.contains("went quiet"))
    }

    func testHeldWhileAnySessionAliveAndReleasedWhenLastDone() {
        let (e, p, n) = make()
        _ = e.handle(Request(cmd: "begin", name: "a"))
        _ = e.handle(Request(cmd: "begin", name: "b"))
        XCTAssertTrue(p.held)
        _ = e.handle(Request(cmd: "done", name: "a"))
        XCTAssertTrue(p.held)
        XCTAssertFalse(n.sent[0].1.contains("can sleep"))
        _ = e.handle(Request(cmd: "done", name: "b"))
        XCTAssertFalse(p.held)
        XCTAssertTrue(n.sent[1].1.contains("can sleep"))
    }

    func testSilentSessionTimesOutAndHeartbeatExtends() {
        let (e, p, n) = make()
        _ = e.handle(Request(cmd: "begin", name: "a", timeout: 60))
        t += 50; XCTAssertTrue(e.handle(Request(cmd: "beat", name: "a")).ok)
        t += 50; e.tick()
        XCTAssertTrue(p.held); XCTAssertTrue(n.sent.isEmpty)
        t += 10; e.tick()
        XCTAssertFalse(p.held)
        XCTAssertEqual(n.sent.count, 1)
        XCTAssertEqual(n.alerts[0].level, .urgent); XCTAssertTrue(n.sent[0].0.contains("went quiet"))
    }

    func testManualUntilOffNeverExpiresAndIsSilent() {
        let (e, p, n) = make()
        e.setManual(duration: 0)
        t += 100_000; e.tick()
        XCTAssertTrue(p.held)
        e.setManual(duration: nil)
        XCTAssertFalse(p.held); XCTAssertTrue(n.sent.isEmpty)
    }

    func testTimedManualEndsByItselfWithoutPing() {
        let (e, p, n) = make()
        e.setManual(duration: 3600)
        t += 3599; e.tick()
        XCTAssertTrue(p.held)
        t += 1; e.tick()
        XCTAssertFalse(p.held); XCTAssertTrue(n.sent.isEmpty)
    }

    func testUnknownSessionErrors() {
        let (e, _, _) = make()
        XCTAssertFalse(e.handle(Request(cmd: "beat", name: "x")).ok)
        XCTAssertFalse(e.handle(Request(cmd: "done", name: "x")).ok)
    }

    func testBeatWithTimeoutRecreatesSessionLostInRestart() {
        let (e, p, _) = make()
        XCTAssertTrue(e.handle(Request(cmd: "beat", name: "job", timeout: 60)).ok)
        XCTAssertTrue(p.held)
        t += 59; e.tick()
        XCTAssertTrue(p.held, "recreated session keeps its timeout")
    }
}
