import Foundation

/// Holds an agent's next tool call while the Mac is strained (hot, or low on memory). The agent's pre-tool hook
/// (`AgentSpec.gate`) is synchronous: the agent waits for it before running the tool, so a hook that keeps asking
/// the app for `strain` until `holding` clears pauses new work without the agent knowing why.
///
/// The gate never decides: it prints nothing that approves or denies (an "allow" skips the user's approval prompt
/// in several agents; an agent told "no" may give up the task), and after `budget` the tool runs anyway. Anything
/// unexpected (app unreachable, an error, no `holding` in the reply) lets the tool run at once.
public enum HookGate {
    /// Longest one tool call is held, in seconds, unless the agent caps its hook timeout lower.
    public static let budget: Double = 600
    /// What the registered hook timeout adds to the budget: the hook's own startup, payload and requests, plus slack
    /// so the agent never kills a hook that is about to let the tool run.
    public static let margin: Double = 10
    /// How often a held hook asks again.
    public static let poll: Double = 3

    /// How long `spec`'s gate may hold a tool: `budget`, or less when the agent caps its hook timeout.
    public static func budget(for spec: AgentSpec) -> Double {
        max(0, min(budget, (spec.gateLimit ?? .infinity) - margin))
    }

    /// The hook timeout the installer registers for the gate event, in seconds.
    public static func timeout(for spec: AgentSpec) -> Int {
        Int(budget(for: spec) + margin)
    }

    /// The budget when `event` is `agent`'s gate, else nil (the hook must not wait).
    public static func budget(agent: String, event: String) -> Double? {
        guard let spec = AgentCatalog.spec(agent), spec.gate == event else { return nil }
        return budget(for: spec)
    }

    /// The hook's last-resort deadline (seconds) for a gate with `budget`: after the wait, before the agent's timeout.
    public static func alarm(budget: Double) -> UInt32 {
        UInt32(budget.rounded(.up)) + 5
    }

    /// What a wait did: how long the tool was held, and the last reason the app gave.
    public struct Hold: Equatable {
        public var seconds: Double
        public var reason: String?
    }

    /// Waits while the app says `holding`, for at most `budget` seconds. Each poll re-sends `beats` (the hook's own
    /// beat requests) so the session doesn't look silent while it's held.
    @discardableResult
    public static func wait(beats: [Request], budget: Double, poll: Double = poll,
                            send: (Request) throws -> Response,
                            sleep: (Double) -> Void = { Thread.sleep(forTimeInterval: $0) },
                            now: () -> Double = { Date().timeIntervalSince1970 }) -> Hold {
        var reason: String?
        func holding() -> Bool {
            guard let r = try? send(Request(cmd: "strain")), r.ok, r.holding == true else { return false }
            reason = r.strain?.reason ?? reason
            return true
        }
        let start = now()
        guard budget > 0, holding() else { return Hold(seconds: 0, reason: nil) }
        while true {
            let left = budget - (now() - start)
            if left <= 0 { break }
            sleep(min(poll, left))
            for b in beats { _ = try? send(b) }
            if !holding() { break }
        }
        return Hold(seconds: max(0, now() - start), reason: reason)
    }

    /// The note shown after a hold, e.g. "Agent Awake held this tool for 3 min: Mac is running hot."
    public static func note(_ hold: Hold) -> String? {
        guard hold.seconds >= 1 else { return nil }
        let time = hold.seconds < 90 ? "\(Int(hold.seconds.rounded())) s" : "\(Int((hold.seconds / 60).rounded())) min"
        return "Agent Awake held this tool for \(time)" + (hold.reason.map { ": \($0)." } ?? " while the Mac was strained.")
    }
}
