import Foundation

/// A Discord channel webhook. Discord has no priority; the title is bolded.
public struct DiscordNotifier: HTTPChannel {
    public let channelName = "Discord"
    let webhook: String

    public init(webhook: String) { self.webhook = webhook }

    public func request(for alert: Alert) -> URLRequest? {
        guard let url = URL(string: webhook), url.scheme == "https" || url.scheme == "http" else { return nil }
        let title = ChannelText.clip(alert.title, 256)
        let text = alert.body.isEmpty ? "**\(title)**" : "**\(title)**\n" + ChannelText.clip(alert.body, 1700)
        return .postJSON(url, [
            "content": text,
            // Agent text must never ping @everyone, roles or users.
            "allowed_mentions": ["parse": [String]()],
        ])
    }
}

/// A Slack incoming webhook. Slack has no priority; the title is bolded.
public struct SlackNotifier: HTTPChannel {
    public let channelName = "Slack"
    let webhook: String

    public init(webhook: String) { self.webhook = webhook }

    public func request(for alert: Alert) -> URLRequest? {
        guard let url = URL(string: webhook), url.scheme == "https" || url.scheme == "http" else { return nil }
        // Slack mrkdwn treats &, < and > as control characters.
        let title = ChannelText.escapeHTML(ChannelText.clip(alert.title, 256))
        let body = ChannelText.escapeHTML(ChannelText.clip(alert.body, 3000))
        return .postJSON(url, ["text": body.isEmpty ? "*\(title)*" : "*\(title)*\n\(body)"])
    }
}
