import Foundation

/// Watches heat and memory while agents work, and keeps the Mac usable:
/// - elevated (hot, or memory low): agents hold new tool calls (their hooks wait on `holding`), and
///   processes they started run at background priority while it's hot;
/// - memory critical: the largest process an agent started is paused (or killed, if the user chose so),
///   one at a time, until memory recovers. Paused processes continue once memory is back to normal.
/// Never touches the agents themselves or anything an agent didn't start.
public final class StrainGuard {
    /// Processes smaller than this aren't worth pausing: they won't relieve memory.
    public static let minRelief: UInt64 = 256 << 20
    /// Wait this long after acting before acting again, so memory has time to recover.
    public static let reliefCooldown: Double = 30

    private let engine: Engine
    private let sensor: StrainSensing
    private let relief: ReliefActing
    private let notifier: Notifier
    private let config: () -> Config
    private let now: () -> Double
    private let lock = NSLock()
    private var strain = Strain.normal
    private var throttled: Set<Int32> = []
    private var paused: [Int32: String] = [:]          // pid -> name, for the resume ping
    private var lastRelief: Double = -.infinity
    private var timer: DispatchSourceTimer?
    /// Called (on an arbitrary thread) when the strain or holding state changes.
    public var onChange: ((Strain, Bool) -> Void)?

    public init(engine: Engine, sensor: StrainSensing, relief: ReliefActing, notifier: Notifier,
                config: @escaping () -> Config = { Config.load() },
                now: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.engine = engine; self.sensor = sensor; self.relief = relief; self.notifier = notifier
        self.config = config; self.now = now
    }

    public func start(interval: Double = 5) {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "agentawake.strain"))
        t.schedule(deadline: .now(), repeating: interval, leeway: .seconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// Current strain, and whether agents should hold new tool calls.
    public func report() -> (Strain, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (strain, holds(strain))
    }

    private func holds(_ s: Strain) -> Bool {
        s.level >= .elevated && config().effectiveHoldWhenStrained
    }

    public func tick() {
        let s = sensor.read()
        let agents = Dictionary(engine.store.list().compactMap { i in i.pid.map { (i.name, $0) } },
                                uniquingKeysWith: { a, _ in a })
        let titles = Dictionary(engine.store.list().map { ($0.name, $0.title) }, uniquingKeysWith: { a, _ in a })
        let cfg = config()
        var alerts: [Alert] = []

        lock.lock()
        let before = strain
        strain = s
        let children = (s.level > .normal || !throttled.isEmpty) && !agents.isEmpty ? relief.agentChildren(of: agents) : []

        // Heat: agent-started work runs on efficiency cores until it cools down.
        if s.thermal >= .elevated {
            for c in children where !throttled.contains(c.pid) && relief.throttle(c.pid, true) { throttled.insert(c.pid) }
        } else if !throttled.isEmpty {
            for pid in throttled { relief.throttle(pid, false) }
            throttled = []
        }
        throttled = throttled.filter { ProcessList.isAlive($0) }

        // Memory almost full: one process at a time, largest first.
        if s.memory == .critical, cfg.effectiveMemoryRelief != .none, now() - lastRelief >= Self.reliefCooldown,
           let c = children.first(where: { paused[$0.pid] == nil && $0.footprint >= Self.minRelief }) {
            let size = ByteCountFormatter.string(fromByteCount: Int64(c.footprint), countStyle: .memory)
            let who = titles[c.session] ?? c.session
            if cfg.effectiveMemoryRelief == .kill {
                if relief.terminate(c.pid) {
                    lastRelief = now()
                    alerts.append(Alert(title: "Memory almost full: stopped \(c.name)",
                                        body: "\(who) started it; it was using \(size). The agent will see the command fail.",
                                        level: .urgent, session: c.session))
                }
            } else if relief.pause(c.pid) {
                lastRelief = now()
                paused[c.pid] = c.name
                alerts.append(Alert(title: "Memory almost full: paused \(c.name)",
                                    body: "\(who) started it; it's using \(size). It continues when memory recovers.",
                                    level: .urgent, session: c.session))
            }
        }
        // Continue paused work once memory is back to normal (not merely below critical, so it doesn't flap).
        var resumed: [String] = []
        if s.memory == .normal, !paused.isEmpty {
            resumed = paused.values.sorted()
            for pid in paused.keys { relief.resume(pid) }
            paused = [:]
        }
        paused = paused.filter { ProcessList.isAlive($0.key) }
        let holding = holds(s), wasHolding = holds(before)
        lock.unlock()

        let continued = resumed.isEmpty ? "" : " Continued \(resumed.joined(separator: ", "))."
        if holding && !wasHolding && !agents.isEmpty {
            alerts.append(Alert(title: "\(s.reason ?? "Mac is strained"): holding agents",
                                body: "\(agents.count) agent\(agents.count == 1 ? "" : "s") will wait before their next step until it recovers.",
                                level: s.level == .critical ? .urgent : .info))
        } else if !holding && wasHolding && !agents.isEmpty {
            alerts.append(Alert(title: "Back to normal", body: "Agents continue." + continued, level: .info))
        } else if !resumed.isEmpty {
            alerts.append(Alert(title: "Memory recovered", body: continued.trimmingCharacters(in: .whitespaces), level: .info))
        }
        alerts.forEach(notifier.send)
        if s != before || holding != wasHolding { onChange?(s, holding) }
    }

    /// On quit: nothing stays paused or throttled behind the user's back.
    public func releaseAll() {
        lock.lock(); defer { lock.unlock() }
        for pid in paused.keys { relief.resume(pid) }
        for pid in throttled { relief.throttle(pid, false) }
        paused = [:]; throttled = []
    }
}
