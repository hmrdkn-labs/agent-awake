import Foundation
import ServiceManagement
import AgentAwakeCore

enum HelperState: Equatable {
    case notInstalled, needsApproval, ready, unavailable(String)
    var label: String {
        switch self {
        case .notInstalled: return "Helper not installed"
        case .needsApproval: return "Waiting for approval in System Settings"
        case .ready: return "Helper ready"
        case .unavailable(let m): return m
        }
    }
}

/// Registers/queries the privileged helper. Needs to run from the signed .app bundle.
enum HelperInstaller {
    private static var service: SMAppService { SMAppService.daemon(plistName: Identity.helperPlist) }

    static func state() -> HelperState {
        switch service.status {
        case .enabled: return .ready
        case .requiresApproval: return .needsApproval
        case .notRegistered: return .notInstalled
        case .notFound: return .notInstalled   // reported until register() is called
        @unknown default: return .unavailable("Unknown helper status")
        }
    }

    /// Registers the daemon; the user must still enable it in System Settings > Login Items.
    static func register() -> HelperState {
        do { try service.register() } catch {
            let s = state()
            if s == .needsApproval || s == .ready { return s }
            return .unavailable("Could not install helper: \(error.localizedDescription)")
        }
        return state()
    }

    static func unregister() { try? service.unregister() }
    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// XPC client for the helper.
final class XPCSleepController: SleepControlling {
    private var connection: NSXPCConnection?
    private let lock = NSLock()

    private func proxy(_ fail: @escaping (String) -> Void) -> SleepControlProtocol? {
        lock.lock(); defer { lock.unlock() }
        if connection == nil {
            let c = NSXPCConnection(machServiceName: Identity.helperMachService, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: SleepControlProtocol.self)
            c.invalidationHandler = { [weak self] in self?.reset() }
            c.interruptionHandler = { [weak self] in self?.reset() }
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in fail("helper unreachable") } as? SleepControlProtocol
    }

    private func reset() { lock.lock(); connection = nil; lock.unlock() }

    func acquire(lease: Double, completion: @escaping (Bool, String?) -> Void) {
        guard let p = proxy({ completion(false, $0) }) else { return completion(false, "helper unreachable") }
        p.acquire(leaseSeconds: lease, reply: completion)
    }

    func release() {
        proxy({ _ in })?.release(reply: {})
    }
}
