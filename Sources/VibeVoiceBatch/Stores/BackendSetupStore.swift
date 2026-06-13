import Foundation
import VibeVoiceBatchCore

@MainActor
final class BackendSetupStore: ObservableObject {
    @Published private(set) var report: BackendSetupReport?
    @Published private(set) var isChecking = false
    @Published var selectedStage: BackendSetupStage = .welcome

    private let backendManager: BackendManager

    init(backendManager: BackendManager = BackendManager()) {
        self.backendManager = backendManager
    }

    func runChecks(profile: BackendProfile) {
        guard !isChecking else { return }
        isChecking = true
        Task {
            let report = await backendManager.setupReportAsync(for: profile)
            self.report = report
            self.isChecking = false
        }
    }

    func reset() {
        report = nil
        selectedStage = .welcome
    }
}

enum BackendSetupStage: String, CaseIterable, Identifiable {
    case welcome
    case mode
    case checks
    case install
    case test
    case confirm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .mode: "Mode"
        case .checks: "System Check"
        case .install: "Backend"
        case .test: "Test Voice"
        case .confirm: "Ready"
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: "sparkles"
        case .mode: "slider.horizontal.3"
        case .checks: "checklist"
        case .install: "square.and.arrow.down"
        case .test: "waveform"
        case .confirm: "checkmark.seal"
        }
    }
}
