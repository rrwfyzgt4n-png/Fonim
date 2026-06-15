import Foundation
import VibeVoiceBatchCore

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var projects: [NarrationProject] = []
    @Published private(set) var scripts: [NarrationScript] = []
    @Published private(set) var batches: [NarrationBatch] = []
    @Published private(set) var voicePresets: [NarrationVoicePreset] = []
    @Published private(set) var generationPresets: [NarrationGenerationPreset] = []
    @Published private(set) var isRefreshing = false
    @Published var alertMessage: String?

    private let fileStore: WorkspaceFileStore

    init(fileStore: WorkspaceFileStore = WorkspaceFileStore()) {
        self.fileStore = fileStore
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        do {
            let snapshot = try fileStore.loadSnapshot()
            projects = snapshot.projects
            scripts = snapshot.scripts
            batches = snapshot.batches
            voicePresets = snapshot.voicePresets
            generationPresets = snapshot.generationPresets
        } catch {
            alertMessage = "Could not load workspace: \(error.localizedDescription)"
        }
        isRefreshing = false
    }

    func scripts(for project: NarrationProject) -> [NarrationScript] {
        scripts.filter { project.scriptIDs.contains($0.id) }
    }

    func batches(for project: NarrationProject) -> [NarrationBatch] {
        batches.filter { project.batchIDs.contains($0.id) }
    }

    @discardableResult
    func saveCurrentVoicePreset(voiceID: String) -> NarrationVoicePreset? {
        do {
            let preset = try fileStore.createVoicePreset(
                title: "Voice \(voiceID)",
                voiceID: voiceID
            )
            refresh()
            alertMessage = nil
            return preset
        } catch {
            alertMessage = "Could not save voice preset: \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func saveGenerationPreset(
        voiceID: String,
        cfgScale: String,
        ddpmInferenceSteps: Int,
        outputFormat: AudioOutputFormat
    ) -> NarrationGenerationPreset? {
        do {
            let title = "Preset \(SessionFormatters.sessionIDDateFormatter.string(from: Date()))"
            let voicePresetID = voicePresets.first { $0.voiceID == voiceID }?.id
            let preset = try fileStore.createGenerationPreset(
                title: title,
                voicePresetID: voicePresetID,
                voiceID: voiceID,
                settings: GenerationSettings(
                    cfgScale: cfgScale,
                    ddpmInferenceSteps: ddpmInferenceSteps
                ),
                outputFormat: outputFormat
            )
            refresh()
            alertMessage = nil
            return preset
        } catch {
            alertMessage = "Could not save generation preset: \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func duplicateVoicePreset(_ preset: NarrationVoicePreset) -> NarrationVoicePreset? {
        do {
            let copy = try fileStore.duplicateVoicePreset(id: preset.id)
            refresh()
            alertMessage = nil
            return copy
        } catch {
            alertMessage = "Could not duplicate voice: \(error.localizedDescription)"
            return nil
        }
    }

    func deleteVoicePreset(_ preset: NarrationVoicePreset) {
        guard !preset.isBuiltIn else {
            alertMessage = "Built-in voices cannot be deleted. Duplicate it first if you want a custom copy."
            return
        }

        do {
            try fileStore.deleteVoicePreset(id: preset.id)
            refresh()
            alertMessage = nil
        } catch {
            alertMessage = "Could not delete voice: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func duplicateGenerationPreset(_ preset: NarrationGenerationPreset) -> NarrationGenerationPreset? {
        do {
            let copy = try fileStore.duplicateGenerationPreset(id: preset.id)
            refresh()
            alertMessage = nil
            return copy
        } catch {
            alertMessage = "Could not duplicate preset: \(error.localizedDescription)"
            return nil
        }
    }

    func deleteGenerationPreset(_ preset: NarrationGenerationPreset) {
        guard !preset.isBuiltIn else {
            alertMessage = "Built-in presets cannot be deleted. Duplicate it first if you want a custom copy."
            return
        }

        do {
            try fileStore.deleteGenerationPreset(id: preset.id)
            refresh()
            alertMessage = nil
        } catch {
            alertMessage = "Could not delete preset: \(error.localizedDescription)"
        }
    }
}
