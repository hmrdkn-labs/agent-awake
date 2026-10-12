import Foundation

/// `~/.agent-awake/config.json` (0600). Holds channel credentials, so it is never world-readable.
/// Every field is optional so older files keep loading.
public struct Config: Codable, Equatable {
    // ntfy (default channel; a random topic is made on first run)
    public var ntfyServer: String?
    public var ntfyTopic: String?
    // Other phone channels; a channel is on when its credentials are set.
    public var bark: Bark?
    public var pushover: Pushover?
    public var telegram: Telegram?
    public var discordWebhook: String?
    public var slackWebhook: String?

    /// When to send phone pings. Mac notifications are used whenever a phone ping isn't.
    public var pingWhen: PingWhen?
    /// Minutes without keyboard/mouse input after which the user counts as away.
    public var awayAfterMinutes: Double?
    /// Show the agent's prompt as the session title (in the menu and in pings). Off: project folder only,
    /// because prompts can hold private text and pings pass through third-party servers.
    public var taskTitles: Bool?
    /// Agents hold new tool calls while the Mac is hot or low on memory (default on).
    public var holdWhenStrained: Bool?
    /// What to do with processes agents started (builds, tests) when memory is almost full.
    public var memoryRelief: MemoryRelief?

    /// `pause`: stop the largest agent-started process until memory recovers, then continue it.
    /// `kill`: end it (the agent sees its command fail). `none`: only hold and ping.
    public enum MemoryRelief: String, Codable, CaseIterable { case none, pause, kill }

    public enum PingWhen: String, Codable, CaseIterable { case away, always, never }
    public struct Bark: Codable, Equatable {
        public var key: String
        public var server: String?          // default https://api.day.app
        public init(key: String, server: String? = nil) { self.key = key; self.server = server }
    }
    public struct Pushover: Codable, Equatable {
        public var token: String
        public var user: String
        public init(token: String, user: String) { self.token = token; self.user = user }
    }
    public struct Telegram: Codable, Equatable {
        public var token: String
        public var chatId: String
        public init(token: String, chatId: String) { self.token = token; self.chatId = chatId }
    }

    public init(ntfyServer: String? = nil, ntfyTopic: String? = nil) {
        self.ntfyServer = ntfyServer; self.ntfyTopic = ntfyTopic
    }

    public var effectivePingWhen: PingWhen { pingWhen ?? .away }
    public var effectiveAwayAfter: Double { (awayAfterMinutes ?? 5) * 60 }
    public var effectiveTaskTitles: Bool { taskTitles ?? false }
    public var effectiveHoldWhenStrained: Bool { holdWhenStrained ?? true }
    public var effectiveMemoryRelief: MemoryRelief { memoryRelief ?? .pause }

    public static func load() -> Config {
        var c = readFile()
        if let t = ProcessInfo.processInfo.environment["AGENT_AWAKE_NTFY_TOPIC"] { c.ntfyTopic = t }
        if let s = ProcessInfo.processInfo.environment["AGENT_AWAKE_NTFY_SERVER"] { c.ntfyServer = s }
        return c
    }

    static func readFile() -> Config {
        (try? JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: Paths.config)))) ?? Config()
    }

    /// First run: invent an unguessable topic and persist it, so phone setup is just "subscribe to this".
    public static func loadEnsuringTopic() -> Config {
        var file = readFile()
        if (file.ntfyTopic ?? "").isEmpty, ProcessInfo.processInfo.environment["AGENT_AWAKE_NTFY_TOPIC"] == nil {
            let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
            file.ntfyTopic = "agent-awake-" + String((0..<16).map { _ in chars.randomElement()! })
            try? file.save()
        }
        return load()
    }

    public func save() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: Paths.dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: URL(fileURLWithPath: Paths.config), options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.config)
    }
}
