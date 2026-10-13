import Foundation
import IOKit

/// One line a minute in `~/.agent-awake/strain.log` (tab-separated, header on top), so the heat limits can be
/// tuned from real days, e.g. a trip home in a bag. Rotates to `strain.log.1` at `maxBytes`. Stays on the Mac.
public final class StrainLog {
    public static let maxBytes = 2 << 20
    static let header = "time\tbattery_c\tchip_c\tthermal\tmemory\tswap_gb\tholding\tagents\tbattery_pct\ton_battery\tlid_closed\n"

    private let path: String
    private let lock = NSLock()

    public init(path: String = Paths.dir + "/strain.log") { self.path = path }

    public func append(strain s: Strain, holding: Bool, agents: Int, power: PowerState, lidClosed: Bool?, at date: Date = Date()) {
        func f(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "" }
        let line = [ISO8601DateFormatter().string(from: date), f(s.batteryTemp), f(s.chipTemp), "\(s.thermal)", "\(s.memory)",
                    f(s.swapUsed.map { Double($0) / Double(1 << 30) }), "\(holding)", "\(agents)",
                    power.batteryPercent.map(String.init) ?? "", "\(power.onBattery)", lidClosed.map { "\($0)" } ?? ""]
            .joined(separator: "\t") + "\n"
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int, size >= Self.maxBytes {
            try? fm.removeItem(atPath: path + ".1")
            try? fm.moveItem(atPath: path, toPath: path + ".1")
        }
        if !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            fm.createFile(atPath: path, contents: Data(Self.header.utf8), attributes: [.posixPermissions: 0o600])
        }
        guard let h = FileHandle(forWritingAtPath: path) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(line.utf8))
    }

    /// Whether the lid is closed (IOPMrootDomain's AppleClamshellState); nil on desktops or if unreadable.
    public static func lidClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }
}
