import XCTest
@testable import AgentAwakeCore

/// The wait itself, with a fake app and a fake clock.
final class HookGateTests: XCTestCase {
    /// A fake app: `holding` answers in order (the last repeats); nil = unreachable (send throws).
    final class App {
        var answers: [Bool?]
        var sent: [Request] = []
        var clock: Double = 1000
        init(_ answers: [Bool?]) { self.answers = answers }

        func send(_ r: Request) throws -> Response {
            sent.append(r)
            guard r.cmd == "strain" else { return Response(ok: true) }
            let a = answers.count > 1 ? answers.removeFirst() : answers.first ?? nil
            guard let holding = a else { throw POSIXError(.ECONNREFUSED) }
            return Response(ok: true, strain: holding ? Strain(thermal: .elevated) : .normal, holding: holding)
        }
        func wait(beats: [Request] = [], budget: Double = 600) -> HookGate.Hold {
            HookGate.wait(beats: beats, budget: budget, send: send, sleep: { self.clock += $0 }, now: { self.clock })
        }
        var strainPolls: Int { sent.filter { $0.cmd == "strain" }.count }
    }

    let beat = Request(cmd: "beat", name: "claude:s", agent: "claude", timeout: SessionStore.defaultTimeout)

    func testWaitsWhileHoldingAndBeatsUntilItClears() {
        let app = App([true, true, true, false])
        let hold = app.wait(beats: [beat])
        XCTAssertEqual(hold, HookGate.Hold(seconds: 9, reason: "Mac is running hot"), "three polls of 3 s")
        XCTAssertEqual(app.strainPolls, 4)
        XCTAssertEqual(app.sent.filter { $0.cmd == "beat" }.count, 3, "a beat per poll keeps the session alive")
        XCTAssertEqual(HookGate.note(hold), "Agent Awake held this tool for 9 s: Mac is running hot.")
    }

    func testStopsAtTheBudget() {
        let app = App([true])
        let hold = app.wait(budget: 10)
        XCTAssertEqual(hold.seconds, 10, "the last sleep is cut to what's left")
        XCTAssertEqual(app.strainPolls, 5)   // first ask, then after 3, 6, 9 and 10 s
        XCTAssertEqual(HookGate.note(HookGate.Hold(seconds: 600, reason: nil)),
                       "Agent Awake held this tool for 10 min while the Mac was strained.")
    }

    func testNeverWaitsWhenTheAppIsUnreachableOrSaysNothing() {
        let unreachable = App([nil])
        XCTAssertEqual(unreachable.wait(beats: [beat]).seconds, 0)
        XCTAssertEqual(unreachable.sent.map(\.cmd), ["strain"], "one try, no beats")

        // An app without the strain feature answers ok with no `holding`; an error reply is not a hold either.
        for reply in [Response(ok: true), Response(ok: false, error: "unknown cmd", holding: true)] {
            var clock = 0.0
            let hold = HookGate.wait(beats: [], budget: 600, send: { _ in reply }, sleep: { clock += $0 }, now: { clock })
            XCTAssertEqual(hold.seconds, 0)
        }
        XCTAssertNil(HookGate.note(HookGate.Hold(seconds: 0, reason: nil)))

        // The app goes away mid-hold: the tool runs.
        let gone = App([true, nil])
        XCTAssertEqual(gone.wait().seconds, 3)
    }

    func testOnlyGateEventsWait() {
        XCTAssertEqual(HookGate.budget(agent: "claude", event: "PreToolUse"), 600)
        XCTAssertNil(HookGate.budget(agent: "claude", event: "PostToolUse"))
        XCTAssertNil(HookGate.budget(agent: "claude", event: "Stop"))
        XCTAssertEqual(HookGate.budget(agent: "gemini", event: "BeforeTool"), 600)
        XCTAssertNil(HookGate.budget(agent: "antigravity", event: "PreToolUse"), "no neutral answer: never gated")
        XCTAssertNil(HookGate.budget(agent: "cursor", event: "preToolUse"))
        XCTAssertNil(HookGate.budget(agent: "amp", event: "gate"))
        XCTAssertNil(HookGate.budget(agent: "nope", event: "PreToolUse"))
        XCTAssertEqual(HookGate.budget(agent: "omp", event: "gate"), 20, "omp blocks tools whose handler passes 30 s")
        XCTAssertEqual(HookGate.alarm(budget: 20), 25)
        for spec in AgentCatalog.all {
            guard let gate = spec.gate else { continue }
            XCTAssertNotNil(spec.action(for: gate), "\(spec.id): the gate is a registered event")
            XCTAssertLessThan(Double(HookGate.alarm(budget: HookGate.budget(for: spec))), Double(HookGate.timeout(for: spec)),
                              "\(spec.id): the hook exits before the agent's timeout")
        }
    }

    func testGateEventsBeatLikeOtherToolEvents() {
        let r = HookAdapter.requests(agent: "claude", event: "PreToolUse", payload: Data(#"{"session_id":"s","cwd":"/p","tool_name":"Bash"}"#.utf8),
                                     env: [:], agentPID: 7, config: Config())
        XCTAssertEqual(r.map(\.cmd), ["beat"])
        XCTAssertEqual(r.first?.name, "claude:s")
        // A plugin gate for a subagent it can't place only waits: no session invented from the hook's pid.
        XCTAssertEqual(HookAdapter.requests(agent: "omp", event: "gate", payload: Data("{}".utf8), env: [:], agentPID: 7, config: Config()).count, 0)
        XCTAssertEqual(HookAdapter.requests(agent: "pi", event: "gate", payload: Data(#"{"session_id":"p1"}"#.utf8), env: [:], agentPID: 7,
                                            config: Config()).map(\.name), ["pi:p1"])
    }

    func testHeldNoteOnlyWhereTheAgentShowsIt() {
        let payload = Data(#"{"session_id":"s"}"#.utf8)
        XCTAssertEqual(HookAdapter.heldStdout(agent: "claude", event: "PreToolUse", payload: payload, env: [:], note: "Held \"3 min\"."),
                       #"{"systemMessage":"Held \"3 min\"."}"#)
        XCTAssertNotNil(HookAdapter.heldStdout(agent: "codex", event: "PreToolUse", payload: payload, env: [:], note: "x"))
        XCTAssertNotNil(HookAdapter.heldStdout(agent: "gemini", event: "BeforeTool", payload: payload, env: [:], note: "x"))
        // Junie feeds stdout to the model, Copilot denies on bad output, Droid shows it in the transcript: print nothing.
        for (agent, event) in [("junie", "PreToolUse"), ("copilot", "preToolUse"), ("droid", "PreToolUse"), ("qwen", "PreToolUse")] {
            XCTAssertNil(HookAdapter.heldStdout(agent: agent, event: event, payload: payload, env: [:], note: "x"), agent)
        }
        // Claude-format hooks running inside Cursor: any JSON there would be read as a decision.
        let cursor = Data(#"{"conversation_id":"c","cursor_version":"2.0","workspace_roots":["/p"]}"#.utf8)
        XCTAssertNil(HookAdapter.heldStdout(agent: "claude", event: "PreToolUse", payload: cursor, env: [:], note: "x"))
        XCTAssertNil(HookAdapter.heldStdout(agent: "claude", event: "PostToolUse", payload: payload, env: [:], note: "x"))
        XCTAssertNil(HookAdapter.stdout(agent: "claude", event: "PreToolUse"), "the gate prints nothing up front: no decision")
    }
}

/// What the installers register for the gate.
extension IntegrationsTests {
    func handler(_ doc: JSONValue, _ event: String, container: [String] = ["hooks"]) -> JSONValue {
        var events = doc
        for key in container { events = events[key]! }
        let element = events[event]!.arrayValue!.last!
        return element["hooks"]?.arrayValue?.last ?? element
    }

    func testGateEventsGetTheLongTimeoutAndOthersStayShort() throws {
        try write(".claude.json", "{}")
        for id in AgentCatalog.all.map(\.id) { try integration(id).connect() }

        let claude = try json(".claude/settings.json")
        XCTAssertEqual(handler(claude, "PreToolUse")["timeout"], .int(610))
        XCTAssertNil(handler(claude, "PreToolUse")["async"], "the agent must wait for the gate")
        XCTAssertEqual(handler(claude, "PostToolUse")["timeout"], .int(5))
        XCTAssertEqual(handler(claude, "PostToolUse")["async"], .bool(true))
        XCTAssertEqual(handler(claude, "Stop")["timeout"], .int(5))

        let codex = try json(".codex/hooks.json")
        XCTAssertEqual(handler(codex, "PreToolUse")["timeout"], .int(610))
        XCTAssertEqual(handler(codex, "PostToolUse")["timeout"], .int(5))
        XCTAssertEqual(handler(codex, "SessionEnd")["timeout"], .int(2))

        let gemini = try json(".gemini/extensions/agentawake/hooks/hooks.json")
        XCTAssertEqual(handler(gemini, "BeforeTool")["timeout"], .int(610_000), "Gemini counts milliseconds")
        XCTAssertEqual(handler(gemini, "AfterTool")["timeout"], .int(5000))

        let antigravity = try json(".gemini/config/hooks.json")["agentawake"]!
        XCTAssertNil(antigravity["PreToolUse"], "Antigravity's PreToolUse must decide: never registered")
        XCTAssertTrue(antigravity.objectPairs!.allSatisfy { handler(.obj([("x", $0.value)]), "x", container: [])["timeout"] == .int(5) })

        let qwen = try json(".qwen/settings.json")
        XCTAssertEqual(handler(qwen, "PreToolUse")["timeout"], .int(610))
        XCTAssertNil(handler(qwen, "PreToolUse")["async"])
        XCTAssertEqual(handler(qwen, "PostToolUse")["async"], .bool(true))

        XCTAssertEqual(handler(try json(".factory/hooks.json"), "PreToolUse", container: [])["timeout"], .int(610))
        XCTAssertEqual(handler(try json(".augment/settings.json"), "PreToolUse")["timeout"], .int(610_000))
        XCTAssertEqual(try json(".copilot/hooks/agentawake.json")["hooks"]!["preToolUse"]!.arrayValue![0]["timeoutSec"], .int(610))
        XCTAssertEqual(try json(".copilot/hooks/agentawake.json")["hooks"]!["postToolUse"]!.arrayValue![0]["timeoutSec"], .int(5))
        XCTAssertEqual(handler(try json(".config/devin/config.json"), "PreToolUse")["timeout"], .int(610))
        XCTAssertEqual(handler(try json(".agents/plugins/agentawake/hooks/hooks.json"), "PreToolUse")["timeout"], .int(610))
        let junie = try json(".junie/config.json")
        XCTAssertEqual(handler(junie, "PreToolUse")["timeout"], .int(610))
        XCTAssertNil(handler(junie, "PreToolUse")["async"])
        let kiro = try json(".kiro/hooks/agentawake.json")["hooks"]!.arrayValue!
        XCTAssertEqual(kiro.first { $0["trigger"] == .string("PreToolUse") }?["timeout"], .int(610))
        XCTAssertEqual(kiro.first { $0["trigger"] == .string("PostToolUse") }?["timeout"], .int(5))

        let cursor = try json(".cursor/hooks.json")["hooks"]!
        XCTAssertNil(cursor["preToolUse"]); XCTAssertNil(cursor["beforeShellExecution"])
        XCTAssertNil(try json(".codeium/windsurf/hooks.json")["hooks"]!["pre_run_command"])
    }

    /// Hooks registered before the gate (PreToolUse async, 5 s) count as out of date, and Connect upgrades them.
    func testOldShortGateRegistrationNeedsRepairAndConnectUpgradesIt() throws {
        try write(".claude.json", "{}")
        let claude = integration("claude")
        try claude.connect()
        var doc = try json(".claude/settings.json")
        var hooks = doc["hooks"]!
        var group = hooks["PreToolUse"]!.arrayValue![0]
        group.set("hooks", .array([.obj([("type", .string("command")), ("command", .string(cmd("claude", "PreToolUse"))),
                                         ("timeout", .int(5)), ("async", .bool(true))])]))
        hooks.set("PreToolUse", .array([group]))
        doc.set("hooks", hooks)
        try write(".claude/settings.json", doc.serialized())
        guard case .broken = claude.status() else { return XCTFail("a short gate must be repaired: \(claude.status())") }

        try claude.connect()
        XCTAssertEqual(claude.status(), .connected)
        let pre = try json(".claude/settings.json")["hooks"]!["PreToolUse"]!.arrayValue!
        XCTAssertEqual(pre.count, 1, "the old entry is replaced, not duplicated")
        XCTAssertEqual(pre[0]["hooks"]!.arrayValue![0]["timeout"], .int(610))
        XCTAssertNil(pre[0]["hooks"]!.arrayValue![0]["async"])

        // Fields an agent adds to our handler don't make it stale.
        var withExtra = try json(".claude/settings.json")
        var h = withExtra["hooks"]!; var g = h["Stop"]!.arrayValue![0]; var stop = g["hooks"]!.arrayValue![0]
        stop.set("statusMessage", .string("x")); g.set("hooks", .array([stop])); h.set("Stop", .array([g])); withExtra.set("hooks", h)
        try write(".claude/settings.json", withExtra.serialized())
        XCTAssertEqual(claude.status(), .connected)
    }

    func testPluginsAwaitTheGateOnlyWhereTheHostAllowsIt() throws {
        for id in ["opencode", "kilo", "omp", "pi"] {
            let i = integration(id)
            try i.connect()
            let text = read(String(i.files[0].dropFirst(home.count + 1)))!
            XCTAssertTrue(text.contains(#"spawn(BIN, ["hook", AGENT, "gate"]"#), id)
            XCTAssertTrue(text.contains("await gate("), id)
        }
        XCTAssertTrue(read(".config/opencode/plugins/agentawake.js")!.contains(#""tool.execute.before": async"#))
        XCTAssertTrue(read(".config/opencode/plugins/agentawake.js")!.contains("const GATE_MS = 608000"))
        XCTAssertTrue(read(".omp/agent/extensions/agentawake.ts")!.contains("const GATE_MS = 28000"), "inside omp's 30 s handler limit")
        try integration("amp").connect()
        XCTAssertFalse(read(".config/amp/plugins/agentawake.ts")!.contains("gate"), "Amp's tool.call must decide: not gated")
    }
}
