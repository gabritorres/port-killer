import Darwin
import Foundation
import Testing
import Defaults
@testable import PortKiller

@MainActor
struct ProjectsStateTests {
    private func manager(in folder: URL, suite: UserDefaults) -> ProjectsState {
        ProjectsState(key: Defaults.Key("projects", default: [], suite: suite), logsDirectory: folder.appendingPathComponent("logs"))
    }

    private func workspace() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PortKiller-tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func waitUntil(_ condition: () -> Bool, seconds: Int = 6) async -> Bool {
        let deadline = Date().addingTimeInterval(Double(seconds))
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test("Saved projects and favorites survive a fresh manager; running state does not")
    func persistence() throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let suiteName = "ProjectsTests-\(UUID())"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let state = manager(in: folder, suite: suite)
        let project = ProjectConfiguration(name: " API ", directory: folder.path, command: " sleep 30 ", port: 8080)
        try state.save(project)
        state.toggleFavorite(project.id)
        let reloaded = manager(in: folder, suite: suite)
        #expect(reloaded.projects.first?.name == "API")
        #expect(reloaded.projects.first?.command == "sleep 30")
        #expect(reloaded.projects.first?.port == 8080)
        #expect(reloaded.projects.first?.isFavorite == false)
        #expect(reloaded.running.isEmpty)
        reloaded.remove(project.id)
        #expect(manager(in: folder, suite: suite).projects.isEmpty)
    }

    @Test("Invalid recipes are rejected before persistence")
    func invalidConfigurations() throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = ProjectConfiguration(name: "Demo", directory: folder.path, command: "sleep 30")
        for invalidPort in [0, -1, 65536] {
            var project = base
            project.port = invalidPort
            #expect(throws: ProjectLaunchError.self) { try project.validated() }
        }
        var project = base
        project.command = "  \n"
        #expect(throws: ProjectLaunchError.self) { try project.validated() }
        project = base
        project.directory = folder.appendingPathComponent("missing").path
        #expect(throws: ProjectLaunchError.self) { try project.validated() }
    }

    @Test("Folder shell characters stay literal, output is logged, and command failures are visible")
    func literalFolderAndFailure() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let unusual = folder.appendingPathComponent("space ' quote $(touch INJECTED) `touch OTHER`")
        try FileManager.default.createDirectory(at: unusual, withIntermediateDirectories: true)
        let suiteName = "ProjectsTests-\(UUID())"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let state = manager(in: folder, suite: suite)
        let project = ProjectConfiguration(name: "Failure", directory: unusual.path, command: "pwd; print -u2 diagnostic; exit 7")
        try state.save(project)
        state.start(project.id)
        #expect(await waitUntil { !state.running.contains(project.id) })
        #expect(state.errors[project.id]?.contains("7") == true)
        let log = try String(contentsOf: state.logURL(for: project.id), encoding: .utf8)
        #expect(log.contains(unusual.path))
        #expect(log.contains("diagnostic"))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("INJECTED").path))
    }

    @Test("Stop owns its process group, prevents duplicate starts and removes child workers")
    func lifecycle() async throws {
        let folder = try workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let suiteName = "ProjectsTests-\(UUID())"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let state = manager(in: folder, suite: suite)
        let project = ProjectConfiguration(name: "Worker", directory: folder.path, command: "sleep 30 & print $!; wait")
        try state.save(project)
        state.start(project.id)
        state.start(project.id)
        #expect(state.running.count == 1)
        #expect(throws: ProjectLaunchError.self) { try state.save(project) }
        state.remove(project.id)
        #expect(state.projects.count == 1)
        let wrotePID = await waitUntil {
            let output = try? String(contentsOf: state.logURL(for: project.id), encoding: .utf8)
            return output?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        #expect(wrotePID)
        let text = try String(contentsOf: state.logURL(for: project.id), encoding: .utf8)
        let worker = try #require(Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        await state.shutdown()
        #expect(state.running.isEmpty)
        #expect(state.errors[project.id] == nil)
        #expect(await waitUntil { kill(worker, 0) != 0 && errno == ESRCH })
        state.start(project.id)
        #expect(state.running.contains(project.id))
        await state.shutdown()
    }

    @Test("An occupied IPv4 or IPv6 TCP port is rejected without stopping its owner")
    func occupiedPorts() throws {
        for family in [AF_INET, AF_INET6] {
            let fd = socket(family, SOCK_STREAM, 0)
            #expect(fd >= 0)
            defer { close(fd) }
            var storage = sockaddr_storage()
            let length: socklen_t
            if family == AF_INET {
                var address = sockaddr_in()
                address.sin_family = sa_family_t(AF_INET)
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                length = socklen_t(MemoryLayout<sockaddr_in>.size)
                withUnsafeMutablePointer(to: &storage) { target in
                    withUnsafePointer(to: &address) { memcpy(target, $0, Int(length)) }
                }
            } else {
                var only: Int32 = 1
                setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &only, socklen_t(MemoryLayout<Int32>.size))
                var address = sockaddr_in6()
                address.sin6_family = sa_family_t(AF_INET6)
                address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
                length = socklen_t(MemoryLayout<sockaddr_in6>.size)
                withUnsafeMutablePointer(to: &storage) { target in
                    withUnsafePointer(to: &address) { memcpy(target, $0, Int(length)) }
                }
            }
            try withUnsafeMutablePointer(to: &storage) { pointer in
                try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    try #require(bind(fd, address, length) == 0)
                    try #require(listen(fd, 1) == 0)
                    var actualLength = length
                    try #require(getsockname(fd, address, &actualLength) == 0)
                }
            }
            let port = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { Int(UInt16(bigEndian: $0.pointee.sin_port)) }
            }
            #expect(throws: ProjectLaunchError.self) { try ProjectProcess.checkPort(port) }
            #expect(fcntl(fd, F_GETFD) >= 0)
        }
    }
}
