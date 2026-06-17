import Foundation
import VibeVoiceBatchCore

@MainActor
final class BackendSetupStore: ObservableObject {
    @Published private(set) var report: BackendSetupReport?
    @Published private(set) var discoveryReport: BackendDiscoveryReport?
    @Published private(set) var catalogReport: BackendCatalogReport?
    @Published private(set) var isChecking = false
    @Published private(set) var isDiscovering = false
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var isTestingVoice = false
    @Published private(set) var testStatusMessage = "No voice test has been run yet."
    @Published private(set) var testLogText = ""
    @Published private(set) var testProgress: GenerationProgressSnapshot?
    @Published private(set) var testRecord: GenerationRecord?
    @Published private(set) var testError: GenerationErrorRecord?
    @Published private(set) var selectedStage: BackendSetupStage = .welcome
    @Published private(set) var highestUnlockedStage: BackendSetupStage = .welcome

    private let backendManager: BackendManager
    private let voiceTestRunner: BackendVoiceTestRunner

    init(
        backendManager: BackendManager = BackendManager(),
        voiceTestRunner: BackendVoiceTestRunner = BackendVoiceTestRunner()
    ) {
        self.backendManager = backendManager
        self.voiceTestRunner = voiceTestRunner
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

    func runDiscovery(profile: BackendProfile) {
        guard !isDiscovering else { return }
        isDiscovering = true
        Task {
            let report = await backendManager.discoveryReportAsync(for: profile)
            self.discoveryReport = report
            self.isDiscovering = false
        }
    }

    func loadCatalog(profile: BackendProfile) {
        guard !isLoadingCatalog else { return }
        isLoadingCatalog = true
        Task {
            let report = await backendManager.catalogReportAsync(for: profile)
            self.catalogReport = report
            self.isLoadingCatalog = false
        }
    }

    func runVoiceTest(
        profile: BackendProfile,
        modelID: String,
        voiceID: String,
        cfgScale: String,
        ddpmInferenceSteps: Int?,
        completion: @escaping (GenerationRecord?) -> Void = { _ in }
    ) {
        guard !isTestingVoice else { return }
        isTestingVoice = true
        testRecord = nil
        testError = nil
        testProgress = nil
        testLogText = ""
        testStatusMessage = "Checking backend..."

        let request = BackendVoiceTestRequest(
            profile: profile,
            modelID: modelID,
            voiceID: voiceID,
            cfgScale: cfgScale,
            ddpmInferenceSteps: ddpmInferenceSteps
        )

        Task {
            do {
                let record = try await voiceTestRunner.run(request) { event in
                    Task { @MainActor in
                        self.handleTestEvent(event)
                    }
                }
                testRecord = record
                testError = record.error
                testStatusMessage = record.status == .completed ? "Test voice complete" : record.status.displayName
                isTestingVoice = false
                completion(record)
            } catch {
                let errorRecord = generationError(from: error)
                testError = errorRecord
                testStatusMessage = errorRecord.explanation
                isTestingVoice = false
                completion(nil)
            }
        }
    }

    func cancelVoiceTest() {
        guard isTestingVoice else { return }
        testStatusMessage = "Cancelling test..."
        Task {
            await voiceTestRunner.cancelActiveTest()
        }
    }

    func reset() {
        report = nil
        discoveryReport = nil
        catalogReport = nil
        clearTest()
        selectedStage = .welcome
        highestUnlockedStage = .welcome
    }

    func selectStage(_ stage: BackendSetupStage) {
        guard stage.isUnlocked(through: highestUnlockedStage) else { return }
        selectedStage = stage
    }

    func goBack() {
        guard let previous = selectedStage.previous else { return }
        selectedStage = previous
    }

    func continueToNextStage() {
        guard let next = selectedStage.next else { return }
        unlockThrough(next)
        selectedStage = next
    }

    func unlockThrough(_ stage: BackendSetupStage) {
        if highestUnlockedStage.isBefore(stage) {
            highestUnlockedStage = stage
        }
    }

    func restartProgress(at stage: BackendSetupStage) {
        selectedStage = stage
        highestUnlockedStage = stage
    }

    func clearDiscovery() {
        discoveryReport = nil
    }

    func clearCatalog() {
        catalogReport = nil
    }

    func clearTest() {
        isTestingVoice = false
        testStatusMessage = "No voice test has been run yet."
        testLogText = ""
        testProgress = nil
        testRecord = nil
        testError = nil
    }

    private func handleTestEvent(_ event: GenerationEvent) {
        switch event {
        case .sessionStarted(let record):
            testStatusMessage = "Created test session \(record.id)"
        case .status(let status):
            testStatusMessage = status
        case .progress(let progress):
            testProgress = progress
            testStatusMessage = progress.message
        case .log(let text):
            testLogText += text
        case .output(let output):
            testStatusMessage = output.durationSeconds.map {
                String(format: "Generated %.2f seconds of audio", $0)
            } ?? "Generated audio"
        }
    }

    private func generationError(from error: Error) -> GenerationErrorRecord {
        if let backendError = error as? BackendError {
            switch backendError {
            case .backendUnavailable(let record), .operationUnavailable(let record), .generationFailed(let record):
                return record
            }
        }
        return GenerationErrorRecord(
            title: "Voice test failed",
            explanation: error.localizedDescription,
            recoverySuggestion: "Check the backend status, then run the test again."
        )
    }
}

enum BackendSetupStage: String, CaseIterable, Identifiable {
    case welcome
    case backend
    case checks
    case install
    case models
    case test
    case confirm

    var id: String { rawValue }

    var title: String {
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

    var systemImage: String {
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

    var stepNumber: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    var next: BackendSetupStage? {
        guard let index = Self.allCases.firstIndex(of: self),
              index < Self.allCases.count - 1 else {
            return nil
        }
        return Self.allCases[index + 1]
    }

    var previous: BackendSetupStage? {
        guard let index = Self.allCases.firstIndex(of: self),
              index > 0 else {
            return nil
        }
        return Self.allCases[index - 1]
    }

    func isBefore(_ other: BackendSetupStage) -> Bool {
        guard let lhs = Self.allCases.firstIndex(of: self),
              let rhs = Self.allCases.firstIndex(of: other) else {
            return false
        }
        return lhs < rhs
    }

    func isUnlocked(through highestUnlockedStage: BackendSetupStage) -> Bool {
        guard let stageIndex = Self.allCases.firstIndex(of: self),
              let unlockedIndex = Self.allCases.firstIndex(of: highestUnlockedStage) else {
            return false
        }
        return stageIndex <= unlockedIndex
    }
}
