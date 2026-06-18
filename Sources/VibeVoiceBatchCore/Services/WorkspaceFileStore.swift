import Foundation

public final class WorkspaceFileStore {
    public let projectRoot: URL
    private let fileManager: FileManager
    private let storagePaths: WorkspaceStoragePaths

    public init(projectRoot: URL = AppDefaults.projectRoot, fileManager: FileManager = .default) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
        self.storagePaths = WorkspaceStoragePaths(projectRoot: projectRoot, fileManager: fileManager)
    }

    public func ensureWorkspaceDirectories() throws {
        try fileManager.createDirectory(at: storagePaths.directory(.projects), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: storagePaths.directory(.scripts), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: storagePaths.directory(.batches), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: storagePaths.directory(.voicePresets), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: storagePaths.directory(.generationPresets), withIntermediateDirectories: true)
    }

    public func loadSnapshot() throws -> WorkspaceSnapshot {
        try ensureWorkspaceDirectories()
        return WorkspaceSnapshot(
            projects: try loadProjects(),
            scripts: try loadScripts(),
            batches: try loadBatches(),
            voicePresets: try loadVoicePresets(),
            generationPresets: try loadGenerationPresets()
        )
    }

    public func loadProjects() throws -> [NarrationProject] {
        WorkspaceSorting.newestFirst(try loadItems(in: storagePaths.directory(.projects), as: NarrationProject.self))
    }

    public func loadScripts() throws -> [NarrationScript] {
        WorkspaceSorting.newestFirst(try loadItems(in: storagePaths.directory(.scripts), as: NarrationScript.self))
    }

    public func loadBatches() throws -> [NarrationBatch] {
        WorkspaceSorting.newestFirst(try loadItems(in: storagePaths.directory(.batches), as: NarrationBatch.self))
    }

    public func loadVoicePresets() throws -> [NarrationVoicePreset] {
        let custom = try loadItems(in: storagePaths.directory(.voicePresets), as: NarrationVoicePreset.self)
        return mergedPresets(defaultVoicePresets(), custom: custom) { $0.displayName < $1.displayName }
    }

    public func loadGenerationPresets() throws -> [NarrationGenerationPreset] {
        let custom = try loadItems(in: storagePaths.directory(.generationPresets), as: NarrationGenerationPreset.self)
        return mergedPresets(defaultGenerationPresets(), custom: custom) { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn && !rhs.isBuiltIn
            }
            return lhs.displayName < rhs.displayName
        }
    }

    public func createProject(
        title: String,
        notes: String = "",
        now: Date = Date()
    ) throws -> NarrationProject {
        try ensureWorkspaceDirectories()
        let project = NarrationProject(
            id: makeUniqueWorkspaceID(prefix: "project", title: title, in: .projects, date: now),
            title: title,
            createdAt: now,
            updatedAt: now,
            notes: notes
        )
        try saveProject(project)
        return project
    }

    public func createScript(
        projectID: String? = nil,
        title: String,
        text: String,
        voice: String = AppDefaults.defaultVoice,
        settings: GenerationSettings = GenerationSettings(),
        notes: String = "",
        now: Date = Date()
    ) throws -> NarrationScript {
        try ensureWorkspaceDirectories()
        if let projectID {
            _ = try loadProject(id: projectID)
        }
        let script = NarrationScript(
            id: makeUniqueWorkspaceID(prefix: "script", title: title, in: .scripts, date: now),
            projectID: projectID,
            title: title,
            text: text,
            createdAt: now,
            updatedAt: now,
            defaultVoice: voice,
            defaultSettings: settings,
            notes: notes
        )
        try saveScript(script)
        if let projectID {
            try linkScript(script.id, toProject: projectID, now: now)
        }
        return script
    }

    public func createBatch(
        projectID: String? = nil,
        title: String,
        scriptIDs: [String],
        notes: String = "",
        now: Date = Date()
    ) throws -> NarrationBatch {
        try ensureWorkspaceDirectories()
        if let projectID {
            _ = try loadProject(id: projectID)
        }
        for scriptID in scriptIDs {
            _ = try loadScript(id: scriptID)
        }
        let items = scriptIDs.enumerated().map { index, scriptID in
            NarrationBatchItem(
                id: "\(index + 1)-\(scriptID)",
                scriptID: scriptID,
                position: index,
                status: .queued
            )
        }
        let batch = NarrationBatch(
            id: makeUniqueWorkspaceID(prefix: "batch", title: title, in: .batches, date: now),
            projectID: projectID,
            title: title,
            createdAt: now,
            updatedAt: now,
            status: items.isEmpty ? .draft : .queued,
            items: items,
            notes: notes
        )
        try saveBatch(batch)
        if let projectID {
            try linkBatch(batch.id, toProject: projectID, now: now)
        }
        return batch
    }

    public func createVoicePreset(
        title: String,
        voiceID: String,
        backendID: String = BackendProfiles.vibeVoiceTTS.id,
        modelID: String = AppDefaults.modelPath,
        locale: String? = nil,
        traits: [String] = [],
        notes: String = "",
        now: Date = Date()
    ) throws -> NarrationVoicePreset {
        try ensureWorkspaceDirectories()
        let preset = NarrationVoicePreset(
            id: makeUniqueWorkspaceID(prefix: "voice_preset", title: title, in: .voicePresets, date: now),
            displayName: title,
            backendID: backendID,
            modelID: modelID,
            voiceID: voiceID,
            locale: locale,
            traits: traits,
            createdAt: now,
            updatedAt: now,
            notes: notes
        )
        try saveVoicePreset(preset)
        return preset
    }

    public func createGenerationPreset(
        title: String,
        backendID: String = BackendProfiles.vibeVoiceTTS.id,
        modelID: String = AppDefaults.modelPath,
        voicePresetID: String? = nil,
        voiceID: String? = nil,
        settings: GenerationSettings,
        outputFormat: AudioOutputFormat,
        notes: String = "",
        now: Date = Date()
    ) throws -> NarrationGenerationPreset {
        try ensureWorkspaceDirectories()
        let preset = NarrationGenerationPreset(
            id: makeUniqueWorkspaceID(prefix: "generation_preset", title: title, in: .generationPresets, date: now),
            displayName: title,
            backendID: backendID,
            modelID: modelID,
            voicePresetID: voicePresetID,
            voiceID: voiceID,
            settings: settings,
            outputFormat: outputFormat,
            createdAt: now,
            updatedAt: now,
            notes: notes
        )
        try saveGenerationPreset(preset)
        return preset
    }

    public func saveProject(_ project: NarrationProject) throws {
        try ensureWorkspaceDirectories()
        try write(project, to: projectURL(project.id))
    }

    public func saveScript(_ script: NarrationScript) throws {
        try ensureWorkspaceDirectories()
        try write(script, to: scriptURL(script.id))
    }

    public func saveBatch(_ batch: NarrationBatch) throws {
        try ensureWorkspaceDirectories()
        try write(batch, to: batchURL(batch.id))
    }

    public func saveVoicePreset(_ preset: NarrationVoicePreset) throws {
        try ensureWorkspaceDirectories()
        guard !preset.isBuiltIn else { return }
        try write(preset, to: voicePresetURL(preset.id))
    }

    public func saveGenerationPreset(_ preset: NarrationGenerationPreset) throws {
        try ensureWorkspaceDirectories()
        guard !preset.isBuiltIn else { return }
        try write(preset, to: generationPresetURL(preset.id))
    }

    public func loadProject(id: String) throws -> NarrationProject {
        try read(NarrationProject.self, from: projectURL(id))
    }

    public func loadScript(id: String) throws -> NarrationScript {
        try read(NarrationScript.self, from: scriptURL(id))
    }

    public func loadBatch(id: String) throws -> NarrationBatch {
        try read(NarrationBatch.self, from: batchURL(id))
    }

    public func loadVoicePreset(id: String) throws -> NarrationVoicePreset {
        if let builtIn = defaultVoicePresets().first(where: { $0.id == id }) {
            return builtIn
        }
        return try read(NarrationVoicePreset.self, from: voicePresetURL(id))
    }

    public func loadGenerationPreset(id: String) throws -> NarrationGenerationPreset {
        if let builtIn = defaultGenerationPresets().first(where: { $0.id == id }) {
            return builtIn
        }
        return try read(NarrationGenerationPreset.self, from: generationPresetURL(id))
    }

    public func duplicateVoicePreset(id: String, now: Date = Date()) throws -> NarrationVoicePreset {
        let source = try loadVoicePreset(id: id)
        return try createVoicePreset(
            title: "\(source.displayName) Copy",
            voiceID: source.voiceID,
            backendID: source.backendID,
            modelID: source.modelID,
            locale: source.locale,
            traits: source.traits,
            notes: source.notes,
            now: now
        )
    }

    public func duplicateGenerationPreset(id: String, now: Date = Date()) throws -> NarrationGenerationPreset {
        let source = try loadGenerationPreset(id: id)
        return try createGenerationPreset(
            title: "\(source.displayName) Copy",
            backendID: source.backendID,
            modelID: source.modelID,
            voicePresetID: source.voicePresetID,
            voiceID: source.voiceID,
            settings: source.settings,
            outputFormat: source.outputFormat,
            notes: source.notes,
            now: now
        )
    }

    public func deleteVoicePreset(id: String) throws {
        let preset = try loadVoicePreset(id: id)
        guard !preset.isBuiltIn else {
            throw WorkspaceError.cannotDeleteBuiltInPreset(
                kind: .voice,
                id: preset.id,
                displayName: preset.displayName
            )
        }
        try fileManager.removeItem(at: voicePresetURL(id))
    }

    public func deleteGenerationPreset(id: String) throws {
        let preset = try loadGenerationPreset(id: id)
        guard !preset.isBuiltIn else {
            throw WorkspaceError.cannotDeleteBuiltInPreset(
                kind: .generation,
                id: preset.id,
                displayName: preset.displayName
            )
        }
        try fileManager.removeItem(at: generationPresetURL(id))
    }

    public func updateScriptText(id: String, text: String, now: Date = Date()) throws -> NarrationScript {
        var script = try loadScript(id: id)
        script.text = text
        script.updatedAt = now
        script.status = .draft
        try saveScript(script)
        return script
    }

    public func appendGenerationSession(
        _ sessionID: String,
        toScript scriptID: String,
        now: Date = Date()
    ) throws -> NarrationScript {
        var script = try loadScript(id: scriptID)
        if !script.generationSessionIDs.contains(sessionID) {
            script.generationSessionIDs.append(sessionID)
        }
        script.updatedAt = now
        script.status = .completed
        try saveScript(script)
        return script
    }

    public func attachGenerationSessions(
        _ sessionIDs: [String],
        toProject projectID: String,
        now: Date = Date()
    ) throws -> NarrationProject {
        var project = try loadProject(id: projectID)
        var addedSession = false
        for sessionID in sessionIDs where !project.generationSessionIDs.contains(sessionID) {
            project.generationSessionIDs.append(sessionID)
            addedSession = true
        }
        guard addedSession else {
            return project
        }
        project.updatedAt = now
        if !project.generationSessionIDs.isEmpty, project.status == .draft {
            project.status = .ready
        }
        try saveProject(project)
        return project
    }

    public func recordBatchItemGeneration(
        batchID: String,
        itemID: String,
        sessionID: String,
        status: WorkspaceItemStatus,
        error: String? = nil,
        now: Date = Date()
    ) throws -> NarrationBatch {
        var batch = try loadBatch(id: batchID)
        guard let index = batch.items.firstIndex(where: { $0.id == itemID }) else {
            throw WorkspaceError.missingBatchItem(batchID: batchID, itemID: itemID)
        }

        batch.items[index].generationSessionID = sessionID
        batch.items[index].status = status
        batch.items[index].lastError = error
        batch.updatedAt = now
        batch.status = aggregateStatus(for: batch.items)
        try saveBatch(batch)
        return batch
    }

    public func archiveProject(id: String, now: Date = Date()) throws -> NarrationProject {
        var project = try loadProject(id: id)
        project.status = .archived
        project.updatedAt = now
        try saveProject(project)
        return project
    }

    private func linkScript(_ scriptID: String, toProject projectID: String, now: Date) throws {
        var project = try loadProject(id: projectID)
        if !project.scriptIDs.contains(scriptID) {
            project.scriptIDs.append(scriptID)
        }
        project.updatedAt = now
        try saveProject(project)
    }

    private func linkBatch(_ batchID: String, toProject projectID: String, now: Date) throws {
        var project = try loadProject(id: projectID)
        if !project.batchIDs.contains(batchID) {
            project.batchIDs.append(batchID)
        }
        project.updatedAt = now
        try saveProject(project)
    }

    private func aggregateStatus(for items: [NarrationBatchItem]) -> WorkspaceItemStatus {
        guard !items.isEmpty else { return .draft }
        if items.contains(where: { $0.status == .running }) {
            return .running
        }
        if items.contains(where: { $0.status == .failed }) {
            return .failed
        }
        if items.allSatisfy({ $0.status == .completed }) {
            return .completed
        }
        if items.allSatisfy({ $0.status == .cancelled }) {
            return .cancelled
        }
        return .queued
    }

    private func loadItems<T: Decodable>(in directory: URL, as type: T.Type) throws -> [T] {
        try ensureWorkspaceDirectories()
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url in
            guard url.pathExtension == "json",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return try read(type, from: url)
        }
    }

    private func makeUniqueWorkspaceID(
        prefix: String,
        title: String,
        in directory: WorkspaceStorageDirectory,
        date: Date
    ) -> String {
        storagePaths.makeUniqueID(prefix: prefix, title: title, in: directory, date: date)
    }

    private func projectURL(_ id: String) -> URL {
        storagePaths.jsonURL(id: id, in: .projects)
    }

    private func scriptURL(_ id: String) -> URL {
        storagePaths.jsonURL(id: id, in: .scripts)
    }

    private func batchURL(_ id: String) -> URL {
        storagePaths.jsonURL(id: id, in: .batches)
    }

    private func voicePresetURL(_ id: String) -> URL {
        storagePaths.jsonURL(id: id, in: .voicePresets)
    }

    private func generationPresetURL(_ id: String) -> URL {
        storagePaths.jsonURL(id: id, in: .generationPresets)
    }

    private func defaultVoicePresets() -> [NarrationVoicePreset] {
        let date = Date(timeIntervalSince1970: 0)
        return AppDefaults.availableVoices.map { voiceID in
            NarrationVoicePreset(
                id: "builtin_voice_\(voiceID)",
                displayName: voiceDisplayName(voiceID),
                voiceID: voiceID,
                locale: voiceLocale(voiceID),
                traits: voiceTraits(voiceID),
                createdAt: date,
                updatedAt: date,
                isBuiltIn: true
            )
        }
    }

    private func defaultGenerationPresets() -> [NarrationGenerationPreset] {
        let date = Date(timeIntervalSince1970: 0)
        return [
            NarrationGenerationPreset(
                id: "builtin_generation_balanced_narration",
                displayName: "Balanced Narration",
                voicePresetID: "builtin_voice_\(AppDefaults.defaultVoice)",
                voiceID: AppDefaults.defaultVoice,
                settings: GenerationSettings(
                    cfgScale: AppDefaults.defaultCFGScale,
                    ddpmInferenceSteps: AppDefaults.defaultDDPMInferenceSteps
                ),
                outputFormat: .wav,
                createdAt: date,
                updatedAt: date,
                notes: "Default local narration profile.",
                isBuiltIn: true
            )
        ]
    }

    private func mergedPresets<T: Identifiable>(
        _ defaults: [T],
        custom: [T],
        sort: (T, T) -> Bool
    ) -> [T] where T.ID == String {
        var byID = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })
        for item in custom {
            byID[item.id] = item
        }
        return byID.values.sorted(by: sort)
    }

    private func voiceDisplayName(_ voiceID: String) -> String {
        voiceID
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func voiceLocale(_ voiceID: String) -> String? {
        voiceID.split(separator: "-").first.map(String.init)
    }

    private func voiceTraits(_ voiceID: String) -> [String] {
        var traits: [String] = []
        if voiceID.hasSuffix("_woman") {
            traits.append("woman")
        }
        if voiceID.hasSuffix("_man") {
            traits.append("man")
        }
        return traits
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONCodecs.metadataDecoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONCodecs.metadataEncoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

}
