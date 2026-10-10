import XCTest
@testable import AgentAwakeCore

final class HerdrWatcherTests: XCTestCase {
    var status = "working"
    var present = true
    var title = "π > Fix login bug"
    func json() -> Data {
        let agents = present ? "[{\"agent\":\"omp\",\"pane_id\":\"w1:p1\",\"agent_status\":\"\(status)\",\"cwd\":\"/src/shop\",\"terminal_title_stripped\":\"\(title)\"}]" : "[]"
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
        XCTAssertEqual(n.sent[0].0, "Agent Awake: Fix login bug done", "ping names the task, not the pane id")
    }

    func testRetitledPaneUpdatesLabelAndUntitledFallsBackToFolder() {
        let (w, e, _, _) = make()
        w.poll(); title = "π ⁝ Write tests"; w.poll()
        XCTAssertEqual(e.store.list().first?.title, "Write tests")
        XCTAssertEqual(HerdrCLI.label(title: "", cwd: "/src/shop", agent: "omp"), "omp · shop")
        XCTAssertEqual(HerdrCLI.label(title: "make -j8 > build.log", cwd: nil, agent: "omp"), "make -j8 > build.log")
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
