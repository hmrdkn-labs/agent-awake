import Foundation
import IOKit.ps

public protocol SleepSettingRunner {
    func setSleepDisabled(_ on: Bool) -> Bool
}

/// Runs `/usr/bin/pmset disablesleep 0|1` with fixed arguments. Needs root.
public struct PMSetRunner: SleepSettingRunner {
    public init() {}
    public func setSleepDisabled(_ on: Bool) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["disablesleep", on ? "1" : "0"]
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
    private let now: () -> Double
    private let markerPath: String
    private let lock = NSLock()
    private var disabled = false
    private var deadline: Double = 0

    public init(runner: SleepSettingRunner = PMSetRunner(),
                power: PowerStateReading = SystemPowerState(),
                markerPath: String = Identity.markerPath,
                now: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.runner = runner; self.power = power; self.markerPath = markerPath; self.now = now
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
        }
    }
}
