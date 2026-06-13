import Foundation

public enum BackendSetupMode: String, Codable, CaseIterable, Equatable, Sendable {
    case simple
    case advanced
    case external

    public var displayName: String {
        switch self {
        case .simple:
            return "Simple"
        case .advanced:
            return "Advanced"
        case .external:
            return "External"
        }
    }
}

public enum BackendSetupCheckState: String, Codable, Equatable, Sendable {
    case waiting
    case checking
    case passed
    case warning
    case failed

    public var isBlocking: Bool {
        self == .failed
    }
}

public struct BackendSetupCheck: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var state: BackendSetupCheckState
    public var message: String
    public var recoverySuggestion: String?
    public var technicalDetails: String?

    public init(
        id: String,
        title: String,
        state: BackendSetupCheckState,
        message: String,
        recoverySuggestion: String? = nil,
        technicalDetails: String? = nil
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.technicalDetails = technicalDetails
    }
}

public struct BackendSetupReport: Codable, Equatable, Sendable {
    public var profileID: String
    public var generatedAt: Date
    public var checks: [BackendSetupCheck]

    public init(profileID: String, generatedAt: Date = Date(), checks: [BackendSetupCheck]) {
        self.profileID = profileID
        self.generatedAt = generatedAt
        self.checks = checks
    }

    public var isReady: Bool {
        !checks.contains { $0.state.isBlocking }
    }

    public var blockingChecks: [BackendSetupCheck] {
        checks.filter { $0.state.isBlocking }
    }
}
