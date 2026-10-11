import Foundation
import IOKit.pwr_mgt

public protocol PowerHolding: AnyObject {
    /// `system`: the Mac doesn't idle-sleep. `display`: the screen doesn't idle-sleep (so it doesn't lock) either.
    func setHeld(system: Bool, display: Bool)
}

/// Agent sessions hold PreventUserIdleSystemSleep (`caffeinate -i`): work runs, the screen still sleeps and locks.
/// The user's own "Keep awake" also holds PreventUserIdleDisplaySleep (`caffeinate -d`), so the screen stays on.
/// Releasing lets the Mac sleep normally.
public final class PowerAssertion: PowerHolding {
    private var system: IOPMAssertionID?
    private var display: IOPMAssertionID?
    public init() {}

    public func setHeld(system wantSystem: Bool, display wantDisplay: Bool) {
        Self.set(&system, wantSystem, kIOPMAssertPreventUserIdleSystemSleep, "Agent Awake: agent session running")
        Self.set(&display, wantDisplay, kIOPMAssertPreventUserIdleDisplaySleep, "Agent Awake: keeping the screen on")
    }

    private static func set(_ id: inout IOPMAssertionID?, _ want: Bool, _ type: String, _ name: String) {
        if want == (id != nil) { return }
        if let held = id {
            IOPMAssertionRelease(held)
            id = nil
        } else {
            var new: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           name as CFString, &new) == kIOReturnSuccess {
                id = new
            }
        }
    }

    deinit {
        [system, display].compactMap { $0 }.forEach { IOPMAssertionRelease($0) }
    }
}
