import SwiftUI
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
    let engine: Engine
    private let lid: LidGuard
    private let server: SocketServer
    private var poll: Timer?

    init() {
        let notifier = NtfyNotifier(config: Config.load())
        let e = Engine(notifier: notifier)
        engine = e
        lid = LidGuard(controller: XPCSleepController(), notifier: notifier)
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
        // Helper approval happens in System Settings; notice it without a relaunch.
        poll = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshHelper() }
        }
        syncLid()
    }

    func refreshHelper() {
        let s = HelperInstaller.state()
        if s != helper {
            helper = s
            FileHandle.standardError.write(Data("[smart-work] helper: \(s.label)\n".utf8))
        }
        if s == .ready { syncLid() }
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

@main
struct SmartWorkApp: App {
    @StateObject private var model = Model()

    init() { NSApplication.shared.setActivationPolicy(.accessory) }

    var body: some Scene {
        MenuBarExtra {
            if let e = model.error { Text(e) }
            Toggle("Keep awake", isOn: $model.manual)
            Toggle("Stay awake with lid closed", isOn: $model.lidMode)
            if model.lidMode {
                Text(model.helper.label)
                if model.helper == .needsApproval {
                    Button("Open Login Items…") { HelperInstaller.openSettings() }
                }
            }
            Divider()
            let agents = model.sessions.filter { $0.name != Engine.manualName }
            if agents.isEmpty {
                Text("No agents running")
            } else {
                ForEach(agents, id: \.name) { s in
                    Text("\(s.name) · \(Text(Date(timeIntervalSince1970: s.startedAt), style: .relative))")
                }
            }
            Divider()
            Button("Quit smart-work") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: model.sessions.isEmpty ? "moon.zzz" : "bolt.fill")
        }
    }
}
