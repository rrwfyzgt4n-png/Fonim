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
                session.metadata.audioDurationSeconds != nil ||
                session.outputURL != nil
        }
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
        GeneratedAudioReference(title: "The Great Train Robbery", creator: "Edwin S. Porter", durationSeconds: 720),
        GeneratedAudioReference(title: "The Wizard of Oz", creator: "MGM", durationSeconds: 6_120),
        GeneratedAudioReference(title: "Citizen Kane", creator: "Orson Welles", durationSeconds: 7_140),
        GeneratedAudioReference(title: "White Christmas", creator: "Bing Crosby", durationSeconds: 182),
        GeneratedAudioReference(title: "Singin' in the Rain", creator: "MGM", durationSeconds: 6_180),
        GeneratedAudioReference(title: "Johnny B. Goode", creator: "Chuck Berry", durationSeconds: 161),
        GeneratedAudioReference(title: "Psycho", creator: "Alfred Hitchcock", durationSeconds: 6_540),
        GeneratedAudioReference(title: "Hey Jude", creator: "The Beatles", durationSeconds: 431),
        GeneratedAudioReference(title: "2001: A Space Odyssey", creator: "Stanley Kubrick", durationSeconds: 8_940),
        GeneratedAudioReference(title: "Stairway to Heaven", creator: "Led Zeppelin", durationSeconds: 482),
        GeneratedAudioReference(title: "The Godfather", creator: "Francis Ford Coppola", durationSeconds: 10_500),
        GeneratedAudioReference(title: "Bohemian Rhapsody", creator: "Queen", durationSeconds: 355),
        GeneratedAudioReference(title: "Star Wars", creator: "George Lucas", durationSeconds: 7_260),
        GeneratedAudioReference(title: "Thriller", creator: "Michael Jackson", durationSeconds: 822),
        GeneratedAudioReference(title: "Never Gonna Give You Up", creator: "Rick Astley", durationSeconds: 213),
        GeneratedAudioReference(title: "Titanic", creator: "James Cameron", durationSeconds: 11_700),
        GeneratedAudioReference(title: "The Lord of the Rings: The Return of the King", creator: "Peter Jackson", durationSeconds: 12_060),
        GeneratedAudioReference(title: "Charlie Bit My Finger", creator: "HDCYT", durationSeconds: 56),
        GeneratedAudioReference(title: "Gangnam Style", creator: "PSY", durationSeconds: 253),
        GeneratedAudioReference(title: "Hamilton", creator: "Lin-Manuel Miranda", durationSeconds: 9_900),
        GeneratedAudioReference(title: "Baby Shark Dance", creator: "Pinkfong", durationSeconds: 136),
        GeneratedAudioReference(title: "Despacito", creator: "Luis Fonsi ft. Daddy Yankee", durationSeconds: 227)
    ]

    private static func formattedCount(_ count: Double) -> String {
        if count >= 2 {
            return String(format: "%.0f", count)
        }
        let value = String(format: "%.1f", count)
        return value.hasSuffix(".0") ? String(value.dropLast(2)) : value
    }
}
