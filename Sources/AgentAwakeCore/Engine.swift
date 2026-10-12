import Foundation

public func formatDuration(_ s: Double) -> String {
    let t = Int(s.rounded())
    if t < 60 { return "\(t)s" }
    if t < 3600 { return "\(t / 60)m" }
    return "\(t / 3600)h\((t % 3600) / 60)m"
}

/// Owns sessions, the power assertion and alerts.
/// Mac is held awake iff at least one session is alive; otherwise it sleeps as macOS normally would.
public final class Engine {
    public static let manualName = "manual"
    /// How long a session that needs the user keeps the Mac awake, so they can answer remotely.
    public static let waitGrace: Double = 15 * 60
    /// How long past its timeout a quiet session may run on because its agent is still running a process.
    public static let busyCap: Double = 4 * 3600

    public let store = SessionStore()
    private let power: PowerHolding
    private let notifier: Notifier
    private let probe: ProcessProbe
    private let now: () -> Double
    private var timer: DispatchSourceTimer?
    /// Called (on an arbitrary thread) whenever the session list changes.
    public var onChange: (([SessionInfo]) -> Void)?
    /// Current strain and whether agents should hold; set by the app to its `StrainGuard`.
    public var strainReport: () -> (Strain, Bool) = { (.normal, false) }

    public init(notifier: Notifier, power: PowerHolding = PowerAssertion(), probe: ProcessProbe = LiveProcessProbe(),
                now: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.notifier = notifier; self.power = power; self.probe = probe; self.now = now
    }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now() + 5, repeating: 5, leeway: .seconds(2))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// Ends sessions that went quiet past their timeout. An agent whose process is gone ends silently;
    /// one still running a process it started (a long build) keeps going, up to `busyCap`.
    public func tick() {
        let t = now()
        var ended = false
        // An agent that exited (closed terminal, crash, kill) sends no Stop: end its session right away, silently.
        for s in store.list() where s.pid.map({ !probe.isAlive($0) }) == true {
            _ = store.done(s.name); ended = true
        }
        for s in store.overdue(now: t) {
            if s.name != Engine.manualName, s.state == .working, let pid = s.pid,
               t - s.lastBeat < s.timeout + Engine.busyCap && probe.isBusy(pid, since: s.lastBeat) { continue }
            _ = store.done(s.name); ended = true
            if s.name == Engine.manualName || s.state == .waiting { continue }   // already pinged / user's own timer
            notifier.send(Alert(title: "\(s.title) went quiet",
                                body: "No sign of progress for \(formatDuration(t - s.lastBeat)). It may be stuck."
                                    + sleepNote(),
                                level: .urgent, session: s.name))
        }
        if ended { changed() }
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
        power.setHeld(system: !list.isEmpty, display: list.contains { $0.name == Engine.manualName })
        onChange?(list)
    }

    private func sleepNote() -> String {
        store.list().isEmpty ? " Nothing else is running, so your Mac can sleep." : ""
    }

    public func handle(_ r: Request) -> Response {
        switch r.cmd {
        case "strain":
            let (s, holding) = strainReport()
            return Response(ok: true, strain: s, holding: holding)
        case "list":
            return Response(ok: true, sessions: store.list())
        case "begin":
            guard let n = r.name, !n.isEmpty else { return Response(ok: false, error: "name required") }
            store.begin(n, label: r.label ?? r.fallbackLabel, agent: r.agent, pid: r.pid,
                        timeout: r.timeout ?? SessionStore.defaultTimeout, now: now())
            changed()
            return Response(ok: true, sessions: store.list())
        case "beat":
            guard let n = r.name, !n.isEmpty else { return Response(ok: false, error: "name required") }
            let updated = store.update(n, now: now()) { s in
                if let l = r.label ?? (s.label == nil ? r.fallbackLabel : nil) { s.label = l }
                if let a = r.agent { s.agent = a }
                if let p = r.pid { s.pid = p }
                if s.state == .waiting {   // the user answered: back to work with the normal timeout
                    s.state = .working
                    s.timeout = r.timeout ?? SessionStore.defaultTimeout
                }
            }
            if let changedUI = updated {
                if changedUI { changed() }
                return Response(ok: true)
            }
            // A beat that carries its timeout recreates the session, so work survives an app restart.
            guard let t = r.timeout else { return Response(ok: false, error: "no such session") }
            store.begin(n, label: r.label ?? r.fallbackLabel, agent: r.agent, pid: r.pid, timeout: t, now: now())
            changed()
            return Response(ok: true)
        case "wait":
            guard let n = r.name, !n.isEmpty else { return Response(ok: false, error: "name required") }
            let wasWaiting = store.get(n)?.state == .waiting
            if store.get(n) == nil {
                store.begin(n, label: r.label ?? r.fallbackLabel, agent: r.agent, pid: r.pid, timeout: Engine.waitGrace, now: now())
            }
            store.update(n, now: now()) { s in
                if let l = r.label ?? (s.label == nil ? r.fallbackLabel : nil) { s.label = l }
                s.state = .waiting
                s.timeout = Engine.waitGrace
            }
            changed()
            // Agents often report one prompt twice (e.g. a permission request, then a notification about it).
            if !wasWaiting, let s = store.get(n) {
                notifier.send(Alert(title: "\(s.title) needs you",
                                    body: (r.message ?? "It is waiting for your answer.")
                                        + " Your Mac stays awake \(formatDuration(Engine.waitGrace)) for you to reply.",
                                    level: .urgent, session: n))
            }
            return Response(ok: true)
        case "done":
            guard let n = r.name, let s = store.done(n) else { return Response(ok: false, error: "no such session") }
            changed()
            switch r.kind ?? .finished {
            case .ended:
                break
            case .failed:
                notifier.send(Alert(title: "\(s.title) stopped with an error",
                                    body: (r.message ?? "Check on it.") + sleepNote(), level: .urgent, session: n))
            case .finished:
                notifier.send(Alert(title: "\(s.title) is done",
                                    body: (r.message ?? "Finished after \(formatDuration(now() - s.startedAt)).")
                                        + sleepNote(),
                                    level: .info, session: n))
            }
            return Response(ok: true, sessions: store.list())
        default:
            return Response(ok: false, error: "unknown cmd \(r.cmd)")
        }
    }
}
