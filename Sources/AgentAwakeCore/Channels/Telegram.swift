import Foundation

/// A Telegram bot messaging the user's chat (HTML parse mode, so agent text is escaped).
public struct TelegramNotifier: HTTPChannel {
    public let channelName = "Telegram"
    let token: String
    let chatId: String
    let api: String

    public init(token: String, chatId: String) { self.init(token: token, chatId: chatId, api: Telegram.api) }

    init(token: String, chatId: String, api: String) {
        self.token = token; self.chatId = chatId; self.api = ChannelText.base(api, default: Telegram.api)
    }

    public func request(for alert: Alert) -> URLRequest? {
        guard let url = URL(string: "\(api)/bot\(token)/sendMessage") else { return nil }
        // Telegram counts the 4096-character limit after entity parsing, i.e. on the raw text.
        let title = ChannelText.escapeHTML(ChannelText.clip(alert.title, 256))
        let body = ChannelText.escapeHTML(ChannelText.clip(alert.body, 3500))
        return .postJSON(url, [
            "chat_id": chatId,
            "text": body.isEmpty ? "<b>\(title)</b>" : "<b>\(title)</b>\n\(body)",
            "parse_mode": "HTML",
        ])
    }
}

/// Telegram setup helpers.
public enum Telegram {
    public static let api = "https://api.telegram.org"

    public enum SetupError: Error, LocalizedError {
        /// The bot API refused the request (bad token, webhook set, …). `reason` is Telegram's description.
        case refused(status: Int, reason: String?)

        public var errorDescription: String? {
            switch self {
            case let .refused(status, reason):
                if status == 401 || status == 404 { return "Telegram didn't accept this bot token." }
                return "Telegram answered \(status)" + (reason.map { ": \($0)" } ?? ".")
            }
        }
    }

    /// The chat that most recently messaged the bot (the user taps Start, then we look). nil = no messages yet.
    public static func discoverChatId(token: String) async throws -> String? {
        try await discoverChatId(token: token, api: api, session: .shared)
    }

    static func discoverChatId(token: String, api: String, session: URLSession) async throws -> String? {
        let base = ChannelText.base(api, default: Telegram.api)
        guard let url = URL(string: "\(base)/bot\(token.trimmingCharacters(in: .whitespacesAndNewlines))/getUpdates")
        else { throw SetupError.refused(status: 0, reason: "invalid token") }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200..<300).contains(status), json?["ok"] as? Bool == true else {
            throw SetupError.refused(status: status, reason: json?["description"] as? String)
        }
        return chatId(fromUpdates: data)
    }

    /// Latest chat id in a getUpdates response.
    static func chatId(fromUpdates data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updates = json["result"] as? [[String: Any]] else { return nil }
        for update in updates.reversed() {
            for key in ["message", "edited_message", "channel_post", "my_chat_member"] {
                if let chat = (update[key] as? [String: Any])?["chat"] as? [String: Any],
                   let id = chat["id"] as? NSNumber {
                    return id.stringValue
                }
            }
        }
        return nil
    }
}
