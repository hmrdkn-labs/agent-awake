import Foundation
import IOKit.ps

public protocol SleepSettingRunner {
    func setSleepDisabled(_ on: Bool) -> Bool
    /// Sleep the Mac now (`pmset sleepnow`); idle-sleep assertions don't block it.
    func sleepNow() -> Bool
}

/// Runs `/usr/bin/pmset` with fixed arguments. Needs root.
public struct PMSetRunner: SleepSettingRunner {
    public init() {}
    public func setSleepDisabled(_ on: Bool) -> Bool { run(["disablesleep", on ? "1" : "0"]) }
    public func sleepNow() -> Bool { run(["sleepnow"]) }

    private func run(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}

public struct PowerState {
    public var onBattery: Bool
    public var batteryPercent: Int?
    public var thermalHot: Bool
    public init(onBattery: Bool, batteryPercent: Int?, thermalHot: Bool) {
        self.onBattery = onBattery; self.batteryPercent = batteryPercent; self.thermalHot = thermalHot
    }
}

public protocol PowerStateReading {
    func read() -> PowerState
}

public struct SystemPowerState: PowerStateReading {
    public init() {}
    public func read() -> PowerState {
        var onBattery = false
        var pct: Int?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for src in list {
                guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any] else { continue }
                if (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue { onBattery = true }
                if let c = d[kIOPSCurrentCapacityKey] as? Int { pct = c }
            }
        }
        let t = ProcessInfo.processInfo.thermalState
        return PowerState(onBattery: onBattery, batteryPercent: pct, thermalHot: t == .serious || t == .critical)
    }
}

/// Root-side policy. Never trusts the client: leases are clamped and must be renewed, and the
/// setting is rolled back on lease expiry, low battery, heat, helper restart (via marker file) or release.
public final class SleepGuard {
    public static let maxLease: Double = 120
    public static let batteryFloor = 10

    private let runner: SleepSettingRunner
    private let power: PowerStateReading
    private let lid: ClamshellReading
    private let after: (Double, @escaping () -> Void) -> Void
    private let now: () -> Double
    private let markerPath: String
    private let lock = NSLock()
    private var disabled = false
    private var deadline: Double = 0
    /// Called when a closed-lid Mac was put to sleep after the setting was restored.
    public var onSleep: (() -> Void)?

    public init(runner: SleepSettingRunner = PMSetRunner(),
                power: PowerStateReading = SystemPowerState(),
                lid: ClamshellReading = Clamshell(),
                markerPath: String = Identity.markerPath,
                after: @escaping (Double, @escaping () -> Void) -> Void = { d, f in
                    DispatchQueue.global().asyncAfter(deadline: .now() + d, execute: f)
                },
                now: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.runner = runner; self.power = power; self.lid = lid; self.markerPath = markerPath
        self.after = after; self.now = now
    }

    public var isHolding: Bool { lock.lock(); defer { lock.unlock() }; return disabled }

    /// Call once at helper start: undo a SleepDisabled this helper left behind (crash, kill, reboot).
    public func recoverFromCrash() {
        lock.lock(); defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: markerPath), runner.setSleepDisabled(false) {
            try? FileManager.default.removeItem(atPath: markerPath)
        }
    }

    public func acquire(lease: Double) -> (ok: Bool, reason: String?) {
        lock.lock(); defer { lock.unlock() }
        if let why = unsafeReason() { turnOff(); return (false, why) }
        if !disabled {
            // Marker first: a crash between the two steps is still recovered.
            guard FileManager.default.createFile(atPath: markerPath, contents: nil) else { return (false, "cannot write marker") }
            guard runner.setSleepDisabled(true) else {
                try? FileManager.default.removeItem(atPath: markerPath)
                return (false, "pmset failed")
            }
            disabled = true
        }
        deadline = now() + min(max(lease, 1), SleepGuard.maxLease)
        return (true, nil)
    }

    public func release() {
        lock.lock(); defer { lock.unlock() }
        turnOff()
    }

    /// Periodic check. Returns the reason if it just turned the setting off for safety.
    @discardableResult
    public func tick() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard disabled else { return nil }
        if let why = unsafeReason() { turnOff(); return why }
        if now() >= deadline { turnOff() }
        return nil
    }

    private func unsafeReason() -> String? {
        let s = power.read()
        if s.thermalHot { return "Mac is running hot" }
        if s.onBattery, let p = s.batteryPercent, p <= SleepGuard.batteryFloor { return "battery at \(p)%" }
        return nil
    }

    /// Retried by `tick` if pmset fails, since `disabled` stays true.
    private func turnOff() {
        deadline = 0
        guard disabled else { return }
        if runner.setSleepDisabled(false) {
            disabled = false
            try? FileManager.default.removeItem(atPath: markerPath)
            after(SleepGuard.settle) { [weak self] in self?.sleepIfLidClosed() }
        }
    }

    /// How long macOS gets to re-evaluate the lid after the setting changes.
    public static let settle: Double = 2

    /// macOS decides to sleep when the lid closes. If that happened while the setting was on (agents working
    /// in a bag), restoring it later doesn't sleep the Mac: it stays awake, hot and draining, until the lid
    /// opens. So once the setting is off, a closed lid that would normally sleep the Mac does it now.
    /// Not with an external display in use: then macOS keeps a closed Mac awake itself.
    private func sleepIfLidClosed() {
        lock.lock()
        let stillOff = !disabled
        lock.unlock()
        guard stillOff, lid.isClosed() == true, lid.closedCausesSleep() == true else { return }
        if runner.sleepNow() { onSleep?() }
    }
}
