import Foundation

/// Pushover with the user's own application token.
public struct PushoverNotifier: HTTPChannel {
    public static let endpoint = "https://api.pushover.net/1/messages.json"
    public let channelName = "Pushover"
    let token: String
    let user: String
    let endpoint: String

    public init(token: String, user: String) { self.init(token: token, user: user, endpoint: PushoverNotifier.endpoint) }

    init(token: String, user: String, endpoint: String) {
        self.token = token; self.user = user; self.endpoint = endpoint
    }

    public func request(for alert: Alert) -> URLRequest? {
        guard let url = URL(string: endpoint) else { return nil }
        // `message` is required and non-empty; Pushover caps title at 250 and message at 1024 characters.
        let message = alert.body.isEmpty ? alert.title : alert.body
        return .postJSON(url, [
            "token": token,
            "user": user,
            "title": ChannelText.clip(alert.title, 250),
            "message": ChannelText.clip(message, 1024),
            // 1 = high: bypasses quiet hours with sound; 0 = normal.
            "priority": alert.level == .urgent ? 1 : 0,
        ])
    }
}
