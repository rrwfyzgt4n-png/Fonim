import Foundation

public enum AppSettingsKeys {
    public static let storageKey = "local.vibevoice.batch.settings.v1"
    public static let currentSchemaVersion = 1
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var defaultBackendID: String
    public var defaultModelID: String
    public var defaultVoice: String
    public var defaultCFGScale: String
    public var defaultDDPMInferenceSteps: Int
    public var outputFolderPath: String
    public var exportFormat: AudioOutputFormat
    public var showAdvancedGenerationControls: Bool
    public var refreshBackendStatusOnLaunch: Bool
    public var hasCompletedSetupAssistant: Bool
    public var setupMode: BackendSetupMode
    public var backendConnections: [String: BackendConnectionSettings]
    public var backendCatalogs: [String: BackendCatalogReport]
    public var chatterboxTemperature: Double
    public var chatterboxExaggeration: Double
    public var chatterboxCFGWeight: Double
    public var chatterboxSeed: Int
    public var chatterboxSpeedFactor: Double
    public var chatterboxLanguage: String
    public var chatterboxSplitText: Bool
    public var chatterboxChunkSize: Int

    public init(
        schemaVersion: Int = AppSettingsKeys.currentSchemaVersion,
        defaultBackendID: String = BackendProfiles.vibeVoiceTTS.id,
        defaultModelID: String = AppDefaults.modelPath,
        defaultVoice: String = AppDefaults.defaultVoice,
        defaultCFGScale: String = AppDefaults.defaultCFGScale,
        defaultDDPMInferenceSteps: Int = AppDefaults.defaultDDPMInferenceSteps,
        outputFolderPath: String = AppDefaults.projectRoot.historyDirectory.path,
        exportFormat: AudioOutputFormat = .wav,
        showAdvancedGenerationControls: Bool = true,
        refreshBackendStatusOnLaunch: Bool = true,
        hasCompletedSetupAssistant: Bool = false,
        setupMode: BackendSetupMode = .simple,
        backendConnections: [String: BackendConnectionSettings] = BackendConnectionSettings.defaultConfigurations,
        backendCatalogs: [String: BackendCatalogReport] = [:],
        chatterboxTemperature: Double = 0.8,
        chatterboxExaggeration: Double = 1.3,
        chatterboxCFGWeight: Double = 0.5,
        chatterboxSeed: Int = 0,
        chatterboxSpeedFactor: Double = 1.0,
        chatterboxLanguage: String = "en",
        chatterboxSplitText: Bool = true,
        chatterboxChunkSize: Int = 120
    ) {
        self.schemaVersion = schemaVersion
        self.defaultBackendID = defaultBackendID
        self.defaultModelID = defaultModelID
        self.defaultVoice = defaultVoice
        self.defaultCFGScale = defaultCFGScale
        self.defaultDDPMInferenceSteps = defaultDDPMInferenceSteps
        self.outputFolderPath = outputFolderPath
        self.exportFormat = exportFormat
        self.showAdvancedGenerationControls = showAdvancedGenerationControls
        self.refreshBackendStatusOnLaunch = refreshBackendStatusOnLaunch
        self.hasCompletedSetupAssistant = hasCompletedSetupAssistant
        self.setupMode = setupMode
        self.backendConnections = backendConnections
        self.backendCatalogs = backendCatalogs
        self.chatterboxTemperature = chatterboxTemperature
        self.chatterboxExaggeration = chatterboxExaggeration
        self.chatterboxCFGWeight = chatterboxCFGWeight
        self.chatterboxSeed = chatterboxSeed
        self.chatterboxSpeedFactor = chatterboxSpeedFactor
        self.chatterboxLanguage = chatterboxLanguage
        self.chatterboxSplitText = chatterboxSplitText
        self.chatterboxChunkSize = chatterboxChunkSize
    }

    public static let defaults = AppSettings()

    public var normalized: AppSettings {
        normalizationResult().settings
    }

    public func normalizationResult() -> AppSettingsNormalizationResult {
        AppSettingsNormalizationResult.normalizing(self)
    }

    public static func loadResult(from data: Data?, decoder: JSONDecoder = JSONDecoder()) -> AppSettingsNormalizationResult {
        guard let data else {
            return AppSettingsNormalizationResult(settings: .defaults)
        }
        do {
            return try decoder.decode(AppSettings.self, from: data).normalizationResult()
        } catch {
            return AppSettingsNormalizationResult(
                settings: .defaults,
                recoveryNotes: [
                    AppSettingsRecoveryNote(
                        reason: .decodeFailed,
                        field: "settings",
                        message: "Saved settings could not be read, so default settings were restored.",
                        technicalDetails: error.localizedDescription
                    )
                ]
            )
        }
    }

    public func backendProfile(id: String) -> BackendProfile {
        BackendProfiles.resolvedProfile(id: id, connectionSettings: backendConnections) ?? BackendProfiles.vibeVoiceTTS
    }

    public var selectedBackendProfile: BackendProfile {
        backendProfile(id: defaultBackendID)
    }

    public func backendConnection(for profileID: String) -> BackendConnectionSettings {
        backendConnections[profileID] ??
            BackendConnectionSettings.defaultSettings(for: profileID) ??
            BackendConnectionSettings()
    }

    public func backendCatalog(for profileID: String) -> BackendCatalogReport? {
        backendCatalogs[profileID]
    }

    public func voiceOptions(for profile: BackendProfile) -> [BackendCatalogVoice] {
        if let catalog = backendCatalog(for: profile.id),
           !catalog.voices.isEmpty {
            return mergedVoiceOptions(catalog.voices, for: profile)
        }

        switch profile.engineType {
        case .vibeVoiceTTS:
            return AppDefaults.availableVoiceCatalogVoices
        case .chatterbox:
            return ChatterboxVoiceCatalog.catalogVoices
        case .kokoro:
            return KokoroVoiceCatalog.catalogVoices
        case .comfyUITTS, .f5TTS, .cosyVoice, .custom:
            let connection = backendConnection(for: profile.id)
            let voice = connection.trimmedDefaultVoice ?? defaultVoice
            return voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                [] :
                [enrichedVoice(BackendCatalogVoice(id: voice, displayName: voice), for: profile)]
        }
    }

    public func preferredVoiceID(for profile: BackendProfile, currentVoice: String? = nil) -> String {
        let voices = voiceOptions(for: profile)
        if let currentVoice,
           voices.contains(where: { $0.id == currentVoice }) {
            return currentVoice
        }
        let connectionVoice = backendConnection(for: profile.id).trimmedDefaultVoice
        if let connectionVoice,
           voices.contains(where: { $0.id == connectionVoice }) {
            return connectionVoice
        }
        if voices.contains(where: { $0.id == defaultVoice }) {
            return defaultVoice
        }
        return voices.first?.id ?? currentVoice ?? defaultVoice
    }

    public mutating func rememberVoice(_ voiceID: String, for backendID: String) {
        let trimmed = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var connection = backendConnection(for: backendID)
        connection.defaultVoice = trimmed
        backendConnections[backendID] = connection
    }

    private func mergedVoiceOptions(_ catalogVoices: [BackendCatalogVoice], for profile: BackendProfile) -> [BackendCatalogVoice] {
        let fallback: [BackendCatalogVoice]
        switch profile.engineType {
        case .vibeVoiceTTS:
            fallback = AppDefaults.availableVoiceCatalogVoices
        case .kokoro:
            fallback = KokoroVoiceCatalog.catalogVoices
        case .chatterbox:
            fallback = ChatterboxVoiceCatalog.catalogVoices
        case .comfyUITTS, .f5TTS, .cosyVoice, .custom:
            fallback = []
        }

        var voicesByID: [String: BackendCatalogVoice] = [:]
        var orderedIDs: [String] = []

        func add(_ voice: BackendCatalogVoice) {
            if voicesByID[voice.id] == nil {
                orderedIDs.append(voice.id)
            }
            voicesByID[voice.id] = voice
        }

        fallback.forEach(add)
        catalogVoices.map { enrichedVoice($0, for: profile) }.forEach(add)

        return orderedIDs.compactMap { voicesByID[$0] }
    }

    private func enrichedVoice(_ voice: BackendCatalogVoice, for profile: BackendProfile) -> BackendCatalogVoice {
        switch profile.engineType {
        case .vibeVoiceTTS:
            if let fallback = AppDefaults.availableVoiceCatalogVoices.first(where: { $0.id == voice.id }) {
                return fallback.mergingMissingMetadata(from: voice)
            }
        case .kokoro:
            let descriptor = KokoroVoiceCatalog.descriptor(for: voice.id, displayName: voice.displayName)
            return BackendCatalogVoice(
                id: voice.id,
                displayName: voice.displayName,
                backendID: voice.backendID ?? profile.id,
                modelIDs: voice.modelIDs.isEmpty ? profile.requiredModels.map(\.id) : voice.modelIDs,
                locale: voice.locale ?? descriptor.locale,
                languageCode: voice.languageCode ?? KokoroVoiceCatalog.languageCode(forLocale: voice.locale ?? descriptor.locale),
                countryFlag: voice.countryFlag,
                traits: voice.traits.isEmpty ? descriptor.traits : voice.traits,
                sourceType: voice.sourceType ?? .predefined,
                rawRuntimeID: voice.rawRuntimeID ?? voice.id
            )
        case .chatterbox:
            if let fallback = ChatterboxVoiceCatalog.catalogVoices.first(where: { $0.id == voice.id }) {
                let merged = fallback.mergingMissingMetadata(from: voice)
                let supportedModelIDs = merged.modelIDs.filter { ChatterboxModelCatalog.isSupportedModel($0) }
                return BackendCatalogVoice(
                    id: merged.id,
                    displayName: merged.displayName,
                    backendID: merged.backendID,
                    modelIDs: supportedModelIDs.isEmpty ? ChatterboxModelCatalog.definitions.map(\.id) : supportedModelIDs,
                    locale: merged.locale,
                    languageCode: merged.languageCode,
                    countryFlag: merged.countryFlag,
                    traits: merged.traits,
                    sourceType: merged.sourceType,
                    rawRuntimeID: merged.rawRuntimeID
                )
            }
            let cleanName = ((voice.displayName as NSString).lastPathComponent as NSString).deletingPathExtension
            let supportedModelIDs = voice.modelIDs.filter { ChatterboxModelCatalog.isSupportedModel($0) }
            return BackendCatalogVoice(
                id: voice.id,
                displayName: cleanName,
                backendID: voice.backendID ?? profile.id,
                modelIDs: supportedModelIDs.isEmpty ? ChatterboxModelCatalog.definitions.map(\.id) : supportedModelIDs,
                locale: voice.locale ?? "en",
                languageCode: voice.languageCode ?? "en",
                countryFlag: voice.countryFlag,
                traits: voice.traits.isEmpty ? ChatterboxVoiceCatalog.traits(forDisplayName: cleanName) : voice.traits,
                sourceType: voice.sourceType ?? .predefined,
                rawRuntimeID: voice.rawRuntimeID ?? voice.id
            )
        case .comfyUITTS, .f5TTS, .cosyVoice, .custom:
            break
        }

        return BackendCatalogVoice(
            id: voice.id,
            displayName: voice.displayName,
            backendID: voice.backendID ?? profile.id,
            modelIDs: voice.modelIDs.isEmpty ? profile.requiredModels.map(\.id) : voice.modelIDs,
            locale: voice.locale,
            languageCode: voice.languageCode,
            countryFlag: voice.countryFlag,
            traits: voice.traits,
            sourceType: voice.sourceType ?? .catalog,
            rawRuntimeID: voice.rawRuntimeID ?? voice.id
        )
    }

    public func generationExtraParameters(for profile: BackendProfile) -> [String: String] {
        var parameters = profile.generationExtraParameters
        guard profile.engineType == .chatterbox else {
            return parameters
        }
        parameters["temperature"] = String(chatterboxTemperature)
        parameters["exaggeration"] = String(chatterboxExaggeration)
        parameters["cfg_weight"] = String(chatterboxCFGWeight)
        parameters["seed"] = String(chatterboxSeed)
        parameters["speed_factor"] = String(chatterboxSpeedFactor)
        parameters["model"] = defaultModelID
        parameters["model_repo_id"] = ChatterboxModelCatalog.definition(for: defaultModelID)?
            .configuration["model.repo_id"] ?? defaultModelID
        let supportedLanguages = ChatterboxModelCatalog.languageCodes(for: defaultModelID)
        let normalizedLanguage = chatterboxLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        parameters["language"] = supportedLanguages.contains(normalizedLanguage) ? normalizedLanguage : (supportedLanguages.first ?? "en")
        parameters["split_text"] = chatterboxSplitText ? "true" : "false"
        parameters["chunk_size"] = String(chatterboxChunkSize)
        parameters["output_format"] = "wav"
        return parameters
    }

    public mutating func applyGenerationExtraParameters(_ parameters: [String: String], for profile: BackendProfile) {
        guard profile.engineType == .chatterbox else { return }
        if let value = Self.doubleParameter("temperature", in: parameters) { chatterboxTemperature = value }
        if let value = Self.doubleParameter("exaggeration", in: parameters) { chatterboxExaggeration = value }
        if let value = Self.doubleParameter("cfg_weight", in: parameters) { chatterboxCFGWeight = value }
        if let value = Self.integerParameter("seed", in: parameters) { chatterboxSeed = value }
        if let value = Self.doubleParameter("speed_factor", in: parameters) { chatterboxSpeedFactor = value }
        if let value = parameters["language"]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            chatterboxLanguage = value.lowercased()
        }
        if let value = Self.booleanParameter("split_text", in: parameters) { chatterboxSplitText = value }
        if let value = Self.integerParameter("chunk_size", in: parameters) { chatterboxChunkSize = value }
    }

    private static func doubleParameter(_ key: String, in parameters: [String: String]) -> Double? {
        parameters[key].flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func integerParameter(_ key: String, in parameters: [String: String]) -> Int? {
        parameters[key].flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func booleanParameter(_ key: String, in parameters: [String: String]) -> Bool? {
        guard let value = parameters[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        if ["true", "yes", "1"].contains(value) { return true }
        if ["false", "no", "0"].contains(value) { return false }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case defaultBackendID
        case defaultModelID
        case defaultVoice
        case defaultCFGScale
        case defaultDDPMInferenceSteps
        case outputFolderPath
        case exportFormat
        case showAdvancedGenerationControls
        case refreshBackendStatusOnLaunch
        case hasCompletedSetupAssistant
        case setupMode
        case backendConnections
        case backendCatalogs
        case chatterboxTemperature
        case chatterboxExaggeration
        case chatterboxCFGWeight
        case chatterboxSeed
        case chatterboxSpeedFactor
        case chatterboxLanguage
        case chatterboxSplitText
        case chatterboxChunkSize
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        defaultBackendID = try container.decodeIfPresent(String.self, forKey: .defaultBackendID) ?? defaults.defaultBackendID
        defaultModelID = try container.decodeIfPresent(String.self, forKey: .defaultModelID) ?? defaults.defaultModelID
        defaultVoice = try container.decodeIfPresent(String.self, forKey: .defaultVoice) ?? defaults.defaultVoice
        defaultCFGScale = try container.decodeIfPresent(String.self, forKey: .defaultCFGScale) ?? defaults.defaultCFGScale
        defaultDDPMInferenceSteps = try container.decodeIfPresent(Int.self, forKey: .defaultDDPMInferenceSteps) ?? defaults.defaultDDPMInferenceSteps
        outputFolderPath = try container.decodeIfPresent(String.self, forKey: .outputFolderPath) ?? defaults.outputFolderPath
        exportFormat = try container.decodeIfPresent(AudioOutputFormat.self, forKey: .exportFormat) ?? defaults.exportFormat
        showAdvancedGenerationControls = try container.decodeIfPresent(Bool.self, forKey: .showAdvancedGenerationControls) ?? defaults.showAdvancedGenerationControls
        refreshBackendStatusOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .refreshBackendStatusOnLaunch) ?? defaults.refreshBackendStatusOnLaunch
        hasCompletedSetupAssistant = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedSetupAssistant) ?? defaults.hasCompletedSetupAssistant
        setupMode = try container.decodeIfPresent(BackendSetupMode.self, forKey: .setupMode) ?? defaults.setupMode
        backendConnections = try container.decodeIfPresent([String: BackendConnectionSettings].self, forKey: .backendConnections) ?? [:]
        backendCatalogs = try container.decodeIfPresent([String: BackendCatalogReport].self, forKey: .backendCatalogs) ?? defaults.backendCatalogs
        chatterboxTemperature = try container.decodeIfPresent(Double.self, forKey: .chatterboxTemperature) ?? defaults.chatterboxTemperature
        chatterboxExaggeration = try container.decodeIfPresent(Double.self, forKey: .chatterboxExaggeration) ?? defaults.chatterboxExaggeration
        chatterboxCFGWeight = try container.decodeIfPresent(Double.self, forKey: .chatterboxCFGWeight) ?? defaults.chatterboxCFGWeight
        chatterboxSeed = try container.decodeIfPresent(Int.self, forKey: .chatterboxSeed) ?? defaults.chatterboxSeed
        chatterboxSpeedFactor = try container.decodeIfPresent(Double.self, forKey: .chatterboxSpeedFactor) ?? defaults.chatterboxSpeedFactor
        chatterboxLanguage = try container.decodeIfPresent(String.self, forKey: .chatterboxLanguage) ?? defaults.chatterboxLanguage
        chatterboxSplitText = try container.decodeIfPresent(Bool.self, forKey: .chatterboxSplitText) ?? defaults.chatterboxSplitText
        chatterboxChunkSize = try container.decodeIfPresent(Int.self, forKey: .chatterboxChunkSize) ?? defaults.chatterboxChunkSize
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(defaultBackendID, forKey: .defaultBackendID)
        try container.encode(defaultModelID, forKey: .defaultModelID)
        try container.encode(defaultVoice, forKey: .defaultVoice)
        try container.encode(defaultCFGScale, forKey: .defaultCFGScale)
        try container.encode(defaultDDPMInferenceSteps, forKey: .defaultDDPMInferenceSteps)
        try container.encode(outputFolderPath, forKey: .outputFolderPath)
        try container.encode(exportFormat, forKey: .exportFormat)
        try container.encode(showAdvancedGenerationControls, forKey: .showAdvancedGenerationControls)
        try container.encode(refreshBackendStatusOnLaunch, forKey: .refreshBackendStatusOnLaunch)
        try container.encode(hasCompletedSetupAssistant, forKey: .hasCompletedSetupAssistant)
        try container.encode(setupMode, forKey: .setupMode)
        try container.encode(backendConnections, forKey: .backendConnections)
        try container.encode(backendCatalogs, forKey: .backendCatalogs)
        try container.encode(chatterboxTemperature, forKey: .chatterboxTemperature)
        try container.encode(chatterboxExaggeration, forKey: .chatterboxExaggeration)
        try container.encode(chatterboxCFGWeight, forKey: .chatterboxCFGWeight)
        try container.encode(chatterboxSeed, forKey: .chatterboxSeed)
        try container.encode(chatterboxSpeedFactor, forKey: .chatterboxSpeedFactor)
        try container.encode(chatterboxLanguage, forKey: .chatterboxLanguage)
        try container.encode(chatterboxSplitText, forKey: .chatterboxSplitText)
        try container.encode(chatterboxChunkSize, forKey: .chatterboxChunkSize)
    }
}
