import XCTest
@testable import AgentAwakeCore

final class AssertionWatcherTests: XCTestCase {
    var holders: [AssertionWatcher.Holder] = []
    let omp = AssertionWatcher.Holder(pid: 501, process: "omp", name: "omp agent session", type: "PreventUserIdleSystemSleep")

    func make() -> (AssertionWatcher, Engine, FakePower, FakeNotifier) {
        let p = FakePower(), n = FakeNotifier()
        let e = Engine(notifier: n, power: p, probe: FakeProbe())
        let w = AssertionWatcher(engine: e, quietPolls: 2, fetch: { self.holders }, cwd: { _ in "/src/shop" })
        return (w, e, p, n)
    }

    func testAllowlistedAssertionIsATurnThatFinishesWhenReleased() {
        let (w, e, p, n) = make()
        holders = [omp]
        w.poll()
        XCTAssertTrue(p.held)
        XCTAssertEqual(e.store.list().first?.title, "oh-my-pi · shop")
        holders = []
        w.poll(); XCTAssertTrue(p.held, "one missed poll is a flicker")
        w.poll(); XCTAssertFalse(p.held)
        XCTAssertEqual(n.sent.first?.0, "oh-my-pi · shop is done")
    }

    func testUnknownAssertionsNeverHoldTheMac() {
        let (w, _, p, _) = make()
        holders = [.init(pid: 9, process: "Claude", name: "Electron", type: "PreventUserIdleSystemSleep")]
        w.poll()
        XCTAssertFalse(p.held)
    }

    func testProcessesReportingThroughHooksAreLeftToThemSilently() {
        let (w, e, _, n) = make()
        holders = [omp]
        w.poll()
        XCTAssertEqual(e.store.list().map(\.name), ["omp:pid501"])
        // The same omp process starts reporting through its hooks: our copy ends without a "done" ping.
        XCTAssertTrue(e.handle(Request(cmd: "begin", name: "omp:ses_1", agent: "omp", pid: 501)).ok)
        w.poll()
        XCTAssertEqual(e.store.list().map(\.name), ["omp:ses_1"])
        XCTAssertTrue(n.sent.isEmpty)
    }

    func testOlderProcessesOfAConnectedAgentAreStillFollowed() {
        let (w, e, p, _) = make()
        XCTAssertTrue(e.handle(Request(cmd: "begin", name: "omp:ses_new", agent: "omp", pid: 777)).ok)
        holders = [omp]   // pid 501 started before Connect: it has no hooks loaded
        w.poll()
        XCTAssertEqual(Set(e.store.list().map(\.name)), ["omp:ses_new", "omp:pid501"])
        XCTAssertTrue(p.held)
    }
}

final class AssertionWatcherHerdrTests: XCTestCase {
    func testAgentsInsideHerdrPanesAreLeftToHerdrOnlyWhileItWatches() {
        let p = FakePower()
        let e = Engine(notifier: FakeNotifier(), power: p, probe: FakeProbe())
        let holder = AssertionWatcher.Holder(pid: 7, process: "omp", name: "omp agent session", type: "PreventUserIdleSystemSleep")
        let w = AssertionWatcher(engine: e, fetch: { [holder] }, cwd: { _ in nil }, env: { _ in ["HERDR_PANE_ID": "wE:p1"] })
        w.herdrFollowsPanes = true
        w.poll()
        XCTAssertFalse(p.held, "herdr reports this one")
        w.herdrFollowsPanes = false
        w.poll()
        XCTAssertTrue(p.held, "herdr off: the assertion is the only signal")
    }
}
