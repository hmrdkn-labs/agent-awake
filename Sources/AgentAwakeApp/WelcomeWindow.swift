import SwiftUI
import CoreImage.CIFilterBuiltins
import AgentAwakeCore

/// First-run setup, one step per page. Also what a second launch of the app opens, so the app is reachable
/// even when its menu bar icon is hidden behind the notch.
@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?

    static func show() {
        Model.shared.refreshIntegrations()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            // Open on whatever Space the user is in, including over a full-screen terminal.
            w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView: WelcomeView(model: .shared) { close() })
            w.center()
            window = w
        }
        // Shown automatically once; after that only on request, however it was closed.
        UserDefaults.standard.set(true, forKey: "welcomed")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func close() { window?.close() }
}

struct WelcomeView: View {
    @ObservedObject var model: Model
    let done: () -> Void
    @State private var page = 0
    private let pages = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: IntroPage()
                case 1: AgentsPage(model: model)
                case 2: PhonePage(model: model)
                default: FinishPage(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(page)

            Divider()
            HStack {
                HStack(spacing: 7) {
                    ForEach(0..<pages, id: \.self) { i in
                        Capsule().fill(i == page ? Brand.amber : Color.secondary.opacity(0.3))
                            .frame(width: i == page ? 18 : 7, height: 7)
                    }
                }
                Spacer()
                if page > 0 {
                    Button("Back") { withAnimation(.snappy) { page -= 1 } }.controlSize(.large)
                }
                Button(page == pages - 1 ? "Done" : page == 0 ? "Get started" : "Continue") {
                    if page == pages - 1 { done() } else { withAnimation(.snappy) { page += 1 } }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(.horizontal, 28).padding(.vertical, 16)
        }
        .frame(width: 600, height: 640)
        .background(.background)
    }
}

/// Title block shared by every page.
private struct PageHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26, weight: .semibold)).foregroundStyle(Brand.amber)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.night.opacity(0.35)))
            Text(title).font(.title.weight(.bold))
            Text(subtitle).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32).padding(.top, 44).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pages

private struct IntroPage: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Brand.night, Brand.night.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                    Text("Agent Awake").font(.system(size: 34, weight: .bold))
                    Text("caffeinate for AI agents").font(.title3).foregroundStyle(.secondary)
                }
                .padding(.top, 36)
            }
            .frame(height: 290)

            VStack(alignment: .leading, spacing: 18) {
                feature("bolt.fill", "Awake only while agents work",
                        "Your Mac stays up while an agent runs and sleeps the moment it finishes.")
                feature("iphone.radiowaves.left.and.right", "Pinged when it matters",
                        "Done, needs you, or stuck: on your phone when you're away, on your Mac when you're not.")
                feature("moon.stars.fill", "Lives in the menu bar",
                        "Look for the moon. Hidden by a full menu bar? Open the app again to get back here.")
            }
            .padding(.horizontal, 44).padding(.top, 6)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Brand.amber).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AgentsPage: View {
    @ObservedObject var model: Model

    var body: some View {
        let found = model.integrations.filter { $0.status != .notInstalled }
        let unconnected = found.filter { $0.status == .available }
        VStack(spacing: 0) {
            PageHeader(symbol: "cpu", title: "Connect your agents",
                       subtitle: "Agent Awake listens to each agent's own hooks: when a prompt starts, when it finishes, and when it's waiting for you. Disconnect anytime.")
            ScrollView {
                VStack(spacing: 0) {
                    if found.isEmpty {
                        Text("No supported agent on this Mac yet. Claude Code, Codex, Cursor, Gemini CLI, Copilot, OpenCode and 12 more are supported; connect them later in Settings.")
                            .foregroundStyle(.secondary).padding(16)
                    }
                    ForEach(Array(found.enumerated()), id: \.element.integration.id) { i, row in
                        if i > 0 { Divider().padding(.leading, 52) }
                        AgentRow(model: model, row: row).padding(.horizontal, 14)
                    }
                    if model.herdrPath != nil {
                        Divider().padding(.leading, 52)
                        HStack(spacing: 12) {
                            AgentIcon(id: "herdr")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("herdr panes").font(.body.weight(.medium))
                                Text("Followed without setup").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Pill(text: "Automatic", color: .green, systemImage: "checkmark")
                        }
                        .padding(.horizontal, 14).padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))
                .padding(.horizontal, 32)
            }
            HStack {
                Text("Anything else: `agentawake run build -- make`").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if unconnected.count > 1 {
                    Button("Connect all") { unconnected.forEach { model.connect($0.integration) } }
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 12)
        }
    }
}

private struct PhonePage: View {
    @ObservedObject var model: Model
    @State private var copied = false
    @State private var ping: PingResult = .idle

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(symbol: "iphone.radiowaves.left.and.right", title: "Get pinged on your phone",
                       subtitle: "Only while you're away from the Mac. When you're at it, you get a normal Mac notification.")
            HStack(alignment: .top, spacing: 22) {
                if let qr = QRCode.image(for: "ntfy://\(URL(string: model.ntfyServer)?.host ?? "ntfy.sh")/\(model.topic)") {
                    Image(nsImage: qr).interpolation(.none).resizable().frame(width: 136, height: 136)
                        .padding(10).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
                }
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Install the free **ntfy** app.")
                    step(2, "iPhone: tap **+** and paste the topic. Android: scan the code.")
                    step(3, "Send a test. Keep the topic secret; it's your private channel.")
                    HStack(spacing: 8) {
                        Text(model.topic).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.6)))
                        Button {
                            model.copyTopic(); copied = true
                        } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                            .help("Copy topic")
                    }
                    HStack(spacing: 10) {
                        Button("Send test ping") { model.testPing(channel: "ntfy") { ping = $0 } }
                            .buttonStyle(.borderedProminent)
                        ping.view
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))
            .padding(.horizontal, 32)

            Button("Prefer Bark, Pushover, Telegram, Discord or Slack?") { SettingsWindow.show(.notifications) }
                .buttonStyle(.link).padding(.top, 14)
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.caption.weight(.bold)).foregroundStyle(.black.opacity(0.8))
                .frame(width: 18, height: 18).background(Circle().fill(Brand.amber))
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FinishPage: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(symbol: "checkmark.seal.fill", title: "Almost done",
                       subtitle: "Two optional switches. Both can be changed later in Settings.")
            Form {
                Section {
                    Toggle(isOn: $model.lidMode) {
                        Text("Keep working with the lid closed")
                        Text("While agents work. Needs a one-time approval in System Settings. Turns itself off when work ends, at 10% battery, or when the Mac gets hot or drains fast in a bag.")
                    }
                    if model.lidMode {
                        LabeledContent("Helper") {
                            if model.helper == .needsApproval {
                                Button("Approve in System Settings…") { HelperInstaller.openSettings() }
                            } else {
                                Text(model.helper.label).foregroundStyle(model.helper == .ready ? .green : .orange)
                            }
                        }
                    }
                }
                Section {
                    Toggle(isOn: $model.launchAtLogin) {
                        Text("Open at login")
                        Text("So agents are covered after a restart.")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, 16)
        }
    }
}

enum QRCode {
    static func image(for text: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
