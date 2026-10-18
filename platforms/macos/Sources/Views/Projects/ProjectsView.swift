import SwiftUI

struct ProjectsView: View {
    @Bindable var manager: ProjectsState
    var searchText = ""
    @State private var editingProject: ProjectConfiguration?
    @State private var deletingProject: ProjectConfiguration?

    private var filtered: [ProjectConfiguration] {
        manager.sortedProjects.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.directory.localizedCaseInsensitiveContains(searchText)
                || ($0.port.map(String.init)?.contains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Projects").font(.title2.bold())
                    Text("Save your start commands. Favorites stay in the menu bar, ready to run.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Project", systemImage: "plus") { editingProject = ProjectConfiguration() }
            }
            if manager.projects.isEmpty {
                ContentUnavailableView("No Saved Projects", systemImage: "folder.badge.plus", description: Text("Add a folder and a start command, such as npm run dev."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(filtered) { project in
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
                    .padding(.vertical, Spacing.xs)
                }
                .listStyle(.inset)
            }
        }
        .padding(Spacing.xl)
        .sheet(item: $editingProject) { project in
            ProjectEditorView(project: project, manager: manager)
        }
        .confirmationDialog("Remove Project?", isPresented: Binding(
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
