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

    public static func parse(_ data: Data) -> [AgentSnapshot]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let agents = result["agents"] as? [[String: Any]] else { return nil }
        return agents.compactMap {
            guard let id = $0["pane_id"] as? String, let st = $0["agent_status"] as? String else { return nil }
            let agent = ($0["agent"] as? String) ?? "agent"
            let title = ($0["terminal_title_stripped"] as? String) ?? ($0["terminal_title"] as? String)
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
        if let c = cwd, !c.isEmpty { return "\(agent) · \((c as NSString).lastPathComponent)" }
        return agent
    }
}

/// Turns herdr's agent states into sessions: working => session alive (heartbeat each poll);
/// leaving "working" for `quietPolls` polls in a row => done, so brief idle flickers don't ping.
public final class HerdrWatcher {
    private let engine: Engine
    private let fetch: () -> Data?
    private let quietPolls: Int
    private let sessionTimeout: Double
    private var tracked: [String: (name: String, quiet: Int, last: String)] = [:]
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()

    public init(engine: Engine, interval: Double = 3, quietPolls: Int = 2, fetch: @escaping () -> Data?) {
        self.engine = engine; self.fetch = fetch; self.quietPolls = quietPolls
        self.sessionTimeout = max(60, interval * 10)
        self.interval = interval
    }
    private let interval: Double

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "agentawake.herdr"))
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel(); timer = nil
        lock.lock(); let all = tracked; tracked = [:]; lock.unlock()
        for (_, v) in all { _ = engine.handle(Request(cmd: "done", name: v.name, message: "Herdr watching stopped.")) }
    }

    public func poll() {
        guard let data = fetch(), let agents = HerdrCLI.parse(data) else { return }   // herdr unreachable: change nothing
        lock.lock(); defer { lock.unlock() }
        let byPane = Dictionary(agents.map { ($0.paneID, $0) }, uniquingKeysWith: { a, _ in a })
        for a in agents where a.status == "working" {
            if var t = tracked[a.paneID] {
                t.quiet = 0; t.last = a.status; tracked[a.paneID] = t
                _ = engine.handle(Request(cmd: "beat", name: t.name, label: a.label))
            } else {
                let name = "\(a.agent) \(a.paneID)"
                tracked[a.paneID] = (name, 0, a.status)
                _ = engine.handle(Request(cmd: "begin", name: name, label: a.label, timeout: sessionTimeout))
            }
        }
        for (pane, t) in tracked where byPane[pane]?.status != "working" {
            let status = byPane[pane]?.status ?? "closed"
            var n = t; n.quiet += 1; n.last = status
            if n.quiet >= quietPolls {
                tracked[pane] = nil
                let msg = status == "blocked" ? "Blocked — it needs you." : status == "closed" ? "Pane closed." : "Finished."
                _ = engine.handle(Request(cmd: "done", name: t.name, message: msg))
            } else {
                tracked[pane] = n
                _ = engine.handle(Request(cmd: "beat", name: t.name))
            }
        }
    }
}
