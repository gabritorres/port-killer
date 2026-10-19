import Darwin
import Foundation

struct ProjectPortOwner: Hashable, Sendable {
    let pid: Int32
    let name: String
    let startedSeconds: UInt64
    let startedMicroseconds: UInt64

    static func read(pid: Int32, name: String) throws -> Self {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            throw ProjectLaunchError.invalid("Cannot verify process \(pid). Refresh and try again.")
        }
        return Self(pid: pid, name: name, startedSeconds: info.pbi_start_tvsec,
                    startedMicroseconds: info.pbi_start_tvusec)
    }
}

struct ProjectPortConflict: Sendable {
    let port: Int
    let owners: [ProjectPortOwner]

    var description: String {
        owners.map { "\($0.name) (PID \($0.pid))" }.joined(separator: "\n")
    }

    /// LISTEN is intentional: TIME_WAIT connections have no server to stop.
    /// Called off the main actor for inspection and takeover; the ordinary
    /// launch probe only calls it after bind reports EADDRINUSE.
    static func listenerNames(on port: Int) throws -> [Int32: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpc"]
        let output = Pipe()
        process.standardOutput = output
        // lsof diagnostics are not listener records. Retain them to distinguish
        // a failed scan from its normal exit 1 for no matching sockets.
        let error = Pipe()
        process.standardError = error
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let diagnostics = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 ||
                (process.terminationStatus == 1 && data.isEmpty && diagnostics.isEmpty) else {
            throw ProjectLaunchError.invalid("Could not inspect port \(port). Refresh and try again.")
        }
        var names: [Int32: String] = [:]
        var pid: Int32?
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            if line.first == "p" { pid = Int32(line.dropFirst()) }
            if line.first == "c", let pid { names[pid] = String(line.dropFirst()) }
        }
        guard data.isEmpty || !names.isEmpty else {
            throw ProjectLaunchError.invalid("Could not identify the listener on port \(port).")
        }
        return names
    }

    static func inspect(_ port: Int) throws -> Self {
        let owners = try listenerNames(on: port).sorted { $0.key < $1.key }.map {
            try ProjectPortOwner.read(pid: $0.key, name: $0.value)
        }
        return Self(port: port, owners: owners)
    }

    func verify(_ current: Self) throws {
        guard current.port == port, Set(current.owners).isSubset(of: Set(owners)) else {
            throw ProjectLaunchError.invalid("Port \(port) has a different owner now. Review its processes again.")
        }
    }

    /// Signal only the confirmed listener PID, never its parent or process group.
    /// Revalidate both socket ownership and process birth time before each signal.
    func signal(_ signal: Int32) throws {
        let current = try Self.inspect(port)
        try verify(current)
        for owner in current.owners {
            guard owner.pid > 1, owner.pid != getpid(),
                  try ProjectPortOwner.read(pid: owner.pid, name: owner.name) == owner else {
                throw ProjectLaunchError.invalid("Cannot safely stop process \(owner.pid). Refresh and try again.")
            }
            if Darwin.kill(owner.pid, signal) != 0 && errno != ESRCH {
                throw ProjectLaunchError.system("Stop process \(owner.pid)", errno)
            }
        }
    }
}
