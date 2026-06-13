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
        setupMode: BackendSetupMode = .simple
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
    }

    public static let defaults = AppSettings()

    public var normalized: AppSettings {
        var copy = self
        if !BackendProfiles.all.contains(where: { $0.id == copy.defaultBackendID }) {
            copy.defaultBackendID = BackendProfiles.vibeVoiceTTS.id
        }
        let selectedProfile = BackendProfiles.all.first { $0.id == copy.defaultBackendID } ?? BackendProfiles.vibeVoiceTTS
        if !selectedProfile.requiredModels.contains(where: { $0.id == copy.defaultModelID }) {
            copy.defaultModelID = selectedProfile.requiredModels.first?.id ?? AppDefaults.modelPath
        }
        if !AppDefaults.availableVoices.contains(copy.defaultVoice) {
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
}
