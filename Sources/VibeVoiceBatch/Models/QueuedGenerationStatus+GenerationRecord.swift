import VibeVoiceBatchCore

extension QueuedGenerationStatus {
    init(recordStatus: GenerationRecordStatus) {
        switch recordStatus {
        case .queued:
            self = .queued
        case .running:
            self = .running
        case .completed:
            self = .completed
        case .failed:
            self = .failed
        case .cancelled:
            self = .cancelled
        }
    }
}
