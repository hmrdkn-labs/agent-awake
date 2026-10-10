import SwiftUI
import CoreImage.CIFilterBuiltins
import AgentAwakeCore

/// First-run and "Setup guide" window. Also what a second launch of the app opens, so the app is
/// reachable even when its menu bar icon is hidden behind the notch.
@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent Awake").font(.largeTitle.weight(.semibold))
                    Text("Keeps your Mac awake while AI agents work, lets it sleep when they finish, and pings your phone.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Image(nsImage: StatusIcon.image(awake: false))
                Text("Agent Awake lives in your menu bar as a moon. Can't see it? The menu bar may be full: hold ⌘ and drag other icons away, or open this app again to get this window.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))

            step(1, "Track your agents") {
                if model.herdrPath != nil {
                    Label("herdr found: working agents are followed automatically.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.callout)
                }
                Text("Any other job: `agentawake run build -- make`, or `begin` / `done` from your agent's hooks.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                if CLIInstaller.canInstall {
                    if model.cliInstalled {
                        Label("Command installed at ~/.local/bin/agentawake", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.caption)
                    } else {
                        Button("Install the agentawake command") { model.installCLI() }
                    }
                }
            }

            step(2, "Get pinged on your phone") {
                HStack(alignment: .top, spacing: 14) {
                    if let qr = QRCode.image(for: "\(model.ntfyServer)/\(model.topic)") {
                        Image(nsImage: qr).interpolation(.none).resizable().frame(width: 112, height: 112)
                            .padding(6).background(RoundedRectangle(cornerRadius: 8).fill(.white))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Install the free **ntfy** app on your iPhone, scan this code, and subscribe. That's your private channel; keep it secret.")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text(model.topic).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                        HStack {
                            Button("Copy topic") { model.copyTopic() }
                            Button("Send test ping") { model.testPing() }
                        }
                    }
                }
            }

            step(3, "Optional: keep working with the lid closed") {
                Toggle("Stay awake with lid closed while agents work", isOn: $model.lidMode)
                Text("Needs a one-time approval in System Settings. Turns itself off when work ends, the battery drops to 10%, or the Mac gets hot.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction).controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 540)
    }

    private func step<C: View>(_ n: Int, _ title: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.callout.weight(.bold)).foregroundStyle(.black.opacity(0.8))
                .frame(width: 24, height: 24).background(Circle().fill(Brand.amber))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content()
            }
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
