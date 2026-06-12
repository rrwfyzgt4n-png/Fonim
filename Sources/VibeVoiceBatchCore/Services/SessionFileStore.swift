import Foundation

public struct GenerationWorkspace: Equatable {
    public let record: SessionRecord
    public let command: DockerRunCommand
}

public final class SessionFileStore {
    public let projectRoot: URL
    private let fileManager: FileManager

    public init(projectRoot: URL = AppDefaults.projectRoot, fileManager: FileManager = .default) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
    }

    public func ensureBaseDirectories() throws {
        try fileManager.createDirectory(at: projectRoot.historyDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectRoot.outputsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectRoot.recoveredDirectory, withIntermediateDirectories: true)
    }

    public func loadSessions() throws -> [SessionRecord] {
        try ensureBaseDirectories()
        let folders = try fileManager.contentsOfDirectory(
            at: projectRoot.historyDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let records = folders.compactMap { folder -> SessionRecord? in
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return try? loadRecord(folderURL: folder)
        }

        return records.sorted {
            if $0.metadata.createdAt == $1.metadata.createdAt {
                return $0.id > $1.id
            }
            return $0.metadata.createdAt > $1.metadata.createdAt
        }
    }

    public func loadRecord(folderURL: URL) throws -> SessionRecord {
        let metadataURL = folderURL.appendingPathComponent("metadata.json", isDirectory: false)
        let inputURL = folderURL.appendingPathComponent("input.txt", isDirectory: false)
        let logURL = folderURL.appendingPathComponent("log.txt", isDirectory: false)

        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try JSONCodecs.metadataDecoder.decode(SessionMetadata.self, from: metadataData)
        let inputText = (try? String(contentsOf: inputURL, encoding: .utf8)) ?? ""
        let logText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let metadataJSON = String(data: metadataData, encoding: .utf8) ?? ""

        return SessionRecord(
            folderURL: folderURL,
            metadata: metadata,
            inputText: inputText,
            logText: logText,
            metadataJSON: metadataJSON
        )
    }

    public func createDraft(
        text: String,
        voice: String,
        cfgScale: String,
        ddpmInferenceSteps: Int = AppDefaults.defaultDDPMInferenceSteps,
        now: Date = Date()
    ) throws -> SessionRecord {
        try ensureBaseDirectories()
        let sessionID = try makeUniqueSessionID(voice: voice, cfgScale: cfgScale, date: now)
        let folder = projectRoot.historyDirectory.appendingPathComponent(sessionID, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)

        try writeString(text, to: folder.appendingPathComponent("input.txt", isDirectory: false))
        let log = "Draft saved at \(ISO8601DateFormatter().string(from: now)).\n"
        try writeString(log, to: folder.appendingPathComponent("log.txt", isDirectory: false))

        let metadata = SessionMetadata(
            sessionID: sessionID,
            createdAt: now,
            status: .draft,
            voice: voice,
            cfgScale: cfgScale,
            ddpmInferenceSteps: ddpmInferenceSteps,
            dockerCommand: "",
            inputWordCount: TextMetrics.wordCount(in: text),
            inputCharacterCount: text.count
        )
        try writeMetadata(metadata, in: folder)
        return try loadRecord(folderURL: folder)
    }

    public func createGenerationSession(
        text: String,
        voice: String,
        cfgScale: String,
        ddpmInferenceSteps: Int = AppDefaults.defaultDDPMInferenceSteps,
        now: Date = Date()
    ) throws -> GenerationWorkspace {
        try ensureBaseDirectories()
        let sessionID = try makeUniqueSessionID(voice: voice, cfgScale: cfgScale, date: now)
        let folder = projectRoot.historyDirectory.appendingPathComponent(sessionID, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)

        let command = DockerCommandBuilder.make(
            sessionID: sessionID,
            voice: voice,
            cfgScale: cfgScale,
            ddpmInferenceSteps: ddpmInferenceSteps,
            projectRoot: projectRoot
        )

        try writeString(text, to: folder.appendingPathComponent("input.txt", isDirectory: false))
        try writeString("", to: folder.appendingPathComponent("log.txt", isDirectory: false))

        let metadata = SessionMetadata(
            sessionID: sessionID,
            createdAt: now,
            status: .running,
            voice: voice,
            cfgScale: cfgScale,
            ddpmInferenceSteps: ddpmInferenceSteps,
            dockerCommand: command.displayCommand,
            inputWordCount: TextMetrics.wordCount(in: text),
            inputCharacterCount: text.count
        )
        try writeMetadata(metadata, in: folder)
        return GenerationWorkspace(record: try loadRecord(folderURL: folder), command: command)
    }

    public func stageInput(_ text: String) throws {
        try ensureBaseDirectories()
        try writeString(text, to: projectRoot.stagingInputFile)
    }

    public func recoverExistingGeneratedWAV(reason: String) throws -> URL? {
        try ensureBaseDirectories()
        let generated = projectRoot.generatedWAVFile
        guard fileManager.fileExists(atPath: generated.path) else { return nil }

        let recovered = try uniqueRecoveredURL(
            baseName: "\(SessionFormatters.sessionIDDateFormatter.string(from: Date()))_\(reason)_input_generated",
            extension: "wav"
        )
        try fileManager.moveItem(at: generated, to: recovered)
        return recovered
    }

    public func moveGeneratedWAVToSession(folderURL: URL) throws -> URL? {
        let generated = projectRoot.generatedWAVFile
        guard fileManager.fileExists(atPath: generated.path) else { return nil }

        let output = folderURL.appendingPathComponent("output.wav", isDirectory: false)
        guard !fileManager.fileExists(atPath: output.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try fileManager.moveItem(at: generated, to: output)
        return output
    }

    public func archiveDeletedSession(_ record: SessionRecord) throws -> URL {
        try ensureBaseDirectories()
        let deletedRoot = projectRoot.recoveredDirectory.appendingPathComponent("deleted_sessions", isDirectory: true)
        try fileManager.createDirectory(at: deletedRoot, withIntermediateDirectories: true)

        let baseName = "\(SessionFormatters.sessionIDDateFormatter.string(from: Date()))_\(record.id)"
        var destination = deletedRoot.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = deletedRoot.appendingPathComponent("\(baseName)_\(suffix)", isDirectory: true)
            suffix += 1
        }

        try fileManager.moveItem(at: record.folderURL, to: destination)
        return destination
    }

    public func appendLog(_ text: String, to folderURL: URL) throws {
        let logURL = folderURL.appendingPathComponent("log.txt", isDirectory: false)
        let data = Data(text.utf8)
        if fileManager.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: logURL, options: .atomic)
        }
    }

    public func replaceLog(_ text: String, in folderURL: URL) throws {
        try writeString(text, to: folderURL.appendingPathComponent("log.txt", isDirectory: false))
    }

    public func writeMetadata(_ metadata: SessionMetadata, in folderURL: URL) throws {
        let data = try JSONCodecs.metadataEncoder.encode(metadata)
        try data.write(to: folderURL.appendingPathComponent("metadata.json", isDirectory: false), options: .atomic)
    }

    public func makeUniqueSessionID(voice: String, cfgScale: String, date: Date) throws -> String {
        try ensureBaseDirectories()
        let voiceSlug = slug(voice, fallback: "voice")
        let cfgSlug = slug(cfgScale, fallback: "cfg")
        let base = "\(SessionFormatters.sessionIDDateFormatter.string(from: date))_\(voiceSlug)_cfg\(cfgSlug)"
        var candidate = base
        var suffix = 2

        while fileManager.fileExists(atPath: projectRoot.historyDirectory.appendingPathComponent(candidate, isDirectory: true).path) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func uniqueRecoveredURL(baseName: String, extension pathExtension: String) throws -> URL {
        var candidate = projectRoot.recoveredDirectory.appendingPathComponent("\(baseName).\(pathExtension)", isDirectory: false)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = projectRoot.recoveredDirectory.appendingPathComponent("\(baseName)_\(suffix).\(pathExtension)", isDirectory: false)
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

    private func writeString(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
