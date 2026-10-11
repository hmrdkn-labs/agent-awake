import Foundation

public enum IntegrationStatus: Equatable {
    case notInstalled                 // agent not found on this Mac
    case available                    // found, not connected
    case connected
    case needsAction(String)          // connected, but the agent still needs a step from the user
    case broken(String)               // partly connected, outdated, or the file can't be read
}

/// One agent's one-click Connect/Disconnect. Built by `Integrations.all(home:)`.
public struct Integration {
    public let id: String
    public let name: String
    /// What Connect writes, for the UI.
    public let files: [String]
    /// Something the user should know or do after connecting (for example Codex's trust step).
    public let note: String?

    fileprivate let installed: () -> Bool
    fileprivate let target: Target

    public func status() -> IntegrationStatus {
        let state: IntegrationStatus
        do { state = try target.status() } catch { return .broken(error.localizedDescription) }
        if state == .available, !installed() { return .notInstalled }
        return state
    }

    public func connect() throws { try target.connect() }
    public func disconnect() throws { try target.disconnect() }
}

/// Where an integration's hooks live.
fileprivate enum Target {
    /// Entries merged into a file the agent shares with the user. `cleanup` lists other files that may hold our
    /// entries from earlier connects (Droid moves between hooks.json and settings.json); disconnect cleans them too.
    case shared(HookFile, cleanup: [HookFile], trust: ((HookFile) throws -> IntegrationStatus)?)
    /// Files that are entirely ours (plugins, extensions, a hooks file in a drop-in directory). `root` is removed
    /// once empty on disconnect.
    case owned([(path: String, content: String)], root: String?, stop: String)

    func status() throws -> IntegrationStatus {
        switch self {
        case let .shared(file, cleanup, trust):
            let p = try file.presence()
            let leftovers = try cleanup.reduce(0) { $0 + (try $1.presence().ours) }
            if p.exact == file.allEvents, p.stale == 0, leftovers == 0 { return try trust?(file) ?? .connected }
            if p.ours + leftovers == 0 { return .available }
            return .broken("Agent Awake's hooks are incomplete or out of date. Connect again to repair them.")
        case let .owned(files, _, _):
            var present = 0
            for (path, content) in files {
                guard let text = try FileOps.read(path) else { continue }
                guard text.contains("agentawake") else { throw IntegrationError.notOurs(path: path) }
                if text == content { present += 1 } else {
                    return .broken("Agent Awake's files are out of date. Connect again to update them.")
                }
            }
            if present == files.count { return .connected }
            return present == 0 ? .available : .broken("Some of Agent Awake's files are missing. Connect again to repair them.")
        }
    }

    func connect() throws {
        switch self {
        case let .shared(file, cleanup, _):
            try file.connect()
            for other in cleanup where other.path != file.path { try other.disconnect() }
        case let .owned(files, _, _):
            for (path, _) in files {
                if let text = try FileOps.read(path), !text.contains("agentawake") { throw IntegrationError.notOurs(path: path) }
            }
            for (path, content) in files where (try FileOps.read(path)) != content {
                try FileOps.writeAtomically(content, to: path)
            }
        }
    }

    func disconnect() throws {
        switch self {
        case let .shared(file, cleanup, _):
            try file.disconnect()
            for other in cleanup where other.path != file.path { try other.disconnect() }
        case let .owned(files, root, stop):
            for (path, _) in files {
                guard let text = try FileOps.read(path) else { continue }
                if text.contains("agentawake") { try FileOps.remove(path) }
            }
            for (path, _) in files { FileOps.removeEmptyDirs((path as NSString).deletingLastPathComponent, stop: root ?? stop) }
            if let root { FileOps.removeEmptyDirs(root, stop: stop) }
        }
    }
}

public enum Integrations {
    /// `/bin/sh -c '[ -x "<bin>" ] && "<home>/.agent-awake/bin/"agentawake hook <agent> <event>; exit 0'`.
    /// The shell joins `"<dir>/"agentawake` into the binary path, which keeps the literal `agentawake hook` marker in
    /// the text even when the home folder needs quoting. A missing binary still exits 0, and stdin passes through.
    public static func hookCommand(agent: String, event: String, home: String) -> String {
        let dir = shimDir(home) + "/"
        let script = "[ -x \(doubleQuoted(dir + "agentawake")) ] && \(doubleQuoted(dir))agentawake hook \(agent) \(event); exit 0"
        return "/bin/sh -c '" + script.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// (Re)points `<home>/.agent-awake/bin/agentawake` at the CLI bundled in the app. Hook commands and plugins use
    /// this stable path, so moving the app doesn't break (or, for Codex, un-trust) connected agents.
    public static func installShim(cliPath: String, home: String = NSHomeDirectory()) throws {
        guard FileOps.isExecutable(cliPath) else { throw IntegrationError.cliMissing(path: cliPath) }
        let link = shimPath(home)
        let fm = FileManager.default
        if (try? fm.destinationOfSymbolicLink(atPath: link)) == cliPath { return }
        do {
            try fm.createDirectory(atPath: shimDir(home), withIntermediateDirectories: true)
            let temp = link + ".tmp-\(getpid())"
            try? fm.removeItem(atPath: temp)
            try fm.createSymbolicLink(atPath: temp, withDestinationPath: cliPath)
            guard rename(temp, link) == 0 else {
                let reason = String(cString: strerror(errno))
                try? fm.removeItem(atPath: temp)
                throw IntegrationError.write(path: link, reason: reason)
            }
        } catch let error as IntegrationError {
            throw error
        } catch {
            throw IntegrationError.write(path: link, reason: error.localizedDescription)
        }
    }

    public static func all(home: String = NSHomeDirectory()) -> [Integration] {
        AgentCatalog.all.compactMap { make($0, home: home) }
    }

    // MARK: Definitions

    static func shimDir(_ home: String) -> String { home + "/.agent-awake/bin" }
    static func shimPath(_ home: String) -> String { shimDir(home) + "/agentawake" }

    private static func doubleQuoted(_ s: String) -> String {
        var out = "\""
        for c in s {
            if "\\\"$`".contains(c) { out.append("\\") }
            out.append(c)
        }
        return out + "\""
    }

    private static func make(_ spec: AgentSpec, home: String) -> Integration? {
        let h = home
        let cmd = { (event: String) in hookCommand(agent: spec.id, event: event, home: h) }
        let events = spec.events.map(\.event)
        let tools: Set<String> = ["PreToolUse", "PostToolUse", "BeforeTool", "AfterTool"]

        /// Claude-style matcher group: `{matcher?, hooks: [handler]}`.
        func group(_ matcher: String?, _ handler: [(String, JSONValue)]) -> JSONValue {
            var pairs: [(String, JSONValue)] = []
            if let matcher { pairs.append(("matcher", .string(matcher))) }
            pairs.append(("hooks", .array([.obj(handler)])))
            return .obj(pairs)
        }
        func shared(_ path: String, container: [String] = ["hooks"], comments: Bool = false,
                    defaults: [(String, JSONValue)] = [], _ entry: (String) -> JSONValue) -> HookFile {
            var file = HookFile(path: path, agent: spec.id, container: container, allowComments: comments,
                                entries: events.map { ($0, entry($0)) })
            file.defaults = defaults
            return file
        }
        func integration(_ files: [String], note: String?, detect: Detection, _ target: Target) -> Integration {
            Integration(id: spec.id, name: spec.name, files: files, note: note,
                        installed: { detect.isInstalled(home: h) }, target: target)
        }
        func plugin(_ path: String, _ source: String, note: String, detect: Detection) -> Integration {
            integration([path], note: note, detect: detect,
                        .owned([(path, source)], root: nil, stop: (path as NSString).deletingLastPathComponent))
        }

        switch spec.id {
        case "claude":
            let path = h + "/.claude/settings.json"
            let file = shared(path) { e in
                var handler: [(String, JSONValue)] = [("type", .string("command")), ("command", .string(cmd(e)))]
                // SessionEnd hooks share a 1.5 s budget that a per-hook timeout would raise; leave it alone.
                if e != "SessionEnd" { handler.append(("timeout", .int(5))) }
                if tools.contains(e) { handler.append(("async", .bool(true))) }
                return group(tools.contains(e) || e == "PermissionRequest" ? "*" : nil, handler)
            }
            return integration([path], note: nil,
                               detect: Detection(binaries: ["claude"], apps: [("Claude.app", nil)], paths: [".claude/settings.json", ".claude/local/claude", ".claude.json"]),
                               .shared(file, cleanup: [], trust: nil))

        case "codex":
            let path = h + "/.codex/hooks.json"
            let file = shared(path) { e in
                group(nil, [("type", .string("command")), ("command", .string(cmd(e))), ("timeout", .int(e == "SessionEnd" ? 2 : 5))])
            }
            let appCLI = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
            let detect = Detection(binaries: ["codex"], apps: [("ChatGPT.app", "com.openai.codex"), ("Codex.app", nil)],
                                   paths: [".codex/config.toml", ".codex/auth.json"])
            let trust: (HookFile) throws -> IntegrationStatus = { file in
                let state = CodexTrust.state(configToml: (try? FileOps.read(h + "/.codex/config.toml")) ?? "")
                if state.hooksOff {
                    return .needsAction("Hooks are turned off in ~/.codex/config.toml ([features] hooks = false). Turn them on to use Agent Awake with Codex.")
                }
                let paths = Set([path, FileOps.canonical(path)])   // Codex keys trust by the realpath
                let keySets = try paths.map { try CodexTrust.keys(for: file, hooksPath: $0) }
                if keySets.contains(where: { keys in !keys.isEmpty && keys.allSatisfy { state.trusted.contains($0) && !state.disabled.contains($0) } }) {
                    return .connected
                }
                let cli = Detection(binaries: ["codex"]).isInstalled(home: h) ? "codex" : "“\(appCLI)”"
                return .needsAction("Codex runs new hooks only after you trust them. Run \(cli) in Terminal and choose “Trust all and continue” (or type /hooks and trust Agent Awake's hooks). The ChatGPT app can't approve hooks itself, so this one-time step happens in the Codex CLI.")
            }
            return integration([path], note: "Codex asks you to trust new hooks once: run codex in Terminal and choose “Trust all and continue”. The ChatGPT app has no trust prompt, so use the CLI (it ships inside the app).",
                               detect: detect, .shared(file, cleanup: [], trust: trust))

        case "gemini":
            let dir = h + "/.gemini/extensions/agentawake"
            var hooks = JSONValue.object([])
            for e in events {
                hooks.set(e, .array([group(tools.contains(e) ? "*" : nil, [
                    ("name", .string("agentawake-\(e)")), ("type", .string("command")), ("command", .string(cmd(e))), ("timeout", .int(5000)),
                ])]))
            }
            let manifest = JSONValue.obj([("name", .string("agentawake")), ("version", .string("1.0.0")),
                                          ("description", .string("Agent Awake: keeps the Mac awake while Gemini works and pings you when it's done."))])
            let files = [(dir + "/gemini-extension.json", manifest.serialized() + "\n"),
                         (dir + "/hooks/hooks.json", JSONValue.obj([("hooks", hooks)]).serialized() + "\n")]
            return integration(files.map(\.0), note: "Installed as a Gemini CLI extension, so it also works in folders you haven't trusted. Restart Gemini CLI to load it.",
                               // ~/.gemini is shared with Antigravity, so only the gemini binary means Gemini CLI.
                               detect: Detection(binaries: ["gemini"]),
                               .owned(files, root: dir, stop: h + "/.gemini/extensions"))

        case "antigravity":
            // One named hook definition ("agentawake") in the hooks file all three Antigravity apps read.
            let path = h + "/.gemini/config/hooks.json"
            let file = shared(path, container: ["agentawake"]) { e in
                let handler: [(String, JSONValue)] = [("type", .string("command")), ("command", .string(cmd(e))), ("timeout", .int(5))]
                return e == "PostToolUse" ? group("*", handler) : .obj(handler)
            }
            return integration([path], note: "Covers Antigravity 2.0, the Antigravity IDE and the agy CLI. Antigravity has no hook for approvals, so Agent Awake hears when work starts and finishes. In agy, /hooks lists it.",
                               detect: Detection(binaries: ["agy"], apps: [("Antigravity.app", nil)],
                                                 paths: [".gemini/antigravity-cli/cli.log", ".gemini/antigravity/installation_id", ".gemini/antigravity-ide"]),
                               .shared(file, cleanup: [], trust: nil))

        case "qwen":
            let path = h + "/.qwen/settings.json"
            let file = shared(path, comments: true) { e in
                var handler: [(String, JSONValue)] = [("type", .string("command")), ("name", .string("agentawake-\(e)")),
                                                     ("command", .string(cmd(e))), ("timeout", .int(5))]
                if tools.contains(e) { handler.append(("async", .bool(true))) }
                return group(tools.contains(e) ? "*" : nil, handler)
            }
            return integration([path], note: "Restart Qwen Code (or open /hooks) to load the hooks.",
                               detect: Detection(binaries: ["qwen"], apps: [("Qwen Code.app", nil)], paths: [".qwen/settings.json"]),
                               .shared(file, cleanup: [], trust: nil))

        case "droid":
            let entry = { (e: String) -> JSONValue in
                group(tools.contains(e) ? "*" : nil, [("type", .string("command")), ("command", .string(cmd(e))), ("timeout", .int(5))])
            }
            let standalone = h + "/.factory/hooks.json", legacy = h + "/.factory/hooks/hooks.json", settings = h + "/.factory/settings.json"
            let candidates = [
                shared(standalone, container: Self.droidContainer(standalone), comments: true, entry),
                shared(legacy, container: Self.droidContainer(legacy), comments: true, entry),
                shared(settings, comments: true, entry),
            ]
            // Edit the file Droid actually reads: hooks.json, else the legacy hooks/hooks.json, else settings.json if it
            // already has hooks (a new hooks.json would hide them), else create hooks.json.
            let chosen: HookFile
            if FileOps.exists(standalone) { chosen = candidates[0] }
            else if FileOps.exists(legacy) { chosen = candidates[1] }
            else if (try? candidates[2].load())?["hooks"] != nil { chosen = candidates[2] }
            else { chosen = candidates[0] }
            return integration([chosen.path], note: "New Droid sessions pick the hooks up; a running session may ask you to review them in /hooks.",
                               detect: Detection(binaries: ["droid"], apps: [("Factory.app", nil)], paths: [".factory/settings.json", ".factory/hooks.json"]),
                               .shared(chosen, cleanup: candidates.filter { $0.path != chosen.path }, trust: nil))

        case "auggie":
            let path = h + "/.augment/settings.json"
            let file = shared(path, comments: true) { e in
                group(tools.contains(e) ? ".*" : nil, [("type", .string("command")), ("command", .string(cmd(e))), ("timeout", .int(5000))])
            }
            return integration([path], note: "Needs Auggie 0.27 or later. Takes effect the next time auggie starts.",
                               detect: Detection(binaries: ["auggie"], paths: [".augment/settings.json"]),
                               .shared(file, cleanup: [], trust: nil))

        case "copilot":
            let path = h + "/.copilot/hooks/agentawake.json"
            var hooks = JSONValue.object([])
            for e in events {
                var entry: [(String, JSONValue)] = [("type", .string("command"))]
                if e == "notification" { entry.append(("matcher", .string("permission_prompt|elicitation_dialog"))) }
                entry += [("bash", .string(cmd(e))), ("timeoutSec", .int(5))]
                hooks.set(e, .array([.obj(entry)]))
            }
            let content = JSONValue.obj([("version", .int(1)), ("hooks", hooks)]).serialized() + "\n"
            return integration([path], note: "Restart Copilot CLI sessions to load the hooks. VS Code's agent mode reads the same file.",
                               detect: Detection(binaries: ["copilot"], prefixed: [(".vscode/extensions", "github.copilot-chat")]),
                               .owned([(path, content)], root: nil, stop: h + "/.copilot/hooks"))

        case "cursor":
            let path = h + "/.cursor/hooks.json"
            let file = shared(path, defaults: [("version", .int(1))]) { e in
                .obj([("command", .string(cmd(e))), ("timeout", .int(5))])
            }
            return integration([path], note: "Cursor has no “needs you” hook, so Agent Awake hears only when work starts and finishes.",
                               detect: Detection(binaries: ["cursor-agent"], apps: [("Cursor.app", nil)], paths: [".cursor/cli-config.json"]),
                               .shared(file, cleanup: [], trust: nil))

        case "windsurf":
            let path = h + "/.codeium/windsurf/hooks.json"
            let file = shared(path) { e in .obj([("command", .string(cmd(e))), ("show_output", .bool(false))]) }
            return integration([path], note: "For the Cascade agent. Devin Local (the newer default agent) is a separate integration.",
                               detect: Detection(apps: [("Windsurf.app", nil), ("Devin.app", nil)], paths: [".codeium/windsurf"]),
                               .shared(file, cleanup: [], trust: nil))

        case "devin":
            let path = h + "/.config/devin/config.json"
            let file = shared(path) { e in
                group("", [("type", .string("command")), ("command", .string(cmd(e))), ("timeout", .int(5))])
            }
            return integration([path], note: nil,
                               detect: Detection(binaries: ["devin"], apps: [("Devin.app", nil)], paths: [".config/devin"]),
                               .shared(file, cleanup: [], trust: nil))

        case "kiro":
            let path = h + "/.kiro/hooks/agentawake.json"
            let hooks: [JSONValue] = events.map { e in
                .obj([("name", .string("agentawake-\(e)")), ("trigger", .string(e)), ("timeout", .int(5)),
                      ("action", .obj([("type", .string("command")), ("command", .string(cmd(e)))]))])
            }
            let content = JSONValue.obj([("version", .string("v1")), ("hooks", .array(hooks))]).serialized() + "\n"
            return integration([path], note: "Needs Kiro 1.0.182 or later (global hooks).",
                               detect: Detection(binaries: ["kiro-cli"], apps: [("Kiro.app", nil)]),
                               .owned([(path, content)], root: nil, stop: h + "/.kiro/hooks"))

        case "goose":
            let dir = h + "/.agents/plugins/agentawake"
            var hooks = JSONValue.object([])
            for e in events {
                hooks.set(e, .array([group(nil, [("type", .string("command")), ("command", .string(cmd(e))), ("timeout", .int(5))])]))
            }
            let manifest = JSONValue.obj([("name", .string("agentawake")), ("version", .string("1.0.0")),
                                          ("description", .string("Agent Awake: keeps the Mac awake while Goose works and pings you when it's done."))])
            let files = [(dir + "/plugin.json", manifest.serialized() + "\n"),
                         (dir + "/hooks/hooks.json", JSONValue.obj([("hooks", hooks)]).serialized() + "\n")]
            return integration(files.map(\.0), note: "Restart Goose to load the plugin.",
                               detect: Detection(binaries: ["goose"], apps: [("Goose.app", nil)], paths: [".config/goose/config.yaml"]),
                               .owned(files, root: dir, stop: h + "/.agents/plugins"))

        case "junie":
            let path = h + "/.junie/config.json"
            let file = shared(path) { e in
                var handler: [(String, JSONValue)] = [("type", .string("command")), ("command", .string(cmd(e))),
                                                     ("timeout", .int(e == "SessionEnd" ? 2 : 5))]
                if e == "UserPromptSubmit" || e == "Stop" { handler.append(("async", .bool(true))) }
                return group(nil, handler)
            }
            return integration([path], note: "Junie CLI only; the JetBrains IDE plugin doesn't run hooks.",
                               detect: Detection(binaries: ["junie"], paths: [".junie"]),
                               .shared(file, cleanup: [], trust: nil))

        case "opencode":
            let path = h + "/.config/opencode/plugins/agentawake.js"
            return plugin(path, PluginSources.opencode(name: spec.name, agent: spec.id, bin: shimPath(h)),
                          note: "Restart OpenCode to load the plugin.",
                          detect: Detection(binaries: ["opencode"], apps: [("OpenCode.app", nil)], paths: [".config/opencode", ".opencode/bin/opencode"]))

        case "kilo":
            let path = h + "/.config/kilo/plugin/agentawake.js"
            return plugin(path, PluginSources.opencode(name: spec.name, agent: spec.id, bin: shimPath(h)),
                          note: "Restart Kilo (or reload the VS Code window) to load the plugin.",
                          detect: Detection(binaries: ["kilo"], paths: [".config/kilo"],
                                            prefixed: [(".vscode/extensions", "kilocode.kilo-code-"), (".cursor/extensions", "kilocode.kilo-code-")]))

        case "amp":
            let path = h + "/.config/amp/plugins/agentawake.ts"
            return plugin(path, PluginSources.amp(bin: shimPath(h)),
                          note: "Run “plugins: reload” in Amp (Ctrl+O) or restart it.",
                          detect: Detection(binaries: ["amp"], apps: [("Amp.app", nil)], paths: [".config/amp", ".amp/bin/amp"]))

        case "omp":
            let path = h + "/.omp/agent/extensions/agentawake.ts"
            return plugin(path, PluginSources.omp(bin: shimPath(h)),
                          note: "Restart omp to load the extension.",
                          detect: Detection(binaries: ["omp"], paths: [".omp/agent"]))

        case "pi":
            let path = h + "/.pi/agent/extensions/agentawake.ts"
            return plugin(path, PluginSources.pi(bin: shimPath(h)),
                          note: "Needs pi 0.80.4 or later. Restart pi to load the extension.",
                          detect: Detection(binaries: ["pi"], paths: [".pi/agent"]))

        default:
            return nil
        }
    }

    /// Droid's hooks.json keeps events at the top level; tolerate a file already in the wrapped `{"hooks": {…}}` form.
    private static func droidContainer(_ path: String) -> [String] {
        guard let text = try? FileOps.read(path), let doc = try? JSONParser.parse(text, allowComments: true).value,
              let pairs = doc.objectPairs, case .object = doc["hooks"] ?? .null else { return [] }
        return pairs.allSatisfy({ $0.key == "hooks" || $0.value.arrayValue == nil }) ? ["hooks"] : []
    }
}
