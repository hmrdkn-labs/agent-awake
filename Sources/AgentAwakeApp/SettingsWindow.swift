import SwiftUI
import AgentAwakeCore

/// Settings: which agents report to us, where pings go, and app behavior.
@MainActor
enum SettingsWindow {
    enum Tab: Hashable { case agents, notifications, general }
    private static var window: NSWindow?
    private static let selection = TabSelection()

    final class TabSelection: ObservableObject { @Published var tab: Tab = .agents }

    static func show(_ tab: Tab = .agents) {
        selection.tab = tab
        Model.shared.refreshIntegrations()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Agent Awake Settings"
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView: SettingsView(model: .shared, selection: selection))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: Model
    @ObservedObject var selection: SettingsWindow.TabSelection

    var body: some View {
        TabView(selection: $selection.tab) {
            AgentsTab(model: model).tabItem { Label("Agents", systemImage: "cpu") }.tag(SettingsWindow.Tab.agents)
            NotificationsTab(model: model).tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsWindow.Tab.notifications)
            GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsWindow.Tab.general)
        }
        .padding(16)
        .frame(width: 640, height: 560)
    }
}

// MARK: - Agents

struct AgentsTab: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agents report when they start, finish and need you through their own hooks. Connect the ones you use; Disconnect removes exactly what was added.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                let installed = model.integrations.filter { $0.status != .notInstalled }
                let missing = model.integrations.filter { $0.status == .notInstalled }
                Section("On this Mac") {
                    if installed.isEmpty {
                        Text("No supported agent found. Install one, then come back here.").foregroundStyle(.secondary)
                    }
                    ForEach(installed, id: \.integration.id) { IntegrationRow(model: model, row: $0) }
                }
                Section("Detected without setup") {
                    automaticRow("herdr panes", detail: model.herdrPath == nil ? "herdr not installed" : "Working panes are followed",
                                 on: model.herdrPath != nil && model.herdrWatch)
                    automaticRow("oh-my-pi, Codex, Zed", detail: "Seen while they hold the Mac awake for a turn", on: true)
                }
                Section("Other supported agents") {
                    ForEach(missing, id: \.integration.id) { IntegrationRow(model: model, row: $0) }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            HStack {
                Text("Hooks call ~/.agent-awake/bin/agentawake and never block your agent.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { model.refreshIntegrations() }
            }
        }
    }

    private func automaticRow(_ name: String, detail: String, on: Bool) -> some View {
        HStack {
            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct IntegrationRow: View {
    @ObservedObject var model: Model
    let row: Model.IntegrationState
    @State private var showFiles = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.integration.name).font(.body.weight(.medium))
                Text(statusText).font(.caption).foregroundStyle(color == .secondary ? .secondary : color)
                    .fixedSize(horizontal: false, vertical: true)
                if showFiles {
                    ForEach(row.integration.files, id: \.self) {
                        Text($0).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            Spacer()
            Button { showFiles.toggle() } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless).help("Files Connect writes")
            switch row.status {
            case .connected, .needsAction, .broken:
                Button("Disconnect") { model.disconnect(row.integration) }
            case .available:
                Button("Connect") { model.connect(row.integration) }.buttonStyle(.borderedProminent)
            case .notInstalled:
                EmptyView()
            }
        }
        .padding(.vertical, 3)
    }

    private var statusText: String {
        switch row.status {
        case .notInstalled: return "Not installed"
        case .available: return "Installed, not connected"
        case .connected: return "Connected"
        case .needsAction(let s): return s
        case .broken(let s): return s
        }
    }
    private var icon: String {
        switch row.status {
        case .connected: return "checkmark.circle.fill"
        case .needsAction: return "exclamationmark.circle.fill"
        case .broken: return "xmark.octagon.fill"
        case .available: return "circle"
        case .notInstalled: return "circle.dotted"
        }
    }
    private var color: Color {
        switch row.status {
        case .connected: return .green
        case .needsAction: return .orange
        case .broken: return .red
        default: return .secondary
        }
    }
}

// MARK: - Notifications

struct NotificationsTab: View {
    @ObservedObject var model: Model
    @State private var draft = Config()
    @State private var telegramStatus = ""

    var body: some View {
        Form {
            Section {
                Picker("Phone pings", selection: binding(\.pingWhen, default: .away)) {
                    Text("When I'm away from the Mac").tag(Config.PingWhen.away)
                    Text("Always").tag(Config.PingWhen.always)
                    Text("Never, Mac notifications only").tag(Config.PingWhen.never)
                }
                Stepper("Away after \(Int(draft.awayAfterMinutes ?? 5)) min without input, or when the screen locks",
                        value: binding(\.awayAfterMinutes, default: 5), in: 1...60)
                Toggle("Show the prompt as the task title", isOn: binding(\.taskTitles, default: false))
                Text("Off: pings say only the agent and project folder. Prompts can hold private text, and pings pass through the services below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("ntfy (free, iPhone and Android)") {
                TextField("Topic", text: optional(\.ntfyTopic))
                TextField("Server", text: optional(\.ntfyServer), prompt: Text("https://ntfy.sh"))
                testButton("ntfy")
            }
            Section("Bark (free, iPhone)") {
                TextField("Device key", text: Binding(
                    get: { draft.bark?.key ?? "" },
                    set: { k in draft.bark = k.isEmpty ? nil : Config.Bark(key: Self.barkKey(k), server: draft.bark?.server) }))
                Text("Paste the key or the whole https://api.day.app/… URL from the Bark app.")
                    .font(.caption).foregroundStyle(.secondary)
                testButton("Bark")
            }
            Section("Pushover") {
                TextField("User key", text: Binding(
                    get: { draft.pushover?.user ?? "" },
                    set: { draft.pushover = Self.pair($0, draft.pushover?.token, Config.Pushover.init(token:user:), swap: true) }))
                TextField("App token", text: Binding(
                    get: { draft.pushover?.token ?? "" },
                    set: { draft.pushover = Self.pair($0, draft.pushover?.user, Config.Pushover.init(token:user:), swap: false) }))
                testButton("Pushover")
            }
            Section("Telegram") {
                TextField("Bot token from @BotFather", text: Binding(
                    get: { draft.telegram?.token ?? "" },
                    set: { draft.telegram = $0.isEmpty ? nil : Config.Telegram(token: $0, chatId: draft.telegram?.chatId ?? "") }))
                HStack {
                    TextField("Chat ID", text: Binding(
                        get: { draft.telegram?.chatId ?? "" },
                        set: { id in if let t = draft.telegram { draft.telegram = Config.Telegram(token: t.token, chatId: id) } }))
                    Button("Find") { findTelegramChat() }.disabled(draft.telegram == nil)
                }
                Text(telegramStatus.isEmpty ? "Send /start to your bot, then press Find." : telegramStatus)
                    .font(.caption).foregroundStyle(.secondary)
                testButton("Telegram")
            }
            Section("Discord and Slack") {
                TextField("Discord webhook URL", text: optional(\.discordWebhook))
                TextField("Slack webhook URL", text: optional(\.slackWebhook))
                HStack { testButton("Discord"); testButton("Slack") }
            }
            HStack {
                Spacer()
                Button("Revert") { draft = model.config }.disabled(draft == model.config)
                Button("Save") { model.saveConfig(draft) }.keyboardShortcut("s").disabled(draft == model.config)
                    .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onAppear { draft = model.config }
    }

    private func testButton(_ channel: String) -> some View {
        Button("Send test") { model.saveConfig(draft); model.testPing(channel: channel) }
    }

    private func findTelegramChat() {
        guard let token = draft.telegram?.token else { return }
        telegramStatus = "Looking…"
        Task {
            do {
                if let id = try await Telegram.discoverChatId(token: token) {
                    draft.telegram = Config.Telegram(token: token, chatId: id)
                    telegramStatus = "Found your chat."
                } else {
                    telegramStatus = "No message yet. Send /start to the bot and try again."
                }
            } catch { telegramStatus = error.localizedDescription }
        }
    }

    private func binding<T>(_ key: WritableKeyPath<Config, T?>, default d: T) -> Binding<T> {
        Binding(get: { draft[keyPath: key] ?? d }, set: { draft[keyPath: key] = $0 })
    }
    private func optional(_ key: WritableKeyPath<Config, String?>) -> Binding<String> {
        Binding(get: { draft[keyPath: key] ?? "" },
                set: { let v = $0.trimmingCharacters(in: .whitespaces); draft[keyPath: key] = v.isEmpty ? nil : v })
    }

    /// Bark shows a URL like https://api.day.app/<key>/title; keep only the key.
    static func barkKey(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let u = URL(string: t), u.host != nil else { return t }
        return u.pathComponents.dropFirst().first ?? t
    }

    /// Two-field credentials: drop the channel when both are empty.
    static func pair<C>(_ value: String, _ other: String?, _ make: (String, String) -> C, swap: Bool) -> C? {
        let o = other ?? ""
        if value.isEmpty && o.isEmpty { return nil }
        return swap ? make(o, value) : make(value, o)
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var model: Model

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $model.launchAtLogin)
            Section {
                Toggle("Stay awake with the lid closed while agents work", isOn: $model.lidMode)
                if model.lidMode {
                    HStack {
                        Text(model.helper.label).foregroundStyle(model.helper == .ready ? .green : .orange)
                        Spacer()
                        if model.helper == .needsApproval { Button("Approve in System Settings…") { HelperInstaller.openSettings() } }
                    }
                }
                Text("Turns itself off when work ends, at 10% battery, or when the Mac gets hot.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.herdrPath != nil {
                Toggle("Follow herdr panes", isOn: $model.herdrWatch)
            }
            Section("Command line") {
                Text("agentawake run build -- make  ·  agentawake begin|beat|done <name>")
                    .font(.caption.monospaced()).textSelection(.enabled)
                if CLIInstaller.canInstall {
                    if model.cliInstalled {
                        Text("Installed at ~/.local/bin/agentawake").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Install the agentawake command") { model.installCLI() }
                    }
                }
            }
            Section {
                Button("Show the setup guide") { WelcomeWindow.show() }
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
