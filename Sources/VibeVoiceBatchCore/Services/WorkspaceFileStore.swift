import Foundation

public final class WorkspaceFileStore {
    public let projectRoot: URL
    private let fileManager: FileManager

    public init(projectRoot: URL = AppDefaults.projectRoot, fileManager: FileManager = .default) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
    }

    public func ensureWorkspaceDirectories() throws {
        try fileManager.createDirectory(at: projectRoot.projectsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectRoot.scriptsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectRoot.batchesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectRoot.voicePresetsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectRoot.generationPresetsDirectory, withIntermediateDirectories: true)
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
        try loadItems(in: projectRoot.projectsDirectory, as: NarrationProject.self)
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.id > rhs.id
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    public func loadScripts() throws -> [NarrationScript] {
        try loadItems(in: projectRoot.scriptsDirectory, as: NarrationScript.self)
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.id > rhs.id
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    public func loadBatches() throws -> [NarrationBatch] {
        try loadItems(in: projectRoot.batchesDirectory, as: NarrationBatch.self)
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.id > rhs.id
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    public func loadVoicePresets() throws -> [NarrationVoicePreset] {
        let custom = try loadItems(in: projectRoot.voicePresetsDirectory, as: NarrationVoicePreset.self)
        return mergedPresets(defaultVoicePresets(), custom: custom) { $0.displayName < $1.displayName }
    }

    public func loadGenerationPresets() throws -> [NarrationGenerationPreset] {
        let custom = try loadItems(in: projectRoot.generationPresetsDirectory, as: NarrationGenerationPreset.self)
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
            id: try makeUniqueWorkspaceID(prefix: "project", title: title, directory: projectRoot.projectsDirectory, date: now),
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
            id: try makeUniqueWorkspaceID(prefix: "script", title: title, directory: projectRoot.scriptsDirectory, date: now),
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
            id: try makeUniqueWorkspaceID(prefix: "batch", title: title, directory: projectRoot.batchesDirectory, date: now),
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
            id: try makeUniqueWorkspaceID(prefix: "voice_preset", title: title, directory: projectRoot.voicePresetsDirectory, date: now),
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
            id: try makeUniqueWorkspaceID(prefix: "generation_preset", title: title, directory: projectRoot.generationPresetsDirectory, date: now),
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
            throw CocoaError(.fileNoSuchFile)
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

    private func makeUniqueWorkspaceID(prefix: String, title: String, directory: URL, date: Date) throws -> String {
        let base = "\(prefix)_\(SessionFormatters.sessionIDDateFormatter.string(from: date))_\(slug(title, fallback: "untitled"))"
        var candidate = base
        var suffix = 2
        while fileManager.fileExists(atPath: directory.appendingPathComponent("\(candidate).json").path) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func projectURL(_ id: String) -> URL {
        projectRoot.projectsDirectory.appendingPathComponent("\(id).json", isDirectory: false)
    }

    private func scriptURL(_ id: String) -> URL {
        projectRoot.scriptsDirectory.appendingPathComponent("\(id).json", isDirectory: false)
    }

    private func batchURL(_ id: String) -> URL {
        projectRoot.batchesDirectory.appendingPathComponent("\(id).json", isDirectory: false)
    }

    private func voicePresetURL(_ id: String) -> URL {
        projectRoot.voicePresetsDirectory.appendingPathComponent("\(id).json", isDirectory: false)
    }

    private func generationPresetURL(_ id: String) -> URL {
        projectRoot.generationPresetsDirectory.appendingPathComponent("\(id).json", isDirectory: false)
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

    private func slug(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return sanitized.isEmpty ? fallback : sanitized
    }
}
