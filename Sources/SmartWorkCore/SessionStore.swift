import Foundation

/// Live work sessions. Time is passed in so expiry is deterministic.
public final class SessionStore {
    public static let defaultTimeout: Double = 30 * 60
    private let lock = NSLock()
    private var sessions: [String: SessionInfo] = [:]

    public init() {}

    public func begin(_ name: String, timeout: Double, now: Double) {
        lock.lock(); defer { lock.unlock() }
        sessions[name] = SessionInfo(name: name, startedAt: now, lastBeat: now, timeout: max(0, timeout))
    }

    @discardableResult
    public func beat(_ name: String, now: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard sessions[name] != nil else { return false }
        sessions[name]!.lastBeat = now
        return true
    }

    public func done(_ name: String) -> SessionInfo? {
        lock.lock(); defer { lock.unlock() }
        return sessions.removeValue(forKey: name)
    }

    /// Removes and returns sessions silent for at least their timeout.
    public func expire(now: Double) -> [SessionInfo] {
        lock.lock(); defer { lock.unlock() }
        let dead = sessions.values.filter { $0.timeout > 0 && now - $0.lastBeat >= $0.timeout }
        for s in dead { sessions[s.name] = nil }
        return dead.sorted { $0.startedAt < $1.startedAt }
    }

    public func list() -> [SessionInfo] {
        lock.lock(); defer { lock.unlock() }
        return sessions.values.sorted { ($0.startedAt, $0.name) < ($1.startedAt, $1.name) }
    }
}
