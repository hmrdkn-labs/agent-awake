import CoreGraphics
import Foundation
import IOKit

/// Whether the user is at the Mac. Decides between a phone ping and a Mac notification.
public protocol PresenceSource {
    func isAway(after seconds: Double) -> Bool
}

/// Reads the live system state. None of these signals needs a permission prompt.
public struct SystemPresence: PresenceSource {
    public init() {}

    /// Away when the screen is locked, the display sleeps, a laptop lid is closed with no external display
    /// in use, or there has been no keyboard/mouse input for `seconds`.
    public func isAway(after seconds: Double) -> Bool {
        SystemPresence.screenLocked || SystemPresence.displayAsleep
            || SystemPresence.lidClosedWithoutExternalDisplay || SystemPresence.idleSeconds >= seconds
    }

    /// Seconds since the last keyboard, mouse or tablet event (kCGAnyInputEventType).
    public static var idleSeconds: Double {
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: any)
    }

    /// The `CGSSessionScreenIsLocked` key is undocumented; absent means unlocked.
    public static var screenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }

    public static var displayAsleep: Bool { CGDisplayIsAsleep(CGMainDisplayID()) != 0 }

    /// nil on Macs without a lid.
    public static var lidClosed: Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? NSNumber)?.boolValue
    }

    /// A closed lid with an external display in use (clamshell mode) still means the user may be at the desk.
    static var lidClosedWithoutExternalDisplay: Bool {
        guard lidClosed == true else { return false }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return true }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return true }
        return !ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 && CGDisplayIsAsleep($0) == 0 }
    }
}
