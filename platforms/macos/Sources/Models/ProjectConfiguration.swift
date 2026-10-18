import Foundation
import Defaults

/// A saved launch recipe, independent of whichever process currently owns a port.
struct ProjectConfiguration: Codable, Hashable, Identifiable, Sendable, Defaults.Serializable {
    var id = UUID()
    var name = ""
    var directory = ""
    var command = ""
    var port: Int?
    var isFavorite = true
    // Optional fields preserve configurations saved before service groups existed.
    var group: String?
    var startOrder: Int?
    var startWithGroup: Bool?
    var sharedEnvironmentKeys: [String]?
    var externalProcessName: String?

    var groupName: String? {
        let value = group?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    func validated() throws -> Self {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        result.group = groupName
        result.sharedEnvironmentKeys = Array(Set(sharedEnvironmentKeys ?? [])).sorted()
        result.directory = (directory as NSString).expandingTildeInPath
        guard !result.name.isEmpty else { throw ProjectLaunchError.invalid("Enter a project name.") }
        guard !result.command.isEmpty else { throw ProjectLaunchError.invalid("Enter a start command.") }
        guard result.directory.hasPrefix("/"), !result.directory.contains("\0"), !result.command.contains("\0") else {
            throw ProjectLaunchError.invalid("Choose an absolute folder path and a valid command.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: result.directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectLaunchError.invalid("The project folder does not exist.")
        }
        if let port, !(1...65535).contains(port) {
            throw ProjectLaunchError.invalid("The port must be between 1 and 65535, or empty.")
        }
        if let startOrder, !(0...999).contains(startOrder) {
            throw ProjectLaunchError.invalid("Start order must be between 0 and 999.")
        }
        for key in result.sharedEnvironmentKeys ?? [] {
            guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                throw ProjectLaunchError.invalid("Shared variable names must contain only letters, numbers and underscores.")
            }
        }
        return result
    }
}

struct ProjectSection: Identifiable {
    let id: String
    let name: String?
    let services: [ProjectConfiguration]
}

/// Only public process metadata is needed to recognize an existing local server.
struct ProjectListener: Equatable {
    let port: Int
    let directory: String?
    let processName: String
}

enum ProjectLaunchError: LocalizedError {
    case invalid(String)
    case occupied(Int)
    case system(String, Int32)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .occupied(let port): return "Port \(port) is already in use. Stop its service or choose another port."
        case .system(let operation, let code): return "\(operation): \(String(cString: strerror(code)))"
        }
    }
}
