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
    private(set) var externalRunning: Set<UUID> = []
    private(set) var listening: Set<UUID> = []
    private(set) var portConflicts: Set<UUID> = []
    private(set) var reclaiming: Set<UUID> = []
    @ObservationIgnored private var cancelledReclaims: Set<UUID> = []
    @ObservationIgnored private let key: Defaults.Key<[ProjectConfiguration]>
    @ObservationIgnored private let logsDirectory: URL
    @ObservationIgnored private var processes: [UUID: ProjectProcess] = [:]
    @ObservationIgnored private var monitors: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var listeners: [ProjectListener] = []
    @ObservationIgnored private var sharedEnvironments: [String: [String: String]] = [:]

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

    func sections(search: String = "", menuOnly: Bool = false) -> [ProjectSection] {
        let grouped = Dictionary(grouping: projects) { project in
            project.groupName.map { "group:\($0)" } ?? "service:\(project.id)"
        }
        return grouped.compactMap { id, allServices in
            let name = allServices.first?.groupName
            if menuOnly && !allServices.contains(where: { $0.isFavorite || isActive($0.id) }) { return nil }
            let matchesGroup = name?.localizedCaseInsensitiveContains(search) == true
            let services = allServices.filter {
                search.isEmpty || matchesGroup || $0.name.localizedCaseInsensitiveContains(search) ||
                    $0.directory.localizedCaseInsensitiveContains(search) ||
                    ($0.port.map(String.init)?.contains(search) ?? false)
            }.sorted {
                if ($0.startOrder ?? 0) != ($1.startOrder ?? 0) { return ($0.startOrder ?? 0) < ($1.startOrder ?? 0) }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            guard !services.isEmpty else { return nil }
            return ProjectSection(id: id, name: name, services: services)
        }.sorted {
            let a = $0.services.contains(where: \.isFavorite)
            let b = $1.services.contains(where: \.isFavorite)
            if a != b { return a }
            return ($0.name ?? $0.services[0].name).localizedStandardCompare($1.name ?? $1.services[0].name) == .orderedAscending
        }
    }

    func isActive(_ id: UUID) -> Bool { running.contains(id) || externalRunning.contains(id) || reclaiming.contains(id) }

    func isReady(_ id: UUID) -> Bool {
        externalRunning.contains(id) || (running.contains(id) &&
            (projects.first(where: { $0.id == id })?.port == nil || listening.contains(id)))
    }

    func updateListeners(_ current: [ProjectListener]) {
        listeners = current
        let ready = Set(projects.filter { project in
            current.contains { matches(project, listener: $0) }
        }.map(\.id))
        if ready != listening { listening = ready }
        let detected = Set(projects.filter { project in
            !running.contains(project.id) && current.contains { matches(project, listener: $0) }
        }.map(\.id))
        if detected != externalRunning { externalRunning = detected }
    }

    private func matches(_ project: ProjectConfiguration, listener: ProjectListener) -> Bool {
        guard project.port == listener.port else { return false }
        if let expectedName = project.externalProcessName, listener.processName == expectedName { return true }
        guard let directory = listener.directory else { return false }
        return URL(fileURLWithPath: directory).resolvingSymlinksInPath().standardizedFileURL ==
            URL(fileURLWithPath: project.directory).resolvingSymlinksInPath().standardizedFileURL
    }

    /// Validate the entire import before changing saved data. Existing IDs update
    /// in place; running services and unrelated saved projects are preserved.
    func importProjects(_ incoming: [ProjectConfiguration]) throws {
        guard Set(incoming.map(\.id)).count == incoming.count else {
            throw ProjectLaunchError.invalid("The import contains duplicate service IDs.")
        }
        guard !incoming.contains(where: { running.contains($0.id) || reclaiming.contains($0.id) }) else {
            throw ProjectLaunchError.invalid("Stop services before replacing their configuration.")
        }
        let validated = try incoming.map { try $0.validated() }
        var updated = projects
        for project in validated {
            if let index = updated.firstIndex(where: { $0.id == project.id }) { updated[index] = project }
            else { updated.append(project) }
        }
        projects = updated
        Defaults[key] = projects
        updateListeners(listeners)
    }

    func startGroup(_ name: String) {
        let services = sections().first(where: { $0.name == name })?.services ?? []
        for project in services where project.startWithGroup != false { start(project.id) }
    }

    func stopGroup(_ name: String) {
        let services = sections().first(where: { $0.name == name })?.services ?? []
        for project in services.reversed() { stop(project.id) }
    }

    func save(_ project: ProjectConfiguration) throws {
        guard !running.contains(project.id), !reclaiming.contains(project.id) else { throw ProjectLaunchError.invalid("Stop the project before editing it.") }
        let valid = try project.validated()
        if let index = projects.firstIndex(where: { $0.id == valid.id }) { projects[index] = valid }
        else { projects.append(valid) }
        Defaults[key] = projects
        errors[valid.id] = nil
        updateListeners(listeners)
    }

    func remove(_ id: UUID) {
        guard !running.contains(id), !reclaiming.contains(id) else { return }
        projects.removeAll { $0.id == id }
        Defaults[key] = projects
        errors[id] = nil
        updateListeners(listeners)
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
        guard !running.contains(id), !reclaiming.contains(id), let saved = projects.first(where: { $0.id == id }) else { return }
        errors[id] = nil
        portConflicts.remove(id)
        if externalRunning.contains(id) {
            // A listener may have stopped since the last scan. Verify that its
            // port is still occupied before deciding to skip a duplicate start.
            if let port = saved.port, (try? ProjectProcess.checkPort(port)) != nil {
                externalRunning.remove(id)
            } else { return }
        }
        do {
            let project = try saved.validated()
            let sharedKeys = project.sharedEnvironmentKeys ?? []
            if !sharedKeys.isEmpty, let group = project.groupName,
               projects.contains(where: { peer in
                   peer.groupName == group && externalRunning.contains(peer.id) &&
                       !Set(sharedKeys).isDisjoint(with: peer.sharedEnvironmentKeys ?? [])
               }) {
                throw ProjectLaunchError.invalid("A linked service is running externally. Start the linked services together from PortKiller to share their temporary variables.")
            }
            if let port = project.port { try ProjectProcess.checkPort(port) }
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            let scope = project.groupName.map { "group:\($0)" } ?? "service:\(id)"
            var environment = sharedEnvironments[scope] ?? [:]
            for key in sharedKeys where environment[key] == nil {
                environment[key] = (0..<48).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
            }
            sharedEnvironments[scope] = environment
            let process = try ProjectProcess(project: project, logURL: logURL(for: id),
                environment: environment.filter { sharedKeys.contains($0.key) })
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
        } catch ProjectLaunchError.occupied(let port) {
            portConflicts.insert(id)
            errors[id] = ProjectLaunchError.occupied(port).localizedDescription
        } catch {
            errors[id] = error.localizedDescription
        }
    }

    func stop(_ id: UUID) {
        if reclaiming.contains(id) { cancelledReclaims.insert(id); return }
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
        for id in running.union(reclaiming) { stop(id) }
        while !running.isEmpty || !reclaiming.isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

extension ProjectsState {
    func inspectPort(for id: UUID) async throws -> ProjectPortConflict {
        guard !running.contains(id), !reclaiming.contains(id),
              let port = projects.first(where: { $0.id == id })?.port else {
            throw ProjectLaunchError.invalid("Stop the service and set its port before continuing.")
        }
        return try await Task.detached { try ProjectPortConflict.inspect(port) }.value
    }

    func reclaimPortAndStart(_ id: UUID, confirmed: ProjectPortConflict) async {
        guard !running.contains(id), !reclaiming.contains(id),
              projects.first(where: { $0.id == id })?.port == confirmed.port else { return }
        reclaiming.insert(id)
        errors[id] = nil
        defer {
            reclaiming.remove(id)
            cancelledReclaims.remove(id)
        }
        do {
            guard !cancelledReclaims.contains(id) else { return }
            try await Task.detached { try confirmed.signal(SIGTERM) }.value
            var current = try await waitForPort(confirmed, id: id)
            guard !cancelledReclaims.contains(id) else { return }
            if !current.owners.isEmpty {
                try await Task.detached { try confirmed.signal(SIGKILL) }.value
                current = try await waitForPort(confirmed, id: id)
            }
            guard !cancelledReclaims.contains(id) else { return }
            guard current.owners.isEmpty else { throw ProjectLaunchError.occupied(confirmed.port) }
            externalRunning.remove(id)
            reclaiming.remove(id)
            start(id)
        } catch {
            if !cancelledReclaims.contains(id) { errors[id] = error.localizedDescription }
        }
    }

    private func waitForPort(_ confirmed: ProjectPortConflict, id: UUID) async throws -> ProjectPortConflict {
        let deadline = Date().addingTimeInterval(2)
        while true {
            let current = try await Task.detached { try ProjectPortConflict.inspect(confirmed.port) }.value
            try confirmed.verify(current)
            if current.owners.isEmpty || Date() >= deadline || cancelledReclaims.contains(id) { return current }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
