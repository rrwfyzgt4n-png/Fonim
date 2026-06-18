import Foundation

public enum AppSettingsRecoveryReason: String, Codable, Equatable, Sendable {
    case decodeFailed
    case schemaMigrated
    case futureSchema
    case missingBackendConnection
    case invalidBackend
    case invalidModel
    case invalidVoice
    case invalidCFGScale
    case invalidDDPMInferenceSteps
    case invalidChatterboxSetting
    case emptyOutputFolder
    case unsupportedExportFormat
}

public struct AppSettingsRecoveryNote: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(reason.rawValue)-\(field)-\(message)" }
    public var reason: AppSettingsRecoveryReason
    public var field: String
    public var message: String
    public var technicalDetails: String?

    public init(
        reason: AppSettingsRecoveryReason,
        field: String,
        message: String,
        technicalDetails: String? = nil
    ) {
        self.reason = reason
        self.field = field
        self.message = message
        self.technicalDetails = technicalDetails
    }
}

public struct AppSettingsNormalizationResult: Equatable, Sendable {
    public var settings: AppSettings
    public var recoveryNotes: [AppSettingsRecoveryNote]

    public init(settings: AppSettings, recoveryNotes: [AppSettingsRecoveryNote] = []) {
        self.settings = settings
        self.recoveryNotes = recoveryNotes
    }

    public var didRecover: Bool {
        !recoveryNotes.isEmpty
    }

    public var needsPersistence: Bool {
        didRecover
    }

    public var recoverySummary: String? {
        guard didRecover else { return nil }
        return recoveryNotes.map(\.message).joined(separator: "\n")
    }

    public static func normalizing(_ settings: AppSettings) -> AppSettingsNormalizationResult {
        var copy = settings
        var notes: [AppSettingsRecoveryNote] = []

        func record(
            _ reason: AppSettingsRecoveryReason,
            field: String,
            message: String,
            technicalDetails: String? = nil
        ) {
            notes.append(
                AppSettingsRecoveryNote(
                    reason: reason,
                    field: field,
                    message: message,
                    technicalDetails: technicalDetails
                )
            )
        }

        func clampDouble(
            _ value: inout Double,
            field: String,
            range: ClosedRange<Double>,
            fallback: Double
        ) {
            guard value.isFinite else {
                value = fallback
                record(
                    .invalidChatterboxSetting,
                    field: field,
                    message: "A saved Chatterbox setting was unreadable, so its default was restored."
                )
                return
            }
            if value < range.lowerBound || value > range.upperBound {
                let oldValue = value
                value = min(range.upperBound, max(range.lowerBound, value))
                record(
                    .invalidChatterboxSetting,
                    field: field,
                    message: "A saved Chatterbox setting was outside the supported range, so \(value) was selected.",
                    technicalDetails: String(oldValue)
                )
            }
        }

        if copy.schemaVersion < AppSettingsKeys.currentSchemaVersion {
            record(
                .schemaMigrated,
                field: "schemaVersion",
                message: "Settings were updated to the current format.",
                technicalDetails: "from=\(copy.schemaVersion) to=\(AppSettingsKeys.currentSchemaVersion)"
            )
            copy.schemaVersion = AppSettingsKeys.currentSchemaVersion
        } else if copy.schemaVersion > AppSettingsKeys.currentSchemaVersion {
            record(
                .futureSchema,
                field: "schemaVersion",
                message: "Settings were saved by a newer version of the app; supported values were preserved.",
                technicalDetails: "from=\(copy.schemaVersion) to=\(AppSettingsKeys.currentSchemaVersion)"
            )
            copy.schemaVersion = AppSettingsKeys.currentSchemaVersion
        }

        for profile in BackendProfiles.all {
            if copy.backendConnections[profile.id] == nil,
               let defaults = BackendConnectionSettings.defaultSettings(for: profile.id) {
                copy.backendConnections[profile.id] = defaults
                record(
                    .missingBackendConnection,
                    field: "backendConnections.\(profile.id)",
                    message: "Default connection settings were added for \(profile.displayName)."
                )
            }
        }

        if !BackendProfiles.all.contains(where: { $0.id == copy.defaultBackendID }) {
            let oldValue = copy.defaultBackendID
            copy.defaultBackendID = BackendProfiles.vibeVoiceTTS.id
            record(
                .invalidBackend,
                field: "defaultBackendID",
                message: "The saved default backend was unavailable, so VibeVoiceTTS was selected.",
                technicalDetails: oldValue
            )
        }

        let selectedProfile = copy.backendProfile(id: copy.defaultBackendID)
        let selectedCatalog = copy.backendCatalog(for: copy.defaultBackendID)
        let catalogModels = selectedCatalog?.models ?? []
        if !catalogModels.isEmpty {
            if !catalogModels.contains(where: { $0.id == copy.defaultModelID }) {
                let oldValue = copy.defaultModelID
                copy.defaultModelID = catalogModels[0].id
                record(
                    .invalidModel,
                    field: "defaultModelID",
                    message: "The saved model was unavailable, so \(copy.defaultModelID) was selected.",
                    technicalDetails: oldValue
                )
            }
        } else if !selectedProfile.requiredModels.contains(where: { $0.id == copy.defaultModelID }) {
            let oldValue = copy.defaultModelID
            copy.defaultModelID = selectedProfile.requiredModels.first?.id ?? AppDefaults.modelPath
            record(
                .invalidModel,
                field: "defaultModelID",
                message: "The saved model was unavailable, so \(copy.defaultModelID) was selected.",
                technicalDetails: oldValue
            )
        }

        let selectedConnection = copy.backendConnection(for: copy.defaultBackendID)
        if selectedProfile.engineType == .kokoro || selectedProfile.engineType == .chatterbox {
            let catalogVoices = selectedCatalog?.voices ?? []
            if !catalogVoices.isEmpty {
                if !catalogVoices.contains(where: { $0.id == copy.defaultVoice }) {
                    let oldValue = copy.defaultVoice
                    copy.defaultVoice = catalogVoices[0].id
                    record(
                        .invalidVoice,
                        field: "defaultVoice",
                        message: "The saved voice was unavailable, so \(copy.defaultVoice) was selected.",
                        technicalDetails: oldValue
                    )
                }
            } else if copy.defaultVoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let oldValue = copy.defaultVoice
                copy.defaultVoice = selectedConnection.trimmedDefaultVoice ?? (selectedProfile.engineType == .chatterbox ? "Emily.wav" : "af_heart")
                record(
                    .invalidVoice,
                    field: "defaultVoice",
                    message: "The saved voice was empty, so \(copy.defaultVoice) was selected.",
                    technicalDetails: oldValue
                )
            }
        } else if !AppDefaults.availableVoices.contains(copy.defaultVoice) {
            let oldValue = copy.defaultVoice
            copy.defaultVoice = AppDefaults.defaultVoice
            record(
                .invalidVoice,
                field: "defaultVoice",
                message: "The saved voice was unavailable, so \(copy.defaultVoice) was selected.",
                technicalDetails: oldValue
            )
        }

        if !AppDefaults.availableCFGScales.contains(copy.defaultCFGScale) {
            let oldValue = copy.defaultCFGScale
            copy.defaultCFGScale = AppDefaults.defaultCFGScale
            record(
                .invalidCFGScale,
                field: "defaultCFGScale",
                message: "The saved CFG value was unsupported, so \(copy.defaultCFGScale) was selected.",
                technicalDetails: oldValue
            )
        }

        if !AppDefaults.availableDDPMInferenceSteps.contains(copy.defaultDDPMInferenceSteps) {
            let oldValue = copy.defaultDDPMInferenceSteps
            copy.defaultDDPMInferenceSteps = AppDefaults.defaultDDPMInferenceSteps
            record(
                .invalidDDPMInferenceSteps,
                field: "defaultDDPMInferenceSteps",
                message: "The saved inference step value was unsupported, so \(copy.defaultDDPMInferenceSteps) was selected.",
                technicalDetails: String(oldValue)
            )
        }

        if copy.outputFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.outputFolderPath = AppDefaults.projectRoot.historyDirectory.path
            record(
                .emptyOutputFolder,
                field: "outputFolderPath",
                message: "The saved output folder was empty, so the default history folder was selected."
            )
        }

        if !selectedProfile.outputFormatSupport.contains(copy.exportFormat) {
            let oldValue = copy.exportFormat
            copy.exportFormat = selectedProfile.outputFormatSupport.first ?? .wav
            record(
                .unsupportedExportFormat,
                field: "exportFormat",
                message: "The saved export format was unsupported by \(selectedProfile.displayName), so \(copy.exportFormat.rawValue.uppercased()) was selected.",
                technicalDetails: oldValue.rawValue
            )
        }

        clampDouble(
            &copy.chatterboxTemperature,
            field: "chatterboxTemperature",
            range: 0.0...2.0,
            fallback: 0.8
        )
        clampDouble(
            &copy.chatterboxExaggeration,
            field: "chatterboxExaggeration",
            range: 0.0...3.0,
            fallback: 1.3
        )
        clampDouble(
            &copy.chatterboxCFGWeight,
            field: "chatterboxCFGWeight",
            range: 0.0...2.0,
            fallback: 0.5
        )
        clampDouble(
            &copy.chatterboxSpeedFactor,
            field: "chatterboxSpeedFactor",
            range: 0.25...4.0,
            fallback: 1.0
        )
        if copy.chatterboxSeed < 0 {
            let oldValue = copy.chatterboxSeed
            copy.chatterboxSeed = 0
            record(
                .invalidChatterboxSetting,
                field: "chatterboxSeed",
                message: "The saved Chatterbox seed was invalid, so 0 was selected.",
                technicalDetails: String(oldValue)
            )
        }
        if copy.chatterboxChunkSize < 50 || copy.chatterboxChunkSize > 500 {
            let oldValue = copy.chatterboxChunkSize
            copy.chatterboxChunkSize = min(500, max(50, copy.chatterboxChunkSize))
            record(
                .invalidChatterboxSetting,
                field: "chatterboxChunkSize",
                message: "The saved Chatterbox chunk size was outside the supported range, so \(copy.chatterboxChunkSize) was selected.",
                technicalDetails: String(oldValue)
            )
        }
        if copy.chatterboxLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.chatterboxLanguage = "en"
            record(
                .invalidChatterboxSetting,
                field: "chatterboxLanguage",
                message: "The saved Chatterbox language was empty, so English was selected."
            )
        }

        return AppSettingsNormalizationResult(settings: copy, recoveryNotes: notes)
    }
}
