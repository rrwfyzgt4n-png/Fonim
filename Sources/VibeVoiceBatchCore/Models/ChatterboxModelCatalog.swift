import Foundation

public struct ChatterboxModelDefinition: Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var detail: String
    public var languageCodes: [String]
    public var capabilities: [String]
    public var runtimeIdentifier: String
    public var configuration: [String: String]

    public init(
        id: String,
        displayName: String,
        detail: String,
        languageCodes: [String],
        capabilities: [String],
        runtimeIdentifier: String,
        configuration: [String: String]
    ) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
        self.languageCodes = languageCodes
        self.capabilities = capabilities
        self.runtimeIdentifier = runtimeIdentifier
        self.configuration = configuration
    }
}

public enum ChatterboxModelCatalog {
    public static let turboID = "chatterbox-turbo"
    public static let originalID = "chatterbox"

    /// Kept only so saved settings from earlier builds can be recognized and repaired.
    public static let multilingualID = "chatterbox-multilingual"

    public static let definitions: [ChatterboxModelDefinition] = [
        ChatterboxModelDefinition(
            id: turboID,
            displayName: "Chatterbox Turbo (Fast, English)",
            detail: "Fast English generation with paralinguistic tag support.",
            languageCodes: ["en"],
            capabilities: ["predefined_voices", "voice_cloning", "paralinguistic_tags"],
            runtimeIdentifier: "turbo",
            configuration: ["model.repo_id": turboID]
        ),
        ChatterboxModelDefinition(
            id: originalID,
            displayName: "Chatterbox Original (English)",
            detail: "Original English Chatterbox model with expressive controls.",
            languageCodes: ["en"],
            capabilities: ["predefined_voices", "voice_cloning", "expressive_controls"],
            runtimeIdentifier: "original",
            configuration: ["model.repo_id": originalID]
        )
    ]

    public static var supportedModelIDs: Set<String> {
        Set(definitions.map(\.id))
    }

    public static var requiredModels: [RequiredModel] {
        definitions.map { definition in
            RequiredModel(
                id: definition.id,
                displayName: definition.displayName,
                source: definition.configuration["model.repo_id"] ?? definition.id,
                approximateDiskSpaceGB: nil,
                licenseNotes: "Chatterbox model and voice license terms must be reviewed before redistribution."
            )
        }
    }

    public static func definition(for modelID: String) -> ChatterboxModelDefinition? {
        let normalized = normalizedModelID(from: modelID)
        return definitions.first { $0.id == normalized }
    }

    public static func displayName(for modelID: String) -> String {
        definition(for: modelID)?.displayName ?? modelID
    }

    public static func languageCodes(for modelID: String) -> [String] {
        definition(for: modelID)?.languageCodes ?? ["en"]
    }

    public static func isSupportedModel(_ modelID: String) -> Bool {
        supportedModelIDs.contains(normalizedModelID(from: modelID))
    }

    public static func catalogModels(
        loadedModelID: String? = nil,
        turboAvailable: Bool? = nil
    ) -> [BackendCatalogModel] {
        definitions.map { definition in
            var detail = definition.detail
            if definition.id == turboID, turboAvailable == false {
                detail += " This runtime reports that Turbo is not available."
            }
            return BackendCatalogModel(
                id: definition.id,
                displayName: definition.displayName,
                owner: "chatterbox",
                detail: detail,
                languageCodes: definition.languageCodes,
                capabilities: definition.capabilities,
                runtimeIdentifier: definition.runtimeIdentifier,
                configuration: definition.configuration,
                isLoaded: loadedModelID.map { $0 == definition.id }
            )
        }
    }

    public static func normalizedModelID(from rawValue: String?) -> String {
        let value = (rawValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch value {
        case turboID, "turbo", "resembleai/chatterbox-turbo":
            return turboID
        case multilingualID, "multilingual":
            return multilingualID
        case originalID, originalID + "-original", "original", "resembleai/chatterbox":
            return originalID
        default:
            if value.contains("multilingual") {
                return multilingualID
            }
            if value.contains("turbo") {
                return turboID
            }
            if value.contains("original") {
                return originalID
            }
            return value.isEmpty ? turboID : value
        }
    }
}
