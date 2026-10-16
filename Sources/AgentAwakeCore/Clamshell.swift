import Foundation
import IOKit

/// The lid, as IOPMrootDomain reports it.
public protocol ClamshellReading {
    /// Whether the lid is closed; nil on desktops or if unreadable.
    func isClosed() -> Bool?
    /// Whether a closed lid sleeps the Mac right now: false with an external display in use, or while
    /// `pmset disablesleep` is on. macOS's own decision, so we never sleep a Mac it would keep awake.
    func closedCausesSleep() -> Bool?
}

public struct Clamshell: ClamshellReading {
    public init() {}
    public func isClosed() -> Bool? { Self.property("AppleClamshellState") }
    public func closedCausesSleep() -> Bool? { Self.property("AppleClamshellCausesSleep") }

    static func property(_ key: String) -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }
}
