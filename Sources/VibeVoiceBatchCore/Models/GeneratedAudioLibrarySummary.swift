import Foundation

public struct GeneratedAudioLibrarySummary: Equatable, Sendable {
    public var generatedSessionCount: Int
    public var sessionsWithKnownDurationCount: Int
    public var totalAudioDurationSeconds: Double
    public var missingDurationCount: Int

    public init(sessions: [SessionRecord]) {
        let generatedSessions = sessions.filter { $0.metadata.status == .completed }
        let durations = generatedSessions.compactMap(Self.durationSeconds)

        generatedSessionCount = generatedSessions.count
        sessionsWithKnownDurationCount = durations.count
        totalAudioDurationSeconds = durations.reduce(0, +)
        missingDurationCount = max(0, generatedSessions.count - durations.count)
    }

    public var hasGeneratedAudioDuration: Bool {
        totalAudioDurationSeconds > 0
    }

    private static func durationSeconds(for session: SessionRecord) -> Double? {
        if let duration = session.metadata.audioDurationSeconds, duration > 0 {
            return duration
        }
        if let outputURL = session.outputURL,
           let duration = inspectedDurationSeconds(at: outputURL) {
            return duration
        }
        if let outputFile = session.metadata.outputFile {
            let url = URL(fileURLWithPath: outputFile)
            if let duration = inspectedDurationSeconds(at: url) {
                return duration
            }
        }
        return nil
    }

    private static func inspectedDurationSeconds(at url: URL) -> Double? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            guard let duration = try WaveAudioInspector.durationSeconds(for: url), duration > 0 else {
                return nil
            }
            return duration
        } catch {
            return nil
        }
    }
}

public struct GeneratedAudioReference: Equatable, Identifiable, Sendable {
    public var id: String { "\(title)-\(creator)" }
    public var title: String
    public var creator: String
    public var durationSeconds: Double

    public init(title: String, creator: String, durationSeconds: Double) {
        self.title = title
        self.creator = creator
        self.durationSeconds = durationSeconds
    }

    public func equivalentCount(for seconds: Double) -> Double {
        guard durationSeconds > 0 else { return 0 }
        return max(0, seconds / durationSeconds)
    }

    public func wholeEquivalentCount(for seconds: Double) -> Int {
        guard seconds > 0, durationSeconds > 0 else { return 0 }
        return max(1, Int(equivalentCount(for: seconds).rounded()))
    }

    public func equivalentText(for seconds: Double) -> String {
        guard seconds > 0, durationSeconds > 0 else {
            return "no comparison yet"
        }
        return "\(wholeEquivalentCount(for: seconds)) \(title) by \(creator)"
    }

    public static let defaultReferences: [GeneratedAudioReference] = MediaRuntimeCatalog.bundled.references
}
