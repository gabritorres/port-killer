import SwiftUI
import UniformTypeIdentifiers

struct ProjectsView: View {
    @Bindable var manager: ProjectsState
    var searchText = ""
    @State private var editingProject: ProjectConfiguration?
    @State private var deletingProject: ProjectConfiguration?
    @State private var importing = false
    @State private var importError: String?

    private var sections: [ProjectSection] { manager.sections(search: searchText) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Projects").font(.title2.bold())
                    Text("Start a whole project or control each service. Favorites stay in the menu bar.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import…", systemImage: "square.and.arrow.down") { importing = true }
                Button("Add Service", systemImage: "plus") { editingProject = ProjectConfiguration() }
            }
            if manager.projects.isEmpty {
                ContentUnavailableView("No Saved Services", systemImage: "folder.badge.plus", description: Text("Add a folder and a start command. Use a shared project name to group related services."))
            } else if sections.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                if let name = section.name {
                                    ProjectGroupHeader(name: name, manager: manager)
                                }
                                ForEach(section.services) { project in
                                    VStack(alignment: .leading, spacing: Spacing.sm) {
                                        ProjectRowView(project: project, manager: manager)
                                        HStack(spacing: Spacing.lg) {
                                            Button("Edit") { editingProject = project }
                                            Button("Remove", role: .destructive) { deletingProject = project }
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.caption)
                                        .disabled(manager.running.contains(project.id))
                                    }
                                    Divider()
                                }
                            }
                            .padding(Spacing.lg)
                            .background(Theme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.md))
                        }
                    }
                }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editingProject) { project in
            ProjectEditorView(project: project, manager: manager)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 1_048_576 else { throw ProjectLaunchError.invalid("Choose a configuration smaller than 1 MB.") }
                let services = try JSONDecoder().decode([ProjectConfiguration].self, from: Data(contentsOf: url))
                try manager.importProjects(services)
            } catch { importError = error.localizedDescription }
        }
        .alert("Could Not Import Services", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
        .confirmationDialog("Remove Service?", isPresented: Binding(
            get: { deletingProject != nil },
            set: { if !$0 { deletingProject = nil } }
        ), presenting: deletingProject) { project in
            Button("Remove \(project.name)", role: .destructive) { manager.remove(project.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Only the saved launch configuration is removed. Your project files are kept.")
        }
    }
}
