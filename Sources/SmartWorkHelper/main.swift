import Foundation
import Security
import SmartWorkCore

// Privileged helper (root LaunchDaemon, registered through SMAppService).
// Exposes one capability over XPC: a short, renewable "stay awake with lid closed" lease.

func log(_ s: String) { FileHandle.standardError.write(Data("[smart-work-helper] \(s)\n".utf8)) }

func ownTeamID() -> String? {
    var code: SecCode?
    var staticCode: SecStaticCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let c = code,
          SecCodeCopyStaticCode(c, [], &staticCode) == errSecSuccess, let sc = staticCode else { return nil }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(sc, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let d = info as? [String: Any] else { return nil }
    return d[kSecCodeInfoTeamIdentifier as String] as? String
}

final class Service: NSObject, SleepControlProtocol {
    let guardian: SleepGuard
    init(_ g: SleepGuard) { guardian = g }
    func acquire(leaseSeconds: Double, reply: @escaping (Bool, String?) -> Void) {
        let r = guardian.acquire(lease: leaseSeconds)
        reply(r.ok, r.reason)
    }
    func release(reply: @escaping () -> Void) { guardian.release(); reply() }
    func version(reply: @escaping (String) -> Void) { reply("1") }
}

final class Delegate: NSObject, NSXPCListenerDelegate {
    let guardian: SleepGuard
    let requirement: String
    private var live = 0
    private let lock = NSLock()
    init(_ g: SleepGuard, requirement: String) { guardian = g; self.requirement = requirement }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        // Only our own app (same Team ID, same identifier) may talk to us.
        c.setCodeSigningRequirement(requirement)
        c.exportedInterface = NSXPCInterface(with: SleepControlProtocol.self)
        c.exportedObject = Service(guardian)
        let drop: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); self.live -= 1; let none = self.live <= 0; self.lock.unlock()
            if none { self.guardian.release() }   // app quit or crashed: sleep normally again
        }
        c.invalidationHandler = drop
        c.interruptionHandler = nil
        lock.lock(); live += 1; lock.unlock()
        c.resume()
        return true
    }
}

guard let team = ownTeamID() else {
    log("helper is not signed with a Team ID; refusing to run")
    exit(78)
}
let requirement = "anchor apple generic and identifier \"\(Identity.appID)\" and certificate leaf[subject.OU] = \"\(team)\""

let guardian = SleepGuard()
guardian.recoverFromCrash()

let t = DispatchSource.makeTimerSource(queue: .global())
t.schedule(deadline: .now() + 5, repeating: 5)
t.setEventHandler { if let why = guardian.tick() { log("lid-closed mode stopped: \(why)") } }
t.resume()

let delegate = Delegate(guardian, requirement: requirement)
let listener = NSXPCListener(machServiceName: Identity.helperMachService)
listener.delegate = delegate
listener.resume()
log("ready (team \(team))")
RunLoop.main.run()
