import SwiftUI
import ServiceManagement
import AgentAwakeCore

@MainActor
final class Model: ObservableObject {
    static let shared = Model()

    @Published var sessions: [SessionInfo] = []
    @Published var error: String?
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

    let topic: String
    let ntfyServer: String
    let herdrPath: String? = HerdrCLI.locate()
    let engine: Engine
    private let notifier: Notifier
    private let lid: LidGuard
    private let server: SocketServer
    private var herdr: HerdrWatcher?
    private var poll: Timer?

    var agents: [SessionInfo] { sessions.filter { $0.name != Engine.manualName } }
    var manual: SessionInfo? { sessions.first { $0.name == Engine.manualName } }

    private init() {
        let config = Config.loadEnsuringTopic()
        topic = config.ntfyTopic ?? ""
        ntfyServer = (config.ntfyServer ?? "https://ntfy.sh").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let n = NtfyNotifier(config: config)
        notifier = n
        let e = Engine(notifier: n)
        engine = e
        lid = LidGuard(controller: XPCSleepController(), notifier: n)
        // "show" comes from a second launch of the app; everything else is session traffic.
        server = SocketServer { [e] req in
            if req.cmd == "show" {
                DispatchQueue.main.async { WelcomeWindow.show() }
                return Response(ok: true)
            }
            return e.handle(req)
        }
        e.onChange = { [weak self] list in
            DispatchQueue.main.async { self?.apply(list) }
        }
        do { try server.start(); e.start() } catch SocketError.alreadyRunning {
            // Another copy is running: bring up its window instead of starting a second daemon.
            _ = try? Client.send(Request(cmd: "show"))
            exit(0)
        } catch { self.error = "\(error)" }
        lid.start()
        if lidMode && helper != .ready && helper != .needsApproval { helper = HelperInstaller.register() }
        FileHandle.standardError.write(Data("[agentawake] helper: \(helper.label)\n".utf8))
        applyHerdr()
        // Helper approval happens in System Settings; notice it without a relaunch.
        poll = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshHelper() }
        }
        syncLid()
    }

    private func applyHerdr() {
        herdr?.stop(); herdr = nil
        guard herdrWatch, let path = herdrPath else { return }
        let w = HerdrWatcher(engine: engine) { HerdrCLI.listAgents(herdr: path) }
        w.start()
        herdr = w
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

    func testPing() {
        notifier.send(Alert(title: "Agent Awake", body: "Test ping. Your phone is set up."))
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
