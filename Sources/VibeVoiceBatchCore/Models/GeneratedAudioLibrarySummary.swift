import Foundation

public struct GeneratedAudioLibrarySummary: Equatable, Sendable {
    public var generatedSessionCount: Int
    public var sessionsWithKnownDurationCount: Int
    public var totalAudioDurationSeconds: Double
    public var missingDurationCount: Int

    public init(sessions: [SessionRecord]) {
        let generatedSessions = sessions.filter { session in
            session.metadata.status == .completed ||
                session.metadata.outputFile != nil ||
                session.metadata.audioDurationSeconds != nil
        }
        let durations = generatedSessions.compactMap(\.metadata.audioDurationSeconds)

        generatedSessionCount = generatedSessions.count
        sessionsWithKnownDurationCount = durations.count
        totalAudioDurationSeconds = durations.reduce(0, +)
        missingDurationCount = max(0, generatedSessions.count - durations.count)
    }

    public var hasGeneratedAudioDuration: Bool {
        totalAudioDurationSeconds > 0
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

    public func equivalentText(for seconds: Double) -> String {
        guard seconds > 0, durationSeconds > 0 else {
            return "no comparison yet"
        }
        let count = equivalentCount(for: seconds)
        let countText = Self.formattedCount(count)
        let playText = countText == "1" ? "play" : "plays"
        return "\(countText) \(playText) of \(title) by \(creator)"
    }

    public static let defaultReferences: [GeneratedAudioReference] = [
        GeneratedAudioReference(title: "Hey Jude", creator: "The Beatles", durationSeconds: 431),
        GeneratedAudioReference(title: "Bohemian Rhapsody", creator: "Queen", durationSeconds: 355),
        GeneratedAudioReference(title: "Clair de Lune", creator: "Claude Debussy", durationSeconds: 300),
        GeneratedAudioReference(title: "Bolero", creator: "Maurice Ravel", durationSeconds: 900),
        GeneratedAudioReference(title: "Rhapsody in Blue", creator: "George Gershwin", durationSeconds: 1_020),
        GeneratedAudioReference(title: "A Love Supreme", creator: "John Coltrane", durationSeconds: 1_976),
        GeneratedAudioReference(title: "The Rite of Spring", creator: "Igor Stravinsky", durationSeconds: 2_100),
        GeneratedAudioReference(title: "Abbey Road", creator: "The Beatles", durationSeconds: 2_823)
    ]

    private static func formattedCount(_ count: Double) -> String {
        if count >= 2 {
            return String(format: "%.0f", count)
        }
        let value = String(format: "%.1f", count)
        return value.hasSuffix(".0") ? String(value.dropLast(2)) : value
    }
}
