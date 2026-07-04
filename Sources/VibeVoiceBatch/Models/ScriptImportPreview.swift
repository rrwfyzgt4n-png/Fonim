import Foundation
import VibeVoiceBatchCore

struct ScriptImportPreview: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let title: String
    let chunks: [ScriptChunk]
    let usesTimestampMarkers: Bool

    var totalWordCount: Int {
        chunks.reduce(0) { $0 + $1.wordCount }
    }

    var materialDescription: String {
        usesTimestampMarkers ? "Timestamped narration only" : "Natural text blocks"
    }
}
