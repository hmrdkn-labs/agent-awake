import Foundation

/// A JSON value that keeps object key order and the exact text of numbers, so editing an agent's settings
/// file leaves every key we don't touch where the user put it.
enum JSONValue: Equatable {
    struct Member: Equatable {
        var key: String
        var value: JSONValue
        init(_ key: String, _ value: JSONValue) { self.key = key; self.value = value }
    }

    case object([Member])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    // MARK: Access

    subscript(key: String) -> JSONValue? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first { $0.key == key }?.value
    }

    /// Sets `key`, keeping its position if it exists and appending it otherwise. No-op on non-objects.
    mutating func set(_ key: String, _ value: JSONValue) {
        guard case .object(var pairs) = self else { return }
        if let i = pairs.firstIndex(where: { $0.key == key }) { pairs[i].value = value } else { pairs.append(Member(key, value)) }
        self = .object(pairs)
    }

    mutating func remove(_ key: String) {
        guard case .object(var pairs) = self else { return }
        pairs.removeAll { $0.key == key }
        self = .object(pairs)
    }

    var objectPairs: [Member]? { if case .object(let p) = self { return p }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }

    // MARK: Builders

    static func obj(_ pairs: [(String, JSONValue)]) -> JSONValue { .object(pairs.map { Member($0.0, $0.1) }) }
    static func int(_ n: Int) -> JSONValue { .number(String(n)) }

    // MARK: Output

    /// Pretty-printed with two-space indentation (the layout `JSON.stringify(x, null, 2)` produces).
    func serialized() -> String {
        var out = ""
        write(to: &out, indent: 0)
        return out
    }

    private func write(to out: inout String, indent: Int) {
        let pad = String(repeating: "  ", count: indent + 1), close = String(repeating: "  ", count: indent)
        switch self {
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            out += "{\n"
            for (i, pair) in pairs.enumerated() {
                out += pad + JSONValue.quote(pair.key) + ": "
                pair.value.write(to: &out, indent: indent + 1)
                out += i == pairs.count - 1 ? "\n" : ",\n"
            }
            out += close + "}"
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += pad
                item.write(to: &out, indent: indent + 1)
                out += i == items.count - 1 ? "\n" : ",\n"
            }
            out += close + "]"
        case .string(let s): out += JSONValue.quote(s)
        case .number(let n): out += n
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }
}

/// Strict JSON parser, optionally accepting JSONC comments (`//`, `/* */`) the way strip-json-comments does:
/// only outside strings, so `"https://…"` stays intact.
struct JSONParser {
    struct Failure: Error { let message: String; let line: Int }

    private let s: [UInt8]
    private var i = 0
    private let allowComments: Bool
    private(set) var sawComment = false

    init(_ text: String, allowComments: Bool) {
        s = Array(text.utf8)
        self.allowComments = allowComments
    }

    /// Parses a whole document. Returns the value and whether comments were skipped.
    static func parse(_ text: String, allowComments: Bool) throws -> (value: JSONValue, hadComments: Bool) {
        var p = JSONParser(text, allowComments: allowComments)
        if p.s.starts(with: [0xEF, 0xBB, 0xBF]) { p.i = 3 }
        try p.skip()
        let v = try p.value()
        try p.skip()
        guard p.i == p.s.count else { throw p.fail("unexpected text after the JSON value") }
        return (v, p.sawComment)
    }

    private func fail(_ message: String) -> Failure {
        Failure(message: message, line: s[0..<min(i, s.count)].reduce(1) { $0 + ($1 == 0x0A ? 1 : 0) })
    }

    private mutating func skip() throws {
        while i < s.count {
            switch s[i] {
            case 0x20, 0x09, 0x0A, 0x0D: i += 1
            case 0x2F where i + 1 < s.count && (s[i + 1] == 0x2F || s[i + 1] == 0x2A):
                guard allowComments else { throw fail("comments are not allowed in this file") }
                sawComment = true
                if s[i + 1] == 0x2F {
                    while i < s.count && s[i] != 0x0A { i += 1 }
                } else {
                    i += 2
                    while i + 1 < s.count && !(s[i] == 0x2A && s[i + 1] == 0x2F) { i += 1 }
                    guard i + 1 < s.count else { throw fail("unterminated comment") }
                    i += 2
                }
            default: return
            }
        }
    }

    private mutating func value() throws -> JSONValue {
        guard i < s.count else { throw fail("unexpected end of file") }
        switch s[i] {
        case UInt8(ascii: "{"): return try object()
        case UInt8(ascii: "["): return try array()
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try number())
        default: throw fail("unexpected character")
        }
    }

    private mutating func literal(_ word: String) throws {
        let w = Array(word.utf8)
        guard i + w.count <= s.count, Array(s[i..<i + w.count]) == w else { throw fail("invalid literal") }
        i += w.count
    }

    private mutating func digits() -> Int {
        let start = i
        while i < s.count, (0x30...0x39).contains(s[i]) { i += 1 }
        return i - start
    }

    private mutating func number() throws -> String {
        let start = i
        if s[i] == UInt8(ascii: "-") { i += 1 }
        guard i < s.count else { throw fail("invalid number") }
        if s[i] == UInt8(ascii: "0") { i += 1 } else if digits() == 0 { throw fail("invalid number") }
        if i < s.count, s[i] == UInt8(ascii: ".") { i += 1; if digits() == 0 { throw fail("invalid number") } }
        if i < s.count, s[i] == UInt8(ascii: "e") || s[i] == UInt8(ascii: "E") {
            i += 1
            if i < s.count, s[i] == UInt8(ascii: "+") || s[i] == UInt8(ascii: "-") { i += 1 }
            if digits() == 0 { throw fail("invalid number") }
        }
        return String(decoding: s[start..<i], as: UTF8.self)
    }

    private mutating func string() throws -> String {
        i += 1
        var bytes: [UInt8] = []
        while i < s.count {
            let c = s[i]
            if c == UInt8(ascii: "\"") { i += 1; return String(decoding: bytes, as: UTF8.self) }
            if c < 0x20 { throw fail("control character in string") }
            if c != UInt8(ascii: "\\") { bytes.append(c); i += 1; continue }
            i += 1
            guard i < s.count else { break }
            let e = s[i]; i += 1
            switch e {
            case UInt8(ascii: "\""): bytes.append(0x22)
            case UInt8(ascii: "\\"): bytes.append(0x5C)
            case UInt8(ascii: "/"): bytes.append(0x2F)
            case UInt8(ascii: "b"): bytes.append(0x08)
            case UInt8(ascii: "f"): bytes.append(0x0C)
            case UInt8(ascii: "n"): bytes.append(0x0A)
            case UInt8(ascii: "r"): bytes.append(0x0D)
            case UInt8(ascii: "t"): bytes.append(0x09)
            case UInt8(ascii: "u"):
                var code = try hex4()
                if (0xD800...0xDBFF).contains(code), i + 1 < s.count, s[i] == UInt8(ascii: "\\"), s[i + 1] == UInt8(ascii: "u") {
                    i += 2
                    let low = try hex4()
                    guard (0xDC00...0xDFFF).contains(low) else { throw fail("invalid surrogate pair") }
                    code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                }
                guard let scalar = Unicode.Scalar(code) else { throw fail("invalid unicode escape") }
                bytes.append(contentsOf: Array(String(Character(scalar)).utf8))
            default: throw fail("invalid escape")
            }
        }
        throw fail("unterminated string")
    }

    private mutating func hex4() throws -> UInt32 {
        guard i + 4 <= s.count, let v = UInt32(String(decoding: s[i..<i + 4], as: UTF8.self), radix: 16) else {
            throw fail("invalid unicode escape")
        }
        i += 4
        return v
    }

    private mutating func object() throws -> JSONValue {
        i += 1
        var pairs: [JSONValue.Member] = []
        try skip()
        if i < s.count, s[i] == UInt8(ascii: "}") { i += 1; return .object(pairs) }
        while true {
            try skip()
            guard i < s.count, s[i] == UInt8(ascii: "\"") else { throw fail("expected a key") }
            let key = try string()
            try skip()
            guard i < s.count, s[i] == UInt8(ascii: ":") else { throw fail("expected ':'") }
            i += 1
            try skip()
            let v = try value()
            if pairs.contains(where: { $0.key == key }) { throw fail("duplicate key \"\(key)\"") }
            pairs.append(JSONValue.Member(key, v))
            try skip()
            guard i < s.count else { throw fail("unexpected end of file") }
            if s[i] == UInt8(ascii: ",") { i += 1; continue }
            if s[i] == UInt8(ascii: "}") { i += 1; return .object(pairs) }
            throw fail("expected ',' or '}'")
        }
    }

    private mutating func array() throws -> JSONValue {
        i += 1
        var items: [JSONValue] = []
        try skip()
        if i < s.count, s[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
        while true {
            try skip()
            items.append(try value())
            try skip()
            guard i < s.count else { throw fail("unexpected end of file") }
            if s[i] == UInt8(ascii: ",") { i += 1; continue }
            if s[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
            throw fail("expected ',' or ']'")
        }
    }
}
