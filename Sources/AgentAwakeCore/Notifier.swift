import Foundation

public struct Config: Codable {
    public var ntfyServer: String?
    public var ntfyTopic: String?

    public static func load() -> Config {
        var c = readFile()
        if let t = ProcessInfo.processInfo.environment["AGENT_AWAKE_NTFY_TOPIC"] { c.ntfyTopic = t }
        if let s = ProcessInfo.processInfo.environment["AGENT_AWAKE_NTFY_SERVER"] { c.ntfyServer = s }
        return c
    }
    private static func readFile() -> Config {
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
        try FileManager.default.createDirectory(atPath: Paths.dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: URL(fileURLWithPath: Paths.config), options: .atomic)
    }

    public init(ntfyServer: String? = nil, ntfyTopic: String? = nil) {
        self.ntfyServer = ntfyServer; self.ntfyTopic = ntfyTopic
    }
}

/// POSTs to ntfy.sh (or a self-hosted server). No topic configured = log only.
public struct NtfyNotifier: Notifier {
    let config: Config
    public init(config: Config) { self.config = config }

    public func send(_ alert: Alert) {
        let title = alert.title, body = alert.body
        guard let topic = config.ntfyTopic, !topic.isEmpty else {
            FileHandle.standardError.write(Data("[agentawake] \(title): \(body) (no ntfy topic configured)\n".utf8))
            return
        }
        let server = (config.ntfyServer ?? "https://ntfy.sh").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(server)/\(topic)") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.httpBody = Data(body.utf8)
        // HTTP header values must be ASCII-safe; ntfy accepts the title via header.
        req.setValue(title.unicodeScalars.filter { $0.isASCII }.map(String.init).joined(), forHTTPHeaderField: "Title")
        URLSession.shared.dataTask(with: req) { _, resp, err in
            if let err = err {
                FileHandle.standardError.write(Data("[agentawake] ntfy failed: \(err.localizedDescription)\n".utf8))
            } else if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
                FileHandle.standardError.write(Data("[agentawake] ntfy HTTP \(h.statusCode)\n".utf8))
            }
        }.resume()
    }
}
