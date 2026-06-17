import Foundation

public struct OutputHousekeepingSummary: Equatable, Sendable {
    public let totalOutputCount: Int
    public let selectedCount: Int
    public let totalAudioDurationSeconds: Double?
    public let totalFileSizeBytes: UInt64
    public let filedCount: Int
    public let unfiledCount: Int
    public let voices: [String]
    public let backends: [String]
    public let projectTitles: [String]
    public let oldestCreatedAt: Date?
    public let newestCreatedAt: Date?
    public let outputFileNames: [String]

    public init(
        selectedRecords: [SessionRecord],
        totalOutputCount: Int,
        projectTitlesBySessionID: [String: [String]] = [:],
        fileSizeBySessionID: [String: UInt64] = [:],
        backendName: (SessionRecord) -> String = { record in
            record.metadata.dockerImage.isEmpty ? "Local service" : record.metadata.dockerImage
        }
    ) {
        self.totalOutputCount = totalOutputCount
        selectedCount = selectedRecords.count
        let durations = selectedRecords.compactMap(\.metadata.audioDurationSeconds)
        totalAudioDurationSeconds = durations.isEmpty ? nil : durations.reduce(0, +)
        totalFileSizeBytes = selectedRecords.reduce(0) { total, record in
            total + (fileSizeBySessionID[record.id] ?? 0)
        }

        let filedIDs = selectedRecords.filter { !(projectTitlesBySessionID[$0.id] ?? []).isEmpty }
        filedCount = filedIDs.count
        unfiledCount = max(0, selectedRecords.count - filedIDs.count)
        voices = Array(Set(selectedRecords.map(\.metadata.voice))).sorted()
        backends = Array(Set(selectedRecords.map(backendName))).sorted()
        projectTitles = Array(Set(projectTitlesBySessionID.values.flatMap { $0 })).sorted()
        oldestCreatedAt = selectedRecords.map(\.metadata.createdAt).min()
        newestCreatedAt = selectedRecords.map(\.metadata.createdAt).max()
        outputFileNames = selectedRecords.compactMap { $0.outputURL?.lastPathComponent }.sorted()
    }

    public var archiveEligibility: String {
        selectedCount == 0 ? "No selection" : "Ready"
    }

    public var filingSummary: String {
        guard selectedCount > 0 else { return "No selection" }
        guard !projectTitles.isEmpty else { return "Unfiled" }
        return projectTitles.joined(separator: ", ")
    }
}
