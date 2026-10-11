import SwiftUI
import AgentAwakeCore

/// The agent's official mark (Resources/AgentIcons, see NOTICE.md there), on a tile so every row lines up.
/// Monochrome marks are template images, tinted for light and dark mode; marks that are already app-icon
/// tiles fill the frame.
struct AgentIcon: View {
    let id: String
    var size: CGFloat = 28

    private static let monochrome: Set<String> = ["copilot", "cursor", "windsurf", "goose", "opencode", "kilo", "pi",
                                                  "auggie", "zed"]
    private static let tiles: Set<String> = ["codex", "gemini", "kiro", "omp", "herdr", "droid"]
    private static var cache: [String: NSImage] = [:]

    var body: some View {
        let radius = size * 0.24
        if let img = Self.mark(id) {
            if Self.tiles.contains(id) {
                Image(nsImage: img).resizable().interpolation(.high)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .overlay {
                        if Self.monochrome.contains(id) {
                            Image(nsImage: img).resizable().renderingMode(.template).interpolation(.high)
                                .foregroundStyle(.primary).scaledToFit().padding(size * 0.18)
                        } else {
                            Image(nsImage: img).resizable().interpolation(.high).scaledToFit().padding(size * 0.14)
                        }
                    }
                    .frame(width: size, height: size)
            }
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .overlay(Image(systemName: "terminal.fill").font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.secondary))
                .frame(width: size, height: size)
        }
    }

    private static func mark(_ id: String) -> NSImage? {
        if let c = cache[id] { return c }
        guard let url = Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "AgentIcons"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[id] = img
        return img
    }
}

/// Small capsule label for a state.
struct Pill: View {
    let text: String
    let color: Color
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let s = systemImage { Image(systemName: s).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
        .foregroundStyle(color)
    }
}

/// One agent: icon, name, state, and the action that fits the state. Long instructions (Codex trust) sit
/// behind an info popover instead of being truncated.
struct AgentRow: View {
    @ObservedObject var model: Model
    let row: Model.IntegrationState
    var showFiles = false
    @State private var showNote = false

    var body: some View {
        HStack(spacing: 12) {
            AgentIcon(id: row.integration.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.integration.name).font(.body.weight(.medium))
                if let sub = subtitle {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if hasNote {
                Button { showNote.toggle() } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .popover(isPresented: $showNote, arrowEdge: .bottom) { note.padding(14).frame(width: 300) }
            }
            trailing
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var trailing: some View {
        switch row.status {
        case .connected:
            Pill(text: "Connected", color: .green, systemImage: "checkmark")
                .contextMenu { Button("Disconnect", role: .destructive) { model.disconnect(row.integration) } }
            Menu {
                Button("Disconnect", role: .destructive) { model.disconnect(row.integration) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(.secondary)
        case .needsAction:
            Button { showNote = true } label: { Pill(text: "One more step", color: .orange, systemImage: "hand.point.up.left.fill") }
                .buttonStyle(.plain)
        case .broken:
            Button("Repair") { model.connect(row.integration) }.controlSize(.small)
        case .available:
            Button("Connect") { model.connect(row.integration) }.buttonStyle(.borderedProminent).controlSize(.small)
        case .notInstalled:
            Text("Not installed").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var subtitle: String? {
        switch row.status {
        case .broken(let m): return m
        case .needsAction: return "Waiting for you in \(row.integration.name)"
        case .connected: return showFiles ? row.integration.files.first.map(abbreviate) : "Reports start, finish and questions"
        case .available: return "Installed"
        case .notInstalled: return nil
        }
    }

    private var hasNote: Bool { row.integration.note != nil || showFiles }

    private var note: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .needsAction(let m) = row.status {
                Label("One more step", systemImage: "hand.point.up.left.fill").font(.headline).foregroundStyle(.orange)
                Text(m).fixedSize(horizontal: false, vertical: true)
            } else if let n = row.integration.note {
                Text(n).fixedSize(horizontal: false, vertical: true)
            }
            if !row.integration.files.isEmpty {
                Divider()
                Text("Connect writes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(row.integration.files, id: \.self) {
                    Text(abbreviate($0)).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
    }

    private func abbreviate(_ path: String) -> String {
        path.hasPrefix(NSHomeDirectory()) ? "~" + path.dropFirst(NSHomeDirectory().count) : path
    }
}

/// Inline feedback for a test ping: sending, sent, or why it failed.
enum PingResult: Equatable {
    case idle, sending, sent, failed(String)

    @ViewBuilder var view: some View {
        switch self {
        case .idle: EmptyView()
        case .sending: ProgressView().controlSize(.small)
        case .sent: Label("Sent", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .failed(let m): Label(m, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
        }
    }
}
