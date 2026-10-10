import Foundation

/// One line of JSON per request, one line per response, over a Unix socket.
public struct Request: Codable {
    public var cmd: String            // begin | beat | done | list
    public var name: String?
    public var timeout: Double?       // seconds of allowed silence; nil/0 = never expires
    public init(cmd: String, name: String? = nil, timeout: Double? = nil) {
        self.cmd = cmd; self.name = name; self.timeout = timeout
    }
}

public struct SessionInfo: Codable, Equatable {
    public var name: String
    public var startedAt: Double
    public var lastBeat: Double
    public var timeout: Double        // 0 = never expires
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
    public static var dir: String { NSHomeDirectory() + "/.smart-work" }
    public static var socket: String { dir + "/daemon.sock" }
    public static var config: String { dir + "/config.json" }
}
