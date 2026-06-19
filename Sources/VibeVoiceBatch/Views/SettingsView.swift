import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TabView {
            BackendsSettingsPane()
                .tabItem {
                    Label("Backends", systemImage: "server.rack")
                }

            ModelsSettingsPane()
                .tabItem {
                    Label("Models", systemImage: "cube.transparent")
                }

            VoicesSettingsPane()
                .tabItem {
                    Label("Voices", systemImage: "waveform")
                }

            OutputSettingsPane()
                .tabItem {
                    Label("Output", systemImage: "folder")
                }

            AdvancedSettingsPane()
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
        }
        .padding(20)
        .frame(width: 620, height: 420)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply to Editor") {
                    appStore.applyDefaultGenerationSettings()
                }
            }

            ToolbarItem(placement: .cancellationAction) {
                Button("Reset Defaults") {
                    settingsStore.resetDefaults()
                    appStore.applyDefaultGenerationSettings()
                }
            }

            ToolbarItem {
                Button("Setup Assistant") {
                    openWindow(id: "backend-setup")
                }
            }
        }
    }
}

private struct BackendsSettingsPane: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appStore: AppStore
    @StateObject private var operationsStore = BackendOperationsStore()

    var body: some View {
        Form {
            Picker("Default backend", selection: backendBinding) {
                ForEach(BackendProfiles.all) { profile in
                    Text(profile.displayName).tag(profile.id)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Runtime", value: selectedBackend.runtime.displayName)
            LabeledContent("Role", value: selectedBackend.role)
            LabeledContent("Status", value: appStore.backendStatus.state.displayName)
            LabeledContent("Project data", value: operationsStore.diskUsage.projectRootBytes.formattedByteCount)
            LabeledContent("Model cache", value: operationsStore.diskUsage.modelCacheBytes.formattedByteCount)

            HStack {
                Button("Refresh Status") {
                    appStore.refreshBackendStatus()
                }

                Button("Show Details") {
                    appStore.showBackendDetails()
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    BackendOperationButton(
                        title: "Install",
                        systemImage: "square.and.arrow.down",
                        kind: .install,
                        selectedBackend: selectedBackend,
                        operationsStore: operationsStore,
                        appStore: appStore
                    )
                    BackendOperationButton(
                        title: "Update",
                        systemImage: "arrow.down.circle",
                        kind: .update,
                        selectedBackend: selectedBackend,
                        operationsStore: operationsStore,
                        appStore: appStore
                    )
                    BackendOperationButton(
                        title: "Prepare",
                        systemImage: "play.circle",
                        kind: .prepare,
                        selectedBackend: selectedBackend,
                        operationsStore: operationsStore,
                        appStore: appStore
                    )
                }
                GridRow {
                    BackendOperationButton(
                        title: "Stop",
                        systemImage: "stop.circle",
                        kind: .stop,
                        selectedBackend: selectedBackend,
                        operationsStore: operationsStore,
                        appStore: appStore
                    )
                    BackendOperationButton(
                        title: "Repair",
                        systemImage: "wrench.and.screwdriver",
                        kind: .repair,
                        selectedBackend: selectedBackend,
                        operationsStore: operationsStore,
                        appStore: appStore
                    )
                    BackendOperationButton(
                        title: "Reset",
                        systemImage: "arrow.counterclockwise.circle",
                        kind: .reset,
                        selectedBackend: selectedBackend,
                        operationsStore: operationsStore,
                        appStore: appStore
                    )
                }
            }

            if let result = operationsStore.latestResult {
                BackendOperationResultSummary(result: result, isRunning: operationsStore.isRunning)
            }
        }
        .formStyle(.grouped)
    }

    private var selectedBackend: BackendProfile {
        settingsStore.selectedBackendProfile
    }

    private var backendBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.defaultBackendID },
            set: { appStore.selectBackend($0) }
        )
    }
}

private struct BackendOperationButton: View {
    let title: String
    let systemImage: String
    let kind: BackendOperationKind
    let selectedBackend: BackendProfile
    @ObservedObject var operationsStore: BackendOperationsStore
    let appStore: AppStore

    var body: some View {
        Button {
            operationsStore.run(kind, profile: selectedBackend) { result in
                appStore.statusMessage = result.message
                appStore.refreshBackendStatus()
            }
        } label: {
            Label(title, systemImage: operationsStore.activeOperation == kind ? "hourglass" : systemImage)
                .frame(minWidth: 96, alignment: .leading)
        }
        .disabled(operationsStore.isRunning || appStore.isGenerating)
        .help(kind.displayName)
    }
}

private struct BackendOperationResultSummary: View {
    let result: BackendOperationResult
    let isRunning: Bool
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(result.kind.displayName, systemImage: isRunning ? "hourglass" : result.status.systemImage)
                    .foregroundStyle(isRunning ? .secondary : result.status.tint)
                Spacer()
                Text(isRunning ? "Running" : result.status.displayName)
                    .foregroundStyle(.secondary)
            }
            Text(result.message)
                .foregroundStyle(.secondary)
            if let recovery = result.recoverySuggestion {
                Text(recovery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if result.technicalDetails?.isEmpty == false {
                DisclosureGroup("Show Details", isExpanded: $showingDetails) {
                    ScrollView {
                        Text(result.technicalDetails ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 80, maxHeight: 140)
                }
            }
        }
    }
}

private struct ModelsSettingsPane: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        Form {
            Picker("Default model", selection: binding(\.defaultModelID)) {
                ForEach(settingsStore.modelOptions(for: selectedBackend)) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Model path", value: settingsStore.settings.defaultModelID)
            LabeledContent("Runtime", value: selectedBackend.runtime.displayName)
            LabeledContent("Image", value: selectedBackend.dockerImage ?? "Not required")
            LabeledContent("Format support", value: selectedBackend.outputFormatSupport.map(\.displayName).joined(separator: ", "))
        }
        .formStyle(.grouped)
    }

    private var selectedBackend: BackendProfile {
        appStore.selectedBackendProfile
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in settingsStore.update { $0[keyPath: keyPath] = value } }
        )
    }
}

private struct VoicesSettingsPane: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        Form {
            Picker("Default voice", selection: defaultVoiceBinding) {
                ForEach(settingsStore.voiceOptions(for: appStore.selectedBackendProfile)) { voice in
                    VoiceInlineLabel(voiceID: voice.id, displayName: voice.displayName, compact: true)
                        .tag(voice.id)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Available voices", value: "\(settingsStore.voiceOptions(for: appStore.selectedBackendProfile).count)")
            HStack {
                Text("Current default")
                Spacer()
                VoiceInlineLabel(voiceID: settingsStore.settings.defaultVoice)
            }
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in settingsStore.update { $0[keyPath: keyPath] = value } }
        )
    }

    private var defaultVoiceBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.preferredVoiceID(for: appStore.selectedBackendProfile) },
            set: { appStore.selectVoice($0) }
        )
    }
}

private struct OutputSettingsPane: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        Form {
            Picker("Export format", selection: binding(\.exportFormat)) {
                ForEach(appStore.selectedBackendProfile.outputFormatSupport, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.menu)

            HStack {
                TextField("Output folder", text: binding(\.outputFolderPath))
                Button("Choose...") {
                    chooseOutputFolder()
                }
            }

            LabeledContent("History folder", value: AppDefaults.projectRoot.historyDirectory.path)
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in settingsStore.update { $0[keyPath: keyPath] = value } }
        )
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: settingsStore.settings.outputFolderPath, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            settingsStore.update { $0.outputFolderPath = url.path }
        }
    }
}

private struct AdvancedSettingsPane: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Picker("Default CFG scale", selection: binding(\.defaultCFGScale)) {
                ForEach(AppDefaults.availableCFGScales, id: \.self) { cfg in
                    Text(cfg).tag(cfg)
                }
            }
            .pickerStyle(.menu)

            Picker("Default DDPM steps", selection: binding(\.defaultDDPMInferenceSteps)) {
                ForEach(AppDefaults.availableDDPMInferenceSteps, id: \.self) { steps in
                    Text("\(steps)").tag(steps)
                }
            }
            .pickerStyle(.menu)

            Toggle("Show advanced controls in editor", isOn: binding(\.showAdvancedGenerationControls))
            Toggle("Refresh backend status on launch", isOn: binding(\.refreshBackendStatusOnLaunch))
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in settingsStore.update { $0[keyPath: keyPath] = value } }
        )
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

private extension AudioOutputFormat {
    var displayName: String {
        rawValue.uppercased()
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

private extension UInt64 {
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
