import SwiftUI
import VibeVoiceBatchCore

struct BackendSetupAssistantView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var setupStore = BackendSetupStore()
    @StateObject private var operationsStore = BackendOperationsStore()

    private var selectedBackend: BackendProfile {
        BackendProfiles.all.first { $0.id == settingsStore.settings.defaultBackendID } ?? BackendProfiles.vibeVoiceTTS
    }

    var body: some View {
        NavigationSplitView {
            List(BackendSetupStage.allCases, selection: $setupStore.selectedStage) { stage in
                Label(stage.title, systemImage: stage.systemImage)
                    .tag(stage)
            }
            .navigationTitle("Setup")
        } detail: {
            VStack(alignment: .leading, spacing: 18) {
                switch setupStore.selectedStage {
                case .welcome:
                    WelcomeSetupPane(onContinue: { setupStore.selectedStage = .mode })
                case .mode:
                    ModeSetupPane(mode: modeBinding, onContinue: { setupStore.selectedStage = .checks })
                case .checks:
                    ChecksSetupPane(
                        profile: selectedBackend,
                        report: setupStore.report,
                        isChecking: setupStore.isChecking,
                        runChecks: { setupStore.runChecks(profile: selectedBackend) },
                        onContinue: { setupStore.selectedStage = .install }
                    )
                case .install:
                    BackendInstallSetupPane(
                        profile: selectedBackend,
                        report: setupStore.report,
                        operationResult: operationsStore.latestResult,
                        isOperationRunning: operationsStore.isRunning,
                        activeOperation: operationsStore.activeOperation,
                        install: { runBackendOperation(.install) },
                        repair: { runBackendOperation(.repair) },
                        prepare: { runBackendOperation(.prepare) },
                        runChecks: { setupStore.runChecks(profile: selectedBackend) },
                        onContinue: { setupStore.selectedStage = .test }
                    )
                case .test:
                    TestVoiceSetupPane(
                        canGenerate: appStore.backendStatus.canStartGeneration && !appStore.isGenerating,
                        prepareTest: prepareTestVoice,
                        onContinue: { setupStore.selectedStage = .confirm }
                    )
                case .confirm:
                    ConfirmSetupPane(
                        isReady: setupStore.report?.isReady == true,
                        complete: completeSetup,
                        rerunChecks: {
                            setupStore.selectedStage = .checks
                            setupStore.runChecks(profile: selectedBackend)
                        }
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Backend Setup Assistant")
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            if setupStore.report == nil {
                setupStore.runChecks(profile: selectedBackend)
            }
        }
    }

    private var modeBinding: Binding<BackendSetupMode> {
        Binding(
            get: { settingsStore.settings.setupMode },
            set: { settingsStore.selectSetupMode($0) }
        )
    }

    private func prepareTestVoice() {
        appStore.updateEditorText("This is a short local narration test.")
        appStore.applyDefaultGenerationSettings()
        appStore.generate()
    }

    private func completeSetup() {
        settingsStore.markSetupAssistantCompleted()
        dismiss()
    }

    private func runBackendOperation(_ kind: BackendOperationKind) {
        operationsStore.run(kind, profile: selectedBackend) { result in
            appStore.statusMessage = result.message
            appStore.refreshBackendStatus()
            setupStore.runChecks(profile: selectedBackend)
        }
    }
}

private struct WelcomeSetupPane: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Local Backend Setup", systemImage: "checkmark.seal")
                .font(.title2.weight(.semibold))

            Text("This assistant checks whether the selected local narration backend is ready before you generate audio.")
                .foregroundStyle(.secondary)

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct ModeSetupPane: View {
    @Binding var mode: BackendSetupMode
    let onContinue: () -> Void

    var body: some View {
        Form {
            Picker("Backend mode", selection: $mode) {
                Text("Simple").tag(BackendSetupMode.simple)
                Text("Advanced").tag(BackendSetupMode.advanced)
                Text("External").tag(BackendSetupMode.external)
            }
            .pickerStyle(.radioGroup)

            LabeledContent("Selected mode", value: mode.displayName)
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
    }
}

private struct ChecksSetupPane: View {
    let profile: BackendProfile
    let report: BackendSetupReport?
    let isChecking: Bool
    let runChecks: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(title: "System Check", subtitle: profile.displayName)

            CheckList(report: report, isChecking: isChecking)

            HStack {
                Button(isChecking ? "Checking..." : "Run Checks", action: runChecks)
                    .disabled(isChecking)
                Spacer()
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct BackendInstallSetupPane: View {
    let profile: BackendProfile
    let report: BackendSetupReport?
    let operationResult: BackendOperationResult?
    let isOperationRunning: Bool
    let activeOperation: BackendOperationKind?
    let install: () -> Void
    let repair: () -> Void
    let prepare: () -> Void
    let runChecks: () -> Void
    let onContinue: () -> Void

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

                Button("Refresh Checks", action: runChecks)
                    .disabled(isOperationRunning)
                Spacer()
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
        }
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
    let canGenerate: Bool
    let prepareTest: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(title: "Test Voice", subtitle: "Generate a short sample through the normal queue.")

            Text("The test uses the same no-overwrite session history and metadata path as any other generation.")
                .foregroundStyle(.secondary)

            HStack {
                Button("Generate Test Voice", action: prepareTest)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canGenerate)
                Button("Skip Test", action: onContinue)
                Spacer()
            }
        }
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
        Group {
            if isChecking {
                ProgressView("Checking backend...")
            } else if let report {
                List(report.checks) { check in
                    CheckRow(check: check)
                }
                .listStyle(.inset)
                .frame(minHeight: 260)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No checks yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
    }
}

private struct CheckRow: View {
    let check: BackendSetupCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(check.title, systemImage: check.state.systemImage)
                .font(.headline)
                .foregroundStyle(check.state.tint)
            Text(check.message)
                .foregroundStyle(.secondary)
            if let recovery = check.recoverySuggestion {
                Text(recovery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
