import Foundation
import Defaults
import Observation

extension Defaults.Keys {
    static let savedProjects = Key<[ProjectConfiguration]>("savedProjects", default: [])
}

@Observable
@MainActor
final class ProjectsState {
    private(set) var projects: [ProjectConfiguration]
    private(set) var running: Set<UUID> = []
    private(set) var stopping: Set<UUID> = []
    private(set) var errors: [UUID: String] = [:]
    @ObservationIgnored private let key: Defaults.Key<[ProjectConfiguration]>
    @ObservationIgnored private let logsDirectory: URL
    @ObservationIgnored private var processes: [UUID: ProjectProcess] = [:]
    @ObservationIgnored private var monitors: [UUID: Task<Void, Never>] = [:]

    init(key: Defaults.Key<[ProjectConfiguration]> = .savedProjects, logsDirectory: URL? = nil) {
        self.key = key
        projects = Defaults[key]
        let appFolder = Bundle.main.object(forInfoDictionaryKey: "PKDevelopmentBuild") as? Bool == true
            ? "PortKiller Projects Dev" : "PortKiller"
        self.logsDirectory = logsDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(appFolder)/ProjectLogs", isDirectory: true)
    }

    var sortedProjects: [ProjectConfiguration] {
        projects.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func save(_ project: ProjectConfiguration) throws {
        guard !running.contains(project.id) else { throw ProjectLaunchError.invalid("Stop the project before editing it.") }
        let valid = try project.validated()
        if let index = projects.firstIndex(where: { $0.id == valid.id }) { projects[index] = valid }
        else { projects.append(valid) }
        Defaults[key] = projects
        errors[valid.id] = nil
    }

    func remove(_ id: UUID) {
        guard !running.contains(id) else { return }
        projects.removeAll { $0.id == id }
        Defaults[key] = projects
        errors[id] = nil
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].isFavorite.toggle()
        Defaults[key] = projects
    }

    func logURL(for id: UUID) -> URL {
        logsDirectory.appendingPathComponent("\(id.uuidString).log")
    }

    func start(_ id: UUID) {
        guard !running.contains(id), let saved = projects.first(where: { $0.id == id }) else { return }
        errors[id] = nil
        do {
            let project = try saved.validated()
            if let port = project.port { try ProjectProcess.checkPort(port) }
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            let process = try ProjectProcess(project: project, logURL: logURL(for: id))
            processes[id] = process
            running.insert(id)
            monitors[id] = Task { [weak self] in
                while !Task.isCancelled {
                    if let exit = process.pollExit() {
                        guard let self else { return }
                        if exit != 0 && !self.stopping.contains(id) {
                            self.errors[id] = "Command exited with code \(exit). Open Logs for details."
                        }
                        self.running.remove(id)
                        self.stopping.remove(id)
                        self.processes[id] = nil
                        self.monitors[id] = nil
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        } catch {
            errors[id] = error.localizedDescription
        }
    }

    func stop(_ id: UUID) {
        guard let process = processes[id], !stopping.contains(id) else { return }
        stopping.insert(id)
        process.signal(SIGTERM)
        Task {
            try? await Task.sleep(for: .seconds(3))
            // The handle marks itself reaped before its PID can be reused.
            process.signal(SIGKILL)
        }
    }

    func shutdown() async {
        for id in running { stop(id) }
        while !running.isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
