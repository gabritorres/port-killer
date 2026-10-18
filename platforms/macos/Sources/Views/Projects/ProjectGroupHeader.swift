import SwiftUI

/// Same group lifecycle controls in the main window and the compact menu.
struct ProjectGroupHeader: View {
    let name: String
    @Bindable var manager: ProjectsState
    var compact = false

    private var services: [ProjectConfiguration] { manager.projects.filter { $0.groupName == name } }
    private var activeCount: Int { services.filter { manager.isReady($0.id) }.count }
    private var externalCount: Int { services.filter { manager.externalRunning.contains($0.id) }.count }
    private var hasOwned: Bool { services.contains { manager.running.contains($0.id) } }
    private var canStart: Bool {
        services.contains { $0.startWithGroup != false && !manager.isActive($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "folder.fill").foregroundStyle(Theme.Colors.link)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(name).font(compact ? .callout.weight(.semibold) : .headline)
                    Text("\(String(activeCount))/\(String(services.count)) ready")
                        .font(.caption).foregroundStyle(.secondary)
                        .help("Services with a port are ready when a TCP listener is detected; this is not an HTTP health check.")
                }
                Spacer(minLength: Spacing.xs)
                Button(compact ? "Start" : "Start Group") { manager.startGroup(name) }
                    .disabled(!canStart)
                    .accessibilityLabel("Start group \(name)")
                Button(compact ? "Stop" : "Stop Group") { manager.stopGroup(name) }
                    .disabled(!hasOwned)
                    .accessibilityLabel("Stop group \(name)")
            }
            .controlSize(.small)
            if externalCount > 0 {
                Text("\(String(externalCount)) external — group actions keep them running")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}
