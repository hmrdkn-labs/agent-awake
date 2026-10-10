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

    func testConnectedAgentsAreLeftToTheirHooks() {
        let (w, _, p, _) = make()
        w.skipAgents = ["omp"]
        holders = [omp]
        w.poll()
        XCTAssertFalse(p.held)
    }
}
