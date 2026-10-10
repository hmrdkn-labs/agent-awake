import Foundation

/// A phone channel that talks HTTP. Building the request is pure (and tested); sending is fire-and-forget.
public protocol HTTPChannel: Notifier {
    /// Human name used in logs and settings ("ntfy", "Bark", …). Never contains credentials.
    var channelName: String { get }
    /// nil when the channel can't form a request (missing credentials or an unparseable server URL).
    func request(for alert: Alert) -> URLRequest?
}

extension HTTPChannel {
    public func send(_ alert: Alert) { send(alert, via: .shared) }

    /// `completion` gets the final HTTP status, or nil when nothing was delivered.
    public func send(_ alert: Alert, via sender: HTTPSender, completion: ((Int?) -> Void)? = nil) {
        guard let req = request(for: alert) else {
            sender.log("\(channelName): not configured, ping dropped")
            completion?(nil)
            return
        }
        sender.send(req, channel: channelName, completion: completion)
    }
}

/// Every phone channel the config turns on.
public enum Channels {
    public static func phone(_ c: Config) -> [(name: String, notifier: Notifier)] {
        let v = ChannelText.value
        var out: [(name: String, notifier: Notifier)] = []
        func add(_ n: HTTPChannel) { out.append((n.channelName, n)) }
        if let topic = v(c.ntfyTopic) { add(NtfyNotifier(server: v(c.ntfyServer), topic: topic)) }
        if let b = c.bark, let key = v(b.key) { add(BarkNotifier(key: key, server: v(b.server))) }
        if let p = c.pushover, let token = v(p.token), let user = v(p.user) {
            add(PushoverNotifier(token: token, user: user))
        }
        if let t = c.telegram, let token = v(t.token), let chat = v(t.chatId) {
            add(TelegramNotifier(token: token, chatId: chat))
        }
        if let url = v(c.discordWebhook) { add(DiscordNotifier(webhook: url)) }
        if let url = v(c.slackWebhook) { add(SlackNotifier(webhook: url)) }
        return out
    }
}

/// Sends channel requests without blocking the caller. Failures are logged by channel name, status and
/// error code only: request URLs and bodies carry credentials, so they never reach the log.
public final class HTTPSender {
    public static let shared = HTTPSender()

    let session: URLSession
    let maxRetryAfter: Double
    let log: (String) -> Void

    public init(maxRetryAfter: Double = 300,
                log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("[agentawake] \($0)\n".utf8)) }) {
        // Ephemeral: no on-disk cache or cookies for requests whose URLs hold credentials.
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        session = URLSession(configuration: cfg)
        self.maxRetryAfter = maxRetryAfter
        self.log = log
    }

    /// One retry on 429 after the server's Retry-After (capped); no retry on any other failure.
    public func send(_ req: URLRequest, channel: String, completion: ((Int?) -> Void)? = nil) {
        send(req, channel: channel, retried: false, completion: completion)
    }

    private func send(_ req: URLRequest, channel: String, retried: Bool, completion: ((Int?) -> Void)?) {
        session.dataTask(with: req) { [self] _, resp, err in
            if let err = err {
                log(HTTPSender.transportFailure(channel: channel, error: err))
                completion?(nil)
                return
            }
            let http = resp as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if status == 429, !retried {
                let wait = HTTPSender.retryAfter(http?.value(forHTTPHeaderField: "Retry-After")) ?? 5
                if wait <= maxRetryAfter {
                    log("\(channel): rate limited, retrying in \(Int(wait.rounded(.up)))s")
                    DispatchQueue.global().asyncAfter(deadline: .now() + wait) {
                        self.send(req, channel: channel, retried: true, completion: completion)
                    }
                    return
                }
            }
            if !(200..<300).contains(status) { log("\(channel): HTTP \(status), ping not delivered") }
            completion?(status)
        }.resume()
    }

    /// Domain and code only: URLError descriptions and userInfo can include the failing URL.
    static func transportFailure(channel: String, error: Error) -> String {
        let e = error as NSError
        return "\(channel): network error (\(e.domain) \(e.code)), ping not delivered"
    }

    /// Retry-After is delta-seconds or an HTTP date.
    static func retryAfter(_ value: String?, now: Date = Date()) -> Double? {
        guard let v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        if let s = Double(v) { return max(0, s) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let d = f.date(from: v) else { return nil }
        return max(0, d.timeIntervalSince(now))
    }
}

// MARK: - Request helpers shared by the channels

extension URLRequest {
    static func postJSON(_ url: URL, _ body: [String: Any]) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 15)
        r.httpMethod = "POST"
        r.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // JSONSerialization writes UTF-8 as-is, so emoji and accents survive end to end.
        r.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        return r
    }
}

enum ChannelText {
    /// Shortens to at most `max` characters, marking the cut.
    static func clip(_ s: String, _ max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }

    /// A replacement key the services accept (`[A-Za-z0-9_-]`, ≤ 64 chars) derived from a session name.
    static func replaceID(_ session: String?) -> String? {
        guard let session = session, !session.isEmpty else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let safe = String(session.map { allowed.contains($0) ? $0 : "-" })
        if safe.count <= 64 && safe == session { return safe }
        // Lossy mapping or too long: add a stable hash so distinct sessions keep distinct keys.
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in session.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return String(safe.prefix(47)) + "-" + String(format: "%016llx", h)
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Trimmed value, or nil when missing or blank.
    static func value(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Server base without trailing slashes, e.g. "https://ntfy.sh".
    static func base(_ server: String?, default def: String) -> String {
        var s = value(server) ?? def
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
