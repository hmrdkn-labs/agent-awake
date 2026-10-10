import Darwin

/// Running-process lookup through libproc: no subprocess, no root, no permission prompt.
public enum ProcessList {
    /// Short names (as `ps -o comm` shows, without the path) of all processes the user can see.
    public static func names() -> Set<String> {
        var out = Set<String>()
        var buf = [CChar](repeating: 0, count: 256)
        for pid in allPIDs() where proc_name(pid, &buf, UInt32(buf.count)) > 0 {
            out.insert(String(cString: buf))
        }
        return out
    }

    public static func contains(_ name: String) -> Bool { names().contains(name) }

    public static func name(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        return proc_name(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
    }

    public static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbsi_ppid)
    }

    /// Current working directory of a process the user owns.
    public static func cwd(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    /// Environment variables of a process the user owns (KERN_PROCARGS2: argc, exec path, argv, env).
    public static func environment(_ pid: pid_t) -> [String: String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [:] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return [:] }
        let argc = buf.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        // NUL-separated strings after argc; skip the exec path, padding NULs, then argc args.
        let strings = buf[MemoryLayout<Int32>.size..<size].split(separator: 0, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
        var env: [String: String] = [:]
        for s in strings.dropFirst(1 + argc) {
            guard let eq = s.firstIndex(of: "=") else { continue }
            env[String(s[..<eq])] = String(s[s.index(after: eq)...])
        }
        return env
    }

    public static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Direct children of `pid` started at or after `since` (Unix seconds).
    public static func childrenStarted(of pid: pid_t, since: Double) -> [pid_t] {
        let n = proc_listchildpids(pid, nil, 0)
        guard n > 0 else { return [] }
        var kids = [pid_t](repeating: 0, count: Int(n) + 16)
        let got = kids.withUnsafeMutableBufferPointer {
            proc_listchildpids(pid, $0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }
        return kids.prefix(Int(max(0, got))).filter { kid in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard kid > 0, proc_pidinfo(kid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
            return Double(info.pbi_start_tvsec) >= since
        }
    }

    private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let n = pids.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }
        return pids.prefix(Int(max(0, n))).filter { $0 > 0 }
    }
}

/// What the engine needs to know about an agent's process when its session goes quiet.
public protocol ProcessProbe {
    func isAlive(_ pid: Int32) -> Bool
    /// The agent started a process (a build, tests) since `since`: quiet is not stuck. Long-lived children
    /// such as MCP servers started earlier and don't count.
    func isBusy(_ pid: Int32, since: Double) -> Bool
}

public struct LiveProcessProbe: ProcessProbe {
    public init() {}
    public func isAlive(_ pid: Int32) -> Bool { ProcessList.isAlive(pid) }
    public func isBusy(_ pid: Int32, since: Double) -> Bool {
        !ProcessList.childrenStarted(of: pid, since: since - 5).isEmpty
    }
}
