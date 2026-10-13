import Foundation

/// App-side policy: while lid-closed mode is wanted, keep renewing a short lease with the helper.
/// If the app dies or stops renewing, the helper restores normal sleep on its own.
public final class LidGuard {
    public static let lease: Double = 90
    public static let renewEvery: Double = 30

    private let controller: SleepControlling
    private let notifier: Notifier
    /// Checked before every renewal; a reason releases lid-closed mode (see `LidSafety`).
    private let safety: () -> String?
    private let lock = NSLock()
    private var wanted = false
    private var denied = false
    private var timer: DispatchSourceTimer?

    public init(controller: SleepControlling, notifier: Notifier, safety: @escaping () -> String? = { nil }) {
        self.controller = controller; self.notifier = notifier; self.safety = safety
    }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now() + LidGuard.renewEvery, repeating: LidGuard.renewEvery)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    public func update(wanted w: Bool) {
        lock.lock()
        let changed = (w != wanted)
        wanted = w
        if changed && w { denied = false }
        lock.unlock()
        guard changed else { return }
        if w { renew() } else { controller.release() }
    }

    public func tick() {
        lock.lock(); let w = wanted; lock.unlock()
        if w { renew() }
    }

    private func renew() {
        if let why = safety() {
            controller.release()
            refused(why)
            return
        }
        controller.acquire(lease: LidGuard.lease) { [weak self] ok, reason in
            guard let self = self else { return }
            if ok { self.lock.lock(); self.denied = false; self.lock.unlock(); return }
            self.refused(reason ?? "helper unavailable")
        }
    }

    /// One ping per refusal streak.
    private func refused(_ reason: String) {
        lock.lock()
        let first = !denied
        denied = true
        lock.unlock()
        if first {
            notifier.send(Alert(title: "Lid-closed mode is off",
                                body: "The Mac will sleep when the lid closes: \(reason).", level: .urgent))
        }
    }
}

/// When lid-closed mode must give up even though agents still work: the Mac is hot (the battery sensor,
/// which tracks the case, or macOS's own level), or on battery it drains faster than `maxDrainPerHour`.
/// Both are what a MacBook working in a bag looks like. Once released with the lid closed, the Mac sleeps.
public final class LidSafety {
    public static let maxDrainPerHour: Double = 20
    /// Drain is measured over at least this long, from samples no older than `window`.
    public static let minSpan: Double = 6 * 60
    public static let window: Double = 15 * 60

    private let lock = NSLock()
    private var samples: [(t: Double, percent: Int)] = []

    public init() {}

    /// The reason to turn lid-closed mode off, or nil if it's fine to keep it.
    public func check(strain: Strain, power: PowerState, now: Double) -> String? {
        lock.lock(); defer { lock.unlock() }
        if strain.thermal >= .elevated {
            return strain.batteryTemp.map { "the battery is at \(Int($0.rounded())) °C" } ?? "the Mac is running hot"
        }
        guard power.onBattery, let p = power.batteryPercent else { samples = []; return nil }
        samples.append((now, p))
        samples.removeAll { now - $0.t > Self.window }
        guard let first = samples.first, now - first.t >= Self.minSpan else { return nil }
        let perHour = Double(first.percent - p) / (now - first.t) * 3600
        return perHour >= Self.maxDrainPerHour ? "the battery is draining \(Int(perHour.rounded()))% an hour" : nil
    }
}
