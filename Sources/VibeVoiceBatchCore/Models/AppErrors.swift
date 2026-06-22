import Foundation

public protocol AppRecoverableError: LocalizedError {
    var userFacingTitle: String { get }
    var userFacingExplanation: String { get }
    var technicalDetails: String? { get }
}

public struct AppErrorMessage: Codable, Equatable, Sendable {
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

    public func formatted(includeTechnicalDetails: Bool = false) -> String {
        var parts = [title, explanation]
        if let recoverySuggestion, !recoverySuggestion.isEmpty {
            parts.append(recoverySuggestion)
        }
        if includeTechnicalDetails, let technicalDetails, !technicalDetails.isEmpty {
            parts.append("Details:\n\(technicalDetails)")
        }
        return parts.joined(separator: "\n\n")
    }
}

public enum WorkspacePresetKind: String, Codable, Equatable, Sendable {
    case voice
    case generation

    public var displayName: String {
        switch self {
        case .voice:
            return "voice"
        case .generation:
            return "generation preset"
        }
    }
}

public enum WorkspaceError: Error, Equatable, Sendable {
    case cannotDeleteBuiltInPreset(kind: WorkspacePresetKind, id: String, displayName: String)
    case cannotDeleteCompletedBatch(id: String, title: String)
    case missingBatchItem(batchID: String, itemID: String)
}

extension WorkspaceError: AppRecoverableError {
    public var userFacingTitle: String {
        switch self {
        case .cannotDeleteBuiltInPreset(let kind, _, _):
            return "Built-in \(kind.displayName) cannot be deleted"
        case .cannotDeleteCompletedBatch:
            return "Completed batch cannot be deleted here"
        case .missingBatchItem:
            return "Batch item not found"
        }
    }

    public var userFacingExplanation: String {
        switch self {
        case .cannotDeleteBuiltInPreset(_, _, let displayName):
            return "\(displayName) is included with the app and is protected."
        case .cannotDeleteCompletedBatch(_, let title):
            return "\(title) has completed. Use History or Outputs for generated audio housekeeping."
        case .missingBatchItem:
            return "The selected batch item no longer exists in this workspace."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .cannotDeleteBuiltInPreset:
            return "Duplicate it first if you want a custom copy."
        case .cannotDeleteCompletedBatch:
            return "Only queued, running, failed, or cancelled batches can be removed from this workspace list."
        case .missingBatchItem:
            return "Refresh the workspace, then choose an available batch item."
        }
    }

    public var technicalDetails: String? {
        switch self {
        case .cannotDeleteBuiltInPreset(let kind, let id, _):
            return "Protected \(kind.rawValue) preset id: \(id)"
        case .cannotDeleteCompletedBatch(let id, _):
            return "Completed batch id: \(id)"
        case .missingBatchItem(let batchID, let itemID):
            return "Batch id: \(batchID)\nItem id: \(itemID)"
        }
    }

    public var errorDescription: String? {
        userFacingTitle
    }

    public var failureReason: String? {
        userFacingExplanation
    }
}

extension BackendError: LocalizedError {
    public var errorDescription: String? {
        record.title
    }

    public var failureReason: String? {
        record.explanation
    }

    public var recoverySuggestion: String? {
        record.recoverySuggestion
    }

    public var helpAnchor: String? {
        record.technicalDetails
    }

    public var record: GenerationErrorRecord {
        switch self {
        case .backendUnavailable(let record),
                .operationUnavailable(let record),
                .generationFailed(let record):
            return record
        }
    }
}

public enum AppErrorPresenter {
    public static func message(
        for error: Error,
        fallbackTitle: String? = nil,
        includeTechnicalDetails: Bool = false
    ) -> String {
        if let recoverable = error as? any AppRecoverableError {
            return AppErrorMessage(
                title: recoverable.userFacingTitle,
                explanation: recoverable.userFacingExplanation,
                recoverySuggestion: recoverable.recoverySuggestion,
                technicalDetails: recoverable.technicalDetails
            )
            .formatted(includeTechnicalDetails: includeTechnicalDetails)
        }

        if let backendError = error as? BackendError {
            let record = backendError.record
            return AppErrorMessage(
                title: record.title,
                explanation: record.explanation,
                recoverySuggestion: record.recoverySuggestion,
                technicalDetails: record.technicalDetails
            )
            .formatted(includeTechnicalDetails: includeTechnicalDetails)
        }

        let description = error.localizedDescription
        if let fallbackTitle, !fallbackTitle.isEmpty {
            return [fallbackTitle, description].joined(separator: "\n\n")
        }
        return description
    }
}
