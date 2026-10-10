import Foundation

/// Turns one agent hook invocation (`agentawake hook <agent> <event>` + the agent's JSON payload) into the
/// requests the app understands. Pure: the CLI supplies stdin, the environment, the agent's PID and the config.
///
/// Payload shapes differ per agent (see AgentCatalog for the event maps):
/// - session id: `session_id` (Claude, Codex, Gemini, Qwen, Droid, Devin, Kiro, Goose, Junie, our plugins),
///   `sessionId` (Copilot CLI), `conversation_id` (Cursor, Auggie), `trajectory_id` (Windsurf);
/// - working directory: `workspace_roots[0]` (Cursor, Auggie), `cwd`, `working_dir` (Goose), `project_path` (Junie),
///   else `DEVIN_PROJECT_DIR` / `CURSOR_PROJECT_DIR` / `PWD` from the environment (Devin, Windsurf);
/// - prompt: `prompt`, `submitted_prompt` (Qwen), `user_prompt` (Auggie), `tool_info.user_prompt` (Windsurf),
///   `message` on Goose's UserPromptSubmit, `USER_PROMPT` env (Kiro).
/// Our plugins (OpenCode, Kilo, Amp, omp, pi) send `{session_id, cwd, prompt?, parent_session_id?, message?}`.
public enum HookAdapter {
    public static func requests(agent: String, event: String, payload: Data, env: [String: String],
                                agentPID: Int32?, config: Config) -> [Request] {
        guard let spec = AgentCatalog.spec(agent), var action = spec.action(for: event) else { return [] }
        let p: Payload
        if payload.allSatisfy({ $0 == 32 || $0 == 9 || $0 == 10 || $0 == 13 }) {
            p = Payload([:])
        } else if let obj = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] {
            p = Payload(obj)
        } else {
            return []   // garbled or truncated: guessing a session from it would invent one
        }

        // Claude-format hooks also run inside Cursor and Devin with the host's payload: count them as the host's,
        // so they merge with the host's own hooks.
        var owner = spec
        if agent == "claude", let host = claudeHost(p, env), let hostSpec = AgentCatalog.spec(host) { owner = hostSpec }
        let id = owner.id
        let sessionID = self.sessionID(p, agent: id)
        let cwd = self.cwd(p, env: env)

        // Notification events carry many kinds; only a few mean the user is needed.
        if action == .needsYou, event.lowercased() == "notification", let allowed = notificationTypes[agent] {
            let type = p.str("notification_type")
            if agent == "droid", type == "idle_prompt" {
                action = .end   // Droid's only idle_prompt is a user cancel, after which Stop never fires
            } else if type.map({ !allowed.contains($0) }) ?? true {
                return []
            }
        }
        if id == "copilot", action == .failed, p.bool("recoverable") == true { action = .beat }

        // Subagents report into their parent's session and never start, finish or end it.
        let parentID = p.str("parent_session_id", "parentID", "parent_id")
        if parentID != nil || p.str("agent_id") != nil {
            guard let parent = parentID ?? sessionID else { return [] }
            let name = "\(id):\(parent)"
            if action == .needsYou {   // a subagent's permission prompt blocks the whole session on the user
                return [Request(cmd: "wait", name: name, agent: id, pid: agentPID, message: needsYouMessage(p, config, plugin: AgentCatalog.spec(id)?.action(for: "needsYou") == .needsYou))]
            }
            return [Request(cmd: "beat", name: name, agent: id, pid: agentPID, timeout: SessionStore.defaultTimeout)]
        }

        let name: String
        if id == "junie", let pid = agentPID {
            name = "\(id):pid\(pid)"   // Junie's Stop has no session id; one TUI process is one session
        } else if let s = sessionID {
            name = "\(id):\(s)"
        } else if let pid = agentPID {
            name = "\(id):pid\(pid)"
        } else if let c = cwd {
            name = "\(id):\(c)"
        } else {
            name = id
        }

        // Qwen also fires UserPromptSubmit for tool-result continuations; only `submitted_prompt` is the user's.
        let continuation = id == "qwen" && action == .start && p.str("submitted_prompt") == nil
        let prompt = continuation ? nil : self.prompt(p, agent: id, action: action, env: env)
        let label: String? = action == .start || prompt != nil
            ? self.label(prompt: prompt, agentName: owner.name, cwd: cwd, keepExisting: continuation, config: config)
            : nil
        // Names a session the app first hears about mid-stream (after a restart, or from a needs-you).
        let fallback = self.label(prompt: nil, agentName: owner.name, cwd: cwd, keepExisting: false,
                                  config: Config())

        switch action {
        case .start:
            return [Request(cmd: "beat", name: name, label: label, fallbackLabel: fallback, agent: id, pid: agentPID,
                            timeout: SessionStore.defaultTimeout)]
        case .beat:
            // Auggie and Droid send tool events from subagent sessions we can't tell apart: let those refresh a
            // known session but never create one.
            let creates = !(id == "auggie" || id == "droid")
            return [Request(cmd: "beat", name: name, label: label, fallbackLabel: fallback, agent: id, pid: agentPID,
                            timeout: creates ? SessionStore.defaultTimeout : nil)]
        case .needsYou:
            return [Request(cmd: "wait", name: name, label: label, fallbackLabel: fallback, agent: id, pid: agentPID,
                            message: needsYouMessage(p, config, plugin: AgentCatalog.spec(id)?.action(for: "needsYou") == .needsYou))]
        case .stop:
            let kind = stopKind(p)
            return [Request(cmd: "done", name: name, agent: id, kind: kind,
                            message: kind == .failed ? errorDetail(p) : nil)]
        case .failed:
            return [Request(cmd: "done", name: name, agent: id, kind: .failed, message: errorDetail(p))]
        case .end:
            return [Request(cmd: "done", name: name, agent: id, kind: .ended)]
        }
    }

    /// What the agent must read on stdout for the hook to be a no-op; nil = print nothing.
    public static func stdout(agent: String, event: String) -> String? {
        agent == "cursor" && event == "beforeSubmitPrompt" ? #"{"continue":true}"# : nil
    }

    static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env", "ksh", "tcsh", "csh"]

    /// The agent's process: the first ancestor of the hook (starting at `start`, its parent) that isn't a shell.
    public static func agentPID(from start: Int32,
                                name: (Int32) -> String? = { ProcessList.name(of: $0) },
                                parent: (Int32) -> Int32? = { ProcessList.parent(of: $0) }) -> Int32? {
        var pid = start
        for _ in 0..<8 {
            guard pid > 1, let n = name(pid) else { return nil }
            if !shells.contains(n) { return pid }
            guard let next = parent(pid) else { return nil }
            pid = next
        }
        return nil
    }

    // MARK: - Payload extraction

    /// Notification types that mean "needs you", per agent that has Notification events.
    static let notificationTypes: [String: Set<String>] = [
        "claude": ["permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"],
        "qwen": ["permission_prompt", "elicitation_dialog"],
        "droid": ["permission_prompt", "elicitation_dialog"],
        "copilot": ["permission_prompt", "elicitation_dialog"],
        "gemini": ["ToolPermission"],
    ]

    static func claudeHost(_ p: Payload, _ env: [String: String]) -> String? {
        // Cursor payloads always carry cursor_version and conversation_id; the env var alone could leak into
        // a terminal inside Cursor where the real Claude Code runs.
        if p.has("cursor_version") || (env["CURSOR_VERSION"] != nil && p.has("conversation_id")) { return "cursor" }
        if env["DEVIN_PROJECT_DIR"] != nil { return "devin" }
        return nil
    }

    static func sessionID(_ p: Payload, agent: String) -> String? {
        switch agent {
        case "cursor", "auggie": return p.str("conversation_id", "session_id", "sessionId")
        default: return p.str("session_id", "sessionId", "sessionID", "conversation_id", "trajectory_id")
        }
    }

    static func cwd(_ p: Payload, env: [String: String]) -> String? {
        p.first("workspace_roots") ?? p.first("workspaceRoots")
            ?? p.str("cwd", "working_dir", "project_path", "directory")
            ?? [env["DEVIN_PROJECT_DIR"], env["CURSOR_PROJECT_DIR"], env["PWD"]].lazy.compactMap { $0 }.first { !$0.isEmpty }
    }

    static func prompt(_ p: Payload, agent: String, action: HookAction, env: [String: String]) -> String? {
        if let s = p.str("submitted_prompt", "prompt", "user_prompt", "tool_info.user_prompt", "initialPrompt") { return s }
        guard action == .start else { return nil }
        if agent == "goose" { return p.str("message") }
        if agent == "kiro", let s = env["USER_PROMPT"], !s.isEmpty { return s }
        return nil
    }

    static func label(prompt: String?, agentName: String, cwd: String?, keepExisting: Bool, config: Config) -> String? {
        if config.effectiveTaskTitles {
            if let t = prompt.flatMap(promptTitle) { return t }
            if keepExisting { return nil }
        }
        guard let folder = cwd?.split(separator: "/").last else { return agentName }
        return "\(agentName) · \(folder)"
    }

    /// First meaningful line of a prompt, about 60 characters.
    static func promptTitle(_ prompt: String) -> String? {
        let line = prompt.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("<") }
        return line.map { clip($0, 60) }
    }

    static func needsYouMessage(_ p: Payload, _ config: Config, plugin: Bool = false) -> String? {
        if let tool = p.str("tool_name", "toolName") {
            switch tool {
            case "AskUserQuestion": return "It has a question for you."
            case "ExitPlanMode": return "Its plan is ready for your review."
            default: break
            }
            // Commands and paths can hold private text (even secrets), and pings pass through third-party
            // servers: show them only when the user opted into task titles.
            if config.effectiveTaskTitles, let detail = toolDetail(p) { return "Allow \(tool): \(detail)?" }
            return "Allow \(tool)?"
        }
        guard let message = p.str("message", "notification_message") else { return nil }
        if config.effectiveTaskTitles { return clip(message, 120) }
        // Plugins pass the agent's own wording: "Allow bash: <patterns>", "Approve <tool>: <reason>", a permission
        // title, or the question itself. Agents' native notification text is generic ("Claude needs your
        // permission to use Bash"). Keep plugin detail out of pings: tool name at most.
        guard plugin else { return clip(message, 120) }
        if ["Allow ", "Approve "].contains(where: message.hasPrefix) {
            let head = message.firstIndex(of: ":").map { String(message[..<$0]) } ?? message
            return head.hasSuffix("?") ? head : head + "?"
        }
        return "It is waiting for your answer."
    }

    static func toolDetail(_ p: Payload) -> String? {
        var input = p.dict("tool_input")
        if input == nil, let args = p.str("toolArgs"),
           let obj = (try? JSONSerialization.jsonObject(with: Data(args.utf8))) as? [String: Any] {
            input = obj
        }
        guard let input else { return nil }
        let detail = Payload(input).str("command", "file_path", "path", "url", "pattern", "description")
        return detail.flatMap { $0.split(whereSeparator: \.isNewline).first.map { clip(String($0), 60) } }
    }

    static func stopKind(_ p: Payload) -> DoneKind {
        switch p.str("status", "agent_stop_cause", "stopReason")?.lowercased() {
        case "error", "failed", "failure": return .failed
        case "aborted", "abort", "cancelled", "canceled", "interrupted": return .ended
        default: return .finished
        }
    }

    static func errorDetail(_ p: Payload) -> String? {
        let code = p.str("error", "error.message").map { s -> String in
            guard s.allSatisfy({ $0.isLowercase || $0 == "_" }) else { return s }
            let words = s.replacingOccurrences(of: "_", with: " ")
            return words.prefix(1).uppercased() + words.dropFirst()   // rate_limit -> Rate limit
        }
        let details = p.str("error_details", "error_message")
        guard let first = code ?? details else { return p.str("message").map { clip($0, 200) } }
        guard let code, let details, details != code else { return clip(first, 200) }
        return clip("\(code): \(details)", 200)
    }

    static func clip(_ s: String, _ n: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= n ? t : t.prefix(n - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Lenient accessors over a decoded JSON object. Keys may be dotted paths (`tool_info.user_prompt`).
struct Payload {
    let obj: [String: Any]
    init(_ obj: [String: Any]) { self.obj = obj }

    func value(_ path: String) -> Any? {
        var cur: Any? = obj
        for key in path.split(separator: ".") { cur = (cur as? [String: Any])?[String(key)] }
        return cur
    }
    func has(_ key: String) -> Bool { obj[key].map { !($0 is NSNull) } ?? false }
    /// First non-empty string among `keys`.
    func str(_ keys: String...) -> String? {
        for k in keys {
            if let s = value(k) as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        }
        return nil
    }
    func bool(_ key: String) -> Bool? { value(key) as? Bool }
    func dict(_ key: String) -> [String: Any]? { value(key) as? [String: Any] }
    /// First non-empty string of an array field.
    func first(_ key: String) -> String? { (value(key) as? [Any])?.lazy.compactMap { $0 as? String }.first { !$0.isEmpty } }
}
