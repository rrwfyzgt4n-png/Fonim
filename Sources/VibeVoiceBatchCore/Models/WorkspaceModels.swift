import Foundation

public enum WorkspaceItemStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case draft
    case ready
    case queued
    case running
    case completed
    case failed
    case cancelled
    case archived
}

public struct NarrationProject: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var status: WorkspaceItemStatus
    public var scriptIDs: [String]
    public var batchIDs: [String]
    public var generationSessionIDs: [String]
    public var notes: String

    public init(
        id: String,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        status: WorkspaceItemStatus = .draft,
        scriptIDs: [String] = [],
        batchIDs: [String] = [],
        generationSessionIDs: [String] = [],
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.scriptIDs = scriptIDs
        self.batchIDs = batchIDs
        self.generationSessionIDs = generationSessionIDs
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        status = try container.decode(WorkspaceItemStatus.self, forKey: .status)
        scriptIDs = try container.decodeIfPresent([String].self, forKey: .scriptIDs) ?? []
        batchIDs = try container.decodeIfPresent([String].self, forKey: .batchIDs) ?? []
        generationSessionIDs = try container.decodeIfPresent([String].self, forKey: .generationSessionIDs) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case status
        case scriptIDs = "script_ids"
        case batchIDs = "batch_ids"
        case generationSessionIDs = "generation_session_ids"
        case notes
    }
}

public struct NarrationScript: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var projectID: String?
    public var title: String
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date
    public var status: WorkspaceItemStatus
    public var defaultBackendID: String
    public var defaultModelID: String
    public var defaultVoice: String
    public var defaultSettings: GenerationSettings
    public var generationSessionIDs: [String]
    public var notes: String

    public init(
        id: String,
        projectID: String? = nil,
        title: String,
        text: String,
        createdAt: Date,
        updatedAt: Date,
        status: WorkspaceItemStatus = .draft,
        defaultBackendID: String = BackendProfiles.vibeVoiceTTS.id,
        defaultModelID: String = AppDefaults.modelPath,
        defaultVoice: String = AppDefaults.defaultVoice,
        defaultSettings: GenerationSettings = GenerationSettings(),
        generationSessionIDs: [String] = [],
        notes: String = ""
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.defaultBackendID = defaultBackendID
        self.defaultModelID = defaultModelID
        self.defaultVoice = defaultVoice
        self.defaultSettings = defaultSettings
        self.generationSessionIDs = generationSessionIDs
        self.notes = notes
    }

    public var inputWordCount: Int {
        TextMetrics.wordCount(in: text)
    }

    public var inputCharacterCount: Int {
        text.count
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case title
        case text
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case status
        case defaultBackendID = "default_backend_id"
        case defaultModelID = "default_model_id"
        case defaultVoice = "default_voice"
        case defaultSettings = "default_settings"
        case generationSessionIDs = "generation_session_ids"
        case notes
    }
}

public struct NarrationBatchItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var scriptID: String
    public var position: Int
    public var status: WorkspaceItemStatus
    public var generationSessionID: String?
    public var lastError: String?

    public init(
        id: String,
        scriptID: String,
        position: Int,
        status: WorkspaceItemStatus = .queued,
        generationSessionID: String? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.scriptID = scriptID
        self.position = position
        self.status = status
        self.generationSessionID = generationSessionID
        self.lastError = lastError
    }

    enum CodingKeys: String, CodingKey {
        case id
        case scriptID = "script_id"
        case position
        case status
        case generationSessionID = "generation_session_id"
        case lastError = "last_error"
    }
}

public struct NarrationBatch: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var projectID: String?
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var status: WorkspaceItemStatus
    public var items: [NarrationBatchItem]
    public var notes: String

    public init(
        id: String,
        projectID: String? = nil,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        status: WorkspaceItemStatus = .draft,
        items: [NarrationBatchItem] = [],
        notes: String = ""
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.items = items
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case status
        case items
        case notes
    }
}

public struct NarrationVoicePreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var backendID: String
    public var modelID: String
    public var voiceID: String
    public var locale: String?
    public var traits: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var notes: String
    public var isBuiltIn: Bool

    public init(
        id: String,
        displayName: String,
        backendID: String = BackendProfiles.vibeVoiceTTS.id,
        modelID: String = AppDefaults.modelPath,
        voiceID: String,
        locale: String? = nil,
        traits: [String] = [],
        createdAt: Date,
        updatedAt: Date,
        notes: String = "",
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.backendID = backendID
        self.modelID = modelID
        self.voiceID = voiceID
        self.locale = locale
        self.traits = traits
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
        self.isBuiltIn = isBuiltIn
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case backendID = "backend_id"
        case modelID = "model_id"
        case voiceID = "voice_id"
        case locale
        case traits
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case notes
        case isBuiltIn = "is_built_in"
    }
}

public struct NarrationGenerationPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var backendID: String
    public var modelID: String
    public var voicePresetID: String?
    public var voiceID: String?
    public var settings: GenerationSettings
    public var outputFormat: AudioOutputFormat
    public var createdAt: Date
    public var updatedAt: Date
    public var notes: String
    public var isBuiltIn: Bool

    public init(
        id: String,
        displayName: String,
        backendID: String = BackendProfiles.vibeVoiceTTS.id,
        modelID: String = AppDefaults.modelPath,
        voicePresetID: String? = nil,
        voiceID: String? = nil,
        settings: GenerationSettings = GenerationSettings(),
        outputFormat: AudioOutputFormat = .wav,
        createdAt: Date,
        updatedAt: Date,
        notes: String = "",
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.backendID = backendID
        self.modelID = modelID
        self.voicePresetID = voicePresetID
        self.voiceID = voiceID
        self.settings = settings
        self.outputFormat = outputFormat
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
        self.isBuiltIn = isBuiltIn
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case backendID = "backend_id"
        case modelID = "model_id"
        case voicePresetID = "voice_preset_id"
        case voiceID = "voice_id"
        case settings
        case outputFormat = "output_format"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case notes
        case isBuiltIn = "is_built_in"
    }
}

public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    public var projects: [NarrationProject]
    public var scripts: [NarrationScript]
    public var batches: [NarrationBatch]
    public var voicePresets: [NarrationVoicePreset]
    public var generationPresets: [NarrationGenerationPreset]

    public init(
        projects: [NarrationProject],
        scripts: [NarrationScript],
        batches: [NarrationBatch],
        voicePresets: [NarrationVoicePreset] = [],
        generationPresets: [NarrationGenerationPreset] = []
    ) {
        self.projects = projects
        self.scripts = scripts
        self.batches = batches
        self.voicePresets = voicePresets
        self.generationPresets = generationPresets
    }
}
