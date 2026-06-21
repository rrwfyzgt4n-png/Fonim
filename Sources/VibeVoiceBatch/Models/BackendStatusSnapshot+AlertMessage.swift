import VibeVoiceBatchCore

extension BackendStatusSnapshot {
    var alertMessageWithDetails: String {
        [
            alertMessage,
            technicalDetails.map { "Details:\n\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }
}
