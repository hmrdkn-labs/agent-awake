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
    var running = true
    var titles = true
    var fetches = 0
    func make() -> (HerdrWatcher, Engine, FakePower, FakeNotifier) {
        let p = FakePower(), n = FakeNotifier()
        let e = Engine(notifier: n, power: p)
        let w = HerdrWatcher(engine: e, quietPolls: 2, idleEvery: 4, isRunning: { self.running }, taskTitles: { self.titles },
                             fetch: { self.fetches += 1; return self.json() })
        return (w, e, p, n)
    }

    func testHerdrQuittingEndsSessionsWithoutSpawning() {
        let (w, _, p, n) = make()
        w.poll(); running = false; let before = fetches; w.poll(); w.poll()
        XCTAssertEqual(fetches, before, "no herdr process: don't spawn the CLI")
        XCTAssertFalse(p.held); XCTAssertTrue(n.sent.isEmpty, "a closed pane ends silently")
    }

    func testIdlePollsBackOffAndWorkingPollsEveryTick() {
        let (w, _, _, _) = make()
        status = "idle"
        for _ in 0..<8 { w.tick() }
        XCTAssertEqual(fetches, 2, "nothing working: every 4th tick")
        status = "working"; w.tick(); w.tick(); w.tick(); w.tick()   // 9th tick polls and starts tracking
        XCTAssertEqual(fetches, 6, "tracking: every tick")
    }

    func testWorkingHoldsAwakeAndFinishPingsAfterQuietPolls() {
        let (w, _, p, n) = make()
        w.poll(); XCTAssertTrue(p.held)
        status = "idle"
        w.poll(); XCTAssertTrue(p.held, "one idle poll is a flicker, not a finish"); XCTAssertTrue(n.sent.isEmpty)
        w.poll(); XCTAssertFalse(p.held)
        XCTAssertEqual(n.sent.count, 1)
        XCTAssertTrue(n.sent[0].1.contains("Finished after"))
        XCTAssertEqual(n.sent[0].0, "Fix login bug is done", "ping names the task, not the pane id")
    }

    func testRetitledPaneUpdatesLabelAndUntitledFallsBackToFolder() {
        let (w, e, _, _) = make()
        w.poll(); title = "π ⁝ Write tests"; w.poll()
        XCTAssertEqual(e.store.list().first?.title, "Write tests")
        XCTAssertEqual(HerdrCLI.label(title: "", cwd: "/src/shop", agent: "omp"), "oh-my-pi · shop")
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
        XCTAssertTrue(n.sent[0].0.hasSuffix("needs you")); XCTAssertEqual(n.alerts[0].level, .urgent)
    }

    func testClosedPaneEndsSession() {
        let (w, _, p, n) = make()
        w.poll(); present = false; w.poll(); w.poll()
        XCTAssertFalse(p.held); XCTAssertTrue(n.sent.isEmpty, "a closed pane ends silently")
    }

    func testUnreachableHerdrChangesNothing() {
        let p = FakePower(), n = FakeNotifier()
        let e = Engine(notifier: n, power: p)
        var up = true
        let w = HerdrWatcher(engine: e, quietPolls: 1, isRunning: { true }, taskTitles: { true }, fetch: { up ? self.json() : nil })
        w.poll(); up = false; w.poll(); w.poll()
        XCTAssertTrue(p.held); XCTAssertTrue(n.sent.isEmpty)
    }
}

extension HerdrWatcherTests {
    func testPaneTitlesStayPrivateUnlessTaskTitlesAreOn() {
        titles = false
        let (w, e, _, _) = make()
        w.poll()
        XCTAssertEqual(e.store.list().first?.title, "oh-my-pi · shop", "agent and folder only")
    }
}
