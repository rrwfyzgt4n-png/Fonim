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

    public init(
        defaultBackendID: String = BackendProfiles.vibeVoiceTTS.id,
        defaultModelID: String = AppDefaults.modelPath,
        defaultVoice: String = AppDefaults.defaultVoice,
        defaultCFGScale: String = AppDefaults.defaultCFGScale,
        defaultDDPMInferenceSteps: Int = AppDefaults.defaultDDPMInferenceSteps,
        outputFolderPath: String = AppDefaults.projectRoot.historyDirectory.path,
        exportFormat: AudioOutputFormat = .wav,
        showAdvancedGenerationControls: Bool = true,
        refreshBackendStatusOnLaunch: Bool = true
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
    }

    public static let defaults = AppSettings()

    public var normalized: AppSettings {
        var copy = self
        if !BackendProfiles.all.contains(where: { $0.id == copy.defaultBackendID }) {
            copy.defaultBackendID = BackendProfiles.vibeVoiceTTS.id
        }
        if copy.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.defaultModelID = AppDefaults.modelPath
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
        if !BackendProfiles.vibeVoiceTTS.outputFormatSupport.contains(copy.exportFormat) {
            copy.exportFormat = .wav
        }
        return copy
    }
}
