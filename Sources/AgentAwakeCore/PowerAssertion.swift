import Foundation
import IOKit.pwr_mgt

public protocol PowerHolding: AnyObject {
    func setHeld(_ held: Bool)
}

/// Holds PreventUserIdleSystemSleep (`caffeinate -i`). The display is NOT held,
/// so macOS still dims/sleeps it on idle. Releasing lets the Mac sleep normally.
public final class PowerAssertion: PowerHolding {
    private var id: IOPMAssertionID = 0
    private var held = false
    public init() {}

    public func setHeld(_ want: Bool) {
        if want == held { return }
        if want {
            let r = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Agent Awake: agent session running" as CFString, &id)
            held = (r == kIOReturnSuccess)
        } else {
            IOPMAssertionRelease(id)
            id = 0; held = false
        }
    }

    deinit { if held { IOPMAssertionRelease(id) } }
}
