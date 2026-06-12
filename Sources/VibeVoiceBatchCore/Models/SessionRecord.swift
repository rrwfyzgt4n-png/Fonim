import Foundation

public struct SessionRecord: Identifiable, Equatable {
    public var id: String { metadata.sessionID }

    public let folderURL: URL
    public var metadata: SessionMetadata
    public var inputText: String
    public var logText: String
    public var metadataJSON: String

    public var inputURL: URL {
        folderURL.appendingPathComponent("input.txt", isDirectory: false)
    }

    public var logURL: URL {
        folderURL.appendingPathComponent("log.txt", isDirectory: false)
    }

    public var metadataURL: URL {
        folderURL.appendingPathComponent("metadata.json", isDirectory: false)
    }

    public var outputURL: URL? {
        let url = folderURL.appendingPathComponent("output.wav", isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
