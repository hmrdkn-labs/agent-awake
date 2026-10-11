import Foundation

public struct AgentSnapshot: Equatable {
    public var paneID: String
    public var agent: String
    public var status: String      // working | idle | blocked | done (herdr's vocabulary)
    public var label: String       // what the user sees: the pane's task title, else its folder, else the agent
}

public enum HerdrCLI {
    /// First `herdr` found in the usual places (GUI apps have a minimal PATH).
    public static func locate() -> String? {
        let home = NSHomeDirectory()
        let dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.cargo/bin", home + "/.herdr/bin"]
        return dirs.map { $0 + "/herdr" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func listAgents(herdr: String) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: herdr)
        p.arguments = ["agent", "list"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }

    /// `taskTitles` false: sessions are named by agent and folder only, as for hooked agents (the pane title is
    /// the agent's task, which can hold private text that pings carry to third-party servers).
    public static func parse(_ data: Data, taskTitles: Bool = true) -> [AgentSnapshot]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let agents = result["agents"] as? [[String: Any]] else { return nil }
        return agents.compactMap {
            guard let id = $0["pane_id"] as? String, let st = $0["agent_status"] as? String else { return nil }
            let agent = ($0["agent"] as? String) ?? "agent"
            let title = taskTitles ? (($0["terminal_title_stripped"] as? String) ?? ($0["terminal_title"] as? String)) : nil
            return AgentSnapshot(paneID: id, agent: agent, status: st,
                                 label: label(title: title, cwd: $0["cwd"] as? String, agent: agent))
        }
    }

    /// Agents set the terminal title to their task behind a short prompt and a status marker
    /// ("π > Fix login" when idle, "π ⁝ Fix login" while busy). Drop that prefix.
    static func label(title: String?, cwd: String?, agent: String) -> String {
        var t = (title ?? "").trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: #"^\S{1,2}\s+[^\p{L}\p{N}\s]{1,2}\s+"#, options: .regularExpression) {
            t = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if !t.isEmpty { return t }
        let name = AgentCatalog.spec(agent)?.name ?? agent
        if let c = cwd, !c.isEmpty { return "\(name) · \((c as NSString).lastPathComponent)" }
        return name
    }
}

/// Turns herdr's agent states into sessions: working => session alive (heartbeat each poll);
/// leaving "working" for `quietPolls` polls in a row => done, so brief idle flickers don't ping.
/// Battery: `herdr agent list` is spawned only while a herdr process exists, every `interval` while an
/// agent is working and every `idleEvery` intervals otherwise.
public final class HerdrWatcher {
    private let engine: Engine
    private let fetch: () -> Data?
    private let isRunning: () -> Bool
    private let taskTitles: () -> Bool
    private let quietPolls: Int
    private let idleEvery: Int
    private let sessionTimeout: Double
    private var tracked: [String: (name: String, quiet: Int, last: String)] = [:]
    private var ticks = 0
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()

    public init(engine: Engine, interval: Double = 3, quietPolls: Int = 2, idleEvery: Int = 4,
                isRunning: @escaping () -> Bool = { ProcessList.contains("herdr") },
                taskTitles: @escaping () -> Bool = { Config.load().effectiveTaskTitles },
                fetch: @escaping () -> Data?) {
        self.engine = engine; self.fetch = fetch; self.isRunning = isRunning; self.taskTitles = taskTitles
        self.quietPolls = quietPolls; self.idleEvery = idleEvery
        self.sessionTimeout = max(60, interval * 10)
        self.interval = interval
    }
    private let interval: Double

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "agentawake.herdr"))
        t.schedule(deadline: .now(), repeating: interval, leeway: .seconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func tick() {
        lock.lock(); let idle = tracked.isEmpty; ticks += 1; let n = ticks; lock.unlock()
        if idle && (n - 1) % idleEvery != 0 { return }
        poll()
    }

    public func stop() {
        timer?.cancel(); timer = nil
        lock.lock(); let all = tracked; tracked = [:]; lock.unlock()
        for (_, v) in all { _ = engine.handle(Request(cmd: "done", name: v.name, kind: .ended)) }
    }

    /// Agents whose own hooks report to us (connected integrations); herdr would only double-count them.
    public var skipAgents: Set<String> {
        get { lock.lock(); defer { lock.unlock() }; return skip }
        set { lock.lock(); skip = newValue; lock.unlock() }
    }
    private var skip: Set<String> = []

    public func poll() {
        let agents: [AgentSnapshot]
        if !isRunning() {
            agents = []                                   // herdr quit: its panes are gone
        } else {
            guard let data = fetch(), let a = HerdrCLI.parse(data, taskTitles: taskTitles()) else { return }   // unreachable: change nothing
            agents = a
        }
        lock.lock(); defer { lock.unlock() }
        let byPane = Dictionary(agents.map { ($0.paneID, $0) }, uniquingKeysWith: { a, _ in a })
        for a in agents where a.status == "working" && !skip.contains(a.agent) {
            if var t = tracked[a.paneID] {
                t.quiet = 0; t.last = a.status; tracked[a.paneID] = t
                _ = engine.handle(Request(cmd: "beat", name: t.name, label: a.label, agent: a.agent, timeout: sessionTimeout))
            } else {
                let name = "\(a.agent) \(a.paneID)"
                tracked[a.paneID] = (name, 0, a.status)
                _ = engine.handle(Request(cmd: "begin", name: name, label: a.label, agent: a.agent, timeout: sessionTimeout))
            }
        }
        for (pane, t) in tracked where byPane[pane]?.status != "working" || skip.contains(byPane[pane]?.agent ?? "") {
            let status = byPane[pane]?.status ?? "closed"
            var n = t; n.quiet += 1; n.last = status
            if n.quiet >= quietPolls {
                tracked[pane] = nil
                switch status {
                case "blocked":
                    _ = engine.handle(Request(cmd: "wait", name: t.name, message: "It is blocked on a question or permission."))
                case "closed":
                    _ = engine.handle(Request(cmd: "done", name: t.name, kind: .ended))
                default:
                    _ = engine.handle(Request(cmd: "done", name: t.name, kind: .finished))
                }
            } else {
                tracked[pane] = n
                _ = engine.handle(Request(cmd: "beat", name: t.name))
            }
        }
    }
}
