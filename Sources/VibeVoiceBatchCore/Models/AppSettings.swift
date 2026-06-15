import Foundation

public enum AppSettingsKeys {
    public static let storageKey = "local.vibevoice.batch.settings.v1"
}

public struct AppSettings: Codable, Equatable, Sendable {
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

    public init(
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
        backendCatalogs: [String: BackendCatalogReport] = [:]
    ) {
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
    }

    public static let defaults = AppSettings()

    public var normalized: AppSettings {
        var copy = self
        for profile in BackendProfiles.all {
            if copy.backendConnections[profile.id] == nil,
               let defaults = BackendConnectionSettings.defaultSettings(for: profile.id) {
                copy.backendConnections[profile.id] = defaults
            }
        }
        if !BackendProfiles.all.contains(where: { $0.id == copy.defaultBackendID }) {
            copy.defaultBackendID = BackendProfiles.vibeVoiceTTS.id
        }
        let selectedProfile = copy.backendProfile(id: copy.defaultBackendID)
        let selectedCatalog = copy.backendCatalog(for: copy.defaultBackendID)
        let catalogModels = selectedCatalog?.models ?? []
        if !catalogModels.isEmpty {
            if !catalogModels.contains(where: { $0.id == copy.defaultModelID }) {
                copy.defaultModelID = catalogModels[0].id
            }
        } else if !selectedProfile.requiredModels.contains(where: { $0.id == copy.defaultModelID }) {
            copy.defaultModelID = selectedProfile.requiredModels.first?.id ?? AppDefaults.modelPath
        }
        let selectedConnection = copy.backendConnection(for: copy.defaultBackendID)
        if selectedProfile.engineType == .kokoro {
            let catalogVoices = selectedCatalog?.voices ?? []
            if !catalogVoices.isEmpty {
                if !catalogVoices.contains(where: { $0.id == copy.defaultVoice }) {
                    copy.defaultVoice = catalogVoices[0].id
                }
            } else if copy.defaultVoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                copy.defaultVoice = selectedConnection.trimmedDefaultVoice ?? "af_heart"
            }
        } else if !AppDefaults.availableVoices.contains(copy.defaultVoice) {
            copy.defaultVoice = AppDefaults.defaultVoice
        }
        if !AppDefaults.availableCFGScales.contains(copy.defaultCFGScale) {
            copy.defaultCFGScale = AppDefaults.defaultCFGScale
        }
        if !AppDefaults.availableDDPMInferenceSteps.contains(copy.defaultDDPMInferenceSteps) {
            copy.defaultDDPMInferenceSteps = AppDefaults.defaultDDPMInferenceSteps
        }
        if copy.outputFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.outputFolderPath = AppDefaults.projectRoot.historyDirectory.path
        }
        if !selectedProfile.outputFormatSupport.contains(copy.exportFormat) {
            copy.exportFormat = selectedProfile.outputFormatSupport.first ?? .wav
        }
        return copy
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

    private enum CodingKeys: String, CodingKey {
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
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
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
        backendConnections = try container.decodeIfPresent([String: BackendConnectionSettings].self, forKey: .backendConnections) ?? defaults.backendConnections
        backendCatalogs = try container.decodeIfPresent([String: BackendCatalogReport].self, forKey: .backendCatalogs) ?? defaults.backendCatalogs
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
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
    }
}
