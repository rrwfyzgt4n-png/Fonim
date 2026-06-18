import Foundation

internal protocol WorkspaceUpdatedItem {
    var id: String { get }
    var updatedAt: Date { get }
}

extension NarrationProject: WorkspaceUpdatedItem {}
extension NarrationScript: WorkspaceUpdatedItem {}
extension NarrationBatch: WorkspaceUpdatedItem {}

internal enum WorkspaceSorting {
    static func newestFirst<T: WorkspaceUpdatedItem>(_ items: [T]) -> [T] {
        items.sorted(by: newestFirst)
    }

    static func newestFirst<T: WorkspaceUpdatedItem>(_ lhs: T, _ rhs: T) -> Bool {
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.id > rhs.id
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}

internal enum WorkspaceStorageDirectory {
    case projects
    case scripts
    case batches
    case voicePresets
    case generationPresets
}

internal struct WorkspaceStoragePaths {
    private let projectRoot: URL
    private let fileManager: FileManager

    init(projectRoot: URL, fileManager: FileManager) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
    }

    func directory(_ directory: WorkspaceStorageDirectory) -> URL {
        switch directory {
        case .projects:
            return projectRoot.projectsDirectory
        case .scripts:
            return projectRoot.scriptsDirectory
        case .batches:
            return projectRoot.batchesDirectory
        case .voicePresets:
            return projectRoot.voicePresetsDirectory
        case .generationPresets:
            return projectRoot.generationPresetsDirectory
        }
    }

    func jsonURL(id: String, in directory: WorkspaceStorageDirectory) -> URL {
        self.directory(directory).appendingPathComponent("\(id).json", isDirectory: false)
    }

    func makeUniqueID(
        prefix: String,
        title: String,
        in directory: WorkspaceStorageDirectory,
        date: Date
    ) -> String {
        let base = "\(prefix)_\(SessionFormatters.sessionIDDateFormatter.string(from: date))_\(slug(title, fallback: "untitled"))"
        var candidate = base
        var suffix = 2
        while fileManager.fileExists(atPath: jsonURL(id: candidate, in: directory).path) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func slug(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return sanitized.isEmpty ? fallback : sanitized
    }
}
