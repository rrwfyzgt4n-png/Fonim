import Foundation

public enum BackendOperationKind: String, Codable, CaseIterable, Equatable, Sendable {
    case install
    case update
    case prepare
    case stop
    case healthCheck
    case repair
    case reset

    public var displayName: String {
        switch self {
        case .install: "Install Backend"
        case .update: "Update Backend"
        case .prepare: "Prepare Backend"
        case .stop: "Stop Backend"
        case .healthCheck: "Health Check"
        case .repair: "Repair Backend"
        case .reset: "Reset Runtime State"
        }
    }
}

public enum BackendOperationStatus: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
    case skipped

    public var displayName: String {
        switch self {
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .skipped: "Skipped"
        }
    }
}

public struct BackendOperationResult: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var profileID: String
    public var kind: BackendOperationKind
    public var status: BackendOperationStatus
    public var startedAt: Date
    public var completedAt: Date
    public var message: String
    public var recoverySuggestion: String?
    public var technicalDetails: String?

    public init(
        id: String = UUID().uuidString,
        profileID: String,
        kind: BackendOperationKind,
        status: BackendOperationStatus,
        startedAt: Date,
        completedAt: Date = Date(),
        message: String,
        recoverySuggestion: String? = nil,
        technicalDetails: String? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.kind = kind
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.technicalDetails = technicalDetails
    }

    public var elapsedSeconds: TimeInterval {
        completedAt.timeIntervalSince(startedAt)
    }
}

public struct BackendDiskUsageReport: Codable, Equatable, Sendable {
    public var projectRootBytes: UInt64
    public var historyBytes: UInt64
    public var outputsBytes: UInt64
    public var recoveredBytes: UInt64
    public var modelCacheBytes: UInt64

    public init(
        projectRootBytes: UInt64,
        historyBytes: UInt64,
        outputsBytes: UInt64,
        recoveredBytes: UInt64,
        modelCacheBytes: UInt64
    ) {
        self.projectRootBytes = projectRootBytes
        self.historyBytes = historyBytes
        self.outputsBytes = outputsBytes
        self.recoveredBytes = recoveredBytes
        self.modelCacheBytes = modelCacheBytes
    }
}
