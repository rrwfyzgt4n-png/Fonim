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
    public var backendID: String?
    public var modelIDs: [String]
    public var locale: String?
    public var languageCode: String?
    public var countryFlag: String?
    public var traits: [String]
    public var sourceType: BackendCatalogVoiceSource?
    public var rawRuntimeID: String?

    public init(
        id: String,
        displayName: String? = nil,
        backendID: String? = nil,
        modelIDs: [String] = [],
        locale: String? = nil,
        languageCode: String? = nil,
        countryFlag: String? = nil,
        traits: [String] = [],
        sourceType: BackendCatalogVoiceSource? = nil,
        rawRuntimeID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.backendID = backendID
        self.modelIDs = modelIDs
        self.locale = locale
        self.languageCode = languageCode
        self.countryFlag = countryFlag
        self.traits = traits
        self.sourceType = sourceType
        self.rawRuntimeID = rawRuntimeID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case backendID
        case modelIDs
        case locale
        case languageCode
        case countryFlag
        case traits
        case sourceType
        case rawRuntimeID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? id
        backendID = try container.decodeIfPresent(String.self, forKey: .backendID)
        modelIDs = try container.decodeIfPresent([String].self, forKey: .modelIDs) ?? []
        locale = try container.decodeIfPresent(String.self, forKey: .locale)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        countryFlag = try container.decodeIfPresent(String.self, forKey: .countryFlag)
        traits = try container.decodeIfPresent([String].self, forKey: .traits) ?? []
        sourceType = try container.decodeIfPresent(BackendCatalogVoiceSource.self, forKey: .sourceType)
        rawRuntimeID = try container.decodeIfPresent(String.self, forKey: .rawRuntimeID)
    }

    public func mergingMissingMetadata(from preferred: BackendCatalogVoice) -> BackendCatalogVoice {
        BackendCatalogVoice(
            id: preferred.id,
            displayName: preferred.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? displayName : preferred.displayName,
            backendID: preferred.backendID ?? backendID,
            modelIDs: preferred.modelIDs.isEmpty ? modelIDs : preferred.modelIDs,
            locale: preferred.locale ?? locale,
            languageCode: preferred.languageCode ?? languageCode,
            countryFlag: preferred.countryFlag ?? countryFlag,
            traits: preferred.traits.isEmpty ? traits : preferred.traits,
            sourceType: preferred.sourceType ?? sourceType,
            rawRuntimeID: preferred.rawRuntimeID ?? rawRuntimeID
        )
    }
}

public enum BackendCatalogVoiceSource: String, Codable, Equatable, Sendable {
    case catalog
    case predefined
    case reference
    case custom
    case savedProfile
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
