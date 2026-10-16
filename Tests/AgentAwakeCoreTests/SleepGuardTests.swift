import XCTest
@testable import AgentAwakeCore

final class FakeRunner: SleepSettingRunner {
    var calls: [Bool] = []
    var failOff = false
    var slept = 0
    func setSleepDisabled(_ on: Bool) -> Bool {
        if !on && failOff { return false }
        calls.append(on); return true
    }
    func sleepNow() -> Bool { slept += 1; return true }
}
final class FakeLid: ClamshellReading {
    var closed: Bool? = false, causesSleep: Bool? = true
    func isClosed() -> Bool? { closed }
    func closedCausesSleep() -> Bool? { causesSleep }
}
final class FakePowerState: PowerStateReading {
    var s = PowerState(onBattery: false, batteryPercent: 80, thermalHot: false)
    func read() -> PowerState { s }
}
final class FakeController: SleepControlling {
    var acquires = 0, releases = 0
    var result: (Bool, String?) = (true, nil)
    func acquire(lease: Double, completion: @escaping (Bool, String?) -> Void) { acquires += 1; completion(result.0, result.1) }
    func release() { releases += 1 }
}

final class SleepGuardTests: XCTestCase {
    var t = 1000.0
    let marker = NSTemporaryDirectory() + "sw-marker-\(UUID().uuidString)"
    let lid = FakeLid()
    var later: [() -> Void] = []
    func make() -> (SleepGuard, FakeRunner, FakePowerState) {
        let r = FakeRunner(), p = FakePowerState()
        return (SleepGuard(runner: r, power: p, lid: lid, markerPath: marker, after: { _, f in self.later.append(f) },
                           now: { self.t }), r, p)
    }
    func settle() { let l = later; later = []; l.forEach { $0() } }

    func testReleaseWithLidClosedSleepsTheMac() {
        let (g, r, p) = make()
        XCTAssertTrue(g.acquire(lease: 60).ok)
        lid.closed = true
        p.s = PowerState(onBattery: true, batteryPercent: 9, thermalHot: false)
        g.tick(); settle()
        XCTAssertEqual(r.slept, 1, "macOS won't sleep on its own: the lid closed while the setting was on")
    }

    func testNoSleepWithLidOpenOrExternalDisplay() {
        let (g, r, _) = make()
        XCTAssertTrue(g.acquire(lease: 60).ok); g.release(); settle()
        lid.closed = true; lid.causesSleep = false   // closed with an external display: a desk setup
        XCTAssertTrue(g.acquire(lease: 60).ok); g.release(); settle()
        XCTAssertEqual(r.slept, 0)
    }

    func testReacquiredBeforeSettleDoesNotSleep() {
        let (g, r, _) = make()
        lid.closed = true
        XCTAssertTrue(g.acquire(lease: 60).ok); g.release()
        XCTAssertTrue(g.acquire(lease: 60).ok); settle()
        XCTAssertEqual(r.slept, 0)
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: marker) }

    func testLeaseExpiryRestoresSleepAndRenewalKeepsItOff() {
        let (g, r, _) = make()
        XCTAssertTrue(g.acquire(lease: 60).ok)
        t += 50; XCTAssertTrue(g.acquire(lease: 60).ok)
        XCTAssertEqual(r.calls, [true], "renewal must not re-run pmset")
        t += 50; g.tick(); XCTAssertTrue(g.isHolding)
        t += 20; g.tick(); XCTAssertFalse(g.isHolding)
        XCTAssertEqual(r.calls, [true, false])
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))
    }

    func testClientCannotRequestLongerThanMaxLease() {
        let (g, _, _) = make()
        XCTAssertTrue(g.acquire(lease: 1_000_000).ok)
        t += SleepGuard.maxLease + 1; g.tick()
        XCTAssertFalse(g.isHolding)
    }

    func testLowBatteryRefusesAndRollsBack() {
        let (g, r, p) = make()
        XCTAssertTrue(g.acquire(lease: 60).ok)
        p.s = PowerState(onBattery: true, batteryPercent: 10, thermalHot: false)
        XCTAssertEqual(g.tick(), "battery at 10%")
        XCTAssertFalse(g.isHolding)
        XCTAssertFalse(g.acquire(lease: 60).ok)
        XCTAssertEqual(r.calls, [true, false])
        p.s = PowerState(onBattery: false, batteryPercent: 5, thermalHot: false)  // on AC: fine
        XCTAssertTrue(g.acquire(lease: 60).ok)
    }

    func testHeatRefuses() {
        let (g, _, p) = make()
        p.s = PowerState(onBattery: false, batteryPercent: 90, thermalHot: true)
        XCTAssertFalse(g.acquire(lease: 60).ok)
        XCTAssertFalse(g.isHolding)
    }

    func testRestartUndoesWhatCrashedHelperLeftBehind() {
        let (g1, _, _) = make()
        XCTAssertTrue(g1.acquire(lease: 60).ok)           // "crash": g1 is abandoned, marker remains
        let (g2, r2, _) = make()
        g2.recoverFromCrash()
        XCTAssertEqual(r2.calls, [false])
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))
    }

    func testNoMarkerMeansUserOwnSettingIsLeftAlone() {
        let (g, r, _) = make()
        g.recoverFromCrash()
        XCTAssertTrue(r.calls.isEmpty)
    }

    func testFailedRestoreIsRetried() {
        let (g, r, _) = make()
        XCTAssertTrue(g.acquire(lease: 5).ok)
        r.failOff = true
        t += 10; g.tick(); XCTAssertTrue(g.isHolding)
        r.failOff = false
        g.tick(); XCTAssertFalse(g.isHolding)
    }
}

final class LidGuardTests: XCTestCase {
    func testRenewsWhileWantedAndReleasesOnce() {
        let c = FakeController(), n = FakeNotifier()
        let g = LidGuard(controller: c, notifier: n)
        g.update(wanted: true); g.tick(); g.tick()
        XCTAssertEqual(c.acquires, 3)
        g.update(wanted: false); g.update(wanted: false); g.tick()
        XCTAssertEqual(c.releases, 1); XCTAssertEqual(c.acquires, 3)
    }

    func testDenialPingsOncePerEpisodeAndRecovers() {
        let c = FakeController(), n = FakeNotifier()
        c.result = (false, "battery at 9%")
        let g = LidGuard(controller: c, notifier: n)
        g.update(wanted: true); g.tick(); g.tick()
        XCTAssertEqual(n.sent.count, 1)
        XCTAssertTrue(n.sent[0].1.contains("battery at 9%"))
        c.result = (true, nil); g.tick()
        c.result = (false, "battery at 9%"); g.tick()
        XCTAssertEqual(n.sent.count, 2)
    }
}
