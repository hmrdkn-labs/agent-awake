import Foundation

/// App-side policy: while lid-closed mode is wanted, keep renewing a short lease with the helper.
/// If the app dies or stops renewing, the helper restores normal sleep on its own.
public final class LidGuard {
    public static let lease: Double = 90
    public static let renewEvery: Double = 30

    private let controller: SleepControlling
    private let notifier: Notifier
    private let lock = NSLock()
    private var wanted = false
    private var denied = false
    private var timer: DispatchSourceTimer?

    public init(controller: SleepControlling, notifier: Notifier) {
        self.controller = controller; self.notifier = notifier
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
        controller.acquire(lease: LidGuard.lease) { [weak self] ok, reason in
            guard let self = self else { return }
            self.lock.lock()
            if ok { self.denied = false; self.lock.unlock(); return }
            let first = !self.denied
            self.denied = true
            self.lock.unlock()
            if first {
                self.notifier.send(title: "Agent Awake: lid-closed mode off",
                                   body: "The Mac will sleep when the lid closes: \(reason ?? "helper unavailable").")
            }
        }
    }
}
