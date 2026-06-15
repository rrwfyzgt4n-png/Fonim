import Foundation

public enum GenerationRecordStatus: String, Codable, CaseIterable, Equatable {
    case queued
    case running
    case completed
    case failed
    case cancelled

    public var displayName: String {
        switch self {
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

public struct GenerationErrorRecord: Codable, Equatable {
    public var title: String
    public var explanation: String
    public var recoverySuggestion: String?
    public var technicalDetails: String?

    public init(
        title: String,
        explanation: String,
        recoverySuggestion: String? = nil,
        technicalDetails: String? = nil
    ) {
        self.title = title
        self.explanation = explanation
        self.recoverySuggestion = recoverySuggestion
        self.technicalDetails = technicalDetails
    }
}

public struct GenerationRecord: Codable, Equatable, Identifiable {
    public let id: String
    public var jobID: String
    public var inputText: String
    public var createdAt: Date
    public var completedAt: Date?
    public var status: GenerationRecordStatus
    public var backendID: String
    public var backendDisplayName: String
    public var engineType: EngineType
    public var modelID: String
    public var voiceID: String
    public var settings: GenerationSettings
    public var exportPath: String?
    public var durationSeconds: Double?
    public var logs: String
    public var error: GenerationErrorRecord?

    public init(
        id: String = UUID().uuidString,
        jobID: String,
        inputText: String,
        createdAt: Date,
        completedAt: Date? = nil,
        status: GenerationRecordStatus,
        backendID: String,
        backendDisplayName: String,
        engineType: EngineType,
        modelID: String,
        voiceID: String,
        settings: GenerationSettings,
        exportPath: String? = nil,
        durationSeconds: Double? = nil,
        logs: String = "",
        error: GenerationErrorRecord? = nil
    ) {
        self.id = id
        self.jobID = jobID
        self.inputText = inputText
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.status = status
        self.backendID = backendID
        self.backendDisplayName = backendDisplayName
        self.engineType = engineType
        self.modelID = modelID
        self.voiceID = voiceID
        self.settings = settings
        self.exportPath = exportPath
        self.durationSeconds = durationSeconds
        self.logs = logs
        self.error = error
    }
}
