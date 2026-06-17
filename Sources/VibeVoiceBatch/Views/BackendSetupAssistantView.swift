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
            return !setupStore.isLoadingCatalog
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
                selectedModelID: selectedSetupModelID,
                selectedVoiceID: selectedSetupVoiceID,
                loadCatalog: { setupStore.loadCatalog(profile: selectedBackend) },
                applyCatalog: applyCatalogDefaults
            )
        case .test:
            TestVoiceSetupPane(
                profile: selectedBackend,
                modelID: selectedSetupModelID,
                voiceID: selectedSetupVoiceID,
                isTesting: setupStore.isTestingVoice,
                statusMessage: setupStore.testStatusMessage,
                progress: setupStore.testProgress,
                logText: setupStore.testLogText,
                record: setupStore.testRecord,
                error: setupStore.testError,
                canTest: !appStore.isGenerating,
                runTest: prepareTestVoice,
                cancelTest: setupStore.cancelVoiceTest,
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
        if settingsStore.modelOptions(for: selectedBackend).contains(where: { $0.id == settingsStore.settings.defaultModelID }) {
            return settingsStore.settings.defaultModelID
        }
        return settingsStore.modelOptions(for: selectedBackend).first?.id ?? selectedBackend.requiredModels.first?.id ?? settingsStore.settings.defaultModelID
    }

    private var selectedSetupVoiceID: String {
        if settingsStore.voiceOptions(for: selectedBackend).contains(where: { $0.id == settingsStore.settings.defaultVoice }) {
            return settingsStore.settings.defaultVoice
        }
        return settingsStore.voiceOptions(for: selectedBackend).first?.id ?? settingsStore.settings.defaultVoice
    }

    private func prepareTestVoice() {
        setupStore.runVoiceTest(
            profile: selectedBackend,
            modelID: selectedSetupModelID,
            voiceID: selectedSetupVoiceID,
            cfgScale: settingsStore.settings.defaultCFGScale,
            ddpmInferenceSteps: settingsStore.settings.defaultDDPMInferenceSteps
        ) { record in
            if let record {
                appStore.revealGenerationRecord(record, status: "Test voice complete")
            } else {
                appStore.refreshHistory()
            }
            appStore.refreshBackendStatus()
        }
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

    private func applyCatalogDefaults(
        _ catalog: BackendCatalogReport,
        model: BackendCatalogModel?,
        voice: BackendCatalogVoice?
    ) {
        settingsStore.update { settings in
            settings.backendCatalogs[selectedBackend.id] = catalog
            var connection = settings.backendConnection(for: selectedBackend.id)
            if let model {
                connection.modelID = model.id
                settings.defaultModelID = model.id
            }
            if let voice {
                connection.defaultVoice = voice.id
                settings.defaultVoice = voice.id
            }
            settings.backendConnections[selectedBackend.id] = connection
        }
        appStore.applyDefaultGenerationSettings()
    }

    private func runBackendOperation(_ kind: BackendOperationKind) {
        operationsStore.run(kind, profile: selectedBackend) { result in
            appStore.statusMessage = result.message
            appStore.refreshBackendStatus()
            setupStore.runChecks(profile: selectedBackend)
        }
    }
}

private struct AssistantStepRail: View {
    let selectedStage: BackendSetupStage
    let highestUnlockedStage: BackendSetupStage
    let selectStage: (BackendSetupStage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Setup Assistant")
                    .font(.title3.weight(.semibold))
                Text("Step \(selectedStage.stepNumber) of \(BackendSetupStage.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            VStack(spacing: 4) {
                ForEach(BackendSetupStage.allCases) { stage in
                    Button {
                        if isUnlocked(stage) {
                            selectStage(stage)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(stepFill(for: stage))
                                    .frame(width: 22, height: 22)
                                Image(systemName: stepSymbol(for: stage))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(stepSymbolTint(for: stage))
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(stage.title)
                                    .lineLimit(1)
                                Text(stepCaption(for: stage))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                            if !isUnlocked(stage) {
                                Image(systemName: "lock.fill")
                                    .imageScale(.small)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedStage == stage ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isUnlocked(stage))
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .background(.regularMaterial)
    }

    private func isUnlocked(_ stage: BackendSetupStage) -> Bool {
        stage.isUnlocked(through: highestUnlockedStage)
    }

    private func isCompleted(_ stage: BackendSetupStage) -> Bool {
        stage.isBefore(selectedStage) || (stage.isBefore(highestUnlockedStage) && stage != selectedStage)
    }

    private func stepSymbol(for stage: BackendSetupStage) -> String {
        if isCompleted(stage) {
            return "checkmark"
        }
        if !isUnlocked(stage) {
            return "lock.fill"
        }
        return stage.systemImage
    }

    private func stepFill(for stage: BackendSetupStage) -> Color {
        if selectedStage == stage {
            return .accentColor
        }
        if isCompleted(stage) {
            return .green.opacity(0.2)
        }
        if !isUnlocked(stage) {
            return .secondary.opacity(0.12)
        }
        return .secondary.opacity(0.16)
    }

    private func stepSymbolTint(for stage: BackendSetupStage) -> Color {
        if selectedStage == stage {
            return .white
        }
        if isCompleted(stage) {
            return .green
        }
        return .secondary
    }

    private func stepCaption(for stage: BackendSetupStage) -> String {
        if selectedStage == stage {
            return "Current"
        }
        if isCompleted(stage) {
            return "Completed"
        }
        if isUnlocked(stage) {
            return "Available"
        }
        return "Locked"
    }
}

private struct AssistantStatusHeader: View {
    let profile: BackendProfile
    let status: BackendStatusSnapshot
    let report: BackendSetupReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: status.state == .ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(status.state.tint)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Backend Readiness")
                        .font(.headline)
                    Text(nextAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(status.state.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.state.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(status.state.tint.opacity(0.12), in: Capsule())
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow {
                    AssistantStatusHeaderValue(title: "Selected Backend", value: profile.displayName)
                    AssistantStatusHeaderValue(title: "Runtime State", value: "\(status.runtime.displayName) / \(status.state.displayName)")
                }
                GridRow {
                    AssistantStatusHeaderValue(title: "Current Blocking Issue", value: blockingIssue)
                    AssistantStatusHeaderValue(title: "Next Recommended Action", value: nextAction)
                }
            }

            if let details = status.technicalDetails,
               !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("Show Details") {
                    Text(details)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var blockingIssue: String {
        if let failed = report?.blockingChecks.first {
            return "\(failed.title): \(failed.message)"
        }
        if status.state == .ready {
            return "None"
        }
        return status.userMessage
    }

    private var nextAction: String {
        if status.state == .ready {
            return "Continue to model, voice, and test generation."
        }
        if let failed = report?.checks.first(where: { $0.state == .failed }) {
            return failed.recoverySuggestion ?? failed.message
        }
        return status.recoverySuggestion ?? status.userMessage
    }
}

private struct AssistantStatusHeaderValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

private struct AssistantFooter: View {
    let canGoBack: Bool
    let canContinue: Bool
    let isFinalStage: Bool
    let selectedStage: BackendSetupStage
    let back: () -> Void
    let continueAction: () -> Void

    var body: some View {
        HStack {
            Button("Back", action: back)
                .disabled(!canGoBack)
            Spacer()
            Text("Step \(selectedStage.stepNumber) of \(BackendSetupStage.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(isFinalStage ? "Finish" : "Continue", action: continueAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct WelcomeSetupPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Local Backend Setup", systemImage: "checkmark.seal")
                .font(.title2.weight(.semibold))

            Text("This assistant checks whether the selected local narration backend is ready before you generate audio.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ChooseBackendSetupPane: View {
    @Binding var selectedBackendID: String
    @Binding var mode: BackendSetupMode
    let statusText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(title: "Choose Backend", subtitle: "Choose how this Mac should run local narration.")

            Form {
                Picker("Backend", selection: $selectedBackendID) {
                    ForEach(BackendProfiles.all) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("Backend mode", selection: $mode) {
                    Text("Simple").tag(BackendSetupMode.simple)
                    Text("Advanced").tag(BackendSetupMode.advanced)
                    Text("External").tag(BackendSetupMode.external)
                }
                .pickerStyle(.radioGroup)

                LabeledContent("Selected mode", value: mode.displayName)
                LabeledContent("Current status", value: statusText)
            }
            .formStyle(.grouped)
        }
    }
}

private struct ChecksSetupPane: View {
    let profile: BackendProfile
    let report: BackendSetupReport?
    let isChecking: Bool
    let runChecks: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(title: "System Check", subtitle: profile.displayName)

            CheckList(report: report, isChecking: isChecking)

            HStack {
                Button(isChecking ? "Checking..." : "Run Checks", action: runChecks)
                    .disabled(isChecking)
                Spacer()
            }
        }
    }
}

private struct BackendInstallSetupPane: View {
    let profile: BackendProfile
    let report: BackendSetupReport?
    let discoveryReport: BackendDiscoveryReport?
    let operationResult: BackendOperationResult?
    let isChecking: Bool
    let isDiscovering: Bool
    let isOperationRunning: Bool
    let activeOperation: BackendOperationKind?
    @Binding var connection: BackendConnectionSettings
    let discover: () -> Void
    let applyCandidate: (BackendDiscoveryCandidate) -> Void
    let install: () -> Void
    let repair: () -> Void
    let prepare: () -> Void
    let runChecks: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(title: "Backend", subtitle: profile.role)

            Form {
                LabeledContent("Runtime", value: profile.runtime.displayName)
                LabeledContent("Image", value: profile.dockerImage ?? "Not required")
                LabeledContent("Model", value: profile.requiredModels.first?.displayName ?? "Not configured")
                LabeledContent("Memory", value: profile.requiredMemoryGB.map { "\(Int($0)) GB" } ?? "Not specified")
            }
            .formStyle(.grouped)

            if profile.engineType == .kokoro {
                KokoroDiscoveryPanel(
                    report: discoveryReport,
                    isDiscovering: isDiscovering,
                    discover: discover,
                    applyCandidate: applyCandidate
                )

                KokoroConnectionForm(connection: $connection)
            }

            CheckList(report: report, isChecking: false)

            if let operationResult {
                SetupOperationResult(result: operationResult, isRunning: isOperationRunning)
            }

            HStack {
                Button {
                    install()
                } label: {
                    Label("Install", systemImage: activeOperation == .install ? "hourglass" : "square.and.arrow.down")
                }
                .disabled(isOperationRunning)

                Button {
                    repair()
                } label: {
                    Label("Repair", systemImage: activeOperation == .repair ? "hourglass" : "wrench.and.screwdriver")
                }
                .disabled(isOperationRunning)

                Button {
                    prepare()
                } label: {
                    Label("Prepare", systemImage: activeOperation == .prepare ? "hourglass" : "play.circle")
                }
                .disabled(isOperationRunning)

                Button(isChecking ? "Checking..." : "Refresh Checks", action: runChecks)
                    .disabled(isOperationRunning || isChecking)
                Spacer()
            }
        }
    }
}

private struct KokoroDiscoveryPanel: View {
    let report: BackendDiscoveryReport?
    let isDiscovering: Bool
    let discover: () -> Void
    let applyCandidate: (BackendDiscoveryCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installed Kokoro")
                        .font(.headline)
                    Text("Find local Kokoro images and running services on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    discover()
                } label: {
                    Label(isDiscovering ? "Finding..." : "Find Kokoro", systemImage: isDiscovering ? "hourglass" : "magnifyingglass")
                }
                .disabled(isDiscovering)
            }

            if isDiscovering {
                ProgressView("Looking for installed Kokoro runtimes...")
            } else if let report {
                Text(report.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if report.candidates.isEmpty {
                    Text("Start your Kokoro container or enter its details manually below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(report.candidates) { candidate in
                            KokoroDiscoveryCandidateRow(
                                candidate: candidate,
                                apply: { applyCandidate(candidate) }
                            )
                        }
                    }
                }
            } else {
                Text("Use discovery if you already have Kokoro installed and running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct KokoroDiscoveryCandidateRow: View {
    let candidate: BackendDiscoveryCandidate
    let apply: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: candidate.serviceBaseURL == nil ? "shippingbox" : "server.rack")
                .foregroundStyle(candidate.confidence.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(candidate.title)
                        .font(.subheadline.weight(.semibold))
                    Text(candidate.confidence.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(candidate.confidence.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(candidate.confidence.tint.opacity(0.14), in: Capsule())
                }

                if let image = candidate.dockerImage {
                    Text(image)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let serviceBaseURL = candidate.serviceBaseURL {
                    Text(serviceBaseURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text(candidate.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Use", action: apply)
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct KokoroConnectionForm: View {
    @Binding var connection: BackendConnectionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kokoro Connection")
                .font(.headline)

            Text("Save the details for the Kokoro install you already have. The assistant will verify what it can and clearly mark anything still missing.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Connection", selection: binding(\.connectionKind)) {
                ForEach(BackendConnectionKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                if connection.connectionKind == .installedDockerImage {
                    GridRow {
                        Text("Image").foregroundStyle(.secondary)
                        TextField("kokoro image name", text: binding(\.dockerImage))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Container").foregroundStyle(.secondary)
                        TextField("optional container name", text: optionalBinding(\.containerName))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if connection.connectionKind == .installedDockerImage ||
                    connection.connectionKind == .externalService {
                    GridRow {
                        Text("Service URL").foregroundStyle(.secondary)
                        TextField("http://127.0.0.1:PORT", text: binding(\.serviceBaseURL))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Health").foregroundStyle(.secondary)
                        TextField("/health", text: binding(\.healthPath))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Generate").foregroundStyle(.secondary)
                        TextField("/v1/audio/speech", text: binding(\.generatePath))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                GridRow {
                    Text("Model").foregroundStyle(.secondary)
                    TextField("kokoro/default", text: binding(\.modelID))
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Voice").foregroundStyle(.secondary)
                    TextField("default voice", text: binding(\.defaultVoice))
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Notes").foregroundStyle(.secondary)
                    TextField("launch command, port, or anything useful", text: binding(\.notes))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<BackendConnectionSettings, Value>) -> Binding<Value> {
        Binding(
            get: { connection[keyPath: keyPath] },
            set: { connection[keyPath: keyPath] = $0 }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<BackendConnectionSettings, String?>) -> Binding<String> {
        Binding(
            get: { connection[keyPath: keyPath] ?? "" },
            set: { connection[keyPath: keyPath] = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
    }
}

private struct ModelsVoicesSetupPane: View {
    let profile: BackendProfile
    let catalogReport: BackendCatalogReport?
    let isLoadingCatalog: Bool
    let selectedModelID: String
    let selectedVoiceID: String
    let loadCatalog: () -> Void
    let applyCatalog: (BackendCatalogReport, BackendCatalogModel?, BackendCatalogVoice?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(title: "Models & Voices", subtitle: "Confirm the model and voice choices before the test generation.")

            Form {
                LabeledContent("Backend", value: profile.displayName)
                LabeledContent("Current model", value: selectedModelID)
                LabeledContent("Current voice", value: selectedVoiceID)
            }
            .formStyle(.grouped)

            if profile.engineType == .kokoro {
                KokoroCatalogPanel(
                    report: catalogReport,
                    isLoading: isLoadingCatalog,
                    loadCatalog: loadCatalog,
                    applyCatalog: applyCatalog
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("VibeVoice choices are bundled with the selected backend profile.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("Use Settings or the inspector to change the default VibeVoice voice and inference settings.")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct KokoroCatalogPanel: View {
    let report: BackendCatalogReport?
    let isLoading: Bool
    let loadCatalog: () -> Void
    let applyCatalog: (BackendCatalogReport, BackendCatalogModel?, BackendCatalogVoice?) -> Void
    @State private var selectedModelID = ""
    @State private var selectedVoiceID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Models and Voices")
                        .font(.headline)
                    Text("Read the choices exposed by the running Kokoro service.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    loadCatalog()
                } label: {
                    Label(isLoading ? "Reading..." : "Read Choices", systemImage: isLoading ? "hourglass" : "list.bullet.rectangle")
                }
                .disabled(isLoading)
            }

            if isLoading {
                ProgressView("Reading Kokoro models and voices...")
            } else if let report {
                Text(report.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if report.models.isEmpty && report.voices.isEmpty {
                    Text("No model or voice choices were returned. Check the service URL above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    catalogPickers(report: report)
                }
            } else {
                Text("After discovery fills the service URL, read choices to populate the app menus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func catalogPickers(report: BackendCatalogReport) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            if !report.models.isEmpty {
                GridRow {
                    Text("Model").foregroundStyle(.secondary)
                    Picker("Model", selection: modelBinding(report.models)) {
                        ForEach(report.models) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            if !report.voices.isEmpty {
                GridRow {
                    Text("Voice").foregroundStyle(.secondary)
                    Picker("Voice", selection: voiceBinding(report.voices)) {
                        ForEach(report.voices) { voice in
                            Text(voice.displayName).tag(voice.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }

        HStack {
            Text("\(report.models.count) models  \(report.voices.count) voices")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Apply Defaults") {
                applyCatalog(
                    report,
                    selectedModel(in: report.models),
                    selectedVoice(in: report.voices)
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(report.models.isEmpty && report.voices.isEmpty)
        }
    }

    private func modelBinding(_ models: [BackendCatalogModel]) -> Binding<String> {
        Binding(
            get: { normalizedModelID(in: models) },
            set: { selectedModelID = $0 }
        )
    }

    private func voiceBinding(_ voices: [BackendCatalogVoice]) -> Binding<String> {
        Binding(
            get: { normalizedVoiceID(in: voices) },
            set: { selectedVoiceID = $0 }
        )
    }

    private func normalizedModelID(in models: [BackendCatalogModel]) -> String {
        if models.contains(where: { $0.id == selectedModelID }) {
            return selectedModelID
        }
        return models.first?.id ?? ""
    }

    private func normalizedVoiceID(in voices: [BackendCatalogVoice]) -> String {
        if voices.contains(where: { $0.id == selectedVoiceID }) {
            return selectedVoiceID
        }
        return voices.first?.id ?? ""
    }

    private func selectedModel(in models: [BackendCatalogModel]) -> BackendCatalogModel? {
        let id = normalizedModelID(in: models)
        return models.first { $0.id == id }
    }

    private func selectedVoice(in voices: [BackendCatalogVoice]) -> BackendCatalogVoice? {
        let id = normalizedVoiceID(in: voices)
        return voices.first { $0.id == id }
    }
}

private struct SetupOperationResult: View {
    let result: BackendOperationResult
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(result.kind.displayName, systemImage: isRunning ? "hourglass" : result.status.systemImage)
                .foregroundStyle(isRunning ? .secondary : result.status.tint)
            Text(result.message)
                .foregroundStyle(.secondary)
            if let recovery = result.recoverySuggestion {
                Text(recovery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct TestVoiceSetupPane: View {
    let profile: BackendProfile
    let modelID: String
    let voiceID: String
    let isTesting: Bool
    let statusMessage: String
    let progress: GenerationProgressSnapshot?
    let logText: String
    let record: GenerationRecord?
    let error: GenerationErrorRecord?
    let canTest: Bool
    let runTest: () -> Void
    let cancelTest: () -> Void
    let openResult: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(title: "Test Voice", subtitle: "Generate a short sample through the selected backend.")

            Form {
                LabeledContent("Backend", value: profile.displayName)
                LabeledContent("Model", value: modelID)
                LabeledContent("Voice", value: voiceID)
                LabeledContent("Status", value: statusMessage)
                if let outputPath = record?.exportPath {
                    LabeledContent("Output", value: outputPath)
                }
            }
            .formStyle(.grouped)

            if isTesting {
                if let fraction = progress?.fractionComplete {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            } else if record?.status == .completed {
                ProgressView(value: 1)
            }

            if let progress {
                Text(progressLine(progress))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let error {
                VStack(alignment: .leading, spacing: 4) {
                    Label(error.title, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error.explanation)
                    if let recovery = error.recoverySuggestion {
                        Text(recovery)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }

            if !logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("Details") {
                    ScrollView {
                        Text(logText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }
            }

            HStack {
                Button {
                    isTesting ? cancelTest() : runTest()
                } label: {
                    Label(isTesting ? "Cancel Test" : "Run Test Voice", systemImage: isTesting ? "xmark.circle" : "waveform")
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canTest)
                Button("Open in History", action: openResult)
                    .disabled(record == nil)
                Spacer()
            }
        }
    }

    private func progressLine(_ progress: GenerationProgressSnapshot) -> String {
        let percent = progress.fractionComplete.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
        let elapsed = progress.elapsedSeconds.map(GenerationTickerState.clock) ?? "--:--"
        return "\(percent)  elapsed \(elapsed)  \(progress.message)"
    }
}

private struct ConfirmSetupPane: View {
    let isReady: Bool
    let complete: () -> Void
    let rerunChecks: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(
                title: isReady ? "Backend Ready" : "Setup Needs Attention",
                subtitle: isReady ? "The selected backend passed setup checks." : "Run checks again after addressing the blocking items."
            )

            HStack {
                Button("Run Checks Again", action: rerunChecks)
                Spacer()
                Button("Finish", action: complete)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isReady)
            }
        }
    }
}

private struct CheckList: View {
    let report: BackendSetupReport?
    let isChecking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Check Results")
                        .font(.headline)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let report {
                    HStack(spacing: 6) {
                        CheckSummaryBadge(title: "Passed", count: count(.passed, in: report), tint: .green)
                        CheckSummaryBadge(title: "Warnings", count: count(.warning, in: report), tint: .orange)
                        CheckSummaryBadge(title: "Blocking", count: report.blockingChecks.count, tint: .red)
                    }
                }
            }

            Divider()

            if isChecking {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking backend readiness...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let report {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(report.checks) { check in
                            CheckRow(check: check)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No checks yet")
                        .font(.headline)
                    Text("Run checks to see backend readiness, recovery actions, and technical details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var summaryText: String {
        if isChecking {
            return "Running system checks now."
        }
        guard let report else {
            return "No results yet."
        }
        return "Checked \(report.checks.count) item\(report.checks.count == 1 ? "" : "s") at \(report.generatedAt.formatted(date: .omitted, time: .shortened))."
    }

    private func count(_ state: BackendSetupCheckState, in report: BackendSetupReport) -> Int {
        report.checks.filter { $0.state == state }.count
    }
}

private struct CheckRow: View {
    let check: BackendSetupCheck

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: check.state.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(check.state.tint)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(check.title)
                        .font(.headline)
                    Spacer()
                    Text(check.state.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(check.state.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(check.state.tint.opacity(0.12), in: Capsule())
                }

                Text(check.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let recovery = check.recoverySuggestion,
                   !recovery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Label("Recommended", systemImage: "arrow.turn.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(recovery)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Copy Fix") {
                            copy(recovery)
                        }
                        .font(.caption)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                }

                if let details = check.technicalDetails,
                   !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DisclosureGroup("Show Details") {
                        Text(details)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct CheckSummaryBadge: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text("\(count)")
                .monospacedDigit()
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(count == 0 ? .secondary : tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}

private struct Header: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

private extension BackendSetupCheckState {
    var displayName: String {
        switch self {
        case .waiting: "Waiting"
        case .checking: "Checking"
        case .passed: "Passed"
        case .warning: "Warning"
        case .failed: "Needs Action"
        }
    }

    var systemImage: String {
        switch self {
        case .waiting: "clock"
        case .checking: "arrow.triangle.2.circlepath"
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .waiting, .checking: .secondary
        case .passed: .green
        case .warning: .orange
        case .failed: .red
        }
    }
}

private extension BackendRuntimeState {
    var tint: Color {
        switch self {
        case .ready: .green
        case .runningJob, .installing, .downloadingModel, .starting: .blue
        case .missing, .stopped, .failed: .orange
        case .unknown: .secondary
        }
    }
}

private extension BackendRuntime {
    var displayName: String {
        switch self {
        case .docker: "Managed local runtime"
        case .localPython: "Local Python"
        case .comfyUI: "ComfyUI"
        case .native: "Native"
        case .externalService: "External service"
        }
    }
}

private extension BackendDiscoveryConfidence {
    var tint: Color {
        switch self {
        case .high: .green
        case .medium: .blue
        case .low: .secondary
        }
    }
}

private extension BackendOperationStatus {
    var systemImage: String {
        switch self {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .skipped: "minus.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .succeeded: .green
        case .failed: .red
        case .skipped: .secondary
        }
    }
}
