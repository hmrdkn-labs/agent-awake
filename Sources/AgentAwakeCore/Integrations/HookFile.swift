import Foundation

/// Our hook entries inside a JSON settings file the agent shares with the user (Claude's settings.json, Codex's
/// hooks.json, Cursor's hooks.json, …). Connect merges; disconnect removes exactly the entries whose command
/// contains `agentawake hook`; everything else in the file is kept as it was, in order.
struct HookFile {
    let path: String
    let agent: String
    /// Key path of the object that maps event names to entry arrays: `["hooks"]` in most files, `[]` when the
    /// events sit at the top level (Factory Droid's hooks.json).
    let container: [String]
    /// The agent itself reads the file as JSONC. Comments are skipped (outside strings only); since they can't be
    /// written back, the first edit keeps the original in the backup.
    let allowComments: Bool
    /// What we register: one array element per catalog event, in catalog order.
    let entries: [(event: String, entry: JSONValue)]
    /// Top-level keys set when missing (Cursor wants `"version": 1`). Ignored when deciding whether a file we
    /// created is empty again.
    var defaults: [(String, JSONValue)] = []

    static let marker = "agentawake hook"

    // MARK: Status

    struct Presence: Equatable {
        var exact: Set<String> = []      // events whose exact current command is registered
        var ours = 0                     // all entries carrying the marker
        var stale = 0                    // ours but not current (old path, old event, other agent id)
    }

    func presence() throws -> Presence {
        guard let doc = try load(), let events = Self.object(at: container, in: doc)?.objectPairs else { return Presence() }
        var p = Presence()
        for member in events {
            let event = member.key, value = member.value
            for element in value.arrayValue ?? [] {
                for handler in Self.handlers(in: element) {
                    guard let command = Self.command(of: handler), command.contains(Self.marker) else { continue }
                    p.ours += 1
                    if isCurrent(handler, event: event), !p.exact.contains(event) { p.exact.insert(event) } else { p.stale += 1 }
                }
            }
        }
        return p
    }

    var allEvents: Set<String> { Set(entries.map(\.event)) }

    // MARK: Connect / disconnect

    func connect() throws {
        let original = try load()
        var doc = original ?? .object([])
        guard case .object = doc else { throw shapeError("the top level isn't a JSON object") }
        var events = try eventsObject(in: doc)

        var found: Set<String> = []
        var pairs = events.objectPairs ?? []
        for index in pairs.indices {
            let event = pairs[index].key
            guard var items = pairs[index].value.arrayValue else {
                if allEvents.contains(event) { throw shapeError("\"\(event)\" isn't a list") }
                continue
            }
            var changed = false
            items = items.compactMap { element in
                // Keep everything that isn't ours, and the first copy of our current command for this event.
                let kept = strip(element) { handler in
                    guard let command = Self.command(of: handler), command.contains(Self.marker) else { return true }
                    guard isCurrent(handler, event: event), !found.contains(event) else { return false }
                    found.insert(event)
                    return true
                }
                if kept != element { changed = true }
                return kept
            }
            if changed { pairs[index].value = .array(items) }
        }
        events = .object(pairs)
        for (event, entry) in entries where !found.contains(event) {
            var items = events[event]?.arrayValue ?? []
            items.append(entry)
            events.set(event, .array(items))
        }
        // Lists we emptied while dropping stale entries go away; empty lists the user had stay.
        if let before = try eventsObject(in: doc).objectPairs {
            let emptied = Set(before.filter { ($0.value.arrayValue?.isEmpty == false) }.map(\.key))
            events = .object((events.objectPairs ?? []).filter { !(emptied.contains($0.key) && $0.value.arrayValue?.isEmpty == true) })
        }
        doc = Self.setting(events, at: container, in: doc)
        for (key, value) in defaults where doc[key] == nil { doc.set(key, value) }

        guard doc != original else { return }
        try FileOps.backupOnce(path)
        try FileOps.writeAtomically(doc.serialized() + "\n", to: path)
    }

    func disconnect() throws {
        guard let original = try load(), case .object = original,
              let events = Self.object(at: container, in: original), var pairs = events.objectPairs else { return }
        var touched = false
        for index in pairs.indices {
            guard let items = pairs[index].value.arrayValue else { continue }
            let kept = items.compactMap { strip($0) { !(Self.command(of: $0)?.contains(Self.marker) ?? false) } }
            if kept != items { pairs[index].value = .array(kept); touched = true }
        }
        guard touched else { return }
        let emptied = Set(pairs.filter { $0.value.arrayValue?.isEmpty == true }.map(\.key))
            .subtracting((events.objectPairs ?? []).filter { $0.value.arrayValue?.isEmpty == true }.map(\.key))
        pairs.removeAll { emptied.contains($0.key) }

        var doc = original
        if pairs.isEmpty, !container.isEmpty {
            doc = Self.removing(container, in: doc)
        } else {
            doc = Self.setting(.object(pairs), at: container, in: doc)
        }
        // A file we created (no backup was needed) that holds nothing else is deleted rather than left empty.
        let defaultKeys = Set(defaults.map(\.0))
        if !FileOps.exists(FileOps.backupPath(path)), (doc.objectPairs ?? []).allSatisfy({ defaultKeys.contains($0.key) }) {
            try FileOps.remove(path)
            return
        }
        try FileOps.backupOnce(path)
        try FileOps.writeAtomically(doc.serialized() + "\n", to: path)
    }

    // MARK: Snippet shown when we refuse to edit

    var snippet: String {
        var events = JSONValue.object([])
        for (event, entry) in entries { events.set(event, .array([entry])) }
        var doc = JSONValue.obj(defaults)
        doc = Self.setting(events, at: container, in: doc)
        return doc.serialized()
    }

    // MARK: Helpers

    func desiredCommand(_ event: String) -> String? {
        desiredHandler(event).flatMap(Self.command(of:))
    }

    /// Our handler (or flat entry) for `event`, as connect writes it.
    func desiredHandler(_ event: String) -> JSONValue? {
        entries.first { $0.event == event }.flatMap { Self.handlers(in: $0.entry).first }
    }

    /// An existing handler of ours is current when it has every field we write, with our values; fields the agent
    /// adds are fine. So a changed timeout or `async` (the tool gate's long synchronous wait) makes an old one stale,
    /// and Connect rewrites it.
    func isCurrent(_ handler: JSONValue, event: String) -> Bool {
        guard let pairs = desiredHandler(event)?.objectPairs else { return false }
        return pairs.allSatisfy { handler[$0.key] == $0.value }
    }

    /// Parsed file, nil when it doesn't exist or is blank.
    func load() throws -> JSONValue? {
        guard let text = try FileOps.read(path) else { return nil }
        if text.allSatisfy({ $0.isWhitespace }) { return nil }
        do {
            return try JSONParser.parse(text, allowComments: allowComments).value
        } catch let failure as JSONParser.Failure {
            throw IntegrationError.unparseable(path: path, reason: "\(failure.message) on line \(failure.line)", snippet: snippet)
        }
    }

    private func shapeError(_ detail: String) -> IntegrationError {
        .unexpectedShape(path: path, detail: detail, snippet: snippet)
    }

    private func eventsObject(in doc: JSONValue) throws -> JSONValue {
        var current = doc
        for key in container {
            guard let next = current[key] else { return .object([]) }
            guard case .object = next else { throw shapeError("\"\(key)\" isn't a JSON object") }
            current = next
        }
        return current
    }

    /// Drops hook handlers for which `keep` is false (handlers without a command are kept). A matcher group whose
    /// `hooks` list becomes empty, or a flat entry that is dropped, disappears (nil).
    private func strip(_ element: JSONValue, keep: (JSONValue) -> Bool) -> JSONValue? {
        if Self.command(of: element) != nil { return keep(element) ? element : nil }
        guard let inner = element["hooks"]?.arrayValue else { return element }
        let kept = inner.filter { handler in Self.command(of: handler) == nil || keep(handler) }
        if kept.count == inner.count { return element }
        if kept.isEmpty { return nil }
        var copy = element
        copy.set("hooks", .array(kept))
        return copy
    }

    /// The shell command of a flat entry or handler (`command`, or Copilot's `bash`).
    static func command(of element: JSONValue) -> String? {
        element["command"]?.stringValue ?? element["bash"]?.stringValue
    }

    static func commands(in element: JSONValue) -> [String] {
        handlers(in: element).compactMap(command(of:))
    }

    /// A flat entry is its own handler; a matcher group holds them in `hooks`.
    static func handlers(in element: JSONValue) -> [JSONValue] {
        if command(of: element) != nil { return [element] }
        return element["hooks"]?.arrayValue ?? []
    }

    static func object(at path: [String], in doc: JSONValue) -> JSONValue? {
        var current = doc
        for key in path {
            guard let next = current[key] else { return nil }
            current = next
        }
        guard case .object = current else { return nil }
        return current
    }

    static func setting(_ value: JSONValue, at path: [String], in doc: JSONValue) -> JSONValue {
        guard let key = path.first else { return value }
        var copy = doc
        var child = JSONValue.object([])
        if let existing = doc[key], case .object = existing { child = existing }
        copy.set(key, setting(value, at: Array(path.dropFirst()), in: child))
        return copy
    }

    static func removing(_ path: [String], in doc: JSONValue) -> JSONValue {
        guard let key = path.first else { return doc }
        var copy = doc
        if path.count == 1 { copy.remove(key); return copy }
        guard let child = doc[key] else { return doc }
        copy.set(key, removing(Array(path.dropFirst()), in: child))
        return copy
    }
}
