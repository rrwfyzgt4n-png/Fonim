import SwiftUI
import VibeVoiceBatchCore

struct InspectorPanelView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    let selection: WorkstationSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inspector")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    generationSection
                    backendSection
                    exportSection
                    metadataSection
                }
                .padding(14)
            }
        }
        .frame(minWidth: 280, idealWidth: 300, maxWidth: 340)
        .background(.regularMaterial)
    }

    private var generationSection: some View {
        InspectorGroup(title: "Generation") {
            Picker("Voice", selection: $store.selectedVoice) {
                ForEach(store.availableVoiceOptions) { voice in
                    Text(voice.displayName).tag(voice.id)
                }
            }
            .pickerStyle(.menu)

            Picker("CFG", selection: $store.cfgScale) {
                ForEach(AppDefaults.availableCFGScales, id: \.self) { cfgScale in
                    Text(cfgScale).tag(cfgScale)
                }
            }
            .pickerStyle(.menu)

            Picker("DDPM Steps", selection: $store.ddpmInferenceSteps) {
                ForEach(AppDefaults.availableDDPMInferenceSteps, id: \.self) { steps in
                    Text("\(steps)").tag(steps)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var backendSection: some View {
        InspectorGroup(title: "Model") {
            Picker("Backend", selection: backendBinding) {
                ForEach(BackendProfiles.all) { profile in
                    Text(profile.displayName).tag(profile.id)
                }
            }
            .pickerStyle(.menu)

            Picker("Model", selection: settingsBinding(\.defaultModelID)) {
                ForEach(store.availableModelOptions) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .pickerStyle(.menu)

            InspectorValue(label: "Status", value: store.backendStatus.state.displayName)
        }
    }

    private var exportSection: some View {
        InspectorGroup(title: "Export") {
            Picker("Format", selection: settingsBinding(\.exportFormat)) {
                ForEach(store.selectedBackendProfile.outputFormatSupport, id: \.self) { format in
                    Text(format.rawValue.uppercased()).tag(format)
                }
            }
            .pickerStyle(.menu)

            InspectorValue(label: "Folder", value: settingsStore.settings.outputFolderPath)
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        switch selection ?? .section(.history) {
        case .historySession:
            if let session = store.selectedSession {
                InspectorGroup(title: "Session Metadata") {
                    InspectorValue(label: "Status", value: session.metadata.status.displayName)
                    InspectorValue(label: "Voice", value: session.metadata.voice)
                    InspectorValue(label: "CFG", value: session.metadata.cfgScale)
                    InspectorValue(label: "Steps", value: session.metadata.ddpmInferenceSteps.map(String.init) ?? "--")
                    InspectorValue(label: "Words", value: "\(session.metadata.inputWordCount)")
                    InspectorValue(label: "Generation", value: SessionFormatters.duration(session.metadata.generationTimeSeconds))
                    InspectorValue(label: "Audio", value: SessionFormatters.duration(session.metadata.audioDurationSeconds))
                    InspectorValue(label: "RTF", value: SessionFormatters.rtf(session.metadata.rtf))
                }
            } else {
                editorMetadata
            }
        case .section(.projects):
            InspectorGroup(title: "Projects") {
                InspectorValue(label: "Count", value: "\(workspaceStore.projects.count)")
            }
        case .section(.scripts):
            InspectorGroup(title: "Scripts") {
                InspectorValue(label: "Count", value: "\(workspaceStore.scripts.count)")
                InspectorValue(label: "Generations", value: "\(workspaceStore.scripts.reduce(0) { $0 + $1.generationSessionIDs.count })")
            }
        case .section(.batches):
            InspectorGroup(title: "Batches") {
                InspectorValue(label: "Count", value: "\(workspaceStore.batches.count)")
                InspectorValue(label: "Items", value: "\(workspaceStore.batches.reduce(0) { $0 + $1.items.count })")
                InspectorValue(label: "Queued", value: "\(store.queuedGenerations.filter { $0.status == .queued }.count)")
                InspectorValue(label: "Running", value: "\(store.queuedGenerations.filter { $0.status == .running }.count)")
            }
        case .section(.voices):
            InspectorGroup(title: "Voices") {
                InspectorValue(label: "Available", value: "\(workspaceStore.voicePresets.count)")
                InspectorValue(label: "Selected", value: store.selectedVoice)
            }
        case .section(.presets):
            InspectorGroup(title: "Preset Metadata") {
                InspectorValue(label: "Count", value: "\(workspaceStore.generationPresets.count)")
                InspectorValue(label: "Default voice", value: settingsStore.settings.defaultVoice)
                InspectorValue(label: "Default CFG", value: settingsStore.settings.defaultCFGScale)
                InspectorValue(label: "Default steps", value: "\(settingsStore.settings.defaultDDPMInferenceSteps)")
            }
        case .section(.outputs):
            InspectorGroup(title: "Outputs") {
                InspectorValue(label: "Count", value: "\(store.outputSessions.count)")
                if let session = store.selectedSession {
                    InspectorValue(label: "Selected", value: session.outputURL?.lastPathComponent ?? "No WAV")
                    InspectorValue(label: "Audio", value: SessionFormatters.duration(session.metadata.audioDurationSeconds))
                    InspectorValue(label: "RTF", value: SessionFormatters.rtf(session.metadata.rtf))
                }
            }
        case .section(.backends):
            InspectorGroup(title: "Backend Metadata") {
                InspectorValue(label: "Backend", value: store.selectedBackendProfile.displayName)
                InspectorValue(label: "Runtime", value: store.selectedBackendProfile.runtime.displayName)
                InspectorValue(label: "Image", value: store.selectedBackendProfile.dockerImage ?? "Not required")
            }
        case .section(.settings):
            InspectorGroup(title: "Settings") {
                InspectorValue(label: "Setup", value: settingsStore.settings.hasCompletedSetupAssistant ? "Complete" : "Incomplete")
                InspectorValue(label: "Mode", value: settingsStore.settings.setupMode.displayName)
            }
        case .section(.history):
            editorMetadata
        }
    }

    private var editorMetadata: some View {
        InspectorGroup(title: "Text Metadata") {
            InspectorValue(label: "Words", value: "\(TextMetrics.wordCount(in: store.editorText))")
            InspectorValue(label: "Characters", value: "\(store.editorText.count)")
            InspectorValue(label: "Unsaved", value: store.hasUnsavedEditorText ? "Yes" : "No")
        }
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in settingsStore.update { $0[keyPath: keyPath] = value } }
        )
    }

    private var backendBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.defaultBackendID },
            set: { store.selectBackend($0) }
        )
    }
}

private struct InspectorGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

private struct InspectorValue: View {
    let label: String
    let value: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Text(label)
                    .foregroundStyle(.secondary)
                Text(value)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
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
