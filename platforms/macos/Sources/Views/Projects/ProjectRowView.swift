import SwiftUI
import AppKit

/// Shared project identity and lifecycle controls for the window and menu bar.
struct ProjectRowView: View {
    let project: ProjectConfiguration
    @Bindable var manager: ProjectsState
    var compact = false

    private var isRunning: Bool { manager.running.contains(project.id) }
    private var isStopping: Bool { manager.stopping.contains(project.id) }
    private var isExternal: Bool { manager.externalRunning.contains(project.id) }
    private var isStarting: Bool { isRunning && !manager.isReady(project.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.md) {
                StatusDot(color: (isStopping || isStarting) ? Theme.Colors.statusWarning : (manager.isReady(project.id) ? Theme.Colors.statusSuccess : Theme.Colors.statusIdle))
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(project.name).fontWeight(.medium).lineLimit(1)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: Spacing.xs)
                Button {
                    manager.toggleFavorite(project.id)
                } label: {
                    Image(systemName: project.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(project.isFavorite ? Theme.Colors.favorite : .secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(project.isFavorite ? "Remove \(project.name) from favorites" : "Favorite \(project.name)")
                Button(isExternal ? "External" : (isStopping ? "Stopping…" : (isRunning ? "Stop" : "Start"))) {
                    if isRunning { manager.stop(project.id) }
                    else { manager.start(project.id) }
                }
                .controlSize(.small)
                .frame(minWidth: ProjectLayout.actionWidth)
                .disabled(isStopping || isExternal)
                .help(isExternal ? "Started outside PortKiller. Stop it in its original terminal to manage its next launch here." : "Start or stop this service")
                .accessibilityLabel(isExternal ? "Running externally: \(project.name)" : "\(isRunning ? "Stop" : "Start") \(project.name)")
            }
            if !compact {
                Text(project.directory).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(project.command).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
            }
            if project.groupName != nil && project.startWithGroup == false {
                Text("Manual start · excluded from Start Group")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = manager.errors[project.id] {
                Text(error).font(.caption).foregroundStyle(Theme.Colors.statusError).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Spacing.lg) {
                if let port = project.port {
                    Button("Open :\(String(port))") {
                        if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
                    }
                    .disabled(!manager.isReady(project.id) || isStopping)
                }
                Button("Logs") { NSWorkspace.shared.open(manager.logURL(for: project.id)) }
                    .disabled(!FileManager.default.fileExists(atPath: manager.logURL(for: project.id).path))
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, compact ? Spacing.lg : 0)
    }

    private var statusText: String {
        if isStopping { return "Stopping" }
        if isExternal { return project.port.map { "Running externally · :\($0)" } ?? "Running externally" }
        if isStarting { return project.port.map { "Starting · waiting for :\($0)" } ?? "Starting" }
        if isRunning { return project.port.map { "Listening · :\($0)" } ?? "Running" }
        return project.port.map { "Stopped · :\($0)" } ?? "Stopped"
    }
}
