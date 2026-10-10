import Foundation

public protocol Notifier {
    func send(title: String, body: String)
}

public struct Config: Codable {
    public var ntfyServer: String?
    public var ntfyTopic: String?

    public static func load() -> Config {
        var c = (try? JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: Paths.config)))) ?? Config()
        if let t = ProcessInfo.processInfo.environment["SMART_WORK_NTFY_TOPIC"] { c.ntfyTopic = t }
        if let s = ProcessInfo.processInfo.environment["SMART_WORK_NTFY_SERVER"] { c.ntfyServer = s }
        return c
    }
    public init(ntfyServer: String? = nil, ntfyTopic: String? = nil) {
        self.ntfyServer = ntfyServer; self.ntfyTopic = ntfyTopic
    }
}

/// POSTs to ntfy.sh (or a self-hosted server). No topic configured = log only.
public struct NtfyNotifier: Notifier {
    let config: Config
    public init(config: Config) { self.config = config }

    public func send(title: String, body: String) {
        guard let topic = config.ntfyTopic, !topic.isEmpty else {
            FileHandle.standardError.write(Data("[smart-work] \(title): \(body) (no ntfy topic configured)\n".utf8))
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
                FileHandle.standardError.write(Data("[smart-work] ntfy failed: \(err.localizedDescription)\n".utf8))
            } else if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
                FileHandle.standardError.write(Data("[smart-work] ntfy HTTP \(h.statusCode)\n".utf8))
            }
        }.resume()
    }
}
