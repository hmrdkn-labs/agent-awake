import SwiftUI
import ServiceManagement
import SmartWorkCore

@MainActor
final class Model: ObservableObject {
    @Published var sessions: [SessionInfo] = []
    @Published var error: String?
    @Published var helper: HelperState = HelperInstaller.state()
    @Published var manual = false {
        didSet { if manual != oldValue { engine.setManual(manual) } }
    }
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
    let herdrPath: String? = HerdrCLI.locate()
    let engine: Engine
    private let notifier: Notifier
    private let lid: LidGuard
    private let server: SocketServer
    private var herdr: HerdrWatcher?
    private var poll: Timer?

    init() {
        let config = Config.loadEnsuringTopic()
        topic = config.ntfyTopic ?? ""
        let n = NtfyNotifier(config: config)
        notifier = n
        let e = Engine(notifier: n)
        engine = e
        lid = LidGuard(controller: XPCSleepController(), notifier: n)
        server = SocketServer { [e] in e.handle($0) }
        e.onChange = { [weak self] list in
            DispatchQueue.main.async { self?.apply(list) }
        }
        do { try server.start(); e.start() } catch SocketError.alreadyRunning {
            FileHandle.standardError.write(Data("smart-work is already running\n".utf8))
            exit(1)
        } catch { self.error = "\(error)" }
        lid.start()
        if lidMode && helper != .ready && helper != .needsApproval { helper = HelperInstaller.register() }
        FileHandle.standardError.write(Data("[smart-work] helper: \(helper.label)\n".utf8))
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
            FileHandle.standardError.write(Data("[smart-work] helper: \(s.label)\n".utf8))
        }
        if s == .ready { syncLid() }
    }

    func testPing() {
        notifier.send(title: "smart-work", body: "Test ping. Your phone is set up.")
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
        let m = list.contains { $0.name == Engine.manualName }
        if m != manual { manual = m }
        syncLid()
    }

    /// Lid-closed mode only while there is work AND the user opted in AND the helper is approved.
    private func syncLid() {
        lid.update(wanted: lidMode && !sessions.isEmpty && helper == .ready)
    }
}

/// Symlinks the bundled CLI into ~/.local/bin (no admin rights needed).
enum CLIInstaller {
    static var target: String { NSHomeDirectory() + "/.local/bin/smart-work" }
    static var source: String { Bundle.main.bundlePath + "/Contents/MacOS/smart-work" }
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

@main
struct SmartWorkApp: App {
    @StateObject private var model = Model()

    init() { NSApplication.shared.setActivationPolicy(.accessory) }

    var body: some Scene {
        MenuBarExtra {
            if let e = model.error { Text(e) }

            let agents = model.sessions.filter { $0.name != Engine.manualName }
            if agents.isEmpty {
                Text(model.manual ? "Keeping awake" : "Idle: Mac sleeps normally")
            } else {
                ForEach(agents, id: \.name) { s in
                    Text("\(s.name) · \(Text(Date(timeIntervalSince1970: s.startedAt), style: .relative))")
                }
            }
            Divider()

            Toggle("Keep awake", isOn: $model.manual)
            Toggle("Stay awake with lid closed", isOn: $model.lidMode)
            if model.lidMode {
                Text(model.helper.label)
                if model.helper == .needsApproval {
                    Button("Open Login Items…") { HelperInstaller.openSettings() }
                }
            }
            if model.herdrPath != nil {
                Toggle("Follow herdr agents", isOn: $model.herdrWatch)
            }
            Divider()

            Menu("Phone notifications") {
                Text("ntfy topic: \(model.topic)")
                Button("Copy topic") { model.copyTopic() }
                Button("Send test ping") { model.testPing() }
            }
            if CLIInstaller.canInstall {
                if model.cliInstalled {
                    Text("Command: ~/.local/bin/smart-work")
                } else {
                    Button("Install smart-work command") { model.installCLI() }
                }
            }
            Toggle("Launch at login", isOn: $model.launchAtLogin)
            Divider()
            Button("Quit smart-work") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: model.sessions.isEmpty ? "moon.zzz" : "bolt.fill")
        }
    }
}
