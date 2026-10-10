import SwiftUI
import AgentAwakeCore

enum Brand {
    static let night = Color(red: 0.13, green: 0.17, blue: 0.55)
    static let amber = Color(red: 1.0, green: 0.78, blue: 0.27)
}

/// The menu bar panel: header with live state, running agents, Keep awake presets, settings.
struct PanelView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let e = model.error {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 14).padding(.bottom, 8)
            }
            Divider()
            agents.padding(14)
            Divider()
            keepAwake.padding(14)
            Divider()
            settings.padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            footer.padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 340)
        .onAppear { model.refreshIntegrations() }   // Codex trust and new installs happen outside the app
    }

    // MARK: header

    private var awake: Bool { !model.sessions.isEmpty }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Awake").font(.headline)
                Text(statusLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(awake ? "AWAKE" : "IDLE")
                .font(.caption2.weight(.bold)).tracking(0.8)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(awake ? Brand.amber : Color.secondary.opacity(0.18)))
                .foregroundStyle(awake ? Color.black.opacity(0.8) : Color.secondary)
        }
        .padding(14)
        .background(
            LinearGradient(colors: [Brand.night.opacity(awake ? 0.28 : 0.12), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var statusLine: String {
        let n = model.agents.count
        if n > 0 { return "\(n) agent\(n == 1 ? "" : "s") working" }
        if let m = model.manual {
            if let end = m.expiresAt {
                return "Awake until \(Date(timeIntervalSince1970: end).formatted(date: .omitted, time: .shortened))"
            }
            return "Awake until you turn it off"
        }
        return "Mac sleeps normally"
    }

    // MARK: agents

    @ViewBuilder private var agents: some View {
        if model.agents.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz").font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No agents working").font(.callout)
                    Text(model.connectedCount > 0
                         ? "Connected agents are picked up when they start."
                         : "Connect your agents in Settings, or wrap a job: agentawake run build -- make")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("WORKING").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(model.agents, id: \.name) { s in
                    HStack(spacing: 8) {
                        AgentIcon(id: s.agent ?? "", size: 20)
                            .overlay(alignment: .bottomTrailing) {
                                Circle().fill(s.state == .waiting ? Color.orange : Color.green).frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                                    .offset(x: 2, y: 2)
                            }
                        Text(s.title).font(.callout).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        if s.state == .waiting {
                            Text("needs you").font(.caption.weight(.medium)).foregroundStyle(.orange)
                        } else {
                            Text(Date(timeIntervalSince1970: s.startedAt), style: .timer)
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .help(s.name)
                }
            }
        }
    }

    // MARK: keep awake

    private static let presets: [(String, Double?)] = [("Off", nil), ("1h", 3600), ("2h", 7200), ("4h", 14400), ("∞", 0)]

    private var keepAwake: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KEEP AWAKE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.0) { label, duration in
                    let selected = isSelected(duration)
                    Button { model.keepAwake(duration) } label: {
                        Text(label).font(.callout.weight(selected ? .semibold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(selected ? Brand.night : Color.secondary.opacity(0.12)))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .help(duration == nil ? "Only agents keep the Mac awake"
                          : duration == 0 ? "Stay awake until you turn it off"
                          : "Stay awake for \(label), then sleep normally")
                }
            }
        }
    }

    /// Timed presets light up while a manual session of that length is running.
    private func isSelected(_ duration: Double?) -> Bool {
        guard let m = model.manual else { return duration == nil }
        return duration != nil && m.timeout == duration
    }

    // MARK: settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            toggle("Stay awake with lid closed", "laptopcomputer", $model.lidMode)
            if model.lidMode && model.helper != .ready {
                HStack {
                    Text(model.helper.label).font(.caption).foregroundStyle(.orange)
                    Spacer()
                    if model.helper == .needsApproval {
                        Button("Approve…") { HelperInstaller.openSettings() }.controlSize(.small)
                    }
                }
                .padding(.leading, 26)
            }
            row("Agents", "cpu", detail: agentsDetail, warn: model.needsActionCount > 0) { SettingsWindow.show(.agents) }
            row("Notifications", "iphone.radiowaves.left.and.right", detail: notificationsDetail, warn: false) {
                SettingsWindow.show(.notifications)
            }
        }
    }

    private var agentsDetail: String {
        if model.needsActionCount > 0 { return "\(model.needsActionCount) need a step" }
        return model.connectedCount == 0 ? "None connected" : "\(model.connectedCount) connected"
    }

    private var notificationsDetail: String {
        let phones = Channels.phone(model.config).map(\.name)
        if phones.isEmpty || model.config.effectivePingWhen == .never { return "Mac only" }
        let when = model.config.effectivePingWhen == .away ? "when away" : "always"
        return "\(phones.joined(separator: ", ")) \(when)"
    }

    private func row(_ title: String, _ icon: String, detail: String, warn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon).font(.callout)
                Spacer()
                Text(detail).font(.caption).foregroundStyle(warn ? Color.orange : Color.secondary).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ title: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            Label(title, systemImage: icon).font(.callout)
            Spacer()
            Toggle(title, isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Button("Settings…") { SettingsWindow.show(.agents) }.keyboardShortcut(",")
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}
