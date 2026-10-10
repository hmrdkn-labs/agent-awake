import Foundation

/// Bark (iOS) through its JSON push endpoint.
public struct BarkNotifier: HTTPChannel {
    public static let defaultServer = "https://api.day.app"
    public let channelName = "Bark"
    let key: String
    let server: String

    public init(key: String, server: String? = nil) {
        self.key = key
        self.server = ChannelText.base(server, default: BarkNotifier.defaultServer)
    }

    public func request(for alert: Alert) -> URLRequest? {
        guard let url = URL(string: server + "/push") else { return nil }
        var body: [String: Any] = [
            "device_key": key,
            "title": ChannelText.clip(alert.title, 200),
            "body": ChannelText.clip(alert.body, 1000),
            "level": alert.level == .urgent ? "timeSensitive" : "active",
            "group": "Agent Awake",
        ]
        // Same id replaces the earlier notification for this session (Bark ≥ 1.5.2; ignored before).
        if let id = ChannelText.replaceID(alert.session) { body["id"] = id }
        return .postJSON(url, body)
    }
}
