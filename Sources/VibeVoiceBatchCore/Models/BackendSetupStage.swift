import Foundation

public enum BackendSetupStage: String, CaseIterable, Identifiable, Sendable {
    case welcome
    case backend
    case checks
    case install
    case models
    case test
    case confirm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .welcome: "Welcome"
        case .backend: "Choose Backend"
        case .checks: "System Check"
        case .install: "Install / Connect"
        case .models: "Models & Voices"
        case .test: "Test Voice"
        case .confirm: "Ready"
        }
    }

    public var systemImage: String {
        switch self {
        case .welcome: "sparkles"
        case .backend: "server.rack"
        case .checks: "checklist"
        case .install: "square.and.arrow.down"
        case .models: "person.wave.2"
        case .test: "waveform"
        case .confirm: "checkmark.seal"
        }
    }

    public var stepNumber: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    public var next: BackendSetupStage? {
        guard let index = Self.allCases.firstIndex(of: self),
              index < Self.allCases.count - 1 else {
            return nil
        }
        return Self.allCases[index + 1]
    }

    public var previous: BackendSetupStage? {
        guard let index = Self.allCases.firstIndex(of: self),
              index > 0 else {
            return nil
        }
        return Self.allCases[index - 1]
    }

    public func isBefore(_ other: BackendSetupStage) -> Bool {
        guard let lhs = Self.allCases.firstIndex(of: self),
              let rhs = Self.allCases.firstIndex(of: other) else {
            return false
        }
        return lhs < rhs
    }

    public func isUnlocked(through highestUnlockedStage: BackendSetupStage) -> Bool {
        guard let stageIndex = Self.allCases.firstIndex(of: self),
              let unlockedIndex = Self.allCases.firstIndex(of: highestUnlockedStage) else {
            return false
        }
        return stageIndex <= unlockedIndex
    }
}

public struct BackendSetupStageLockingPolicy: Equatable, Sendable {
    public let selectedStage: BackendSetupStage
    public let highestUnlockedStage: BackendSetupStage

    public init(selectedStage: BackendSetupStage, highestUnlockedStage: BackendSetupStage) {
        self.selectedStage = selectedStage
        self.highestUnlockedStage = highestUnlockedStage
    }

    public func isUnlocked(_ stage: BackendSetupStage) -> Bool {
        stage.isUnlocked(through: highestUnlockedStage)
    }

    public func isCompleted(_ stage: BackendSetupStage) -> Bool {
        stage.isBefore(selectedStage) || (stage.isBefore(highestUnlockedStage) && stage != selectedStage)
    }

    public var lockedStages: [BackendSetupStage] {
        BackendSetupStage.allCases.filter { !isUnlocked($0) }
    }
}

public struct BackendSetupCheckListPresentation: Equatable, Sendable {
    public enum ContentState: Equatable, Sendable {
        case empty
        case checking
        case results(count: Int)
    }

    public let state: ContentState
    public let minimumHeight: Double

    public init(report: BackendSetupReport?, isChecking: Bool, minimumHeight: Double = 300) {
        self.minimumHeight = minimumHeight
        if isChecking {
            state = .checking
        } else if let report {
            state = .results(count: report.checks.count)
        } else {
            state = .empty
        }
    }

    public var usesScrollableResults: Bool {
        if case .results = state {
            return true
        }
        return false
    }
}
