import XCTest
@testable import AgentAwakeCore

final class FakePower: PowerHolding { var held = false; func setHeld(_ h: Bool) { held = h } }
final class FakeNotifier: Notifier {
    var sent: [(String, String)] = []
    func send(title: String, body: String) { sent.append((title, body)) }
}

final class EngineTests: XCTestCase {
    var t = 1000.0
    func make() -> (Engine, FakePower, FakeNotifier) {
        let p = FakePower(), n = FakeNotifier()
        return (Engine(notifier: n, power: p, now: { self.t }), p, n)
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
        XCTAssertTrue(n.sent[0].0.contains("timed out"))
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
}
