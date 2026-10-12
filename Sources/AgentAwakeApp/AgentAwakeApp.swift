import SwiftUI
import ServiceManagement
import AgentAwakeCore

@MainActor
final class Model: ObservableObject {
    static let shared = Model()

    @Published var sessions: [SessionInfo] = []
    @Published var error: String?
    /// Heat and memory, and whether agents are holding because of them.
    @Published var strain = Strain.normal
    @Published var holding = false
    @Published var helper: HelperState = HelperInstaller.state()
    /// "Stay awake with the lid closed" (needs the privileged helper).
    @Published var lidMode = UserDefaults.standard.bool(forKey: "lidMode") {
        didSet {
            guard lidMode != oldValue else { return }
            UserDefaults.standard.set(lidMode, forKey: "lidMode")
            if lidMode {
                helper = HelperInstaller.register()
                if helper == .needsApproval { HelperInstaller.openSettings() }
            }
            syncLid()
        }
    }
    /// Follow herdr agents automatically (on by default when herdr is installed).
    @Published var herdrWatch = UserDefaults.standard.object(forKey: "herdrWatch") as? Bool ?? true {
        didSet {
            guard herdrWatch != oldValue else { return }
            UserDefaults.standard.set(herdrWatch, forKey: "herdrWatch")
            applyHerdr()
        }
    }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { self.error = "Launch at login: \(error.localizedDescription)" }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
    @Published var cliInstalled = CLIInstaller.isInstalled
    /// Saved config; the Settings window edits a draft and saves through `saveConfig`.
    @Published private(set) var config: Config
    @Published private(set) var integrations: [IntegrationState] = []

    struct IntegrationState {
        let integration: Integration
        let status: IntegrationStatus
    }

    var topic: String { config.ntfyTopic ?? "" }
    var ntfyServer: String { (config.ntfyServer ?? "https://ntfy.sh").trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    let herdrPath: String? = HerdrCLI.locate()
    let engine: Engine
    private let local: LocalNotifier
    private let router: AlertRouter
    private let lid: LidGuard
    private let server: SocketServer
    private let assertions: AssertionWatcher
    let strainGuard: StrainGuard
    private var herdr: HerdrWatcher?
    private var poll: Timer?

    var agents: [SessionInfo] { sessions.filter { $0.name != Engine.manualName } }
    var manual: SessionInfo? { sessions.first { $0.name == Engine.manualName } }
    var connectedCount: Int { integrations.filter { if case .connected = $0.status { return true }; return false }.count }
    var needsActionCount: Int { integrations.filter { if case .needsAction = $0.status { return true }; return false }.count }

    private init() {
        let initial = Config.loadEnsuringTopic()
        config = initial
        let local = LocalNotifier()
        self.local = local
        // Reads the saved config per alert, so Settings changes apply without a restart.
        let router = AlertRouter(config: { Config.load() }, local: local)
        self.router = router
        let e = Engine(notifier: router)
        engine = e
        lid = LidGuard(controller: XPCSleepController(), notifier: router)
        assertions = AssertionWatcher(engine: e)
        // "show" comes from a second launch of the app, "settings" from `agentawake settings`;
        // everything else is session traffic.
        server = SocketServer { [e] req in
            switch req.cmd {
            case "show":
                DispatchQueue.main.async { WelcomeWindow.show() }
                return Response(ok: true)
            case "settings":
                let tab: SettingsWindow.Tab = req.name == "notifications" ? .notifications : req.name == "general" ? .general : .agents
                DispatchQueue.main.async { SettingsWindow.show(tab) }
                return Response(ok: true)
            default:
                break
            }
            return e.handle(req)
        }
        let g = StrainGuard(engine: e, sensor: LiveStrainSensor(), relief: LiveRelief(), notifier: router)
        strainGuard = g
        e.strainReport = { [g] in g.report() }
        e.onChange = { [weak self] list in
            DispatchQueue.main.async { self?.apply(list) }
        }
        g.onChange = { [weak self] s, holding in
            DispatchQueue.main.async { self?.strain = s; self?.holding = holding }
        }
        g.start()
        do { try server.start(); e.start() } catch SocketError.alreadyRunning {
            // Another copy is running: bring up its window instead of starting a second daemon.
            _ = try? Client.send(Request(cmd: "show"))
            exit(0)
        } catch { self.error = "\(error)" }
        // Hooks call ~/.agent-awake/bin/agentawake; keep it pointing at this copy of the app.
        if CLIInstaller.canInstall {
            do { try Integrations.installShim(cliPath: CLIInstaller.source) } catch { self.error = "Hook command: \(error.localizedDescription)" }
        }
        lid.start()
        if lidMode && helper != .ready && helper != .needsApproval { helper = HelperInstaller.register() }
        FileHandle.standardError.write(Data("[agentawake] helper: \(helper.label)\n".utf8))
        refreshIntegrations()
        applyHerdr()
        assertions.start()
        // Helper approval and Codex hook trust happen outside the app; notice them without a relaunch.
        poll = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshHelper() }
        }
        syncLid()
    }

    private func applyHerdr() {
        herdr?.stop(); herdr = nil
        assertions.herdrFollowsPanes = herdrWatch && herdrPath != nil
        guard herdrWatch, let path = herdrPath else { return }
        let w = HerdrWatcher(engine: engine) { HerdrCLI.listAgents(herdr: path) }
        w.skipAgents = hookedAgents
        w.start()
        herdr = w
    }

    /// Agents that report through their own hooks; the herdr and assertion watchers leave them alone.
    private var hookedAgents: Set<String> {
        Set(integrations.compactMap { if case .connected = $0.status { return $0.integration.id }; return nil })
    }

    func refreshIntegrations() {
        integrations = Integrations.all().map { IntegrationState(integration: $0, status: $0.status()) }
        herdr?.skipAgents = hookedAgents
        assertions.skipAgents = hookedAgents
    }

    func connect(_ i: Integration) {
        do { try i.connect() } catch { self.error = "\(i.name): \(error.localizedDescription)" }
        refreshIntegrations()
    }

    func disconnect(_ i: Integration) {
        do { try i.disconnect() } catch { self.error = "\(i.name): \(error.localizedDescription)" }
        refreshIntegrations()
    }

    func saveConfig(_ c: Config) {
        do { try c.save(); config = c } catch { self.error = "Settings: \(error.localizedDescription)" }
    }

    func refreshHelper() {
        let s = HelperInstaller.state()
        if s != helper {
            helper = s
            FileHandle.standardError.write(Data("[agentawake] helper: \(s.label)\n".utf8))
        }
        if s == .ready { syncLid() }
    }

    /// nil = off, 0 = until turned off, otherwise seconds.
    func keepAwake(_ duration: Double?) { engine.setManual(duration: duration) }

    /// Straight to the phone (or one channel), whether or not the user is at the Mac. `result` gets the
    /// outcome on the main thread, so the UI can say "Sent" or why it failed.
    func testPing(channel: String? = nil, result: ((PingResult) -> Void)? = nil) {
        let alert = Alert(title: "Agent Awake", body: "Test ping. This channel works.")
        let targets = Channels.phone(config).filter { channel == nil || $0.name == channel }
        guard !targets.isEmpty else {
            local.send(alert)
            result?(.failed("Set this channel up first"))
            return
        }
        result?(.sending)
        for t in targets {
            guard let http = t.notifier as? HTTPChannel else { t.notifier.send(alert); result?(.sent); continue }
            http.send(alert, via: .shared) { status in
                DispatchQueue.main.async {
                    switch status {
                    case .some(200..<300): result?(.sent)
                    case .some(let s): result?(.failed("\(t.name) answered HTTP \(s)"))
                    case .none: result?(.failed("Couldn't reach \(t.name)"))
                    }
                }
            }
        }
    }

    func copyTopic() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(topic, forType: .string)
    }

    func installCLI() {
        do { try CLIInstaller.install(); cliInstalled = true } catch { self.error = "\(error.localizedDescription)" }
    }

    private func apply(_ list: [SessionInfo]) {
        sessions = list
        syncLid()
    }

    /// Lid-closed mode only while there is work AND the user opted in AND the helper is approved.
    private func syncLid() {
        lid.update(wanted: lidMode && !sessions.isEmpty && helper == .ready)
    }
}

/// Symlinks the bundled CLI into ~/.local/bin (no admin rights needed).
enum CLIInstaller {
    static var target: String { NSHomeDirectory() + "/.local/bin/agentawake" }
    static var source: String { Bundle.main.bundlePath + "/Contents/MacOS/agentawake" }
    static var canInstall: Bool { Bundle.main.bundlePath.hasSuffix(".app") }
    static var isInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: target)) == source
    }
    static func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: target)
        try fm.createSymbolicLink(atPath: target, withDestinationPath: source)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !UserDefaults.standard.bool(forKey: "welcomed") { WelcomeWindow.show() }
    }

    /// Nothing an agent started stays paused or throttled after Agent Awake quits.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Model.shared.strainGuard.releaseAll() }
    }

    /// Opening the app again (Finder, Spotlight, Dock) shows the welcome window, since a menu bar
    /// icon can be hidden behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        WelcomeWindow.show()
        return false
    }
}

@main
struct AgentAwakeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @ObservedObject private var model = Model.shared

    init() { NSApplication.shared.setActivationPolicy(.accessory) }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            let n = model.agents.count
            Image(nsImage: StatusIcon.image(awake: !model.sessions.isEmpty))
            if n > 1 { Text("\(n)") }
        }
        .menuBarExtraStyle(.window)
    }
}
