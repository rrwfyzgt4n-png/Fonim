import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct BackendSetupAssistantView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var setupStore = BackendSetupStore()
    @StateObject private var operationsStore = BackendOperationsStore()

    private var selectedBackend: BackendProfile {
        settingsStore.selectedBackendProfile
    }

    private var canContinueFromCurrentStage: Bool {
        switch setupStore.selectedStage {
        case .welcome, .backend:
            return true
        case .checks:
            return setupStore.report != nil && !setupStore.isChecking
        case .install:
            return !operationsStore.isRunning
        case .models:
            return !setupStore.isLoadingCatalog &&
                !selectedSetupModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !selectedSetupVoiceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .test:
            return !setupStore.isTestingVoice
        case .confirm:
            return setupStore.report?.isReady == true
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            AssistantStepRail(
                selectedStage: setupStore.selectedStage,
                highestUnlockedStage: setupStore.highestUnlockedStage,
                selectStage: setupStore.selectStage
            )
            .frame(width: 210)

            Divider()

            VStack(spacing: 0) {
                AssistantStatusHeader(
                    profile: selectedBackend,
                    status: appStore.backendStatus,
                    report: setupStore.report
                )

                Divider()

                assistantContent

                Divider()

                AssistantFooter(
                    canGoBack: setupStore.selectedStage != .welcome,
                    canContinue: canContinueFromCurrentStage,
                    isFinalStage: setupStore.selectedStage == .confirm,
                    selectedStage: setupStore.selectedStage,
                    back: goBack,
                    continueAction: continueAssistant
                )
            }
        }
        .frame(width: 960, height: 680)
        .onAppear {
            if setupStore.report == nil {
                setupStore.runChecks(profile: selectedBackend)
            }
        }
        .onChange(of: settingsStore.settings.defaultBackendID) { _ in
            setupStore.runChecks(profile: selectedBackend)
        }
    }

    @ViewBuilder
    private var assistantContent: some View {
        if setupStore.selectedStage == .checks {
            activePane
                .padding(28)
                .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                activePane
                    .padding(28)
                    .frame(maxWidth: 760, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private var activePane: some View {
        switch setupStore.selectedStage {
        case .welcome:
            WelcomeSetupPane()
        case .backend:
            ChooseBackendSetupPane(
                selectedBackendID: backendBinding,
                mode: modeBinding,
                statusText: appStore.backendStatus.state.displayName
            )
        case .checks:
            ChecksSetupPane(
                profile: selectedBackend,
                report: setupStore.report,
                isChecking: setupStore.isChecking,
                runChecks: { setupStore.runChecks(profile: selectedBackend) }
            )
        case .install:
            BackendInstallSetupPane(
                profile: selectedBackend,
                report: setupStore.report,
                discoveryReport: setupStore.discoveryReport,
                operationResult: operationsStore.latestResult,
                isChecking: setupStore.isChecking,
                isDiscovering: setupStore.isDiscovering,
                isOperationRunning: operationsStore.isRunning,
                activeOperation: operationsStore.activeOperation,
                connection: selectedConnectionBinding,
                discover: { setupStore.runDiscovery(profile: selectedBackend) },
                applyCandidate: applyDiscoveryCandidate,
                install: { runBackendOperation(.install) },
                repair: { runBackendOperation(.repair) },
                prepare: { runBackendOperation(.prepare) },
                runChecks: { setupStore.runChecks(profile: selectedBackend) }
            )
        case .models:
            ModelsVoicesSetupPane(
                profile: selectedBackend,
                catalogReport: setupStore.catalogReport,
                isLoadingCatalog: setupStore.isLoadingCatalog,
                modelOptions: setupModelOptions,
                voiceOptions: setupVoiceOptions,
                defaultModelID: settingsStore.settings.defaultModelID,
                defaultVoiceID: settingsStore.settings.preferredVoiceID(for: selectedBackend),
                selectedModelID: selectedModelBinding,
                selectedVoiceID: selectedVoiceBinding,
                loadCatalog: { setupStore.loadCatalog(profile: selectedBackend) },
                useAsDefault: useAssistantSelectionsAsDefaults
            )
        case .test:
            TestVoiceSetupPane(
                profile: selectedBackend,
                modelID: selectedSetupModelID,
                voiceID: selectedSetupVoiceID,
                backendStatus: appStore.backendStatus,
                isTesting: setupStore.isTestingVoice,
                statusMessage: setupStore.testStatusMessage,
                progress: setupStore.testProgress,
                logText: setupStore.testLogText,
                record: setupStore.testRecord,
                error: setupStore.testError,
                canTest: !appStore.isGenerating,
                runTest: prepareTestVoice,
                cancelTest: setupStore.cancelVoiceTest,
                playResult: playTestResult,
                revealResult: revealTestResult,
                openResult: openTestResult
            )
        case .confirm:
            ConfirmSetupPane(
                isReady: setupStore.report?.isReady == true,
                complete: completeSetup,
                rerunChecks: {
                    setupStore.selectStage(.checks)
                    setupStore.runChecks(profile: selectedBackend)
                }
            )
        }
    }

    private var modeBinding: Binding<BackendSetupMode> {
        Binding(
            get: { settingsStore.settings.setupMode },
            set: { settingsStore.selectSetupMode($0) }
        )
    }

    private func goBack() {
        setupStore.goBack()
    }

    private func continueAssistant() {
        if setupStore.selectedStage == .confirm {
            completeSetup()
            return
        }
        setupStore.continueToNextStage()
    }

    private var backendBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.defaultBackendID },
            set: { backendID in
                appStore.selectBackend(backendID)
                setupStore.clearDiscovery()
                setupStore.clearCatalog()
                setupStore.clearTest()
                setupStore.resetModelVoiceSelection()
                setupStore.restartProgress(at: .backend)
                setupStore.runChecks(profile: settingsStore.selectedBackendProfile)
            }
        )
    }

    private var selectedConnectionBinding: Binding<BackendConnectionSettings> {
        Binding(
            get: { settingsStore.backendConnection(for: selectedBackend.id) },
            set: { connection in
                settingsStore.update { settings in
                    settings.backendConnections[selectedBackend.id] = connection
                }
            }
        )
    }

    private var selectedSetupModelID: String {
        if setupModelOptions.contains(where: { $0.id == setupStore.selectedModelID }) {
            return setupStore.selectedModelID
        }
        if setupModelOptions.contains(where: { $0.id == settingsStore.settings.defaultModelID }) {
            return settingsStore.settings.defaultModelID
        }
        return setupModelOptions.first?.id ?? selectedBackend.requiredModels.first?.id ?? settingsStore.settings.defaultModelID
    }

    private var selectedSetupVoiceID: String {
        if setupVoiceOptions.contains(where: { $0.id == setupStore.selectedVoiceID }) {
            return setupStore.selectedVoiceID
        }
        let preferredVoice = settingsStore.settings.preferredVoiceID(for: selectedBackend)
        if setupVoiceOptions.contains(where: { $0.id == preferredVoice }) {
            return preferredVoice
        }
        return setupVoiceOptions.first?.id ?? preferredVoice
    }

    private var setupModelOptions: [BackendCatalogModel] {
        if let catalog = setupStore.catalogReport, !catalog.models.isEmpty {
            return catalog.models
        }
        return settingsStore.modelOptions(for: selectedBackend)
    }

    private var setupVoiceOptions: [BackendCatalogVoice] {
        if let catalog = setupStore.catalogReport, !catalog.voices.isEmpty {
            return catalog.voices
        }
        return settingsStore.voiceOptions(for: selectedBackend)
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { selectedSetupModelID },
            set: { setupStore.selectModel($0) }
        )
    }

    private var selectedVoiceBinding: Binding<String> {
        Binding(
            get: { selectedSetupVoiceID },
            set: { setupStore.selectVoice($0) }
        )
    }

    private func prepareTestVoice() {
        setupStore.runVoiceTest(
            profile: selectedBackend,
            modelID: selectedSetupModelID,
            voiceID: selectedSetupVoiceID,
            cfgScale: settingsStore.settings.defaultCFGScale,
            ddpmInferenceSteps: settingsStore.settings.defaultDDPMInferenceSteps
        ) { record in
            appStore.refreshHistory()
            appStore.statusMessage = record?.status == .completed ? "Test voice complete" : "Test voice finished"
            appStore.refreshBackendStatus()
        }
    }

    private func playTestResult() {
        guard let record = setupStore.testRecord else { return }
        appStore.playGenerationRecord(record)
    }

    private func revealTestResult() {
        guard let record = setupStore.testRecord else { return }
        appStore.revealGenerationRecordOutput(record)
    }

    private func openTestResult() {
        guard let record = setupStore.testRecord else { return }
        appStore.revealGenerationRecord(record, status: "Opened test voice in history")
    }

    private func completeSetup() {
        settingsStore.markSetupAssistantCompleted()
        dismiss()
    }

    private func applyDiscoveryCandidate(_ candidate: BackendDiscoveryCandidate) {
        settingsStore.update { settings in
            settings.backendConnections[selectedBackend.id] = candidate.connectionSettings
        }
        appStore.refreshBackendStatus()
        setupStore.runChecks(profile: settingsStore.selectedBackendProfile)
    }

    private func useAssistantSelectionsAsDefaults(modelID: String, voiceID: String) {
        settingsStore.update { settings in
            if let catalog = setupStore.catalogReport {
                settings.backendCatalogs[selectedBackend.id] = catalog
            }
            var connection = settings.backendConnection(for: selectedBackend.id)
            if selectedBackend.engineType == .kokoro || selectedBackend.engineType == .chatterbox {
                connection.modelID = modelID
                connection.defaultVoice = voiceID
                settings.backendConnections[selectedBackend.id] = connection
            }
            settings.defaultModelID = modelID
            settings.defaultVoice = voiceID
            settings.rememberVoice(voiceID, for: selectedBackend.id)
        }
        appStore.applyDefaultGenerationSettings()
        appStore.statusMessage = "Saved \(selectedBackend.displayName) model and voice defaults"
    }

    private func runBackendOperation(_ kind: BackendOperationKind) {
        operationsStore.run(kind, profile: selectedBackend) { result in
            appStore.statusMessage = result.message
            appStore.refreshBackendStatus()
            setupStore.runChecks(profile: selectedBackend)
        }
    }
}
