import Foundation

public struct BackendCatalogModel: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var owner: String?
    public var detail: String?
    public var languageCodes: [String]
    public var capabilities: [String]
    public var runtimeIdentifier: String?
    public var configuration: [String: String]
    public var isLoaded: Bool?

    public init(
        id: String,
        displayName: String? = nil,
        owner: String? = nil,
        detail: String? = nil,
        languageCodes: [String] = [],
        capabilities: [String] = [],
        runtimeIdentifier: String? = nil,
        configuration: [String: String] = [:],
        isLoaded: Bool? = nil
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.owner = owner
        self.detail = detail
        self.languageCodes = languageCodes
        self.capabilities = capabilities
        self.runtimeIdentifier = runtimeIdentifier
        self.configuration = configuration
        self.isLoaded = isLoaded
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case owner
        case detail
        case languageCodes
        case capabilities
        case runtimeIdentifier
        case configuration
        case isLoaded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? id
        owner = try container.decodeIfPresent(String.self, forKey: .owner)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        languageCodes = try container.decodeIfPresent([String].self, forKey: .languageCodes) ?? []
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        runtimeIdentifier = try container.decodeIfPresent(String.self, forKey: .runtimeIdentifier)
        configuration = try container.decodeIfPresent([String: String].self, forKey: .configuration) ?? [:]
        isLoaded = try container.decodeIfPresent(Bool.self, forKey: .isLoaded)
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
