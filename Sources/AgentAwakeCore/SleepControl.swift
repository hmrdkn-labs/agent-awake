import Foundation

/// XPC interface of the privileged helper. Deliberately tiny: the helper decides policy, not the client.
@objc public protocol SleepControlProtocol {
    /// Keep the Mac awake with the lid closed for `leaseSeconds` (clamped by the helper). Must be renewed.
    func acquire(leaseSeconds: Double, reply: @escaping (Bool, String?) -> Void)
    func release(reply: @escaping () -> Void)
    func version(reply: @escaping (String) -> Void)
}

/// Client-side view of the helper, so the policy in `LidGuard` is testable without XPC.
public protocol SleepControlling: AnyObject {
    func acquire(lease: Double, completion: @escaping (Bool, String?) -> Void)
    func release()
}
