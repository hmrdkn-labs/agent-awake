import AppKit
import Sparkle

/// Automatic updates (Sparkle 2): checks the appcast on GitHub and installs signed updates in place, at the
/// same path, so macOS keeps the Login Item and the helper's approval.
@MainActor
enum Updates {
    /// Created on first use. Model touches it only once this copy owns the socket (see Model.init).
    static let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                         userDriverDelegate: nil)

    /// An LSUIElement app is not active when its menu item is clicked, so Sparkle's window would open behind.
    static func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
