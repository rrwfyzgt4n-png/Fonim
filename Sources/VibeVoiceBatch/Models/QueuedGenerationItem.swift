import Foundation
import VibeVoiceBatchCore

enum QueuedGenerationStatus: String, Equatable {
    case queued
    case paused
    case running
    case completed
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .paused: "Paused"
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            true
        case .queued, .paused, .running:
            false
        }
    }
}

struct QueuedGenerationItem: Identifiable, Equatable {
    let id: String
    let createdAt: Date
    let sourceText: String
    let backendID: String
    let modelID: String
    let voice: String
    let cfgScale: String
    let ddpmInferenceSteps: Int
    var scriptID: String?
    var batchID: String?
    var batchItemID: String?
    var status: QueuedGenerationStatus
    var sessionID: String?
    var startedAt: Date?
    var completedAt: Date?
    var statusMessage: String
    var progressFraction: Double?
    var currentStep: Int?
    var totalSteps: Int?
    var elapsedSeconds: TimeInterval
    var estimatedRemainingSeconds: TimeInterval?
    var errorMessage: String?

    init(
        job: GenerationJob,
        scriptID: String? = nil,
        batchID: String? = nil,
        batchItemID: String? = nil
    ) {
        id = job.id
        createdAt = job.createdAt
        sourceText = job.inputText
        backendID = job.backendID
        modelID = job.modelID
        voice = job.voiceID
        cfgScale = job.settings.cfgScale
        ddpmInferenceSteps = job.settings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps
        self.scriptID = scriptID
        self.batchID = batchID
        self.batchItemID = batchItemID
        status = .queued
        sessionID = nil
        startedAt = nil
        completedAt = nil
        statusMessage = "Waiting"
        progressFraction = nil
        currentStep = nil
        totalSteps = nil
        elapsedSeconds = 0
        estimatedRemainingSeconds = nil
        errorMessage = nil
    }
}
