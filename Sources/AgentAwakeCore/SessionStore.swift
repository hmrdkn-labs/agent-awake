import Foundation

/// Live work sessions. Time is passed in so expiry is deterministic.
public final class SessionStore {
    public static let defaultTimeout: Double = 30 * 60
    private let lock = NSLock()
    private var sessions: [String: SessionInfo] = [:]

    public init() {}

    public func begin(_ name: String, label: String? = nil, agent: String? = nil, pid: Int32? = nil,
                      timeout: Double, now: Double) {
        lock.lock(); defer { lock.unlock() }
        sessions[name] = SessionInfo(name: name, label: label, agent: agent, pid: pid, state: .working,
                                     startedAt: now, lastBeat: now, timeout: max(0, timeout))
    }

    /// Applies `f` to an existing session and stamps `lastBeat`. Returns nil if there is no such session,
    /// otherwise whether anything the UI shows changed.
    @discardableResult
    public func update(_ name: String, now: Double, _ f: (inout SessionInfo) -> Void = { _ in }) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        guard var s = sessions[name] else { return nil }
        let before = s
        f(&s)
        s.lastBeat = now
        sessions[name] = s
        return s.label != before.label || s.state != before.state || s.agent != before.agent
    }

    public func get(_ name: String) -> SessionInfo? {
        lock.lock(); defer { lock.unlock() }
        return sessions[name]
    }

    public func done(_ name: String) -> SessionInfo? {
        lock.lock(); defer { lock.unlock() }
        return sessions.removeValue(forKey: name)
    }

    /// Sessions silent for at least their timeout (not removed; the engine decides).
    public func overdue(now: Double) -> [SessionInfo] {
        lock.lock(); defer { lock.unlock() }
        return sessions.values.filter { $0.timeout > 0 && now - $0.lastBeat >= $0.timeout }
            .sorted { $0.startedAt < $1.startedAt }
    }

    public func list() -> [SessionInfo] {
        lock.lock(); defer { lock.unlock() }
        return sessions.values.sorted { ($0.startedAt, $0.name) < ($1.startedAt, $1.name) }
    }
}
