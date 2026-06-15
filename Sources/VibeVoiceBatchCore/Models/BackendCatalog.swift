import Foundation

public struct BackendCatalogModel: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var owner: String?

    public init(id: String, displayName: String? = nil, owner: String? = nil) {
        self.id = id
        self.displayName = displayName ?? id
        self.owner = owner
    }
}

public struct BackendCatalogVoice: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String

    public init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName ?? id
    }
}

public struct BackendCatalogReport: Codable, Equatable, Sendable {
    public var profileID: String
    public var generatedAt: Date
    public var models: [BackendCatalogModel]
    public var voices: [BackendCatalogVoice]
    public var message: String
    public var technicalDetails: String?

    public init(
        profileID: String,
        generatedAt: Date = Date(),
        models: [BackendCatalogModel],
        voices: [BackendCatalogVoice],
        message: String,
        technicalDetails: String? = nil
    ) {
        self.profileID = profileID
        self.generatedAt = generatedAt
        self.models = models
        self.voices = voices
        self.message = message
        self.technicalDetails = technicalDetails
    }
}
