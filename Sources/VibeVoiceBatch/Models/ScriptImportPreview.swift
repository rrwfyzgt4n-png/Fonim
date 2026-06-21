import Foundation
import VibeVoiceBatchCore

struct ScriptImportPreview: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let title: String
    let chunks: [ScriptChunk]

    var totalWordCount: Int {
        chunks.reduce(0) { $0 + $1.wordCount }
    }
}
