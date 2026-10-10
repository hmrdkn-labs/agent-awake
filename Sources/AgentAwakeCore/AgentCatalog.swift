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

    public func action(for event: String) -> HookAction? {
        events.first { $0.event == event }?.action
    }
}

public enum AgentCatalog {
    private static let plugin: [(event: String, action: HookAction)] = HookAction.allCases.map { ($0.rawValue, $0) }

    public static let all: [AgentSpec] = [
        AgentSpec(id: "claude", name: "Claude Code", events: [
            ("UserPromptSubmit", .start), ("PreToolUse", .beat), ("PostToolUse", .beat),
            ("PermissionRequest", .needsYou), ("Notification", .needsYou),
            ("Stop", .stop), ("StopFailure", .failed), ("SessionEnd", .end),
        ]),
        AgentSpec(id: "codex", name: "Codex", events: [
            ("UserPromptSubmit", .start), ("PreToolUse", .beat), ("PostToolUse", .beat),
            ("PermissionRequest", .needsYou), ("Stop", .stop), ("SessionEnd", .end),
        ]),
        AgentSpec(id: "gemini", name: "Gemini CLI", events: [
            ("BeforeAgent", .start), ("BeforeTool", .beat), ("AfterTool", .beat),
            ("Notification", .needsYou), ("AfterAgent", .stop), ("SessionEnd", .end),
        ]),
        AgentSpec(id: "qwen", name: "Qwen Code", events: [
            ("UserPromptSubmit", .start), ("PreToolUse", .beat), ("PostToolUse", .beat),
            ("PermissionRequest", .needsYou), ("Notification", .needsYou),
            ("Stop", .stop), ("StopFailure", .failed), ("SessionEnd", .end),
        ]),
        AgentSpec(id: "droid", name: "Factory Droid", events: [
            ("UserPromptSubmit", .start), ("PreToolUse", .beat), ("PostToolUse", .beat),
            ("Notification", .needsYou), ("Stop", .stop), ("SessionEnd", .end),
        ]),
        AgentSpec(id: "auggie", name: "Augment (Auggie)", events: [
            ("PromptSubmit", .start), ("PostToolUse", .beat), ("Stop", .stop), ("SessionEnd", .end),
        ]),
        AgentSpec(id: "copilot", name: "GitHub Copilot", events: [
            ("userPromptSubmitted", .start), ("postToolUse", .beat), ("notification", .needsYou),
            ("agentStop", .stop), ("errorOccurred", .failed), ("sessionEnd", .end),
        ]),
        AgentSpec(id: "cursor", name: "Cursor", events: [
            ("beforeSubmitPrompt", .start), ("postToolUse", .beat), ("stop", .stop), ("sessionEnd", .end),
        ]),
        AgentSpec(id: "windsurf", name: "Windsurf Cascade", events: [
            ("pre_user_prompt", .start), ("post_run_command", .beat), ("post_write_code", .beat),
            ("post_cascade_response", .stop),
        ]),
        AgentSpec(id: "devin", name: "Devin Local", events: [
            ("UserPromptSubmit", .start), ("PostToolUse", .beat), ("PermissionRequest", .needsYou),
            ("Stop", .stop), ("SessionEnd", .end),
        ]),
        AgentSpec(id: "kiro", name: "Kiro", events: [
            ("UserPromptSubmit", .start), ("PostToolUse", .beat), ("Stop", .stop),
        ]),
        AgentSpec(id: "goose", name: "Goose", events: [
            ("UserPromptSubmit", .start), ("PostToolUse", .beat), ("Stop", .stop), ("SessionEnd", .end),
        ]),
        AgentSpec(id: "junie", name: "Junie CLI", events: [
            ("UserPromptSubmit", .start), ("Stop", .stop), ("StopFailure", .failed), ("SessionEnd", .end),
        ]),
        AgentSpec(id: "opencode", name: "OpenCode", events: plugin),
        AgentSpec(id: "kilo", name: "Kilo Code", events: plugin),
        AgentSpec(id: "amp", name: "Amp", events: plugin),
        AgentSpec(id: "omp", name: "oh-my-pi", events: plugin),
        AgentSpec(id: "pi", name: "pi", events: plugin),
    ]

    public static func spec(_ id: String) -> AgentSpec? { all.first { $0.id == id } }
}
