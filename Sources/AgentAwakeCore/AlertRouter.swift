import Foundation

/// Sends each alert to the phone or the Mac. `pingWhen`: always → phone, never → Mac, away → phone only
/// while the user is away. With no phone channel set up, alerts always go to the Mac.
/// An alert identical (title and body) to one sent in the last 30 s is dropped.
public final class AlertRouter: Notifier {
    public static let coalesceWindow: Double = 30

    public enum Route: Equatable { case local, phone }

    private let config: () -> Config
    private let presence: PresenceSource
    private let local: Notifier
    private let phone: (Config) -> [Notifier]
    private let now: () -> Double
    private let lock = NSLock()
    private var recent: [Key: Double] = [:]

    private struct Key: Hashable { let title: String, body: String }

    public init(config: @escaping () -> Config,
                presence: PresenceSource = SystemPresence(),
                local: Notifier,
                phone: @escaping (Config) -> [Notifier] = { Channels.phone($0).map { $0.notifier } },
                now: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.config = config; self.presence = presence; self.local = local; self.phone = phone; self.now = now
    }

    public func send(_ alert: Alert) {
        guard admit(alert) else { return }
        let cfg = config()
        let phones = phone(cfg)
        switch route(cfg, phoneConfigured: !phones.isEmpty) {
        case .local: local.send(alert)
        case .phone: phones.forEach { $0.send(alert) }
        }
    }

    /// Where an alert would go right now.
    public func route(for config: Config) -> Route { route(config, phoneConfigured: !phone(config).isEmpty) }

    private func route(_ cfg: Config, phoneConfigured: Bool) -> Route {
        guard phoneConfigured else { return .local }
        switch cfg.effectivePingWhen {
        case .always: return .phone
        case .never: return .local
        case .away: return presence.isAway(after: cfg.effectiveAwayAfter) ? .phone : .local
        }
    }

    private func admit(_ alert: Alert) -> Bool {
        let t = now(), key = Key(title: alert.title, body: alert.body)
        lock.lock(); defer { lock.unlock() }
        recent = recent.filter { t - $0.value < AlertRouter.coalesceWindow }
        if recent[key] != nil { return false }
        recent[key] = t
        return true
    }
}
