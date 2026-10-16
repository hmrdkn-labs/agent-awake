import AppKit
import Sparkle

/// Automatic updates (Sparkle 2): checks the appcast on GitHub and installs signed updates in place, at the
/// same path, so macOS keeps the Login Item and the helper's approval.
@MainActor
enum Updates {
    private static let reminders = Reminders()

    /// Created on first use. Model touches it only once this copy owns the socket (see Model.init).
    static let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                         userDriverDelegate: reminders)

    /// An LSUIElement app is not active when its menu item is clicked, so Sparkle's window would open behind.
    static func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// A menu bar app has no Dock icon to badge, so a background check that finds an update brings its window
    /// to the front instead of leaving it behind other apps.
    private final class Reminders: NSObject, SPUStandardUserDriverDelegate {
        var supportsGentleScheduledUpdateReminders: Bool { true }

        func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                       state: SPUUserUpdateState) {
            if handleShowingUpdate { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}
