import SwiftUI
import AppKit

enum ProjectLayout {
    static let editorWidth: CGFloat = 580
    static let editorHeight: CGFloat = 680
    static let commandHeight: CGFloat = 72
    static let actionWidth: CGFloat = 68
}

struct ProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var project: ProjectConfiguration
    let manager: ProjectsState
    @State private var portText = ""
    @State private var errorMessage: String?
    @State private var groupText = ""
    @State private var order = 0
    @State private var startWithGroup = true
    @State private var sharedKeysText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text(manager.projects.contains(where: { $0.id == project.id }) ? "Edit Service" : "Add Service")
                .font(.title2.bold())
            Form {
                TextField("Name", text: $project.name)
                TextField("Project / group (optional)", text: $groupText)
                LabeledContent("Folder") {
                    HStack(spacing: Spacing.md) {
                        TextField("/path/to/project", text: $project.directory)
                            .accessibilityLabel("Project folder")
                        Button("Choose…", action: chooseFolder)
                    }
                }
                LabeledContent("Start command") {
                    TextEditor(text: $project.command)
                        .font(.body.monospaced())
                        .frame(height: ProjectLayout.commandHeight)
                        .accessibilityLabel("Start command")
                }
                TextField("Port (optional)", text: $portText)
                Toggle("Favorite — show project in the menu bar", isOn: $project.isFavorite)
                if !groupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Stepper("Start order: \(String(order))", value: $order, in: 0...999)
                    Toggle("Include in Start Group", isOn: $startWithGroup)
                    TextField("Shared temporary variables (comma-separated names)", text: $sharedKeysText)
                    Text("Services in this project share an in-memory random value for each named variable. Values are never saved. Lower start orders launch first; they do not wait for readiness.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Text("Runs in a login zsh shell inside this folder. Keep the command in the foreground (for example, pnpm dev). Closing PortKiller stops projects it started. Logs are replaced on each start.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Theme.Colors.statusError)
                    .accessibilityLabel("Error: \(errorMessage)")
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xxl)
        .frame(width: ProjectLayout.editorWidth, height: ProjectLayout.editorHeight)
        .onAppear {
            portText = project.port.map(String.init) ?? ""
            groupText = project.groupName ?? ""
            order = project.startOrder ?? 0
            startWithGroup = project.startWithGroup != false
            sharedKeysText = (project.sharedEnvironmentKeys ?? []).joined(separator: ", ")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        project.directory = url.path
        if project.name.isEmpty { project.name = url.lastPathComponent }
    }

    private func save() {
        let trimmed = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && Int(trimmed) == nil {
            errorMessage = "Enter a port number, or leave it empty."
            return
        }
        project.port = Int(trimmed)
        project.group = groupText
        project.startOrder = order
        project.startWithGroup = startWithGroup
        project.sharedEnvironmentKeys = sharedKeysText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        do {
            try manager.save(project)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
