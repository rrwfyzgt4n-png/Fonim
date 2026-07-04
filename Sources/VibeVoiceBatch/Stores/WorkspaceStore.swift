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

    var activeScripts: [NarrationScript] {
        scripts.filter { $0.status.isActiveWorkspaceItem }
    }

    var uncompletedBatches: [NarrationBatch] {
        batches.filter { $0.status != .completed && $0.status != .archived }
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
            alertMessage = AppErrorPresenter.message(for: error, fallbackTitle: "Could not load workspace")
        }
        isRefreshing = false
    }

    func scripts(for project: NarrationProject) -> [NarrationScript] {
        scripts.filter { project.scriptIDs.contains($0.id) }
    }

    func batches(for project: NarrationProject) -> [NarrationBatch] {
        batches.filter { project.batchIDs.contains($0.id) }
    }

    func projects(containingGenerationSession sessionID: String) -> [NarrationProject] {
        projects.filter { $0.generationSessionIDs.contains(sessionID) }
    }

    @discardableResult
    func createProject(title: String) -> NarrationProject? {
        guard let trimmed = title.trimmedOrNil else { return nil }
        do {
            let project = try fileStore.createProject(title: trimmed)
            refresh()
            alertMessage = nil
            return project
        } catch {
            alertMessage = AppErrorPresenter.message(for: error, fallbackTitle: "Could not create project")
            return nil
        }
    }

    @discardableResult
    func importScriptBatch(
        projectID: String? = nil,
        title: String,
        chunks: [ScriptChunk],
        backendID: String,
        modelID: String,
        voice: String,
        settings: GenerationSettings
    ) -> ScriptImportResult? {
        do {
            let result = try fileStore.createScriptBatch(
                projectID: projectID,
                title: title,
                chunks: chunks,
                backendID: backendID,
                modelID: modelID,
                voice: voice,
                settings: settings,
                notes: "Imported text split into \(chunks.count) generation chunks."
            )
            refresh()
            alertMessage = nil
            return result
        } catch {
            alertMessage = AppErrorPresenter.message(for: error, fallbackTitle: "Could not import script")
            return nil
        }
    }

    @discardableResult
    func createProjectRebatch(
        project: NarrationProject,
        scripts: [NarrationScript],
        backendID: String,
        modelID: String,
        voice: String,
        settings: GenerationSettings,
        settingsSourceDescription: String = "current generation settings"
    ) -> ScriptImportResult? {
        let chunks = scripts
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { ScriptChunk(title: $0.title, text: $0.text) }
        guard !chunks.isEmpty else { return nil }

        do {
            let result = try fileStore.createScriptBatch(
                projectID: project.id,
                title: "\(project.title) Re-batch",
                chunks: chunks,
                backendID: backendID,
                modelID: modelID,
                voice: voice,
                settings: settings,
                notes: "Re-batched from project scripts using \(settingsSourceDescription)."
            )
            refresh()
            alertMessage = nil
            return result
        } catch {
            alertMessage = AppErrorPresenter.message(for: error, fallbackTitle: "Could not re-batch project")
            return nil
        }
    }

    func deleteUncompletedBatch(_ batch: NarrationBatch) {
        do {
            try fileStore.deleteUncompletedBatch(id: batch.id)
            refresh()
            alertMessage = nil
        } catch {
            alertMessage = AppErrorPresenter.message(for: error, fallbackTitle: "Could not delete batch")
        }
    }

    @discardableResult
    func fileGenerationSessions(_ sessionIDs: [String], into project: NarrationProject) -> NarrationProject? {
        do {
            let updated = try fileStore.attachGenerationSessions(sessionIDs, toProject: project.id)
            refresh()
            alertMessage = nil
            return updated
        } catch {
            alertMessage = AppErrorPresenter.message(for: error, fallbackTitle: "Could not file outputs into project")
            return nil
        }
    }

    @discardableResult
    func saveCurrentVoicePreset(
        voiceID: String,
        title: String? = nil,
        backendID: String = BackendProfiles.vibeVoiceTTS.id,
        modelID: String = AppDefaults.modelPath,
        locale: String? = nil,
        traits: [String] = []
    ) -> NarrationVoicePreset? {
        do {
            let displayName = title ?? "Voice \(voiceID)"
            let preset = try fileStore.createVoicePreset(
                title: displayName,
                voiceID: voiceID,
                backendID: backendID,
                modelID: modelID,
                locale: locale,
                traits: traits
            )
            refresh()
            alertMessage = nil
            return preset
        } catch {
            alertMessage = AppErrorPresenter.message(for: error, fallbackTitle: "Could not save voice preset")
            return nil
        }
    }

    @discardableResult
    func saveGenerationPreset(
        backendID: String,
        modelID: String,
        voiceID: String,
        cfgScale: String,
        ddpmInferenceSteps: Int,
        outputFormat: AudioOutputFormat,
        extraParameters: [String: String] = [:]
    ) -> NarrationGenerationPreset? {
        do {
            let title = "Preset \(SessionFormatters.sessionIDDateFormatter.string(from: Date()))"
            let voicePresetID = voicePresets.first { $0.voiceID == voiceID }?.id
            let preset = try fileStore.createGenerationPreset(
                title: title,
                backendID: backendID,
                modelID: modelID,
                voicePresetID: voicePresetID,
                voiceID: voiceID,
                settings: GenerationSettings(
                    cfgScale: cfgScale,
                    ddpmInferenceSteps: ddpmInferenceSteps,
                    extraParameters: extraParameters
                ),
                outputFormat: outputFormat
            )
            refresh()
            alertMessage = nil
            return preset
        } catch {
            alertMessage = AppErrorPresenter.message(for: error, fallbackTitle: "Could not save generation preset")
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
            alertMessage = AppErrorPresenter.message(for: error, fallbackTitle: "Could not duplicate voice")
            return nil
        }
    }

    func deleteVoicePreset(_ preset: NarrationVoicePreset) {
        guard !preset.isBuiltIn else {
            alertMessage = AppErrorPresenter.message(
                for: WorkspaceError.cannotDeleteBuiltInPreset(
                    kind: .voice,
                    id: preset.id,
                    displayName: preset.displayName
                )
            )
            return
        }

        do {
            try fileStore.deleteVoicePreset(id: preset.id)
            refresh()
            alertMessage = nil
        } catch {
            alertMessage = AppErrorPresenter.message(for: error, fallbackTitle: "Could not delete voice")
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
            alertMessage = AppErrorPresenter.message(for: error, fallbackTitle: "Could not duplicate preset")
            return nil
        }
    }

    func deleteGenerationPreset(_ preset: NarrationGenerationPreset) {
        guard !preset.isBuiltIn else {
            alertMessage = AppErrorPresenter.message(
                for: WorkspaceError.cannotDeleteBuiltInPreset(
                    kind: .generation,
                    id: preset.id,
                    displayName: preset.displayName
                )
            )
            return
        }

        do {
            try fileStore.deleteGenerationPreset(id: preset.id)
            refresh()
            alertMessage = nil
        } catch {
            alertMessage = AppErrorPresenter.message(for: error, fallbackTitle: "Could not delete preset")
        }
    }
}

private extension WorkspaceItemStatus {
    var isActiveWorkspaceItem: Bool {
        self != .completed && self != .cancelled && self != .archived
    }
}
