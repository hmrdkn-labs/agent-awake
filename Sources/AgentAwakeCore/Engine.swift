import Foundation

public func formatDuration(_ s: Double) -> String {
    let t = Int(s.rounded())
    if t < 60 { return "\(t)s" }
    if t < 3600 { return "\(t / 60)m" }
    return "\(t / 3600)h\((t % 3600) / 60)m"
}

/// Owns sessions, the power assertion and notifications.
/// Mac is held awake iff at least one session is alive; otherwise it sleeps as macOS normally would.
public final class Engine {
    public static let manualName = "manual"
    public let store = SessionStore()
    private let power: PowerHolding
    private let notifier: Notifier
    private let now: () -> Double
    private var timer: DispatchSourceTimer?
    /// Called (on an arbitrary thread) whenever the session list changes.
    public var onChange: (([SessionInfo]) -> Void)?

    public init(notifier: Notifier, power: PowerHolding = PowerAssertion(),
                now: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.notifier = notifier; self.power = power; self.now = now
    }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    public func tick() {
        let expired = store.expire(now: now())
        guard !expired.isEmpty else { return }
        changed()
        let idle = store.list().isEmpty
        for s in expired where s.name != Engine.manualName {
            notifier.send(title: "Agent Awake: \(s.title) timed out",
                          body: "No heartbeat for \(formatDuration(s.timeout)). Check on it." + (idle ? " No sessions left; Mac can sleep." : ""))
        }
    }

    /// Manual "Keep awake": nil = off, 0 = until turned off, otherwise for that many seconds.
    public func setManual(duration: Double?) {
        if let d = duration {
            store.begin(Engine.manualName, label: "Keep awake", timeout: d, now: now())
        } else {
            _ = store.done(Engine.manualName)
        }
        changed()
    }

    private func changed() {
        let list = store.list()
        power.setHeld(!list.isEmpty)
        onChange?(list)
    }

    public func handle(_ r: Request) -> Response {
        switch r.cmd {
        case "list":
            return Response(ok: true, sessions: store.list())
        case "begin":
            guard let n = r.name, !n.isEmpty else { return Response(ok: false, error: "name required") }
            store.begin(n, label: r.label, timeout: r.timeout ?? SessionStore.defaultTimeout, now: now())
            changed()
            return Response(ok: true, sessions: store.list())
        case "beat":
            guard let n = r.name, let relabeled = store.beat(n, label: r.label, now: now()) else {
                return Response(ok: false, error: "no such session")
            }
            if relabeled { changed() }
            return Response(ok: true)
        case "done":
            guard let n = r.name, let s = store.done(n) else { return Response(ok: false, error: "no such session") }
            changed()
            let idle = store.list().isEmpty
            notifier.send(title: "Agent Awake: \(s.title) done",
                          body: (r.message ?? "Finished after \(formatDuration(now() - s.startedAt)).") + (idle ? " No sessions left; Mac can sleep." : ""))
            return Response(ok: true, sessions: store.list())
        default:
            return Response(ok: false, error: "unknown cmd \(r.cmd)")
        }
    }
}
