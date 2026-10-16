import Foundation
import IOKit.pwr_mgt

/// Zero-setup detection for agents that already keep the Mac awake themselves while a turn runs.
/// Their sleep assertion appearing means "working", disappearing means "finished". Only an allowlist of
/// (process, assertion) pairs counts: plenty of apps hold assertions for unrelated reasons (Claude's
/// desktop app holds one for hours), so an unknown assertion never keeps a session alive.
public final class AssertionWatcher {
    public struct Holder: Equatable {
        public var pid: Int32
        public var process: String
        public var name: String
        public var type: String
    }

    public struct Rule {
        public var agent: String
        public var title: String
        public var matches: (Holder) -> Bool
    }

    public static let rules: [Rule] = [
        Rule(agent: "omp", title: "oh-my-pi") { $0.process == "omp" && $0.name == "omp agent session" },
        Rule(agent: "codex", title: "Codex") { $0.process == "codex" && $0.name == "Codex is running an active turn" },
        Rule(agent: "zed", title: "Zed agent") { $0.process.lowercased() == "zed" && $0.type == "PreventUserIdleSystemSleep" },
    ]

    private let engine: Engine
    private let fetch: () -> [Holder]
    private let cwd: (Int32) -> String?
    private let env: (Int32) -> [String: String]
    private let interval: Double
    private let quietPolls: Int
    private var tracked: [String: Int] = [:]   // session name -> polls without its assertion
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()

    public init(engine: Engine, interval: Double = 10, quietPolls: Int = 2,
                fetch: @escaping () -> [Holder] = AssertionWatcher.liveHolders,
                cwd: @escaping (Int32) -> String? = ProcessList.cwd,
                env: @escaping (Int32) -> [String: String] = ProcessList.environment) {
        self.engine = engine; self.fetch = fetch; self.cwd = cwd; self.env = env
        self.interval = interval; self.quietPolls = quietPolls
    }

    /// While the herdr watcher runs, agents inside herdr panes are its to report (it knows their task and
    /// blocked state); we only count the ones outside herdr.
    public var herdrFollowsPanes: Bool {
        get { lock.lock(); defer { lock.unlock() }; return herdr }
        set { lock.lock(); herdr = newValue; lock.unlock() }
    }
    private var herdr = false

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "agentawake.assertions"))
        t.schedule(deadline: .now() + 2, repeating: interval, leeway: .seconds(3))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel(); timer = nil
        lock.lock(); let names = Array(tracked.keys); tracked = [:]; lock.unlock()
        for n in names { _ = engine.handle(Request(cmd: "done", name: n, kind: .ended)) }
    }

    public func poll() {
        let me = ProcessInfo.processInfo.processIdentifier
        var seen: [String: (Rule, Int32)] = [:]
        lock.lock(); let inHerdr = herdr, own = Set(tracked.keys); lock.unlock()
        // Processes that report through their own hooks: their assertions would only double-count them.
        // Decided per process, so agents started before Connect stay followed.
        let hooked = Set(engine.store.list().filter { !own.contains($0.name) }.compactMap(\.pid))
        for h in fetch() where h.pid != me && !hooked.contains(h.pid) {
            guard let r = Self.rules.first(where: { $0.matches(h) }) else { continue }
            let name = "\(r.agent):pid\(h.pid)"
            if inHerdr, seen[name] == nil, env(h.pid)["HERDR_PANE_ID"] != nil { continue }
            seen[name] = (r, h.pid)
        }
        lock.lock(); defer { lock.unlock() }
        for name in tracked.keys where engine.store.get(name)?.pid.map(hooked.contains) == true {
            tracked[name] = nil
            _ = engine.handle(Request(cmd: "done", name: name, kind: .ended))   // its hooks took over
        }
        for (name, (rule, pid)) in seen {
            if tracked[name] == nil {
                let folder = cwd(pid).map { ($0 as NSString).lastPathComponent }
                _ = engine.handle(Request(cmd: "begin", name: name, label: folder.map { "\(rule.title) · \($0)" } ?? rule.title,
                                          agent: rule.agent, pid: pid, timeout: interval * 6))
            } else {
                _ = engine.handle(Request(cmd: "beat", name: name, timeout: interval * 6))
            }
            tracked[name] = 0
        }
        for (name, quiet) in tracked where seen[name] == nil {
            if quiet + 1 >= quietPolls {
                tracked[name] = nil
                _ = engine.handle(Request(cmd: "done", name: name, kind: .finished))
            } else {
                tracked[name] = quiet + 1
                _ = engine.handle(Request(cmd: "beat", name: name))
            }
        }
    }

    /// Every process's power assertions, via IOPMCopyAssertionsByProcess (no root, no prompt).
    public static func liveHolders() -> [Holder] {
        var dict: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess,
              let byPID = dict?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        var out: [Holder] = []
        for (pidNum, list) in byPID {
            let pid = pidNum.int32Value
            let process = ProcessList.name(of: pid) ?? ""
            for a in list {
                out.append(Holder(pid: pid, process: process,
                                  name: a[kIOPMAssertionNameKey] as? String ?? "",
                                  type: a[kIOPMAssertionTypeKey] as? String ?? ""))
            }
        }
        return out
    }
}
