import CryptoKit
import Foundation

/// Codex skips user hooks until the user trusts them. Trust is stored in `~/.codex/config.toml` as
/// `[hooks.state."<abs hooks.json>:<snake_event>:<group>:<handler>"]` with a `trusted_hash` of the handler; editing
/// the handler (a new timeout, for instance) changes the hash and Codex skips it again until re-trusted. We only
/// read it: trusting is the user's security decision (Codex CLI: "Trust all and continue", or /hooks).
enum CodexTrust {
    struct State { var trusted: [String: String] = [:]; var disabled: Set<String> = []; var hooksOff = false }

    /// `trusted_hash` per `hooks.state` key, the keys with `enabled = false`, and whether
    /// `[features] hooks = false` (or the older `codex_hooks = false`) turns hooks off.
    static func state(configToml text: String) -> State {
        var state = State()
        var table: String? = nil      // current hooks.state key
        var inFeatures = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                table = nil
                inFeatures = line.hasPrefix("[features]")
                let prefix = "[hooks.state."
                if line.hasPrefix(prefix), !line.hasPrefix("[[") {
                    table = unquoteKey(String(line.dropFirst(prefix.count)))
                }
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let value = parts[1].split(separator: "#").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if let key = table {
                if parts[0] == "trusted_hash", value.count > 2 { state.trusted[key] = String(value.dropFirst().dropLast()) }
                if parts[0] == "enabled", value == "false" { state.disabled.insert(key) }
            } else if inFeatures, parts[0] == "hooks" || parts[0] == "codex_hooks", value == "false" {
                state.hooksOff = true
            }
        }
        return state
    }

    /// `"…"]` or `'…'"]` → the key text.
    private static func unquoteKey(_ s: String) -> String? {
        guard let quote = s.first, quote == "\"" || quote == "'" else { return nil }
        var out = "", escaped = false
        for c in s.dropFirst() {
            if quote == "\"", escaped { out.append(c); escaped = false; continue }
            if quote == "\"", c == "\\" { escaped = true; continue }
            if c == quote { return out }
            out.append(c)
        }
        return nil
    }

    static func snake(_ event: String) -> String {
        var out = ""
        for c in event {
            if c.isUppercase, !out.isEmpty { out.append("_") }
            out.append(contentsOf: c.lowercased())
        }
        return out
    }

    /// Trust keys of our current entries (`<path>:<snake_event>:<group index>:<handler index>`) with the hash Codex
    /// stores once the user trusts that entry.
    static func keys(for file: HookFile, hooksPath: String) throws -> [(key: String, hash: String)] {
        guard let doc = try file.load(), let events = HookFile.object(at: file.container, in: doc) else { return [] }
        var keys: [(key: String, hash: String)] = []
        for (event, _) in file.entries {
            guard let groups = events[event]?.arrayValue else { continue }
            outer: for (g, group) in groups.enumerated() {
                for (h, handler) in (group["hooks"]?.arrayValue ?? []).enumerated() where file.isCurrent(handler, event: event) {
                    keys.append(("\(hooksPath):\(snake(event)):\(g):\(h)", hash(event: event, handler: handler)))
                    break outer
                }
            }
        }
        return keys
    }

    /// Codex's trust hash of one command handler in a group without a matcher (ours): `sha256:` + hex SHA-256 of the
    /// compact, key-sorted JSON `{"event_name", "hooks": [{type, command, timeout, async}]}`, the timeout defaulting
    /// to 600 s (1 s for SessionEnd and Interrupt). Not documented; checked against hashes Codex 0.162 wrote.
    static func hash(event: String, handler: JSONValue) -> String {
        let snake = snake(event)
        let fallback = snake == "session_end" || snake == "interrupt" ? 1 : 600
        let timeout = handler["timeout"].flatMap { if case .number(let n) = $0 { return Int(n) } else { return nil } } ?? fallback
        let normalized: [String: Any] = [
            "event_name": snake,
            "hooks": [["type": "command", "command": HookFile.command(of: handler) ?? "", "timeout": timeout,
                       "async": handler["async"] == .bool(true)]],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
