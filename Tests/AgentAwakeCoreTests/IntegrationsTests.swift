import XCTest
@testable import AgentAwakeCore

final class IntegrationsTests: XCTestCase {
    var home = ""

    override func setUpWithError() throws {
        home = NSTemporaryDirectory() + "aa-integrations-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        XCTAssertNotEqual(home, NSHomeDirectory(), "tests must never touch the real home folder")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    // MARK: Helpers

    func integration(_ id: String) -> Integration { Integrations.all(home: home).first { $0.id == id }! }
    func path(_ rel: String) -> String { home + "/" + rel }
    func write(_ rel: String, _ text: String) throws {
        let p = path(rel)
        try FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: p, atomically: true, encoding: .utf8)
    }
    func read(_ rel: String) -> String? { try? String(contentsOfFile: path(rel), encoding: .utf8) }
    func json(_ rel: String) throws -> JSONValue { try JSONParser.parse(read(rel)!, allowComments: true).value }
    func cmd(_ agent: String, _ event: String) -> String { Integrations.hookCommand(agent: agent, event: event, home: home) }
    func events(_ id: String) -> [String] { AgentCatalog.spec(id)!.events.map(\.event) }

    /// All files under the temp home that mention our marker.
    func filesWithMarker() -> [String] {
        let e = FileManager.default.enumerator(atPath: home)
        var hits: [String] = []
        while let rel = e?.nextObject() as? String {
            if rel.hasSuffix(".agentawake-backup") { continue }
            if let t = read(rel), t.contains("agentawake hook") { hits.append(rel) }
        }
        return hits
    }

    let herdrClaude = """
    {
      "agentPushNotifEnabled": true,
      "inputNeededNotifEnabled": false,
      "hooks": {
        "SessionStart": [
          {
            "matcher": "^(startup|resume|clear|compact|fork)$",
            "hooks": [
              {
                "type": "command",
                "command": "bash '/Users/me/.claude/hooks/herdr-agent-state.sh' session",
                "timeout": 10
              }
            ]
          }
        ]
      }
    }

    """

    let herdrCodex = """
    {
      "hooks": {
        "SessionStart": [
          {
            "hooks": [
              {
                "command": "bash '/Users/me/.codex/herdr-agent-state.sh' session",
                "timeout": 10,
                "type": "command"
              }
            ]
          }
        ]
      }
    }
    """

    // MARK: Hook command

    func testHookCommandKeepsMarkerAndAlwaysExitsZero() throws {
        let spaced = home + "/My Home"
        let c = Integrations.hookCommand(agent: "claude", event: "Stop", home: spaced)
        XCTAssertTrue(c.contains("agentawake hook claude Stop"))
        XCTAssertTrue(c.hasPrefix("/bin/sh -c '") && c.hasSuffix("; exit 0'"))

        // Missing binary: silent, exit 0.
        let missing = try run("/bin/sh", ["-c", c], stdin: "{}")
        XCTAssertEqual(missing.status, 0); XCTAssertEqual(missing.out, "")

        // Present binary: gets the args and the payload on stdin, even with a space in the home path.
        let bin = spaced + "/.agent-awake/bin/agentawake"
        try FileManager.default.createDirectory(atPath: spaced + "/.agent-awake/bin", withIntermediateDirectories: true)
        try "#!/bin/sh\necho \"$@\" > \"$0.log\"; cat >> \"$0.log\"; exit 3\n".write(toFile: bin, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin)
        let ran = try run("/bin/sh", ["-c", c], stdin: "{\"session_id\":\"x\"}")
        XCTAssertEqual(ran.status, 0, "a failing CLI must not fail the agent's hook")
        XCTAssertEqual(try String(contentsOfFile: bin + ".log", encoding: .utf8), "hook claude Stop\n{\"session_id\":\"x\"}")
    }

    // MARK: Claude (shared settings file)

    func testClaudeConnectIntoEmptyHomeRegistersExactlyCatalogEvents() throws {
        // Claude writes ~/.claude.json on first run; with it, detection doesn't depend on what this host has installed.
        try write(".claude.json", "{}")
        let claude = integration("claude")
        XCTAssertEqual(claude.status(), .available)
        try claude.connect()
        let doc = try json(".claude/settings.json")
        let hooks = doc["hooks"]!.objectPairs!
        XCTAssertEqual(hooks.map(\.key), events("claude"))
        for (event, value) in hooks.map({ ($0.key, $0.value) }) {
            let handler = value.arrayValue![0]["hooks"]!.arrayValue![0]
            XCTAssertEqual(handler["command"]?.stringValue, cmd("claude", event))
            XCTAssertEqual(handler["type"]?.stringValue, "command")
        }
        XCTAssertEqual(doc["hooks"]!["PostToolUse"]!.arrayValue![0]["hooks"]!.arrayValue![0]["async"], .bool(true))
        XCTAssertNil(doc["hooks"]!["SessionEnd"]!.arrayValue![0]["hooks"]!.arrayValue![0]["timeout"], "SessionEnd keeps Claude's short budget")
        XCTAssertEqual(claude.status(), .connected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(".claude/settings.json.agentawake-backup")), "nothing to back up")

        let before = read(".claude/settings.json")
        try claude.connect()
        XCTAssertEqual(read(".claude/settings.json"), before, "connect is idempotent")

        try claude.disconnect()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(".claude/settings.json")), "a file we created and emptied is removed")
        XCTAssertEqual(claude.status(), .available, "Claude is still installed, just not connected")
    }

    func testClaudeMergesIntoRealisticSettingsAndDisconnectRestoresThem() throws {
        try write(".claude/settings.json", herdrClaude)
        let original = try json(".claude/settings.json")
        let claude = integration("claude")
        XCTAssertEqual(claude.status(), .available)

        try claude.connect()
        let doc = try json(".claude/settings.json")
        XCTAssertEqual(doc.objectPairs!.map(\.key), ["agentPushNotifEnabled", "inputNeededNotifEnabled", "hooks"], "key order kept")
        XCTAssertEqual(doc["agentPushNotifEnabled"], .bool(true))
        XCTAssertEqual(doc["hooks"]!["SessionStart"], original["hooks"]!["SessionStart"], "herdr's hook untouched")
        XCTAssertEqual(doc["hooks"]!.objectPairs!.map(\.key), ["SessionStart"] + events("claude"))
        XCTAssertEqual(read(".claude/settings.json.agentawake-backup"), herdrClaude, "backup holds the original bytes")
        XCTAssertEqual(claude.status(), .connected)

        let connected = read(".claude/settings.json")
        try claude.connect()
        XCTAssertEqual(read(".claude/settings.json"), connected)

        try claude.disconnect()
        XCTAssertEqual(try json(".claude/settings.json"), original, "disconnect leaves exactly the user's settings")
        XCTAssertEqual(read(".claude/settings.json.agentawake-backup"), herdrClaude, "backup made once")
        XCTAssertEqual(claude.status(), .available)
    }

    func testDisconnectRemovesOnlyOurHandlerFromAMixedGroupAndStaleEntriesAreRepaired() throws {
        let stale = Integrations.hookCommand(agent: "claude", event: "Stop", home: "/Users/old")
        try write(".claude/settings.json", """
        {"hooks": {
          "Stop": [{"hooks": [{"type": "command", "command": "say done"}, {"type": "command", "command": \(JSONValue.quote(stale))}]}],
          "SessionStart": [{"hooks": [{"type": "command", "command": \(JSONValue.quote(cmd("claude", "SessionStart")))}]}],
          "Empty": []
        }}
        """)
        let claude = integration("claude")
        if case .broken = claude.status() {} else { XCTFail("old entries show as needing repair") }

        try claude.connect()
        let hooks = try json(".claude/settings.json")["hooks"]!
        XCTAssertNil(hooks["SessionStart"], "event no longer in the catalog is cleaned up")
        XCTAssertEqual(hooks["Empty"], .array([]), "the user's own empty list stays")
        let stop = hooks["Stop"]!.arrayValue!
        XCTAssertEqual(stop.count, 2)
        XCTAssertEqual(stop[0]["hooks"]!.arrayValue!.map { $0["command"]!.stringValue! }, ["say done"], "outdated command dropped, user hook kept")
        XCTAssertEqual(stop[1]["hooks"]!.arrayValue![0]["command"]?.stringValue, cmd("claude", "Stop"))
        XCTAssertEqual(claude.status(), .connected)

        try claude.disconnect()
        let after = try json(".claude/settings.json")["hooks"]!
        XCTAssertEqual(after.objectPairs!.map(\.key), ["Stop", "Empty"])
        XCTAssertEqual(after["Stop"]!.arrayValue!.count, 1)
        XCTAssertEqual(filesWithMarker(), [])
    }

    func testUnparseableFileIsRefusedAndLeftUntouched() throws {
        let broken = "{\n  \"hooks\": {\n    \"Stop\": [\n"
        try write(".claude/settings.json", broken)
        let claude = integration("claude")
        XCTAssertThrowsError(try claude.connect()) { error in
            guard case let IntegrationError.unparseable(p, reason, snippet)? = error as? IntegrationError else { return XCTFail("\(error)") }
            XCTAssertEqual(p, self.path(".claude/settings.json"))
            XCTAssertTrue(reason.contains("line"))
            XCTAssertTrue(snippet.contains("agentawake hook claude Stop"), "the error shows what to add by hand")
        }
        XCTAssertThrowsError(try claude.disconnect())
        XCTAssertEqual(read(".claude/settings.json"), broken)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(".claude/settings.json.agentawake-backup")))
        if case .broken = claude.status() {} else { XCTFail("unreadable file reports broken") }

        // Claude reads strict JSON, so comments are refused rather than stripped.
        let commented = "{ // mine\n \"model\": \"opus\" }\n"
        try write(".claude/settings.json", commented)
        XCTAssertThrowsError(try claude.connect())
        XCTAssertEqual(read(".claude/settings.json"), commented)

        // Not an object where our hooks go.
        try write(".claude/settings.json", "{\"hooks\": []}")
        XCTAssertThrowsError(try claude.connect())
        XCTAssertEqual(read(".claude/settings.json"), "{\"hooks\": []}")
    }

    func testJSONCSettingsAreMergedWhereTheAgentAllowsComments() throws {
        let qwenText = """
        {
          // Qwen settings
          "$version": 4,
          "model": { "name": "qwen3-coder" /* default */ },
          "url": "https://example.com//x"
        }
        """
        try write(".qwen/settings.json", qwenText)
        let qwen = integration("qwen")
        try qwen.connect()
        let doc = try json(".qwen/settings.json")
        XCTAssertEqual(doc.objectPairs!.map(\.key), ["$version", "model", "url", "hooks"])
        XCTAssertEqual(doc["url"]?.stringValue, "https://example.com//x", "`//` inside strings isn't a comment")
        XCTAssertEqual(doc["$version"], .number("4"))
        XCTAssertEqual(doc["hooks"]!.objectPairs!.map(\.key), events("qwen"))
        XCTAssertEqual(read(".qwen/settings.json.agentawake-backup"), qwenText, "the commented original is kept")
        XCTAssertEqual(qwen.status(), .connected)
    }

    // MARK: Codex

    func testCodexAppendsAfterUserHooksAndNeedsTrustUntilEveryEntryIsTrusted() throws {
        try write(".codex/hooks.json", herdrCodex)
        try write(".codex/config.toml", """
        model = "gpt-5"

        [hooks.state."\(path(".codex/hooks.json")):session_start:0:0"]
        trusted_hash = "sha256:989a"

        """)
        let codex = integration("codex")
        XCTAssertEqual(codex.status(), .available)
        XCTAssertNotNil(codex.note)
        try codex.connect()

        let doc = try json(".codex/hooks.json")
        XCTAssertEqual(doc.objectPairs!.map(\.key), ["hooks"], "Codex rejects unknown top-level keys")
        XCTAssertEqual(doc["hooks"]!["SessionStart"], try JSONParser.parse(herdrCodex, allowComments: false).value["hooks"]!["SessionStart"],
                       "herdr's trusted group stays first, so its trust key doesn't move")
        XCTAssertEqual(doc["hooks"]!.objectPairs!.map(\.key), ["SessionStart"] + events("codex"))
        guard case .needsAction(let message) = codex.status() else { return XCTFail("untrusted hooks need the user") }
        XCTAssertTrue(message.contains("Trust all and continue"))

        // Trust all but one: still needs action. Then all: connected. Codex keys trust by the realpath
        // (/private/var/… for this temp folder), as `codex app-server` hooks/list reports.
        let hooksPath = FileOps.canonical(path(".codex/hooks.json"))
        var toml = read(".codex/config.toml")!
        for event in events("codex").dropLast() {
            toml += "\n[hooks.state.\"\(hooksPath):\(CodexTrust.snake(event)):0:0\"]\ntrusted_hash = \"sha256:abc\"\n"
        }
        try write(".codex/config.toml", toml)
        if case .needsAction = codex.status() {} else { XCTFail("one hook still untrusted") }
        toml += "\n[hooks.state.\"\(hooksPath):session_end:0:0\"]\ntrusted_hash = \"sha256:def\"\n"
        try write(".codex/config.toml", toml)
        XCTAssertEqual(codex.status(), .connected)
        XCTAssertEqual(read(".codex/config.toml"), toml, "we never write trust ourselves")

        // A disabled hook or hooks switched off need the user again.
        try write(".codex/config.toml", toml + "\n[features]\nhooks = false\n")
        if case .needsAction(let m) = codex.status() { XCTAssertTrue(m.contains("hooks = false")) } else { XCTFail() }

        try codex.disconnect()
        XCTAssertEqual(try json(".codex/hooks.json"), try JSONParser.parse(herdrCodex, allowComments: false).value)
    }

    func testCodexSnakeEventNames() {
        XCTAssertEqual(CodexTrust.snake("UserPromptSubmit"), "user_prompt_submit")
        XCTAssertEqual(CodexTrust.snake("PreToolUse"), "pre_tool_use")
        XCTAssertEqual(CodexTrust.snake("Stop"), "stop")
    }

    // MARK: Other shared formats

    func testCursorFlatEntriesKeepUserHooksAndVersion() throws {
        try write(".cursor/hooks.json", "{\"version\": 1, \"hooks\": {\"stop\": [{\"command\": \"./audit.sh\"}]}}")
        let cursor = integration("cursor")
        try cursor.connect()
        let doc = try json(".cursor/hooks.json")
        XCTAssertEqual(doc["version"], .number("1"))
        let stop = doc["hooks"]!["stop"]!.arrayValue!
        XCTAssertEqual(stop.map { $0["command"]!.stringValue! }, ["./audit.sh", cmd("cursor", "stop")])
        XCTAssertEqual(cursor.status(), .connected)
        try cursor.disconnect()
        XCTAssertEqual(try json(".cursor/hooks.json")["hooks"]!["stop"]!.arrayValue!.count, 1)
    }

    func testCursorCreatesVersionedFileAndDeletesItOnDisconnect() throws {
        let cursor = integration("cursor")
        try cursor.connect()
        XCTAssertEqual(try json(".cursor/hooks.json")["version"], .number("1"))
        try cursor.disconnect()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(".cursor/hooks.json")))
    }

    func testDroidWritesTopLevelEventsOrSettingsWhenItAlreadyHoldsHooks() throws {
        let droid = integration("droid")
        try droid.connect()
        let doc = try json(".factory/hooks.json")
        XCTAssertEqual(doc.objectPairs!.map(\.key), events("droid"), "standalone hooks.json keys events at the top level")
        XCTAssertEqual(droid.status(), .connected)
        try droid.disconnect()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(".factory/hooks.json")))

        try write(".factory/settings.json", "{\"model\": \"x\", \"hooks\": {\"Stop\": [{\"hooks\": [{\"type\": \"command\", \"command\": \"mine\"}]}]}}")
        let droid2 = integration("droid")
        XCTAssertEqual(droid2.files, [path(".factory/settings.json")])
        try droid2.connect()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(".factory/hooks.json")), "a new hooks.json would hide settings.json hooks")
        XCTAssertEqual(try json(".factory/settings.json")["hooks"]!["Stop"]!.arrayValue!.count, 2)
        XCTAssertEqual(droid2.status(), .connected)
    }

    func testJunieNeverRegistersPermissionRequest() throws {
        try integration("junie").connect()
        let hooks = try json(".junie/config.json")["hooks"]!
        XCTAssertNil(hooks["PermissionRequest"], "a Junie PermissionRequest hook auto-approves")
        XCTAssertEqual(hooks.objectPairs!.map(\.key), events("junie"))
    }

    // MARK: Files we own

    func testOwnedFilesConnectStatusDisconnect() throws {
        for (id, rel) in [("copilot", ".copilot/hooks/agentawake.json"), ("kiro", ".kiro/hooks/agentawake.json"),
                          ("gemini", ".gemini/extensions/agentawake/hooks/hooks.json"), ("goose", ".agents/plugins/agentawake/hooks/hooks.json")] {
            let i = integration(id)
            try i.connect()
            XCTAssertEqual(i.status(), .connected, id)
            let text = read(rel)!
            for event in events(id) { XCTAssertTrue(text.contains("agentawake hook \(id) \(event);"), "\(id) \(event)") }
            try i.disconnect()
            XCTAssertNotEqual(i.status(), .connected, id)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(".gemini/extensions/agentawake")), "extension dir removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path(".agents/plugins/agentawake")), "plugin dir removed")
    }

    func testOwnedFileThatIsNotOursIsRefused() throws {
        try write(".copilot/hooks/agentawake.json", "{\"version\": 1, \"hooks\": {}}")
        let copilot = integration("copilot")
        XCTAssertThrowsError(try copilot.connect())
        XCTAssertEqual(read(".copilot/hooks/agentawake.json"), "{\"version\": 1, \"hooks\": {}}")
        if case .broken = copilot.status() {} else { XCTFail() }
        try copilot.disconnect()
        XCTAssertNotNil(read(".copilot/hooks/agentawake.json"), "disconnect never deletes a file we didn't write")
    }

    // MARK: Every agent

    func testEveryCatalogAgentConnectsIdempotentlyAndDisconnectsCleanly() throws {
        let all = Integrations.all(home: home)
        XCTAssertEqual(all.map(\.id), AgentCatalog.all.map(\.id))
        for i in all {
            XCTAssertFalse(i.files.isEmpty, i.id)
            XCTAssertTrue(i.files.allSatisfy { $0.hasPrefix(home + "/") }, i.id)
            try i.connect()
            let status = i.status()
            XCTAssertTrue(status == .connected || i.id == "codex", "\(i.id): \(status)")
            let snapshot = i.files.map { read(String($0.dropFirst(home.count + 1))) }
            try i.connect()
            XCTAssertEqual(i.files.map { read(String($0.dropFirst(home.count + 1))) }, snapshot, "\(i.id) idempotent")
            for file in i.files {
                let text = read(String(file.dropFirst(home.count + 1)))!
                XCTAssertFalse(text.contains("agentawake hook") && !text.contains("agentawake hook \(i.id) "), i.id)
            }
        }
        for i in all {
            try i.disconnect()
            XCTAssertNotEqual(i.status(), .connected, i.id)
        }
        XCTAssertEqual(filesWithMarker(), [])
    }

    // MARK: Shim

    func testInstallShimPointsAtTheCLIAndRepoints() throws {
        let a = path("A/agentawake"), b = path("B/agentawake")
        for p in [a, b] {
            try write(String(p.dropFirst(home.count + 1)), "#!/bin/sh\n")
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: p)
        }
        try Integrations.installShim(cliPath: a, home: home)
        let link = path(".agent-awake/bin/agentawake")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link), a)
        try Integrations.installShim(cliPath: b, home: home)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link), b)
        XCTAssertThrowsError(try Integrations.installShim(cliPath: path("missing"), home: home))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link), b)
    }

    // MARK: JSON

    func testJSONRoundTripKeepsOrderNumbersAndEscapes() throws {
        let text = "{\"b\": 1.50, \"a\": [true, null, -2e3], \"s\": \"tab\\t \\u00e9 \\ud83d\\ude00 \\\"q\\\" /\"}"
        let v = try JSONParser.parse(text, allowComments: false).value
        XCTAssertEqual(v.objectPairs!.map(\.key), ["b", "a", "s"])
        XCTAssertEqual(v["b"], .number("1.50"))
        XCTAssertEqual(v["s"]?.stringValue, "tab\t é 😀 \"q\" /")
        XCTAssertEqual(try JSONParser.parse(v.serialized(), allowComments: false).value, v)
        XCTAssertThrowsError(try JSONParser.parse("{\"a\": 1,}", allowComments: true))
        XCTAssertThrowsError(try JSONParser.parse("{\"a\": 1, \"a\": 2}", allowComments: false))
    }

    // MARK: Plugins

    func testGeneratedPluginsAreValidJavaScriptAndTypeScript() throws {
        let plugins = ["opencode", "kilo", "amp", "omp", "pi"].map(integration)
        try plugins.forEach { try $0.connect() }
        let node = tool("node"), bun = tool("bun")
        var checked = 0
        for i in plugins {
            let file = i.files[0]
            if file.hasSuffix(".js") {
                guard let node else { continue }
                let mjs = file.replacingOccurrences(of: ".js", with: ".check.mjs")
                try FileManager.default.copyItem(atPath: file, toPath: mjs)
                let r = try run(node, ["--check", mjs])
                XCTAssertEqual(r.status, 0, "\(i.id): \(r.err)")
                try FileManager.default.removeItem(atPath: mjs)
                checked += 1
            } else {
                guard let bun else { continue }
                let r = try run(bun, ["build", "--no-bundle", file])
                XCTAssertEqual(r.status, 0, "\(i.id): \(r.err)")
                checked += 1
            }
        }
        if node == nil || bun == nil {
            throw XCTSkip("Syntax-checked \(checked) of \(plugins.count) plugins; missing: \([node == nil ? "node" : nil, bun == nil ? "bun" : nil].compactMap { $0 })")
        }
    }

    /// Runs each plugin against a fake agent API and a fake `agentawake` that logs what it receives.
    func testPluginsReportActionsThroughTheShim() throws {
        guard let bun = tool("bun") else { throw XCTSkip("bun not installed: plugin behavior not exercised") }
        let logs = path("hook-logs")
        // One file per invocation, renamed into place when complete: detached children run concurrently.
        try write(".agent-awake/bin/agentawake", "#!/bin/sh\nf=$(mktemp \"\(logs)/call.XXXXXX\")\n{ printf '%s %s ' \"$2\" \"$3\"; cat; } > \"$f\" && mv \"$f\" \"$f.done\"\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path(".agent-awake/bin/agentawake"))

        let harness: [String: String] = [
            "opencode": """
            const m = await import(process.argv[2])
            const client = { session: { get: async ({ path }) => ({ data: { id: path.id, parentID: path.id === "child" ? "root" : undefined } }) } }
            const h = await m.default.server({ directory: "/proj", client })
            await h["chat.message"]({ sessionID: "root" }, { parts: [{ type: "text", text: "Fix the bug" }] })
            const ev = (type, properties) => h.event({ event: { type, properties } })
            ev("session.status", { sessionID: "root", status: { type: "busy" } })
            ev("session.status", { sessionID: "child", status: { type: "busy" } })
            ev("permission.asked", { sessionID: "child", permission: "bash", patterns: ["rm -rf x"] })
            ev("session.status", { sessionID: "child", status: { type: "idle" } })
            ev("session.status", { sessionID: "root", status: { type: "idle" } })
            ev("session.deleted", { info: { id: "root" } })
            const v2 = { location: { directory: "/v2" }, session: { get: async () => ({ parentID: null }) },
              event: { subscribe: async function* () { yield { type: "session.status", data: { sessionID: "two", status: { type: "busy" } } };
                                                       yield { type: "session.error", data: { sessionID: "two", error: { name: "APIError", data: { message: "overloaded" } } } } } } }
            m.default.setup(v2)
            await new Promise((r) => setTimeout(r, 300))
            """,
            "omp": """
            const m = await import(process.argv[2])
            const on = {}
            m.default({ on: (e, f) => { on[e] = f } })
            const ctx = { cwd: "/proj", sessionManager: { getSessionId: () => "s1" }, agent: { kind: "main" } }
            const sub = { cwd: "/proj", sessionManager: { getSessionId: () => "s2" }, agent: { kind: "sub" } }
            on.before_agent_start({ prompt: "Do it" }, ctx); on.agent_start({}, ctx); on.agent_start({}, sub)
            on.tool_approval_requested({ toolName: "bash" }, ctx); on.session_stop({}, sub); on.session_stop({}, ctx)
            on.session_shutdown({}, ctx)
            await new Promise((r) => setTimeout(r, 300))
            """,
            "pi": """
            const m = await import(process.argv[2])
            const on = {}
            m.default({ on: (e, f) => { on[e] = f } })
            const ctx = { cwd: "/proj", sessionManager: { getSessionId: () => "p1" } }
            on.before_agent_start({ prompt: "Go" }, ctx); on.agent_start({}, ctx)
            on.ui_prompt_start({ title: "Pick one" }, ctx); on.agent_before_settle({ outcome: "error" }, ctx)
            on.agent_settled({ aborted: false }, ctx); on.session_shutdown({ reason: "reload" }, ctx); on.session_shutdown({ reason: "quit" }, ctx)
            await new Promise((r) => setTimeout(r, 300))
            """,
            "amp": """
            const m = await import(process.argv[2])
            const on = {}; let dispose; let stateCb
            m.default({ system: { executor: { kind: "local" } }, on: (e, f) => { on[e] = f }, onDispose: (f) => { dispose = f } })
            const ctx = { thread: { id: "T1", parentThreadID: async () => null, state: { subscribe: (cb) => { stateCb = cb; return { unsubscribe() {} } } } } }
            on["session.start"]({ thread: { id: "T1" } }, ctx)
            const r = on["agent.start"]({ thread: { id: "T1" }, message: "Ship it", id: "m1" }, ctx)
            if (JSON.stringify(r) !== "{}") throw new Error("agent.start must return {}")
            stateCb("running"); stateCb("awaiting-approval")
            if (on["agent.end"]({ thread: { id: "T1" }, status: "cancelled" }, ctx) !== undefined) throw new Error("agent.end must return nothing")
            await new Promise((r) => setTimeout(r, 100))
            dispose()
            await new Promise((r) => setTimeout(r, 300))
            """,
        ]
        let realHome = realpath(home, nil).map { p in defer { free(p) }; return String(cString: p) } ?? home
        let expected: [String: [String]] = [
            "opencode": [
                #"opencode start {"session_id":"root","cwd":"/proj","prompt":"Fix the bug"}"#,
                #"opencode beat {"session_id":"child","cwd":"/proj","parent_session_id":"root"}"#,
                #"opencode needsYou {"session_id":"root","cwd":"/proj","message":"Allow bash: rm -rf x"}"#,
                #"opencode stop {"session_id":"root","cwd":"/proj"}"#,
                #"opencode end {"session_id":"root","cwd":"/proj"}"#,
                #"opencode start {"session_id":"two","cwd":"/v2"}"#,
                #"opencode failed {"session_id":"two","cwd":"/v2","message":"overloaded"}"#,
            ],
            "omp": [
                #"omp start {"session_id":"s1","cwd":"/proj","prompt":"Do it"}"#,
                #"omp needsYou {"session_id":"s1","cwd":"/proj","message":"Approve bash"}"#,
                #"omp stop {"session_id":"s1","cwd":"/proj"}"#,
                #"omp end {"session_id":"s1","cwd":"/proj"}"#,
            ],
            "pi": [
                #"pi start {"session_id":"p1","cwd":"/proj","prompt":"Go"}"#,
                #"pi needsYou {"session_id":"p1","cwd":"/proj","message":"Pick one"}"#,
                #"pi failed {"session_id":"p1","cwd":"/proj","message":"The run ended with an error"}"#,
                #"pi end {"session_id":"p1","cwd":"/proj"}"#,
            ],
            "amp": [
                "amp start {\"session_id\":\"T1\",\"cwd\":\"\(realHome)\",\"prompt\":\"Ship it\"}",
                "amp needsYou {\"session_id\":\"T1\",\"cwd\":\"\(realHome)\",\"message\":\"Waiting for tool approval\"}",
                "amp stop {\"session_id\":\"T1\",\"cwd\":\"\(realHome)\",\"status\":\"cancelled\"}",
                "amp end {\"session_id\":\"T1\",\"cwd\":\"\(realHome)\"}",
            ],
        ]
        for (id, script) in harness.sorted(by: { $0.key < $1.key }) {
            try? FileManager.default.removeItem(atPath: logs)
            try FileManager.default.createDirectory(atPath: logs, withIntermediateDirectories: true)
            let plugin = integration(id)
            try plugin.connect()
            var file = plugin.files[0]
            if file.hasSuffix(".js") {   // Bun runs OpenCode/Kilo plugins as ES modules
                let mjs = file.replacingOccurrences(of: ".js", with: ".mjs")
                try FileManager.default.copyItem(atPath: file, toPath: mjs)
                file = mjs
            }
            try write("harness-\(id).mjs", script)
            let r = try run(bun, [path("harness-\(id).mjs"), file], cwd: home)
            XCTAssertEqual(r.status, 0, "\(id): \(r.err)")
            XCTAssertEqual(r.out, "", "\(id) plugins print nothing")
            let want = expected[id]!.sorted()
            var got: [String] = []
            for _ in 0..<50 {   // children are detached; give them a moment to finish writing
                got = FileOps.contents(ofDirectory: logs).filter { $0.hasSuffix(".done") }.compactMap { read("hook-logs/" + $0) }.sorted()
                if got.count >= want.count { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            XCTAssertEqual(got, want, id)
        }
    }

    // MARK: Process helpers

    func tool(_ name: String) -> String? {
        let dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.bun/bin"]
        return dirs.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    func run(_ exe: String, _ args: [String], stdin: String = "", cwd: String? = nil) throws -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
        try p.run()
        inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        try inPipe.fileHandleForWriting.close()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}

extension IntegrationsTests {
    /// Antigravity's hooks.json maps hook *names* to definitions; ours is one named definition next to the user's.
    func testAntigravityAddsOneNamedDefinitionAndDisconnectRestoresTheFile() throws {
        let herdr = """
        {
          "herdr": {
            "PreInvocation": [
              { "command": "bash '/x/herdr-agent-state.sh' session", "timeout": 10, "type": "command" }
            ]
          }
        }

        """
        try write(".gemini/config/hooks.json", herdr)
        let ag = integration("antigravity")
        try ag.connect()
        let doc = try json(".gemini/config/hooks.json")
        XCTAssertNotNil(doc["herdr"], "the user's definition stays")
        let ours = doc["agentawake"]!
        XCTAssertEqual(ours.objectPairs!.map(\.key), ["PreInvocation", "PostToolUse", "PostInvocation", "Stop"])
        XCTAssertEqual(ours["Stop"]!.arrayValue![0]["command"]?.stringValue,
                       Integrations.hookCommand(agent: "antigravity", event: "Stop", home: home), "flat handler for non-tool events")
        XCTAssertEqual(ours["PostToolUse"]!.arrayValue![0]["matcher"]?.stringValue, "*")
        XCTAssertEqual(ag.status(), .connected)
        try ag.disconnect()
        XCTAssertNil(try json(".gemini/config/hooks.json")["agentawake"])
        XCTAssertEqual(try json(".gemini/config/hooks.json"), try JSONParser.parse(herdr, allowComments: false).value)
    }
}
