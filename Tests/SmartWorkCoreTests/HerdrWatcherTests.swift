import XCTest
@testable import SmartWorkCore

final class HerdrWatcherTests: XCTestCase {
    var status = "working"
    var present = true
    func json() -> Data {
        let agents = present ? "[{\"agent\":\"omp\",\"pane_id\":\"w1:p1\",\"agent_status\":\"\(status)\"}]" : "[]"
        return Data("{\"result\":{\"agents\":\(agents)}}".utf8)
    }
    func make() -> (HerdrWatcher, Engine, FakePower, FakeNotifier) {
        let p = FakePower(), n = FakeNotifier()
        let e = Engine(notifier: n, power: p)
        return (HerdrWatcher(engine: e, quietPolls: 2, fetch: { self.json() }), e, p, n)
    }

    func testWorkingHoldsAwakeAndFinishPingsAfterQuietPolls() {
        let (w, _, p, n) = make()
        w.poll(); XCTAssertTrue(p.held)
        status = "idle"
        w.poll(); XCTAssertTrue(p.held, "one idle poll is a flicker, not a finish"); XCTAssertTrue(n.sent.isEmpty)
        w.poll(); XCTAssertFalse(p.held)
        XCTAssertEqual(n.sent.count, 1)
        XCTAssertTrue(n.sent[0].1.contains("Finished."))
    }

    func testFlickerBackToWorkingCancelsFinish() {
        let (w, _, p, n) = make()
        w.poll(); status = "idle"; w.poll(); status = "working"; w.poll(); status = "idle"; w.poll()
        XCTAssertTrue(p.held); XCTAssertTrue(n.sent.isEmpty)
    }

    func testBlockedSaysItNeedsYou() {
        let (w, _, _, n) = make()
        w.poll(); status = "blocked"; w.poll(); w.poll()
        XCTAssertTrue(n.sent[0].1.contains("needs you"))
    }

    func testClosedPaneEndsSession() {
        let (w, _, p, n) = make()
        w.poll(); present = false; w.poll(); w.poll()
        XCTAssertFalse(p.held); XCTAssertTrue(n.sent[0].1.contains("Pane closed"))
    }

    func testUnreachableHerdrChangesNothing() {
        let p = FakePower(), n = FakeNotifier()
        let e = Engine(notifier: n, power: p)
        var up = true
        let w = HerdrWatcher(engine: e, quietPolls: 1, fetch: { up ? self.json() : nil })
        w.poll(); up = false; w.poll(); w.poll()
        XCTAssertTrue(p.held); XCTAssertTrue(n.sent.isEmpty)
    }
}
