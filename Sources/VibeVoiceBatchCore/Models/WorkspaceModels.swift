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
    public var notes: String

    public init(
        id: String,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        status: WorkspaceItemStatus = .draft,
        scriptIDs: [String] = [],
        batchIDs: [String] = [],
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.scriptIDs = scriptIDs
        self.batchIDs = batchIDs
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case status
        case scriptIDs = "script_ids"
        case batchIDs = "batch_ids"
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

public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    public var projects: [NarrationProject]
    public var scripts: [NarrationScript]
    public var batches: [NarrationBatch]

    public init(
        projects: [NarrationProject],
        scripts: [NarrationScript],
        batches: [NarrationBatch]
    ) {
        self.projects = projects
        self.scripts = scripts
        self.batches = batches
    }
}
