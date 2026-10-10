import Foundation

/// ntfy (ntfy.sh or self-hosted) through the JSON publish API at the server root, so titles keep their UTF-8.
public struct NtfyNotifier: HTTPChannel {
    public static let defaultServer = "https://ntfy.sh"
    public let channelName = "ntfy"
    let server: String
    let topic: String?

    public init(server: String? = nil, topic: String) {
        self.server = ChannelText.base(server, default: NtfyNotifier.defaultServer)
        self.topic = ChannelText.value(topic)
    }

    /// Without a topic every ping is dropped (and logged).
    public init(config: Config) {
        server = ChannelText.base(config.ntfyServer, default: NtfyNotifier.defaultServer)
        topic = ChannelText.value(config.ntfyTopic)
    }

    public func request(for alert: Alert) -> URLRequest? {
        guard let topic = topic, let url = URL(string: server + "/") else { return nil }
        var body: [String: Any] = [
            "topic": topic,
            // ntfy rejects titles over 1 KB; messages over 4 KB turn into attachments.
            "title": ChannelText.clip(alert.title, 200),
            "message": ChannelText.clip(alert.body, 1000),
            // 4 = high on Android, time-sensitive on iOS; 3 = default.
            "priority": alert.level == .urgent ? 4 : 3,
            "tags": [alert.level == .urgent ? "warning" : "white_check_mark"],
        ]
        // Newer servers replace the earlier notification with the same sequence id; older ones ignore it.
        if let id = ChannelText.replaceID(alert.session) { body["sequence_id"] = id }
        return .postJSON(url, body)
    }
}
