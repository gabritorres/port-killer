import Darwin
import Defaults
import Foundation

@main
struct ProjectPortConflictSmoke {
    @MainActor
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pk-port-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("server.py")
        try """
        import socket, sys, signal
        family = socket.AF_INET6 if sys.argv[1] == '6' else socket.AF_INET
        mode = sys.argv[3]
        if mode == 'ignore': signal.signal(signal.SIGTERM, signal.SIG_IGN)
        s = socket.socket(family)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if family == socket.AF_INET6: s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        s.bind(('::1' if family == socket.AF_INET6 else '127.0.0.1', int(sys.argv[4])))
        s.listen(5)
        with open(sys.argv[2], 'w') as f: f.write(str(s.getsockname()[1]))
        while True:
            c, _ = s.accept()
            c.sendall(b'ok')
            c.shutdown(socket.SHUT_WR)
            c.close()
            if mode == 'once': break
        s.close()
        """.write(to: script, atomically: true, encoding: .utf8)

        for family in [4, 6] {
            let (server, port) = try await fixture(folder, script: script, family: family, mode: "once")
            do { try ProjectProcess.checkPort(port); fatalError("Active listener accepted") }
            catch ProjectLaunchError.occupied { }
            try exchange(port: port, ipv6: family == 6)
            await wait { server.pollExit() != nil }
            precondition(oldBindIsOccupied(port, ipv6: family == 6), "Fixture must retain TIME_WAIT")
            try ProjectProcess.checkPort(port)
            print("PASS: IPv\(family) listener is rejected; immediate restart after TIME_WAIT is allowed")
        }

        let suiteName = "pk-conflicts-\(UUID())"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let state = ProjectsState(key: Defaults.Key("projects", default: [], suite: suite), logsDirectory: folder)
        let (external, port) = try await fixture(folder, script: script, family: 4, mode: "ignore")
        let project = ProjectConfiguration(name: "Replacement", directory: folder.path,
            command: "/usr/bin/python3 -m http.server \(port) --bind 127.0.0.1", port: port)
        try state.save(project)
        state.start(project.id)
        precondition(state.portConflicts.contains(project.id) && state.running.isEmpty)
        let confirmed = try await state.inspectPort(for: project.id)
        precondition(!confirmed.owners.isEmpty)
        let wrong = ProjectPortConflict(port: port, owners: confirmed.owners.map {
            ProjectPortOwner(pid: $0.pid, name: $0.name, startedSeconds: $0.startedSeconds + 1,
                             startedMicroseconds: $0.startedMicroseconds)
        })
        await state.reclaimPortAndStart(project.id, confirmed: wrong)
        precondition(!state.running.contains(project.id))
        let preserved = try ProjectPortConflict.inspect(port)
        precondition(preserved.owners == confirmed.owners)
        print("PASS: normal Start preserves a competing listener; stale process identity cannot kill it")

        await state.reclaimPortAndStart(project.id, confirmed: confirmed)
        precondition(state.running.contains(project.id), state.errors[project.id] ?? "Replacement did not start")
        await wait { (try? ProjectPortConflict.inspect(port).owners.isEmpty) == false }
        let takenOver = try ProjectPortConflict.inspect(port)
        precondition(takenOver.owners != confirmed.owners)
        await wait { external.pollExit() != nil }
        await state.shutdown()
        let stopped = try ProjectPortConflict.inspect(port)
        precondition(stopped.owners.isEmpty)
        print("PASS: confirmed takeover escalates for a resistant listener, starts the replacement and cleans up")

        let (first, racePort) = try await fixture(folder, script: script, family: 4, mode: "loop")
        let old = try ProjectPortConflict.inspect(racePort)
        first.signal(SIGTERM)
        await wait { first.pollExit() != nil }
        let (replacement, _) = try await fixture(folder, script: script, family: 4, mode: "loop", port: racePort)
        var race = project
        race.id = UUID()
        race.port = racePort
        try state.save(race)
        await state.reclaimPortAndStart(race.id, confirmed: old)
        precondition(!state.running.contains(race.id))
        let raced = try ProjectPortConflict.inspect(racePort)
        precondition(!raced.owners.isEmpty)
        replacement.signal(SIGTERM)
        await wait { replacement.pollExit() != nil }
        print("PASS: an intervening listener is preserved and requires fresh confirmation")


        let (resistant, cancelPort) = try await fixture(folder, script: script, family: 4, mode: "ignore")
        var cancelled = project
        cancelled.id = UUID()
        cancelled.port = cancelPort
        try state.save(cancelled)
        let cancelSnapshot = try ProjectPortConflict.inspect(cancelPort)
        let takeover = Task { await state.reclaimPortAndStart(cancelled.id, confirmed: cancelSnapshot) }
        await wait { state.reclaiming.contains(cancelled.id) }
        state.stop(cancelled.id)
        await takeover.value
        precondition(!state.running.contains(cancelled.id) && !state.reclaiming.contains(cancelled.id))
        let afterCancel = try ProjectPortConflict.inspect(cancelPort)
        precondition(afterCancel.owners == cancelSnapshot.owners)
        resistant.signal(SIGKILL)
        await wait { resistant.pollExit() != nil }
        print("PASS: Stop cancels a pending takeover without escalation or launching a replacement")
    }

    @MainActor
    static func fixture(_ folder: URL, script: URL, family: Int, mode: String, port: Int = 0) async throws -> (ProjectProcess, Int) {
        let file = folder.appendingPathComponent(UUID().uuidString)
        let project = ProjectConfiguration(name: "Fixture", directory: folder.path,
            command: "/usr/bin/python3 '\(script.path)' \(family) '\(file.path)' \(mode) \(port)")
        let process = try ProjectProcess(project: project, logURL: file.appendingPathExtension("log"))
        await wait { FileManager.default.fileExists(atPath: file.path) &&
            (try? String(contentsOf: file, encoding: .utf8).isEmpty) == false }
        return (process, Int(try String(contentsOf: file, encoding: .utf8))!)
    }

    static func address(port: Int, ipv6: Bool) -> (sockaddr_storage, socklen_t) {
        var storage = sockaddr_storage()
        if ipv6 {
            var value = sockaddr_in6()
            value.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            value.sin6_family = sa_family_t(AF_INET6)
            value.sin6_port = UInt16(port).bigEndian
            value.sin6_addr = in6addr_loopback
            withUnsafePointer(to: &value) { source in _ = withUnsafeMutablePointer(to: &storage) { memcpy($0, source, MemoryLayout<sockaddr_in6>.size) } }
            return (storage, socklen_t(MemoryLayout<sockaddr_in6>.size))
        }
        var value = sockaddr_in()
        value.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        value.sin_family = sa_family_t(AF_INET)
        value.sin_port = UInt16(port).bigEndian
        value.sin_addr.s_addr = inet_addr("127.0.0.1")
        withUnsafePointer(to: &value) { source in _ = withUnsafeMutablePointer(to: &storage) { memcpy($0, source, MemoryLayout<sockaddr_in>.size) } }
        return (storage, socklen_t(MemoryLayout<sockaddr_in>.size))
    }

    static func exchange(port: Int, ipv6: Bool) throws {
        let fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var (value, length) = address(port: port, ipv6: ipv6)
        precondition(withUnsafePointer(to: &value) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) } } == 0)
        var buffer = [UInt8](repeating: 0, count: 64)
        while recv(fd, &buffer, buffer.count, 0) > 0 { }
    }

    static func oldBindIsOccupied(_ port: Int, ipv6: Bool) -> Bool {
        let fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var (value, length) = address(port: port, ipv6: ipv6)
        return withUnsafePointer(to: &value) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) } } != 0 && errno == EADDRINUSE
    }

    @MainActor
    static func wait(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        preconditionFailure("Timed out")
    }
}
