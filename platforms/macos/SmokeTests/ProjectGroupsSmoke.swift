import Foundation
import Defaults

/// Runs without Xcode's Testing module. Exercises the real model, persistence,
/// process groups and runtime environment; never uses the user's saved services.
@main
struct ProjectGroupsSmoke {
    @MainActor
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pk-groups-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suiteName = "pk-groups-\(UUID())"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let key = Defaults.Key<[ProjectConfiguration]>("services", default: [], suite: suite)
        let state = ProjectsState(key: key, logsDirectory: folder.appendingPathComponent("logs"))

        let legacy = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","name":"Legacy","directory":"/tmp","command":"sleep 30","isFavorite":true}
        """.utf8)
        let decoded = try JSONDecoder().decode(ProjectConfiguration.self, from: legacy)
        precondition(decoded.groupName == nil && decoded.startWithGroup == nil)
        print("PASS: existing saved configurations still decode")

        let shared = ["PK_GROUP_SMOKE_SECRET"]
        let a = ProjectConfiguration(name: "A", directory: folder.path, command: "printenv PK_GROUP_SMOKE_SECRET; sleep 30", group: "Demo", startOrder: 20, sharedEnvironmentKeys: shared)
        let b = ProjectConfiguration(name: "B", directory: folder.path, command: "printenv PK_GROUP_SMOKE_SECRET; sleep 30", group: "Demo", startOrder: 10, sharedEnvironmentKeys: shared)
        let manual = ProjectConfiguration(name: "Manual", directory: folder.path, command: "sleep 30", group: "Demo", startWithGroup: false)
        let other = ProjectConfiguration(name: "Other", directory: folder.path, command: "sleep 30", group: "Other")
        try state.importProjects([a,b,manual,other])
        try state.importProjects([a])
        precondition(state.projects.count == 4)
        precondition(state.sections(search: "Demo").first?.services.count == 3)
        precondition(state.sections(search: "Demo").first?.services.map(\.id) == [manual.id, b.id, a.id])
        var invalid = other
        invalid.directory = folder.appendingPathComponent("missing").path
        do { try state.importProjects([invalid]); fatalError("Invalid import accepted") }
        catch is ProjectLaunchError { }
        precondition(state.projects.first(where: { $0.id == other.id })?.directory == folder.path)
        let fresh = ProjectsState(key: key)
        precondition(fresh.projects.first(where: { $0.id == a.id })?.groupName == "Demo")
        print("PASS: import is idempotent and atomic; groups persist and search includes services")

        state.start(other.id)
        state.startGroup("Demo")
        precondition(state.running == Set([a.id,b.id,other.id]))
        precondition(state.isReady(a.id) && state.isReady(b.id))
        await wait {
            [a,b].allSatisfy { project in
                let log = try? String(contentsOf: state.logURL(for: project.id), encoding: .utf8)
                return log?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
        }
        let aValue = try String(contentsOf: state.logURL(for: a.id), encoding: .utf8)
        let bValue = try String(contentsOf: state.logURL(for: b.id), encoding: .utf8)
        precondition(aValue == bValue && aValue.trimmingCharacters(in: .whitespacesAndNewlines).count == 96)
        let persisted = try JSONEncoder().encode(state.projects)
        precondition(!String(decoding: persisted, as: UTF8.self).contains(aValue.trimmingCharacters(in: .whitespacesAndNewlines)))
        state.stopGroup("Demo")
        await wait { !state.running.contains(a.id) && !state.running.contains(b.id) }
        precondition(state.running.contains(other.id))
        await state.shutdown()
        print("PASS: group starts eligible services, shares temporary values without persisting them, and stops only its own group")

        let external = ProjectConfiguration(name: "External", directory: folder.path, command: "sleep 30", port: 12345, group: "Demo")
        try state.save(external)
        state.updateListeners([ProjectListener(port: 12345, directory: "/unrelated", processName: "node")])
        precondition(!state.isActive(external.id) && !state.isReady(external.id))
        state.updateListeners([ProjectListener(port: 12345, directory: folder.path, processName: "node")])
        precondition(state.isActive(external.id) && state.isReady(external.id) && state.externalRunning.contains(external.id))
        state.stopGroup("Demo")
        precondition(state.externalRunning.contains(external.id))
        print("PASS: external listeners require matching identity and are not stopped by group actions")
    }

    @MainActor
    static func wait(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(8)
        while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        precondition(condition(), "Timed out")
    }
}
