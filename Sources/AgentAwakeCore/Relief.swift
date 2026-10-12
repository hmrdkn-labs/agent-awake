import Foundation
import Darwin

/// Finds and acts on processes agents started, through libproc and signals: no root, no subprocess.
public final class LiveRelief: ReliefActing {
    /// Deep enough for agent -> shell -> npm -> node -> worker chains, bounded against pathological trees.
    public static let maxDepth = 8

    private let grace: TimeInterval
    private let queue = DispatchQueue(label: "agent-awake.relief", qos: .utility)

    /// `grace`: how long a process gets to exit on SIGTERM before SIGKILL.
    public init(grace: TimeInterval = 3) { self.grace = grace }

    /// Every descendant is reported, including the shells hosting a command: a shell's footprint is tiny, so the
    /// largest-first order naturally puts the real build or test process first. Agent pids are never reported or
    /// walked through from another agent (a nested agent's children belong to its own session), and the walk stops
    /// at processes not running as the current user (root helpers, sudo).
    public func agentChildren(of agents: [String: Int32]) -> [AgentChild] {
        var seen = Set(agents.values)
        var out: [AgentChild] = []
        for (session, agent) in agents.sorted(by: { $0.key < $1.key }) {
            var frontier = [agent]
            for _ in 0..<Self.maxDepth where !frontier.isEmpty {
                var next: [pid_t] = []
                for parent in frontier {
                    for kid in ProcessList.children(of: parent) where seen.insert(kid).inserted {
                        guard ProcessList.isOwnedByUser(kid), let footprint = ProcessList.footprint(of: kid) else { continue }
                        next.append(kid)
                        out.append(AgentChild(pid: kid, name: ProcessList.name(of: kid) ?? "?", footprint: footprint,
                                              session: session))
                    }
                }
                frontier = next
            }
        }
        return out.sorted { ($0.footprint, $1.pid) > ($1.footprint, $0.pid) }
    }

    /// PRIO_DARWIN_BG: efficiency cores, throttled disk and network I/O. Works on any process the user owns.
    @discardableResult public func throttle(_ pid: Int32, _ on: Bool) -> Bool {
        guard Self.mayAct(on: pid) else { return false }
        return setpriority(PRIO_DARWIN_PROCESS, id_t(pid), on ? PRIO_DARWIN_BG : 0) == 0
    }

    @discardableResult public func pause(_ pid: Int32) -> Bool { Self.mayAct(on: pid) && kill(pid, SIGSTOP) == 0 }

    @discardableResult public func resume(_ pid: Int32) -> Bool { Self.mayAct(on: pid) && kill(pid, SIGCONT) == 0 }

    @discardableResult public func terminate(_ pid: Int32) -> Bool {
        guard Self.mayAct(on: pid), let started = ProcessList.startTime(of: pid), kill(pid, SIGTERM) == 0 else {
            return false
        }
        kill(pid, SIGCONT) // a paused process can't act on SIGTERM until it runs again
        queue.asyncAfter(deadline: .now() + grace) {
            // Same start time: still the process we signalled, not a new one that reused the pid.
            guard ProcessList.startTime(of: pid) == started, !ProcessList.isZombie(pid) else { return }
            kill(pid, SIGKILL)
        }
        return true
    }

    /// Never signal ourselves, a process group (0, negative) or launchd, nor anything not run by this user.
    private static func mayAct(on pid: Int32) -> Bool {
        pid > 1 && pid != getpid() && ProcessList.isOwnedByUser(pid)
    }
}
