import Foundation

public struct MediaRuntimeCatalog: Equatable, Sendable {
    public var references: [GeneratedAudioReference]
    public var sourceDescription: String

    public init(references: [GeneratedAudioReference], sourceDescription: String = "fallback") {
        self.references = references
        self.sourceDescription = sourceDescription
    }

    public func readableReferences(for seconds: Double, maximumEquivalentCount: Int = 200) -> [GeneratedAudioReference] {
        let availableReferences = references.isEmpty ? Self.fallbackReferences : references
        guard seconds > 0 else { return availableReferences }

        let closeWholeNumberMatches = availableReferences.filter { reference in
            let exactCount = reference.equivalentCount(for: seconds)
            let roundedCount = reference.wholeEquivalentCount(for: seconds)
            return roundedCount >= 1 &&
                roundedCount <= maximumEquivalentCount &&
                exactCount >= 0.75 &&
                abs(exactCount - Double(roundedCount)) <= 0.35
        }

        if !closeWholeNumberMatches.isEmpty {
            return closeWholeNumberMatches
        }

        return availableReferences.filter { reference in
            let roundedCount = reference.wholeEquivalentCount(for: seconds)
            return roundedCount >= 1 && roundedCount <= maximumEquivalentCount
        }
    }

    public func randomReadableReference(for seconds: Double, excluding current: GeneratedAudioReference? = nil) -> GeneratedAudioReference {
        let matches = readableReferences(for: seconds)
        let choices = matches.filter { $0 != current }
        return choices.randomElement() ?? matches.randomElement() ?? Self.fallbackReferences[0]
    }

    public static let bundled = loadBundledCatalog()

    public static func loadBundledCatalog(fileManager: FileManager = .default) -> MediaRuntimeCatalog {
        for url in bundledResourceCandidates(fileManager: fileManager) {
            guard fileManager.fileExists(atPath: url.path),
                  let csvText = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            let catalog = parse(csvText: csvText, sourceDescription: url.lastPathComponent)
            if !catalog.references.isEmpty {
                return catalog
            }
        }
        return MediaRuntimeCatalog(references: fallbackReferences, sourceDescription: "fallback")
    }

    public static func parse(csvText: String, sourceDescription: String = "csv") -> MediaRuntimeCatalog {
        let rows = csvText
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        let references = rows
            .dropFirst(rows.first?.lowercased().contains("runtime") == true ? 1 : 0)
            .compactMap { row -> GeneratedAudioReference? in
                let fields = parseCSVRow(row)
                guard fields.count >= 3 else { return nil }
                let title = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let artist = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let runtime = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty,
                      !artist.isEmpty,
                      let duration = durationSeconds(from: runtime),
                      duration > 0 else {
                    return nil
                }
                return GeneratedAudioReference(title: title, creator: artist, durationSeconds: duration)
            }

        return MediaRuntimeCatalog(references: references, sourceDescription: sourceDescription)
    }

    public static func durationSeconds(from runtime: String) -> Double? {
        let rawParts = runtime.split(separator: ":")
        let parts = rawParts
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(Double.init)
        guard parts.count == rawParts.count else { return nil }

        switch parts.count {
        case 2:
            return parts[0] * 60 + parts[1]
        case 3:
            return parts[0] * 3_600 + parts[1] * 60 + parts[2]
        default:
            return nil
        }
    }

    private static func bundledResourceCandidates(fileManager: FileManager) -> [URL] {
        var candidates: [URL] = []

        if let url = Bundle.main.url(forResource: "media_runtimes", withExtension: "csv") {
            candidates.append(url)
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("media_runtimes.csv", isDirectory: false))
        }

        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        candidates.append(currentDirectory.appendingPathComponent("Resources/media_runtimes.csv", isDirectory: false))

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var isInsideQuotes = false
        var index = row.startIndex

        while index < row.endIndex {
            let character = row[index]
            if character == "\"" {
                let nextIndex = row.index(after: index)
                if isInsideQuotes, nextIndex < row.endIndex, row[nextIndex] == "\"" {
                    current.append("\"")
                    index = row.index(after: nextIndex)
                    continue
                }
                isInsideQuotes.toggle()
            } else if character == ",", !isInsideQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = row.index(after: index)
        }

        fields.append(current)
        return fields
    }

    private static let fallbackReferences: [GeneratedAudioReference] = [
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
}
