import SwiftUI
import AppKit

/// Shared project identity and lifecycle controls for the window and menu bar.
struct ProjectRowView: View {
    let project: ProjectConfiguration
    @Bindable var manager: ProjectsState
    var compact = false
    @State private var conflict: ProjectPortConflict?
    @State private var inspectingPort = false
    @State private var portActionError: String?

    private var isRunning: Bool { manager.running.contains(project.id) }
    private var isStopping: Bool { manager.stopping.contains(project.id) }
    private var isExternal: Bool { manager.externalRunning.contains(project.id) }
    private var isStarting: Bool { isRunning && !manager.isReady(project.id) }
    private var isReclaiming: Bool { manager.reclaiming.contains(project.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.md) {
                StatusDot(color: (isStopping || isStarting || isReclaiming) ? Theme.Colors.statusWarning : (manager.isReady(project.id) ? Theme.Colors.statusSuccess : Theme.Colors.statusIdle))
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
                .disabled(isStopping || isExternal || isReclaiming || inspectingPort)
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
            if let error = portActionError ?? manager.errors[project.id] {
                Text(error).font(.caption).foregroundStyle(Theme.Colors.statusError).fixedSize(horizontal: false, vertical: true)
            }
            if !isRunning, let port = project.port,
               isExternal || manager.portConflicts.contains(project.id) || isReclaiming {
                Button(isReclaiming ? "Freeing :\(String(port))…" : "Free :\(String(port)) & Start…") {
                    inspectingPort = true
                    portActionError = nil
                    Task { @MainActor in
                        defer { inspectingPort = false }
                        do {
                            let snapshot = try await manager.inspectPort(for: project.id)
                            if snapshot.owners.isEmpty { manager.start(project.id) }
                            else { conflict = snapshot }
                        } catch { portActionError = error.localizedDescription }
                    }
                }
                .buttonStyle(.borderless).font(.caption)
                .disabled(inspectingPort || isReclaiming)
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
        .alert("Free port :\(String(project.port ?? 0))?", isPresented: Binding(
            get: { conflict != nil }, set: { if !$0 { conflict = nil } }
        ), presenting: conflict) { snapshot in
            Button("Stop Processes & Start", role: .destructive) {
                Task { await manager.reclaimPortAndStart(project.id, confirmed: snapshot) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { snapshot in
            Text("Stop these listening processes, then start \(project.name)?\n\n\(snapshot.description)\n\nThis interrupts their services. Processes that do not stop gracefully will be forced to quit.")
        }
    }

    private var statusText: String {
        if isReclaiming { return "Freeing port" }
        if isStopping { return "Stopping" }
        if isExternal { return project.port.map { "Running externally · :\($0)" } ?? "Running externally" }
        if isStarting { return project.port.map { "Starting · waiting for :\($0)" } ?? "Starting" }
        if isRunning { return project.port.map { "Listening · :\($0)" } ?? "Running" }
        return project.port.map { "Stopped · :\($0)" } ?? "Stopped"
    }
}
