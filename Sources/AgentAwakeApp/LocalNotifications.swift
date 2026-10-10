import AgentAwakeCore
import Foundation
import UserNotifications

/// Mac notifications through UNUserNotificationCenter. Works only inside the .app bundle; under
/// `swift run` (no bundle identifier) alerts go to stderr instead.
/// Keep a strong reference: the notification center holds its delegate weakly.
final class LocalNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter?

    override init() {
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        guard let center = center else { return }
        center.delegate = self
        // Prompts once; later calls return the recorded answer.
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if !granted {
                LocalNotifier.log("Mac notifications are off" + (error.map { " (\(($0 as NSError).code))" } ?? ""))
            }
        }
    }

    func send(_ alert: Alert) {
        guard let center = center else { return LocalNotifier.log("\(alert.title): \(alert.body)") }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                LocalNotifier.post(alert, on: center, timeSensitive: settings.timeSensitiveSetting == .enabled)
            case .notDetermined:
                // The first alert can beat the user's answer to the prompt.
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { LocalNotifier.post(alert, on: center, timeSensitive: false) }
                    else { LocalNotifier.log("\(alert.title): \(alert.body)") }
                }
            default:
                LocalNotifier.log("\(alert.title): \(alert.body) (Mac notifications are off)")
            }
        }
    }

    /// `timeSensitive` is enabled only when the app carries the time-sensitive entitlement and the user allows it.
    private static func post(_ alert: Alert, on center: UNUserNotificationCenter, timeSensitive: Bool) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = alert.session ?? "agentawake"
        content.interruptionLevel = alert.level == .urgent && timeSensitive ? .timeSensitive : .active
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            if let error = error {
                LocalNotifier.log("Mac notification failed (\((error as NSError).domain) \((error as NSError).code))")
            }
        }
    }

    private static func log(_ s: String) {
        FileHandle.standardError.write(Data("[agentawake] \(s)\n".utf8))
    }

    /// Show banners even while the app is active (e.g. its menu is open).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
