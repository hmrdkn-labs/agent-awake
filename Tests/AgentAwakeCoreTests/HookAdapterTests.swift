import XCTest
@testable import AgentAwakeCore

/// Payloads are the shapes documented in the hook research for each agent (docs examples or source schemas).
final class HookAdapterTests: XCTestCase {
    var env: [String: String] = ["PWD": "/Users/me/fallback"]
    var config = Config()

    func run(_ agent: String, _ event: String, _ json: String, pid: Int32? = 4242) -> [Request] {
        HookAdapter.requests(agent: agent, event: event, payload: Data(json.utf8), env: env, agentPID: pid, config: config)
    }

    func check(_ got: [Request], _ want: [Request], file: StaticString = #filePath, line: UInt = #line) {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let s = { (rs: [Request]) in rs.map { String(decoding: try! enc.encode($0), as: UTF8.self) } }
        XCTAssertEqual(s(got), s(want), file: file, line: line)
    }

    func beat(_ name: String, _ agent: String, label: String? = nil, pid: Int32? = 4242, timeout: Double? = SessionStore.defaultTimeout) -> Request {
        Request(cmd: "beat", name: name, label: label, agent: agent, pid: pid, timeout: timeout)
    }
    func wait(_ name: String, _ agent: String, _ message: String?, label: String? = nil, pid: Int32? = 4242) -> Request {
        Request(cmd: "wait", name: name, label: label, agent: agent, pid: pid, message: message)
    }
    func done(_ name: String, _ agent: String, _ kind: DoneKind, _ message: String? = nil) -> Request {
        Request(cmd: "done", name: name, agent: agent, kind: kind, message: message)
    }

    // MARK: Claude Code

    let claudeBase = #""session_id":"abc123","transcript_path":"/Users/me/.claude/projects/x/00893aaf.jsonl","cwd":"/Users/me/project""#

    func testClaudePromptStartsWithFolderLabel() {
        check(run("claude", "UserPromptSubmit", #"{\#(claudeBase),"permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"Write a function to calculate the factorial of a number"}"#),
              [beat("claude:abc123", "claude", label: "Claude Code · project")])
    }

    func testClaudePromptTitleWhenTaskTitlesOn() {
        config.taskTitles = true
        check(run("claude", "UserPromptSubmit", #"{\#(claudeBase),"hook_event_name":"UserPromptSubmit","prompt":"Write a function to calculate the factorial of a number"}"#),
              [beat("claude:abc123", "claude", label: "Write a function to calculate the factorial of a number")])
        let long = String(repeating: "refactor the parser ", count: 10)
        let got = run("claude", "UserPromptSubmit", #"{\#(claudeBase),"prompt":"\n  <pasted_content id=1>\n\#(long)\nsecond line"}"#)
        XCTAssertEqual(got.first?.label, "refactor the parser refactor the parser refactor the parser…")
        XCTAssertEqual(got.first?.label?.count, 60)
    }

    func testClaudeToolEventsBeatWithoutLabel() {
        check(run("claude", "PreToolUse", #"{\#(claudeBase),"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test"},"tool_use_id":"t1"}"#),
              [beat("claude:abc123", "claude")])
        check(run("claude", "PostToolUse", #"{\#(claudeBase),"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":{"stdout":"ok"}}"#),
              [beat("claude:abc123", "claude")])
    }

    let permissionRequest = #"{"session_id":"abc123","transcript_path":"...","cwd":"/Users/me/project","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf node_modules","description":"Remove node_modules directory"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"rm -rf node_modules"}],"behavior":"allow","destination":"localSettings"}]}"#

    func testClaudePermissionRequestNeedsYouWithoutPrivateDetailByDefault() {
        check(run("claude", "PermissionRequest", permissionRequest), [wait("claude:abc123", "claude", "Allow Bash?")])
        config.taskTitles = true
        check(run("claude", "PermissionRequest", permissionRequest), [wait("claude:abc123", "claude", "Allow Bash: rm -rf node_modules?")])
        check(run("claude", "PermissionRequest", #"{"session_id":"abc123","cwd":"/p","tool_name":"AskUserQuestion","tool_input":{}}"#),
              [wait("claude:abc123", "claude", "It has a question for you.")])
    }

    func testClaudeNotificationOnlyCountsWhenTheUserIsNeeded() {
        check(run("claude", "Notification", #"{"session_id":"abc123","transcript_path":"...","cwd":"/Users/me/project","hook_event_name":"Notification","message":"Claude needs your permission","title":"Permission needed","notification_type":"permission_prompt"}"#),
              [wait("claude:abc123", "claude", "Claude needs your permission")])
        for type in ["elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"] {
            XCTAssertEqual(run("claude", "Notification", #"{"session_id":"abc123","message":"m","notification_type":"\#(type)"}"#).first?.cmd, "wait", type)
        }
        for type in ["idle_prompt", "auth_success", "elicitation_complete", "agent_completed", "quota_auto_resume_fired"] {
            check(run("claude", "Notification", #"{"session_id":"abc123","cwd":"/p","hook_event_name":"Notification","message":"Claude is waiting for your input","notification_type":"\#(type)"}"#), [])
        }
        check(run("claude", "Notification", #"{"session_id":"abc123","message":"untyped"}"#), [])
    }

    func testClaudeStopFailureAndSessionEnd() {
        check(run("claude", "Stop", #"{"session_id":"abc123","transcript_path":"~/.claude/projects/.../x.jsonl","cwd":"/Users/me","permission_mode":"default","hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"I've completed the refactoring. Here's a summary...","background_tasks":[{"id":"task-001","type":"shell","status":"running","description":"tail logs","command":"tail -f /var/log/syslog"}],"session_crons":[{"id":"cron-001","schedule":"0 9 * * 1-5","recurring":true,"prompt":"check the build"}]}"#),
              [done("claude:abc123", "claude", .finished)])
        check(run("claude", "StopFailure", #"{"session_id":"abc123","transcript_path":"...","cwd":"/Users/me","hook_event_name":"StopFailure","error":"rate_limit","error_details":"429 Too Many Requests","last_assistant_message":"API Error: Rate limit reached"}"#),
              [done("claude:abc123", "claude", .failed, "Rate limit: 429 Too Many Requests")])
        check(run("claude", "SessionEnd", #"{"session_id":"abc123","transcript_path":"...","cwd":"/Users/me","hook_event_name":"SessionEnd","reason":"other"}"#),
              [done("claude:abc123", "claude", .ended)])
    }

    func testClaudeSubagentOnlyBeatsTheParent() {
        let sub = #""session_id":"abc123","cwd":"/Users/me/project","agent_id":"agent-7","agent_type":"Explore""#
        check(run("claude", "PreToolUse", #"{\#(sub),"hook_event_name":"PreToolUse","tool_name":"Grep","tool_input":{"pattern":"x"}}"#),
              [beat("claude:abc123", "claude")])
        check(run("claude", "Stop", #"{\#(sub),"hook_event_name":"Stop"}"#), [beat("claude:abc123", "claude")])
        check(run("claude", "SessionEnd", #"{\#(sub),"reason":"other"}"#), [beat("claude:abc123", "claude")])
        // A subagent's permission prompt still blocks the session on the user.
        check(run("claude", "PermissionRequest", #"{\#(sub),"tool_name":"Bash","tool_input":{"command":"ls"}}"#),
              [wait("claude:abc123", "claude", "Allow Bash?")])
        check(run("claude", "PreToolUse", #"{"agent_id":"agent-7","tool_name":"Grep"}"#), [])   // parent unknown
    }

    func testUnknownAgentOrEventIsIgnored() {
        check(run("claude", "SubagentStop", #"{"session_id":"abc123"}"#), [])
        check(run("nope", "Stop", #"{"session_id":"abc123"}"#), [])
        check(run("claude", "Stop", "not json"), [])
    }

    func testMissingPayloadFallsBackToPidThenCwd() {
        check(run("claude", "Stop", ""), [done("claude:pid4242", "claude", .finished)])
        check(run("claude", "Stop", "{}", pid: nil), [done("claude:/Users/me/fallback", "claude", .finished)])
    }

    // MARK: Codex

    func testCodexLifecycle() {
        let base = #""session_id":"thr_123","transcript_path":"/workspace/.codex/rollout.jsonl","cwd":"/workspace","model":"gpt-5","permission_mode":"default""#
        check(run("codex", "UserPromptSubmit", #"{\#(base),"hook_event_name":"UserPromptSubmit","turn_id":"t1","prompt":"Rename foo to bar"}"#),
              [beat("codex:thr_123", "codex", label: "Codex · workspace")])
        check(run("codex", "PreToolUse", #"{\#(base),"hook_event_name":"PreToolUse","turn_id":"t1","tool_name":"Bash","tool_input":{"command":"cargo build"},"tool_use_id":"u1"}"#),
              [beat("codex:thr_123", "codex")])
        check(run("codex", "PermissionRequest", #"{\#(base),"hook_event_name":"PermissionRequest","turn_id":"t1","tool_name":"apply_patch","tool_input":{"description":"edit main.rs"}}"#),
              [wait("codex:thr_123", "codex", "Allow apply_patch?")])
        check(run("codex", "Stop", #"{\#(base),"turn_id":"t1","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":null}"#),
              [done("codex:thr_123", "codex", .finished)])
        check(run("codex", "SessionEnd", #"{"session_id":"thr_123","transcript_path":"/workspace/.codex/rollout.jsonl","cwd":"/workspace","hook_event_name":"SessionEnd","reason":"other"}"#),
              [done("codex:thr_123", "codex", .ended)])
    }

    func testCodexSubagentPromptIsAHeartbeatWithoutLabel() {
        config.taskTitles = true
        check(run("codex", "UserPromptSubmit", #"{"session_id":"thr_123","cwd":"/workspace","hook_event_name":"UserPromptSubmit","turn_id":"t2","agent_id":"sub-1","agent_type":"worker","prompt":"look at tests"}"#),
              [beat("codex:thr_123", "codex")])
    }

    // MARK: Cursor

    let cursorBase = #""conversation_id":"conv-1","generation_id":"gen-1","model":"claude-4","hook_event_name":"%@","cursor_version":"1.7.2","workspace_roots":["/Users/me/repo"],"user_email":"me@example.com","transcript_path":null"#

    func cursor(_ event: String, _ extra: String) -> String {
        "{" + cursorBase.replacingOccurrences(of: "%@", with: event) + (extra.isEmpty ? "" : "," + extra) + "}"
    }

    func testCursorLifecycle() {
        env["CURSOR_VERSION"] = "1.7.2"; env["CURSOR_PROJECT_DIR"] = "/Users/me/repo"
        check(run("cursor", "beforeSubmitPrompt", cursor("beforeSubmitPrompt", #""prompt":"fix the login bug","attachments":[{"type":"file","file_path":"/Users/me/repo/a.ts"}]"#)),
              [beat("cursor:conv-1", "cursor", label: "Cursor · repo")])
        check(run("cursor", "postToolUse", cursor("postToolUse", #""tool_name":"Shell","tool_input":{"command":"ls"},"tool_output":"a","tool_use_id":"x","cwd":"/Users/me/repo/sub","duration":12"#)),
              [beat("cursor:conv-1", "cursor")])
        check(run("cursor", "stop", cursor("stop", #""status":"completed","loop_count":0"#)), [done("cursor:conv-1", "cursor", .finished)])
        check(run("cursor", "stop", cursor("stop", #""status":"error","loop_count":0"#)), [done("cursor:conv-1", "cursor", .failed)])
        check(run("cursor", "stop", cursor("stop", #""status":"aborted","loop_count":0"#)), [done("cursor:conv-1", "cursor", .ended)])
        check(run("cursor", "sessionEnd", cursor("sessionEnd", #""session_id":"conv-1","reason":"window_close","duration_ms":5000,"is_background_agent":false,"final_status":"completed""#)),
              [done("cursor:conv-1", "cursor", .ended)])
    }

    func testCursorBeforeSubmitPromptPrintsTheDocumentedNoOp() {
        XCTAssertEqual(HookAdapter.stdout(agent: "cursor", event: "beforeSubmitPrompt"), #"{"continue":true}"#)
        XCTAssertNil(HookAdapter.stdout(agent: "cursor", event: "stop"))
        XCTAssertNil(HookAdapter.stdout(agent: "claude", event: "UserPromptSubmit"))
    }

    func testClaudeHooksRunByCursorMergeWithCursorSession() {
        env["CURSOR_VERSION"] = "1.7.2"; env["CLAUDE_PROJECT_DIR"] = "/Users/me/repo"
        let native = run("cursor", "beforeSubmitPrompt", cursor("beforeSubmitPrompt", #""prompt":"fix it""#))
        let viaClaude = run("claude", "UserPromptSubmit", cursor("beforeSubmitPrompt", #""prompt":"fix it""#))
        check(viaClaude, native)
        check(run("claude", "Stop", cursor("stop", #""status":"completed","loop_count":0"#)), [done("cursor:conv-1", "cursor", .finished)])
        // Env alone is enough when the payload is Cursor's (conversation_id) even without cursor_version.
        check(run("claude", "SessionEnd", #"{"conversation_id":"conv-1","workspace_roots":["/Users/me/repo"],"reason":"user_close"}"#),
              [done("cursor:conv-1", "cursor", .ended)])
    }

    func testRealClaudeInsideCursorTerminalStaysClaude() {
        env["CURSOR_VERSION"] = "1.7.2"
        check(run("claude", "Stop", #"{\#(claudeBase),"hook_event_name":"Stop"}"#), [done("claude:abc123", "claude", .finished)])
    }

    // MARK: Devin Local

    func testClaudeHooksRunByDevinMergeWithDevinSession() {
        env["DEVIN_PROJECT_DIR"] = "/Users/me/proj"
        let payload = #"{"hook_event_name":"UserPromptSubmit","session_id":"dv-1","prompt_id":"p1","prompt":"add tests"}"#
        let native = run("devin", "UserPromptSubmit", payload)
        check(native, [beat("devin:dv-1", "devin", label: "Devin Local · proj")])
        check(run("claude", "UserPromptSubmit", payload), native)
        check(run("devin", "PermissionRequest", #"{"hook_event_name":"PermissionRequest","session_id":"dv-1","prompt_id":"p1","tool_name":"exec","tool_input":{"command":"make"}}"#),
              [wait("devin:dv-1", "devin", "Allow exec?")])
        check(run("claude", "Stop", #"{"hook_event_name":"Stop","session_id":"dv-1","prompt_id":"p1","stop_hook_active":false}"#),
              [done("devin:dv-1", "devin", .finished)])
    }

    // MARK: GitHub Copilot

    func testCopilotCamelCase() {
        let base = #""sessionId":"cp-1","timestamp":1704614400000,"cwd":"/tmp/app""#
        check(run("copilot", "userPromptSubmitted", #"{\#(base),"prompt":"add a README"}"#),
              [beat("copilot:cp-1", "copilot", label: "GitHub Copilot · app")])
        check(run("copilot", "postToolUse", #"{\#(base),"toolName":"bash","toolArgs":"{\"command\":\"ls\"}","toolResult":{"resultType":"success","textResultForLlm":"a"}}"#),
              [beat("copilot:cp-1", "copilot")])
        check(run("copilot", "notification", #"{\#(base),"hook_event_name":"Notification","message":"Copilot needs permission to run bash","title":"Permission","notification_type":"permission_prompt"}"#),
              [wait("copilot:cp-1", "copilot", "Copilot needs permission to run bash")])
        check(run("copilot", "notification", #"{\#(base),"hook_event_name":"Notification","message":"idle","notification_type":"agent_idle"}"#), [])
        check(run("copilot", "agentStop", #"{\#(base),"transcriptPath":"/x","stopReason":"end_turn","stop_hook_active":false}"#),
              [done("copilot:cp-1", "copilot", .finished)])
        check(run("copilot", "errorOccurred", #"{\#(base),"error":{"message":"Model unavailable","name":"ApiError"},"errorContext":"model_call","recoverable":false}"#),
              [done("copilot:cp-1", "copilot", .failed, "Model unavailable")])
        check(run("copilot", "errorOccurred", #"{\#(base),"error":{"message":"retrying","name":"ApiError"},"recoverable":true}"#),
              [beat("copilot:cp-1", "copilot")])
        check(run("copilot", "sessionEnd", #"{\#(base),"reason":"user_exit"}"#), [done("copilot:cp-1", "copilot", .ended)])
    }

    func testCopilotToolArgsDetailWhenTitlesOn() {
        config.taskTitles = true
        XCTAssertEqual(HookAdapter.needsYouMessage(Payload(["toolName": "bash", "toolArgs": #"{"command":"ls -la"}"#]), config),
                       "Allow bash: ls -la?")
    }

    // MARK: Gemini CLI

    func testGemini() {
        let base = #""session_id":"g-1","transcript_path":"","cwd":"/tmp/test","timestamp":"2026-10-10T10:00:00Z""#
        check(run("gemini", "BeforeAgent", #"{\#(base),"hook_event_name":"BeforeAgent","prompt":"explain this repo"}"#),
              [beat("gemini:g-1", "gemini", label: "Gemini CLI · test")])
        check(run("gemini", "BeforeTool", #"{ "session_id": "g-1", "cwd": "/tmp/test", "hook_event_name": "BeforeTool", "tool_name": "write_file", "tool_input": { "file_path": "test.txt", "content": "Test content" } }"#),
              [beat("gemini:g-1", "gemini")])
        check(run("gemini", "Notification", #"{\#(base),"hook_event_name":"Notification","notification_type":"ToolPermission","message":"Tool run_shell_command requires execution","details":{"type":"exec","title":"Shell","command":"npm test","rootCommand":"npm"}}"#),
              [wait("gemini:g-1", "gemini", "Tool run_shell_command requires execution")])
        check(run("gemini", "AfterAgent", #"{\#(base),"hook_event_name":"AfterAgent","prompt":"explain this repo","prompt_response":"It is...","stop_hook_active":false}"#),
              [done("gemini:g-1", "gemini", .finished)])
        check(run("gemini", "SessionEnd", #"{\#(base),"hook_event_name":"SessionEnd","reason":"exit"}"#), [done("gemini:g-1", "gemini", .ended)])
    }

    // MARK: Qwen Code

    func testQwen() {
        config.taskTitles = true
        let base = #""session_id":"q-1","transcript_path":"/t","cwd":"/Users/me/q","hook_event_name":"%@","timestamp":"t","permission_mode":"default""#
        func q(_ e: String, _ extra: String) -> String { "{" + base.replacingOccurrences(of: "%@", with: e) + "," + extra + "}" }
        check(run("qwen", "UserPromptSubmit", q("UserPromptSubmit", #""prompt":"build it","submitted_prompt":"build it","prompt_id":"p1""#)),
              [beat("qwen:q-1", "qwen", label: "build it")])
        // Tool-result continuation: keeps the title set by the real prompt.
        check(run("qwen", "UserPromptSubmit", q("UserPromptSubmit", #""prompt":"[tool result]","prompt_id":"p1""#)),
              [beat("qwen:q-1", "qwen")])
        check(run("qwen", "Notification", q("Notification", #""message":"Qwen Code needs your permission to use Shell","notification_type":"permission_prompt""#)),
              [wait("qwen:q-1", "qwen", "Qwen Code needs your permission to use Shell")])
        check(run("qwen", "Notification", q("Notification", #""message":"Qwen Code is waiting for your input","notification_type":"idle_prompt""#)), [])
        check(run("qwen", "StopFailure", q("StopFailure", #""error":"loop_detected""#)), [done("qwen:q-1", "qwen", .failed, "Loop detected")])
        check(run("qwen", "PreToolUse", q("PreToolUse", #""tool_name":"Shell","tool_input":{},"tool_use_id":"u","agent_id":"sub""#)),
              [beat("qwen:q-1", "qwen")])
    }

    // MARK: Factory Droid

    func testDroid() {
        let base = #""session_id":"abc123","transcript_path":"/Users/.../session.jsonl","cwd":"/Users/me/project","permission_mode":"off""#
        check(run("droid", "UserPromptSubmit", #"{\#(base),"hook_event_name":"UserPromptSubmit","prompt":"hi","has_images":false,"message_id":"m"}"#),
              [beat("droid:abc123", "droid", label: "Factory Droid · project")])
        // Tool events may come from subagent sessions: refresh only, never create.
        check(run("droid", "PreToolUse", #"{\#(base),"hook_event_name":"PreToolUse","tool_name":"Create","tool_input":{"file_path":"/Users/me/project/file.txt","content":"file content"}}"#),
              [beat("droid:abc123", "droid", timeout: nil)])
        check(run("droid", "Notification", #"{\#(base),"hook_event_name":"Notification","message":"Factory CLI needs permission to execute 1 tool(s)","notification_type":"permission_prompt"}"#),
              [wait("droid:abc123", "droid", "Factory CLI needs permission to execute 1 tool(s)")])
        // Cancel: idle_prompt is the only signal (no Stop follows).
        check(run("droid", "Notification", #"{\#(base),"hook_event_name":"Notification","message":"Agent stopped by user and is waiting for input","notification_type":"idle_prompt"}"#),
              [done("droid:abc123", "droid", .ended)])
        check(run("droid", "Stop", #"{\#(base),"hook_event_name":"Stop","stop_hook_active":false,"tool_execution_count":3,"elapsed_time":5000}"#),
              [done("droid:abc123", "droid", .finished)])
    }

    // MARK: Auggie

    func testAuggie() {
        check(run("auggie", "PromptSubmit", #"{"hook_event_name":"PromptSubmit","conversation_id":"conv-xyz789","workspace_roots":["/Users/username/project"],"user_prompt":"fix ci"}"#),
              [beat("auggie:conv-xyz789", "auggie", label: "Augment (Auggie) · project")])
        check(run("auggie", "PostToolUse", #"{"hook_event_name":"PostToolUse","conversation_id":"conv-xyz789","workspace_roots":["/Users/username/project"],"tool_name":"launch-process","tool_input":{},"tool_output":"ok"}"#),
              [beat("auggie:conv-xyz789", "auggie", timeout: nil)])
        check(run("auggie", "Stop", #"{"hook_event_name":"Stop","conversation_id":"conv-xyz789","workspace_roots":["/Users/username/project"],"agent_stop_cause":"end_turn"}"#),
              [done("auggie:conv-xyz789", "auggie", .finished)])
        check(run("auggie", "Stop", #"{"hook_event_name":"Stop","conversation_id":"conv-xyz789","workspace_roots":[],"agent_stop_cause":"interrupted"}"#),
              [done("auggie:conv-xyz789", "auggie", .ended)])
    }

    // MARK: Windsurf, Kiro, Goose, Junie

    func testWindsurfUsesTrajectoryAndPwd() {
        env["PWD"] = "/Users/me/ws"
        let base = #""trajectory_id":"traj-1","execution_id":"ex-1","timestamp":"2026-10-10T10:00:00Z","model_name":"swe-1""#
        check(run("windsurf", "pre_user_prompt", #"{"agent_action_name":"pre_user_prompt",\#(base),"tool_info":{"user_prompt":"make the tests pass"}}"#),
              [beat("windsurf:traj-1", "windsurf", label: "Windsurf Cascade · ws")])
        config.taskTitles = true
        XCTAssertEqual(run("windsurf", "pre_user_prompt", #"{"agent_action_name":"pre_user_prompt",\#(base),"tool_info":{"user_prompt":"make the tests pass"}}"#).first?.label,
                       "make the tests pass")
        check(run("windsurf", "post_run_command", #"{"agent_action_name":"post_run_command",\#(base),"tool_info":{"command_line":"npm test","cwd":"/Users/me/ws"}}"#),
              [beat("windsurf:traj-1", "windsurf")])
        check(run("windsurf", "post_cascade_response", #"{"agent_action_name":"post_cascade_response",\#(base),"tool_info":{"response":"Done."}}"#),
              [done("windsurf:traj-1", "windsurf", .finished)])
    }

    func testKiro() {
        check(run("kiro", "UserPromptSubmit", #"{"hook_event_name":"UserPromptSubmit","cwd":"/Users/me/k","session_id":"k-1","prompt":"spec it"}"#),
              [beat("kiro:k-1", "kiro", label: "Kiro · k")])
        check(run("kiro", "PostToolUse", #"{"hook_event_name":"PostToolUse","cwd":"/Users/me/k","session_id":"k-1","tool_name":"fs_write","tool_input":{},"tool_response":{}}"#),
              [beat("kiro:k-1", "kiro")])
        check(run("kiro", "Stop", #"{"hook_event_name":"Stop","cwd":"/Users/me/k","session_id":"k-1"}"#), [done("kiro:k-1", "kiro", .finished)])
    }

    func testGoosePromptIsInMessage() {
        config.taskTitles = true
        check(run("goose", "UserPromptSubmit", #"{"event":"UserPromptSubmit","session_id":"20261010_1","message":"summarize the logs","working_dir":"/Users/me/g"}"#),
              [beat("goose:20261010_1", "goose", label: "summarize the logs")])
        config.taskTitles = false
        check(run("goose", "UserPromptSubmit", #"{"event":"UserPromptSubmit","session_id":"20261010_1","message":"summarize the logs","working_dir":"/Users/me/g"}"#),
              [beat("goose:20261010_1", "goose", label: "Goose · g")])
        check(run("goose", "PostToolUse", #"{"event":"PostToolUse","session_id":"20261010_1","tool_name":"developer__shell","tool_input":{"command":"ls"},"tool_call_id":"c1"}"#),
              [beat("goose:20261010_1", "goose")])
        check(run("goose", "Stop", #"{"event":"Stop","session_id":"20261010_1","last_assistant_message":"Done","working_dir":"/Users/me/g"}"#),
              [done("goose:20261010_1", "goose", .finished)])
        check(run("goose", "SessionEnd", #"{"event":"SessionEnd","session_id":"20261010_1"}"#), [done("goose:20261010_1", "goose", .ended)])
    }

    func testJunieStopWithoutSessionIdMatchesItsStart() {
        let start = run("junie", "UserPromptSubmit", #"{"hook_event_name":"UserPromptSubmit","session_id":"j-1","cwd":"/Users/me/j","project_path":"/Users/me/j","prompt":"go"}"#, pid: 777)
        check(start, [beat("junie:pid777", "junie", label: "Junie CLI · j", pid: 777)])
        check(run("junie", "Stop", #"{"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Done"}"#, pid: 777),
              [done("junie:pid777", "junie", .finished)])
        check(run("junie", "StopFailure", #"{"hook_event_name":"StopFailure","error":"server_error","error_details":"502 Bad Gateway"}"#, pid: 777),
              [done("junie:pid777", "junie", .failed, "Server error: 502 Bad Gateway")])
        // No PID: session id, else the working directory.
        check(run("junie", "SessionEnd", #"{"hook_event_name":"SessionEnd","session_id":"j-1","reason":"other"}"#, pid: nil),
              [done("junie:j-1", "junie", .ended)])
        check(run("junie", "Stop", #"{"hook_event_name":"Stop","stop_hook_active":false}"#, pid: nil),
              [done("junie:/Users/me/fallback", "junie", .finished)])
    }

    // MARK: Plugins (OpenCode, Kilo, Amp, omp, pi): our action names, our payload

    func testPluginIdentityEvents() {
        let names = ["opencode": "OpenCode", "kilo": "Kilo Code", "amp": "Amp", "omp": "oh-my-pi", "pi": "pi"]
        for (id, name) in names {
            let s = #""session_id":"ses_1","cwd":"/Users/me/app""#
            check(run(id, "start", #"{\#(s),"prompt":"ship it"}"#), [beat("\(id):ses_1", id, label: "\(name) · app")])
            check(run(id, "beat", #"{\#(s)}"#), [beat("\(id):ses_1", id)])
            check(run(id, "needsYou", #"{\#(s),"message":"Allow bash?"}"#), [wait("\(id):ses_1", id, "Allow bash?")])
            check(run(id, "stop", #"{\#(s)}"#), [done("\(id):ses_1", id, .finished)])
            check(run(id, "stop", #"{\#(s),"status":"cancelled"}"#), [done("\(id):ses_1", id, .ended)])
            check(run(id, "failed", #"{\#(s),"message":"Provider returned 500"}"#), [done("\(id):ses_1", id, .failed, "Provider returned 500")])
            check(run(id, "end", #"{\#(s)}"#), [done("\(id):ses_1", id, .ended)])
            // Child session: beats the parent, never ends it.
            check(run(id, "stop", #"{"session_id":"ses_child","parent_session_id":"ses_1","cwd":"/Users/me/app"}"#), [beat("\(id):ses_1", id)])
            check(run(id, "Stop", #"{\#(s)}"#), [])   // plugins only speak our action names
        }
    }

    // MARK: Whole catalog sanity

    func testEveryCatalogEventProducesARequest() {
        for spec in AgentCatalog.all {
            for (event, action) in spec.events {
                let json = event.lowercased() == "notification"
                    ? #"{"session_id":"s","cwd":"/p","notification_type":"\#(spec.id == "gemini" ? "ToolPermission" : "permission_prompt")","message":"m"}"#
                    : #"{"session_id":"s","sessionId":"s","conversation_id":"s","trajectory_id":"s","cwd":"/p"}"#
                let got = run(spec.id, event, json, pid: nil)
                XCTAssertEqual(got.count, 1, "\(spec.id) \(event)")
                let want = ["start": "beat", "beat": "beat", "needsYou": "wait", "stop": "done", "failed": "done", "end": "done"]
                XCTAssertEqual(got.first?.cmd, want[action.rawValue], "\(spec.id) \(event)")
                XCTAssertEqual(got.first?.name, "\(spec.id):s", "\(spec.id) \(event)")
            }
        }
    }

    // MARK: Agent PID

    func testAgentPIDSkipsShells() {
        let names: [Int32: String] = [300: "sh", 200: "zsh", 100: "node", 50: "launchd"]
        let parents: [Int32: Int32] = [300: 200, 200: 100, 100: 50]
        XCTAssertEqual(HookAdapter.agentPID(from: 300, name: { names[$0] }, parent: { parents[$0] }), 100)
        XCTAssertEqual(HookAdapter.agentPID(from: 100, name: { names[$0] }, parent: { parents[$0] }), 100)
        XCTAssertNil(HookAdapter.agentPID(from: 300, name: { $0 == 300 ? "sh" : nil }, parent: { parents[$0] }))
        XCTAssertNil(HookAdapter.agentPID(from: 1, name: { _ in "launchd" }, parent: { _ in 0 }))
        XCTAssertNotNil(HookAdapter.agentPID(from: getpid()), "a real process resolves")
    }
}
