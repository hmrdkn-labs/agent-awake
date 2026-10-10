import Foundation

public enum IntegrationError: LocalizedError, Equatable {
    /// The file exists but isn't valid JSON (or has syntax the agent doesn't allow). Nothing was changed.
    case unparseable(path: String, reason: String, snippet: String)
    /// A file at a path we own (plugin, extension) was not written by Agent Awake. Nothing was changed.
    case notOurs(path: String)
    /// The file has an unexpected shape where our hooks go (for example `hooks` is a list). Nothing was changed.
    case unexpectedShape(path: String, detail: String, snippet: String)
    case cliMissing(path: String)
    case write(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .unparseable(path, reason, snippet):
            return "Agent Awake left \(path) unchanged because it couldn't read it (\(reason)). "
                + "Fix the file, or add this to it yourself:\n\n\(snippet)"
        case let .notOurs(path):
            return "\(path) already exists and wasn't created by Agent Awake, so it was left alone. "
                + "Move it away and connect again."
        case let .unexpectedShape(path, detail, snippet):
            return "Agent Awake left \(path) unchanged: \(detail). Add this to it yourself:\n\n\(snippet)"
        case let .cliMissing(path):
            return "The agentawake command line tool isn't at \(path)."
        case let .write(path, reason):
            return "Couldn't write \(path): \(reason)"
        }
    }
}

enum FileOps {
    static let backupSuffix = ".agentawake-backup"
    private static var fm: FileManager { .default }

    static func exists(_ path: String) -> Bool { fm.fileExists(atPath: path) }

    /// File text, or nil when the file doesn't exist. Throws when it exists but can't be read as UTF-8.
    static func read(_ path: String) throws -> String? {
        guard exists(path) else { return nil }
        guard let data = fm.contents(atPath: path) else { throw IntegrationError.write(path: path, reason: "it can't be read") }
        guard let text = String(data: data, encoding: .utf8) else {
            throw IntegrationError.unparseable(path: path, reason: "it isn't UTF-8 text", snippet: "")
        }
        return text
    }

    /// Follows symlinks so a dotfiles-managed settings file is edited in place, not replaced by a regular file.
    static func resolved(_ path: String) -> String {
        var current = path
        for _ in 0..<16 {
            guard let dest = try? fm.destinationOfSymbolicLink(atPath: current) else { return current }
            current = dest.hasPrefix("/") ? dest : ((current as NSString).deletingLastPathComponent as NSString).appendingPathComponent(dest)
        }
        return current
    }

    static func backupPath(_ path: String) -> String { path + backupSuffix }

    /// Absolute path with every symlink resolved (realpath), as Codex keys its hook trust state.
    static func canonical(_ path: String) -> String {
        guard let p = realpath(path, nil) else { return path }
        defer { free(p) }
        return String(cString: p)
    }

    /// Copies the current contents to `<path>.agentawake-backup` the first time we edit a file.
    static func backupOnce(_ path: String) throws {
        let backup = backupPath(path)
        guard exists(path), !exists(backup), let data = fm.contents(atPath: path) else { return }
        do { try data.write(to: URL(fileURLWithPath: backup), options: .withoutOverwriting) } catch {
            throw IntegrationError.write(path: backup, reason: error.localizedDescription)
        }
    }

    /// Writes through symlinks, atomically (temp file + rename), keeping the file's permissions.
    static func writeAtomically(_ text: String, to path: String) throws {
        let target = resolved(path)
        let dir = (target as NSString).deletingLastPathComponent
        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let perms = (try? fm.attributesOfItem(atPath: target))?[.posixPermissions]
            try Data(text.utf8).write(to: URL(fileURLWithPath: target), options: .atomic)
            if let perms { try fm.setAttributes([.posixPermissions: perms], ofItemAtPath: target) }
        } catch {
            throw IntegrationError.write(path: path, reason: error.localizedDescription)
        }
    }

    static func remove(_ path: String) throws {
        guard exists(path) || (try? fm.destinationOfSymbolicLink(atPath: path)) != nil else { return }
        do { try fm.removeItem(atPath: path) } catch {
            throw IntegrationError.write(path: path, reason: error.localizedDescription)
        }
    }

    /// Removes `dir` and then its parents up to (not including) `stop`, each only while empty.
    static func removeEmptyDirs(_ dir: String, stop: String) {
        var current = dir
        while current.hasPrefix(stop + "/"), current != stop {
            guard let items = try? fm.contentsOfDirectory(atPath: current) else { return }
            if items.contains(where: { $0 != ".DS_Store" }) { return }
            try? fm.removeItem(atPath: current)
            current = (current as NSString).deletingLastPathComponent
        }
    }

    static func isExecutable(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue && fm.isExecutableFile(atPath: path)
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    static func contents(ofDirectory path: String) -> [String] { (try? fm.contentsOfDirectory(atPath: path)) ?? [] }
}
