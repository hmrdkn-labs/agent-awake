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
