import Foundation

/// Something the user should hear about. The app routes it: phone channels when the user is away,
/// a Mac notification when they are at the Mac.
public struct Alert: Equatable {
    public enum Level: String, Codable {
        case info        // finished
        case urgent      // needs you, failed, stuck, safety stop
    }
    public var title: String
    public var body: String
    public var level: Level
    /// Session the alert is about; channels that support it replace older alerts of the same session.
    public var session: String?

    public init(title: String, body: String, level: Level = .info, session: String? = nil) {
        self.title = title; self.body = body; self.level = level; self.session = session
    }
}

public protocol Notifier {
    func send(_ alert: Alert)
}
