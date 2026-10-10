import Foundation

/// How we tell an agent is on this Mac. A GUI app doesn't inherit the shell PATH, so binaries are probed in the
/// usual install locations; app bundles in /Applications and ~/Applications; and config files/dirs the agent
/// creates on first run.
struct Detection {
    var binaries: [String] = []
    /// App bundle names, optionally with the bundle id that must match (ChatGPT.app is Codex only as com.openai.codex).
    var apps: [(name: String, bundleID: String?)] = []
    /// Paths relative to home whose existence means the agent is installed.
    var paths: [String] = []
    /// Directory (relative to home) holding `<prefix>*` entries, e.g. VS Code extensions.
    var prefixed: [(dir: String, prefix: String)] = []

    func isInstalled(home: String) -> Bool {
        if paths.contains(where: { FileOps.exists(home + "/" + $0) }) { return true }
        if !binaries.isEmpty {
            let dirs = Self.binaryDirs(home: home)
            if binaries.contains(where: { bin in dirs.contains { FileOps.isExecutable($0 + "/" + bin) } }) { return true }
        }
        for (name, bundleID) in apps {
            for root in ["/Applications", home + "/Applications"] {
                let app = root + "/" + name
                guard FileOps.isDirectory(app) else { continue }
                guard let bundleID else { return true }
                let plist = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")
                if plist?["CFBundleIdentifier"] as? String == bundleID { return true }
            }
        }
        for (dir, prefix) in prefixed where FileOps.contents(ofDirectory: home + "/" + dir).contains(where: { $0.hasPrefix(prefix) }) {
            return true
        }
        return false
    }

    static func binaryDirs(home: String) -> [String] {
        var dirs = [
            "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
            home + "/.local/bin", home + "/bin", home + "/.bin", home + "/.bun/bin", home + "/.opencode/bin",
            home + "/.amp/bin", home + "/.npm-global/bin", home + "/.volta/bin", home + "/.fnm/bin",
            home + "/Library/pnpm", home + "/.yarn/bin", home + "/.cargo/bin", home + "/go/bin",
        ]
        let nvm = home + "/.nvm/versions/node"
        dirs += FileOps.contents(ofDirectory: nvm).sorted().map { nvm + "/" + $0 + "/bin" }
        return dirs
    }
}
