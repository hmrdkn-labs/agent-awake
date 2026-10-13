import XCTest
@testable import AgentAwakeCore

final class LidSafetyTests: XCTestCase {
    func battery(_ pct: Int) -> PowerState { PowerState(onBattery: true, batteryPercent: pct, thermalHot: false) }

    func testHotBatteryEndsLidModeAtOnce() {
        let s = LidSafety()
        XCTAssertNil(s.check(strain: Strain(batteryTemp: 44), power: battery(90), now: 0))
        XCTAssertEqual(s.check(strain: Strain(thermal: .elevated, batteryTemp: 45.4), power: battery(90), now: 30),
                       "the battery is at 45 °C")
    }

    func testFastDrainEndsLidModeOnlyAfterEnoughSamples() {
        let s = LidSafety()
        // 33% an hour, like the evening this was written for: 100% -> 59% in 75 minutes.
        var reason: String?
        for i in 0...12 {   // every 30 s for 6 minutes
            reason = s.check(strain: .normal, power: battery(100 - i * 33 / 120), now: Double(i * 30))
            if i * 30 < Int(LidSafety.minSpan) { XCTAssertNil(reason, "too early to judge at \(i * 30) s") }
        }
        XCTAssertEqual(reason, "the battery is draining 30% an hour")
    }

    func testNormalDrainAndChargingKeepLidMode() {
        let s = LidSafety()
        for i in 0...40 {   // 10% an hour for 20 minutes
            XCTAssertNil(s.check(strain: .normal, power: battery(90 - i / 18), now: Double(i * 30)))
        }
        _ = s.check(strain: .normal, power: battery(50), now: 2000)
        XCTAssertNil(s.check(strain: .normal, power: PowerState(onBattery: false, batteryPercent: 49, thermalHot: false), now: 2030))
        XCTAssertNil(s.check(strain: .normal, power: battery(40), now: 2400), "plugging in starts the measurement over")
    }

    func testLidGuardReleasesAndPingsOnceWhenUnsafe() {
        let c = FakeController(), n = FakeNotifier()
        var why: String? = nil
        let g = LidGuard(controller: c, notifier: n) { why }
        g.update(wanted: true)
        XCTAssertEqual(c.acquires, 1)
        why = "the battery is at 47 °C"
        g.tick(); g.tick()
        XCTAssertEqual(c.acquires, 1); XCTAssertEqual(c.releases, 2)
        XCTAssertEqual(n.alerts.map(\.body), ["The Mac will sleep when the lid closes: the battery is at 47 °C."])
        why = nil
        g.tick()
        XCTAssertEqual(c.acquires, 2, "cooled down with the lid open: back on")
    }
}

final class StrainTemperatureTests: XCTestCase {
    func testBatteryTemperatureRaisesTheHeatLevelBeforeMacOSDoes() {
        func sensor(_ battery: Double?) -> Strain {
            LiveStrainSensor(readers: .init(thermalPressure: { 0 }, thermalState: { .nominal }, memoryPressure: { 2 },
                                            swapUsed: { nil }, temperatures: { .init(battery: battery, chip: 80) })).read()
        }
        XCTAssertEqual(sensor(nil).thermal, .normal)
        XCTAssertEqual(sensor(44.9).thermal, .normal)
        XCTAssertEqual(sensor(45).thermal, .elevated)
        XCTAssertEqual(sensor(50).thermal, .critical)
        XCTAssertTrue(sensor(46).holdsAgents)
        XCTAssertFalse(sensor(30).holdsAgents, "memory warning alone")
        XCTAssertEqual(sensor(46).chipTemp, 80)
    }

    func testLogWritesHeaderOnceAndRotates() throws {
        let dir = NSTemporaryDirectory() + "aa-log-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let log = StrainLog(path: dir + "/strain.log")
        let p = PowerState(onBattery: true, batteryPercent: 61, thermalHot: false)
        log.append(strain: Strain(batteryTemp: 46.2), holding: true, agents: 3, power: p, lidClosed: true)
        log.append(strain: .normal, holding: false, agents: 0, power: p, lidClosed: nil)
        let lines = try String(contentsOfFile: dir + "/strain.log", encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("time\tbattery_c"))
        XCTAssertTrue(lines[1].hasSuffix("\t46.2\t\tnormal\tnormal\t\ttrue\t3\t61\ttrue\ttrue") || lines[1].contains("\t46.2\t\tnormal\tnormal\t\ttrue\t3\t61\ttrue\ttrue"))
        try Data(count: StrainLog.maxBytes).write(to: URL(fileURLWithPath: dir + "/strain.log"))
        log.append(strain: .normal, holding: false, agents: 0, power: p, lidClosed: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/strain.log.1"))
        XCTAssertEqual(try String(contentsOfFile: dir + "/strain.log", encoding: .utf8).split(separator: "\n").count, 2)
    }
}
