import Darwin
import Foundation

/// Owns a child and its dedicated process group. Never signals a PID discovered
/// by port scanning. The unreaped child reserves the group ID until cleanup.
@MainActor
final class ProjectProcess {
    private(set) var pid: pid_t = 0
    private var reaped = false

    init(project: ProjectConfiguration, logURL: URL, environment overrides: [String: String] = [:]) throws {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        var code = posix_spawn_file_actions_init(&actions)
        guard code == 0 else { throw ProjectLaunchError.system("Prepare process", code) }
        defer { posix_spawn_file_actions_destroy(&actions) }
        code = posix_spawnattr_init(&attributes)
        guard code == 0 else { throw ProjectLaunchError.system("Prepare process group", code) }
        defer { posix_spawnattr_destroy(&attributes) }

        func check(_ result: Int32) throws {
            guard result == 0 else { throw ProjectLaunchError.system("Configure process", result) }
        }
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        try check(posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, logURL.path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR))
        try check(posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO))

        // Pass paths and commands as arguments: spaces, quotes and shell syntax
        // in folder names cannot turn into another command. Only the explicitly
        // saved command is evaluated. cd follows login-shell initialization.
        let arguments = ["/bin/zsh", "-l", "-c", "cd -- \"$1\" || exit\neval \"$2\"", "portkiller-project", project.directory, project.command]
        let argv = arguments.map { strdup($0) } + [nil]
        let inheritedEnvironment = ProcessInfo.processInfo.environment.merging(overrides) { _, new in new }
        let environment = inheritedEnvironment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            environment.forEach { free($0) }
        }
        code = argv.withUnsafeBufferPointer {
            arguments in environment.withUnsafeBufferPointer {
                posix_spawn(&pid, "/bin/zsh", &actions, &attributes, arguments.baseAddress!, $0.baseAddress!)
            }
        }
        guard code == 0 else { throw ProjectLaunchError.system("Start project", code) }
    }

    func signal(_ signal: Int32) {
        guard !reaped, pid > 0 else { return }
        Darwin.kill(-pid, signal)
    }

    /// Inspect without reaping, clean up remaining workers while the leader's
    /// PID cannot be reused, then reap. Returns a conventional shell exit code.
    func pollExit() -> Int32? {
        guard !reaped else { return nil }
        var info = siginfo_t()
        guard waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0 else {
            return nil
        }
        guard info.si_pid == pid else { return nil }
        signal(SIGKILL)
        var status: Int32 = 0
        guard waitpid(pid, &status, 0) == pid else { return nil }
        reaped = true
        return status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
    }

    /// Probe both TCP address families before starting, including wildcard and
    /// IPv6-only listeners. No currently running service is stopped to free it.
    static func checkPort(_ port: Int) throws {
        let ipv4 = socket(AF_INET, SOCK_STREAM, 0)
        guard ipv4 >= 0 else { throw ProjectLaunchError.system("Check port", errno) }
        defer { close(ipv4) }
        var address4 = sockaddr_in()
        address4.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address4.sin_family = sa_family_t(AF_INET)
        address4.sin_port = UInt16(port).bigEndian
        try withUnsafePointer(to: &address4) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try checkBind(ipv4, address: $0, length: socklen_t(MemoryLayout<sockaddr_in>.size), port: port)
            }
        }
        let ipv6 = socket(AF_INET6, SOCK_STREAM, 0)
        guard ipv6 >= 0 else { throw ProjectLaunchError.system("Check IPv6 port", errno) }
        defer { close(ipv6) }
        var v6Only: Int32 = 1
        guard setsockopt(ipv6, IPPROTO_IPV6, IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw ProjectLaunchError.system("Check IPv6 port", errno)
        }
        var address6 = sockaddr_in6()
        address6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address6.sin6_family = sa_family_t(AF_INET6)
        address6.sin6_port = UInt16(port).bigEndian
        try withUnsafePointer(to: &address6) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try checkBind(ipv6, address: $0, length: socklen_t(MemoryLayout<sockaddr_in6>.size), port: port)
            }
        }
    }

    private static func checkBind(_ fd: Int32, address: UnsafePointer<sockaddr>, length: socklen_t, port: Int) throws {
        guard bind(fd, address, length) == 0 else {
            if errno == EADDRINUSE {
                // A recently closed connection can prevent a plain bind while
                // no server remains. Do not turn TIME_WAIT into a port conflict.
                if try ProjectPortConflict.listenerNames(on: port).isEmpty { return }
                throw ProjectLaunchError.occupied(port)
            }
            throw ProjectLaunchError.system("Check port", errno)
        }
    }
}
