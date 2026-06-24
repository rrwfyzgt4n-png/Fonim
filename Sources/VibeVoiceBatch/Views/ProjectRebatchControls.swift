import SwiftUI
import VibeVoiceBatchCore

struct ProjectRebatchControls: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @State private var settingsSource = ProjectRebatchSettingsSource.current
    @State private var selectedPresetID: String?

    let project: NarrationProject
    let scripts: [NarrationScript]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                settingsPicker
                presetPicker
                rebatchButton
                summary
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                settingsPicker
                presetPicker
                HStack {
                    rebatchButton
                    summary
                }
            }
        }
        .onAppear(perform: ensurePresetSelection)
        .onChange(of: workspaceStore.generationPresets) { _ in
            ensurePresetSelection()
        }
    }

    private var settingsPicker: some View {
        Picker("Re-batch settings", selection: $settingsSource) {
            ForEach(ProjectRebatchSettingsSource.allCases) { source in
                Text(source.label).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
        .disabled(scripts.isEmpty)
    }

    @ViewBuilder
    private var presetPicker: some View {
        if settingsSource == .generationPreset {
            Picker("Preset", selection: presetBinding) {
                if workspaceStore.generationPresets.isEmpty {
                    Text("No Presets").tag("")
                } else {
                    ForEach(workspaceStore.generationPresets) { preset in
                        Text(preset.displayName).tag(preset.id)
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 220)
            .disabled(scripts.isEmpty || workspaceStore.generationPresets.isEmpty)
        }
    }

    private var rebatchButton: some View {
        Button {
            rebatchProject()
        } label: {
            Label("Queue Re-batch", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!canRebatch)
        .help("Create and queue a new batch from this project's scripts using the selected settings source.")
    }

    @ViewBuilder
    private var summary: some View {
        if canRebatch {
            VoiceInlineLabel(voiceID: resolvedVoiceID, compact: true)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: { selectedPresetID ?? workspaceStore.generationPresets.first?.id ?? "" },
            set: { selectedPresetID = $0.isEmpty ? nil : $0 }
        )
    }

    private var selectedPreset: NarrationGenerationPreset? {
        guard let selectedPresetID else { return workspaceStore.generationPresets.first }
        return workspaceStore.generationPresets.first { $0.id == selectedPresetID } ?? workspaceStore.generationPresets.first
    }

    private var canRebatch: Bool {
        !scripts.isEmpty && resolvedConfiguration != nil
    }

    private var resolvedVoiceID: String {
        resolvedConfiguration?.voiceID ?? appStore.selectedVoice
    }

    private var resolvedConfiguration: ProjectRebatchConfiguration? {
        switch settingsSource {
        case .current:
            return ProjectRebatchConfiguration(
                backendID: appStore.selectedBackendProfile.id,
                modelID: appStore.selectedModelID,
                voiceID: appStore.selectedVoice,
                settings: GenerationSettings(
                    cfgScale: appStore.cfgScale,
                    ddpmInferenceSteps: appStore.ddpmInferenceSteps
                )
            )
        case .generationPreset:
            guard let preset = selectedPreset else { return nil }
            return ProjectRebatchConfiguration(
                backendID: preset.backendID,
                modelID: preset.modelID,
                voiceID: preset.voiceID ?? appStore.selectedVoice,
                settings: preset.settings
            )
        }
    }

    private func rebatchProject() {
        guard let configuration = resolvedConfiguration else { return }
        guard let result = workspaceStore.createProjectRebatch(
            project: project,
            scripts: scripts,
            backendID: configuration.backendID,
            modelID: configuration.modelID,
            voice: configuration.voiceID,
            settings: configuration.settings
        ) else {
            return
        }
        appStore.queueImportedScripts(result.scripts, batch: result.batch)
    }

    private func ensurePresetSelection() {
        guard !workspaceStore.generationPresets.isEmpty else {
            selectedPresetID = nil
            if settingsSource == .generationPreset {
                settingsSource = .current
            }
            return
        }
        if let selectedPresetID,
           workspaceStore.generationPresets.contains(where: { $0.id == selectedPresetID }) {
            return
        }
        selectedPresetID = workspaceStore.generationPresets.first?.id
    }
}

private enum ProjectRebatchSettingsSource: String, CaseIterable, Identifiable {
    case current
    case generationPreset

    var id: String { rawValue }

    var label: String {
        switch self {
        case .current:
            return "Current Settings"
        case .generationPreset:
            return "Generation Preset"
        }
    }
}

private struct ProjectRebatchConfiguration {
    var backendID: String
    var modelID: String
    var voiceID: String
    var settings: GenerationSettings
}
