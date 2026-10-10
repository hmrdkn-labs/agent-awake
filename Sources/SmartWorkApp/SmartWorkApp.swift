import SwiftUI
import SmartWorkCore

@MainActor
final class Model: ObservableObject {
    @Published var sessions: [SessionInfo] = []
    @Published var error: String?
    @Published var manual = false {
        didSet { if manual != oldValue { engine.setManual(manual) } }
    }
    let engine: Engine
    private let server: SocketServer

    init() {
        let e = Engine(notifier: NtfyNotifier(config: Config.load()))
        engine = e
        server = SocketServer { [e] in e.handle($0) }
        e.onChange = { [weak self] list in
            DispatchQueue.main.async { self?.apply(list) }
        }
        do { try server.start(); e.start() } catch SocketError.alreadyRunning {
            FileHandle.standardError.write(Data("smart-work is already running\n".utf8))
            exit(1)
        } catch { self.error = "\(error)" }
    }

    private func apply(_ list: [SessionInfo]) {
        sessions = list
        let m = list.contains { $0.name == Engine.manualName }
        if m != manual { manual = m }
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
