import Foundation

/// What a hook event means to Agent Awake.
public enum HookAction: String, Codable, CaseIterable {
    case start       // a prompt was submitted: work begins
    case beat        // still working (tool use)
    case needsYou    // waiting on the user (permission, question)
    case stop        // the turn finished
    case failed      // the turn stopped on an error
    case end         // the session closed
}

/// An agent we can connect to. `events` maps the agent's own hook event names to actions; the installer
/// registers exactly these events, and `agentawake hook <id> <event>` interprets them. Plugin-based
/// agents (we write the plugin) call the hook with our own action names, so their map is the identity.
public struct AgentSpec {
    public let id: String
    public let name: String
    public let events: [(event: String, action: HookAction)]
    /// The pre-tool event the agent waits on before running a tool, where an empty reply means "no decision" (the
    /// tool runs, still asking the user if it would have): the hook holds there while the Mac is strained
    /// (`HookGate`). It's one of `events`, registered synchronously with a long timeout. nil = no safe gate.
    public let gate: String?
    /// Longest the agent lets a hook run, in seconds, when that's below `HookGate.budget` + margin.
    public let gateLimit: Double?

    public init(id: String, name: String, events: [(event: String, action: HookAction)], gate: String? = nil,
                gateLimit: Double? = nil) {
        self.id = id; self.name = name; self.events = events; self.gate = gate; self.gateLimit = gateLimit
    }

    public func action(for event: String) -> HookAction? {
        events.first { $0.event == event }?.action
    }
}

/// Gates (hook docs, 2026-10): every agent below with a `gate` treats an empty stdout and exit 0 as "no decision"
/// and lets the tool run when the hook times out. Not gated: Antigravity (PreToolUse must decide: "allow" skips
/// review, "ask" forces a prompt, no output or a timeout denies), Cursor (preToolUse needs a decision; invalid
/// output blocks), Windsurf (no hook timeout setting), Amp (`tool.call` must return "allow", and how that combines
/// with a permissions plugin's answer isn't defined).
public enum AgentCatalog {
    /// Plugin agents: our action names, plus `gate`, which the plugin awaits before each tool.
    private static let plugin: [(event: String, action: HookAction)] = HookAction.allCases.map { ($0.rawValue, $0) }
    private static let gatedPlugin = plugin + [("gate", .beat)]

    public static let all: [AgentSpec] = [
        AgentSpec(id: "claude", name: "Claude Code", events: [
            ("UserPromptSubmit", .start), ("PreToolUse", .beat), ("PostToolUse", .beat),
            ("PermissionRequest", .needsYou), ("Notification", .needsYou),
            ("Stop", .stop), ("StopFailure", .failed), ("SessionEnd", .end),
        ], gate: "PreToolUse"),
        AgentSpec(id: "codex", name: "Codex", events: [
            ("UserPromptSubmit", .start), ("PreToolUse", .beat), ("PostToolUse", .beat),
            ("PermissionRequest", .needsYou), ("Stop", .stop), ("SessionEnd", .end),
        ], gate: "PreToolUse"),
        AgentSpec(id: "gemini", name: "Gemini CLI", events: [
            ("BeforeAgent", .start), ("BeforeTool", .beat), ("AfterTool", .beat),
            ("Notification", .needsYou), ("AfterAgent", .stop), ("SessionEnd", .end),
        ], gate: "BeforeTool"),
        // Antigravity 2.0, the IDE and the agy CLI share ~/.gemini/config/hooks.json. No hook fires while it waits
        // for an approval (PreToolUse must decide, so we don't register it).
        AgentSpec(id: "antigravity", name: "Antigravity", events: [
            ("PreInvocation", .start), ("PostToolUse", .beat), ("PostInvocation", .beat), ("Stop", .stop),
        ]),
        AgentSpec(id: "qwen", name: "Qwen Code", events: [
            ("UserPromptSubmit", .start), ("PreToolUse", .beat), ("PostToolUse", .beat),
            ("PermissionRequest", .needsYou), ("Notification", .needsYou),
            ("Stop", .stop), ("StopFailure", .failed), ("SessionEnd", .end),
        ], gate: "PreToolUse"),
        AgentSpec(id: "droid", name: "Factory Droid", events: [
            ("UserPromptSubmit", .start), ("PreToolUse", .beat), ("PostToolUse", .beat),
            ("Notification", .needsYou), ("Stop", .stop), ("SessionEnd", .end),
        ], gate: "PreToolUse"),
        AgentSpec(id: "auggie", name: "Augment (Auggie)", events: [
            ("PromptSubmit", .start), ("PreToolUse", .beat), ("PostToolUse", .beat), ("Stop", .stop), ("SessionEnd", .end),
        ], gate: "PreToolUse"),
        AgentSpec(id: "copilot", name: "GitHub Copilot", events: [
            ("userPromptSubmitted", .start), ("preToolUse", .beat), ("postToolUse", .beat), ("notification", .needsYou),
            ("agentStop", .stop), ("errorOccurred", .failed), ("sessionEnd", .end),
        ], gate: "preToolUse"),
        AgentSpec(id: "cursor", name: "Cursor", events: [
            ("beforeSubmitPrompt", .start), ("postToolUse", .beat), ("stop", .stop), ("sessionEnd", .end),
        ]),
        AgentSpec(id: "windsurf", name: "Windsurf Cascade", events: [
            ("pre_user_prompt", .start), ("post_run_command", .beat), ("post_write_code", .beat),
            ("post_cascade_response", .stop),
        ]),
        AgentSpec(id: "devin", name: "Devin Local", events: [
            ("UserPromptSubmit", .start), ("PreToolUse", .beat), ("PostToolUse", .beat), ("PermissionRequest", .needsYou),
            ("Stop", .stop), ("SessionEnd", .end),
        ], gate: "PreToolUse"),
        AgentSpec(id: "kiro", name: "Kiro", events: [
            ("UserPromptSubmit", .start), ("PreToolUse", .beat), ("PostToolUse", .beat), ("Stop", .stop),
        ], gate: "PreToolUse"),
        AgentSpec(id: "goose", name: "Goose", events: [
            ("UserPromptSubmit", .start), ("PreToolUse", .beat), ("PostToolUse", .beat), ("Stop", .stop), ("SessionEnd", .end),
        ], gate: "PreToolUse"),
        AgentSpec(id: "junie", name: "Junie CLI", events: [
            ("UserPromptSubmit", .start), ("PreToolUse", .beat), ("Stop", .stop), ("StopFailure", .failed), ("SessionEnd", .end),
        ], gate: "PreToolUse"),
        AgentSpec(id: "opencode", name: "OpenCode", events: gatedPlugin, gate: "gate"),
        AgentSpec(id: "kilo", name: "Kilo Code", events: gatedPlugin, gate: "gate"),
        AgentSpec(id: "amp", name: "Amp", events: plugin),
        // omp blocks a tool whose tool_call handler runs past extensionHandlers.toolCallTimeoutMs (default 30 s).
        AgentSpec(id: "omp", name: "oh-my-pi", events: gatedPlugin, gate: "gate", gateLimit: 30),
        AgentSpec(id: "pi", name: "pi", events: gatedPlugin, gate: "gate"),
    ]

    public static func spec(_ id: String) -> AgentSpec? { all.first { $0.id == id } }
}
