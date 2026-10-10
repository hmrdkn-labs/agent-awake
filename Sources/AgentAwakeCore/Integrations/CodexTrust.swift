import Foundation

/// Codex skips user hooks until the user trusts them. Trust is stored in `~/.codex/config.toml` as
/// `[hooks.state."<abs hooks.json>:<snake_event>:<group>:<handler>"]` with a `trusted_hash`. We only read it:
/// trusting is the user's security decision (Codex CLI: "Trust all and continue", or /hooks).
enum CodexTrust {
    struct State { var trusted: Set<String> = []; var disabled: Set<String> = []; var hooksOff = false }

    /// Keys of the `hooks.state` tables that hold a `trusted_hash`, those with `enabled = false`, and whether
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
                if parts[0] == "trusted_hash", value.count > 2 { state.trusted.insert(key) }
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

    /// Trust keys of our current entries: `<path>:<snake_event>:<group index>:<handler index>`.
    static func keys(for file: HookFile, hooksPath: String) throws -> [String] {
        guard let doc = try file.load(), let events = HookFile.object(at: file.container, in: doc) else { return [] }
        var keys: [String] = []
        for (event, _) in file.entries {
            guard let groups = events[event]?.arrayValue, let wanted = file.desiredCommand(event) else { continue }
            outer: for (g, group) in groups.enumerated() {
                for (h, handler) in (group["hooks"]?.arrayValue ?? []).enumerated() where HookFile.command(of: handler) == wanted {
                    keys.append("\(hooksPath):\(snake(event)):\(g):\(h)")
                    break outer
                }
            }
        }
        return keys
    }
}
