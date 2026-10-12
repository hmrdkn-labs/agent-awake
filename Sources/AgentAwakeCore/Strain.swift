import Foundation

/// How hard the Mac is struggling. Ordered: a higher level is worse.
public enum StrainLevel: Int, Codable, Comparable, CaseIterable {
    case normal      // thermal nominal/fair, memory pressure normal
    case elevated    // thermal serious, or memory pressure warning: hold new agent work
    case critical    // thermal critical, or memory pressure critical: also act on agent-started processes

    public static func < (a: StrainLevel, b: StrainLevel) -> Bool { a.rawValue < b.rawValue }
}

/// One reading of the Mac's thermal and memory state.
public struct Strain: Codable, Equatable {
    public var thermal: StrainLevel
    public var memory: StrainLevel
    /// Bytes of swap in use, when known (shown to the user, not used for the level).
    public var swapUsed: UInt64?

    public init(thermal: StrainLevel = .normal, memory: StrainLevel = .normal, swapUsed: UInt64? = nil) {
        self.thermal = thermal; self.memory = memory; self.swapUsed = swapUsed
    }

    public static let normal = Strain()
    public var level: StrainLevel { max(thermal, memory) }

    /// Short human reason, nil when normal. Memory first: it's the one that ends in killed apps.
    public var reason: String? {
        switch (memory, thermal) {
        case (.critical, _): return "Memory is almost full"
        case (_, .critical): return "Mac is overheating"
        case (.elevated, _): return "Memory is running low"
        case (_, .elevated): return "Mac is running hot"
        default: return nil
        }
    }
}

/// Reads the current strain. Live implementation: `LiveStrainSensor`.
public protocol StrainSensing: AnyObject {
    func read() -> Strain
}

/// A process an agent started (a build, tests, a dev server): a descendant of an agent's process,
/// never the agent itself.
public struct AgentChild: Equatable {
    public var pid: Int32
    public var name: String
    /// Physical footprint in bytes (what Activity Monitor calls Memory).
    public var footprint: UInt64
    /// The session whose agent started it.
    public var session: String

    public init(pid: Int32, name: String, footprint: UInt64, session: String) {
        self.pid = pid; self.name = name; self.footprint = footprint; self.session = session
    }
}

/// What Agent Awake may do to agent-started processes. Live implementation: `LiveRelief`.
public protocol ReliefActing: AnyObject {
    /// Descendants of the given agent processes (session name -> agent pid), largest footprint first.
    func agentChildren(of agents: [String: Int32]) -> [AgentChild]
    /// Background priority (efficiency cores, throttled I/O) on or off. Returns false if not allowed.
    @discardableResult func throttle(_ pid: Int32, _ on: Bool) -> Bool
    @discardableResult func pause(_ pid: Int32) -> Bool     // SIGSTOP
    @discardableResult func resume(_ pid: Int32) -> Bool    // SIGCONT
    /// SIGTERM, then SIGKILL if it's still alive after a short grace. Returns false if it couldn't be signalled.
    @discardableResult func terminate(_ pid: Int32) -> Bool
}
