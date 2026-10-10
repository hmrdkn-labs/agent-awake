import Foundation

/// One line of JSON per request, one line per response, over a Unix socket.
///
/// Commands:
/// - `begin`  start (or restart) a session.
/// - `beat`   heartbeat; with `timeout` it recreates a session the app lost (restart), and it moves a
///            waiting session back to working.
/// - `wait`   the agent needs the user (permission, question). Pings once, keeps the Mac awake for
///            `Engine.waitGrace` so the user can answer remotely, then lets it sleep. Creates the session if needed.
/// - `done`   finish; `kind` decides the ping.
/// - `list`, `show` (app only: open the setup window).
public struct Request: Codable {
    public var cmd: String
    public var name: String?
    public var label: String?         // human title for the menu and pings; defaults to name
    public var agent: String?         // integration id ("claude", "codex", …) for display and dedupe
    public var pid: Int32?            // the agent's process; lets the app tell "busy in a long tool" from "gone"
    public var timeout: Double?       // seconds of allowed silence; nil/0 = never expires
    public var kind: DoneKind?        // for `done`
    public var message: String?       // detail for the ping
    public init(cmd: String, name: String? = nil, label: String? = nil, agent: String? = nil, pid: Int32? = nil,
                timeout: Double? = nil, kind: DoneKind? = nil, message: String? = nil) {
        self.cmd = cmd; self.name = name; self.label = label; self.agent = agent; self.pid = pid
        self.timeout = timeout; self.kind = kind; self.message = message
    }
}

public enum DoneKind: String, Codable {
    case finished      // turn complete: normal ping
    case failed        // stopped on an error: urgent ping
    case ended         // session closed: no ping
}

public enum SessionState: String, Codable {
    case working, waiting
}

public struct SessionInfo: Codable, Equatable {
    public var name: String
    public var label: String?
    public var agent: String?
    public var pid: Int32?
    public var state: SessionState
    public var startedAt: Double
    public var lastBeat: Double
    public var timeout: Double        // 0 = never expires
    public var title: String { label ?? name }
    /// When the session expires if it stays silent; nil = never.
    public var expiresAt: Double? { timeout > 0 ? lastBeat + timeout : nil }
}

public struct Response: Codable {
    public var ok: Bool
    public var error: String?
    public var sessions: [SessionInfo]?
    public init(ok: Bool, error: String? = nil, sessions: [SessionInfo]? = nil) {
        self.ok = ok; self.error = error; self.sessions = sessions
    }
}

public enum Paths {
    public static var dir: String { NSHomeDirectory() + "/.agent-awake" }
    public static var socket: String { dir + "/daemon.sock" }
    public static var config: String { dir + "/config.json" }
}
