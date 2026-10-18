import SwiftUI
import AppKit

/// Shared project identity and lifecycle controls for the window and menu bar.
struct ProjectRowView: View {
    let project: ProjectConfiguration
    @Bindable var manager: ProjectsState
    var compact = false

    private var isRunning: Bool { manager.running.contains(project.id) }
    private var isStopping: Bool { manager.stopping.contains(project.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.md) {
                StatusDot(color: isStopping ? Theme.Colors.statusWarning : (isRunning ? Theme.Colors.statusSuccess : Theme.Colors.statusIdle))
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
                Button(isStopping ? "Stopping…" : (isRunning ? "Stop" : "Start")) {
                    if isRunning { manager.stop(project.id) }
                    else { manager.start(project.id) }
                }
                .controlSize(.small)
                .frame(minWidth: ProjectLayout.actionWidth)
                .disabled(isStopping)
                .accessibilityLabel("\(isRunning ? "Stop" : "Start") \(project.name)")
            }
            if !compact {
                Text(project.directory).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(project.command).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
            }
            if let error = manager.errors[project.id] {
                Text(error).font(.caption).foregroundStyle(Theme.Colors.statusError).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Spacing.lg) {
                if let port = project.port {
                    Button("Open :\(port)") {
                        if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
                    }
                    .disabled(!isRunning || isStopping)
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
        if isRunning { return project.port.map { "Running · port \($0) expected" } ?? "Running" }
        return project.port.map { "Stopped · :\($0)" } ?? "Stopped"
    }
}
