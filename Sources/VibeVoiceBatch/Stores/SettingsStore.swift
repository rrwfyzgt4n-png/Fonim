import Foundation
import VibeVoiceBatchCore

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings {
        didSet {
            persist()
        }
    }
    @Published private(set) var settingsRecoveryNotes: [AppSettingsRecoveryNote]
    @Published private(set) var settingsRecoverySummary: String?

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let loadResult = AppSettings.loadResult(from: userDefaults.data(forKey: AppSettingsKeys.storageKey))
        settings = loadResult.settings
        settingsRecoveryNotes = loadResult.recoveryNotes
        settingsRecoverySummary = loadResult.recoverySummary
        if loadResult.needsPersistence {
            persist()
        }
    }

    var selectedBackendProfile: BackendProfile {
        settings.selectedBackendProfile
    }

    func backendProfile(id: String) -> BackendProfile {
        settings.backendProfile(id: id)
    }

    func backendConnection(for profileID: String) -> BackendConnectionSettings {
        settings.backendConnection(for: profileID)
    }

    func backendCatalog(for profileID: String) -> BackendCatalogReport? {
        settings.backendCatalog(for: profileID)
    }

    func modelOptions(for profile: BackendProfile) -> [BackendCatalogModel] {
        if let catalog = settings.backendCatalog(for: profile.id),
           !catalog.models.isEmpty {
            let models = availableModels(in: catalog.models, for: profile)
            if !models.isEmpty {
                return models
            }
        }
        return profile.requiredModels.map { model in
            BackendCatalogModel(id: model.id, displayName: model.displayName)
        }
    }

    func voiceOptions(for profile: BackendProfile) -> [BackendCatalogVoice] {
        settings.voiceOptions(for: profile)
    }

    func generationVoiceOptions(for profile: BackendProfile) -> [BackendCatalogVoice] {
        let voices = voiceOptions(for: profile)
        guard profile.engineType == .chatterbox else {
            return voices
        }

        let modelID = settings.defaultBackendID == profile.id ?
            settings.defaultModelID :
            profile.requiredModels.first?.id ?? settings.defaultModelID
        let languageCode = settings.chatterboxLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ChatterboxModelCatalog.languageCodes(for: modelID).contains(languageCode) else {
            return []
        }

        return voices.filter {
            ChatterboxVoiceCatalog.voice($0, supportsOutputLanguage: languageCode)
        }
    }

    func update(_ edit: (inout AppSettings) -> Void) {
        var copy = settings
        edit(&copy)
        apply(copy.normalizationResult())
    }

    func resetDefaults() {
        settingsRecoveryNotes = []
        settingsRecoverySummary = nil
        settings = .defaults
    }

    func selectSetupMode(_ mode: BackendSetupMode) {
        update { $0.setupMode = mode }
    }

    func markSetupAssistantCompleted() {
        update { $0.hasCompletedSetupAssistant = true }
    }

    func updateBackendConnection(
        for profileID: String,
        edit: (inout BackendConnectionSettings) -> Void
    ) {
        update { settings in
            var connection = settings.backendConnections[profileID] ??
                BackendConnectionSettings.defaultSettings(for: profileID) ??
                BackendConnectionSettings()
            edit(&connection)
            settings.backendConnections[profileID] = connection
            if settings.defaultBackendID == profileID {
                let resolved = settings.backendProfile(id: profileID)
                if !resolved.requiredModels.contains(where: { $0.id == settings.defaultModelID }) {
                    settings.defaultModelID = resolved.requiredModels.first?.id ?? settings.defaultModelID
                }
            }
        }
    }

    func saveBackendCatalog(_ catalog: BackendCatalogReport, for profileID: String) {
        update { settings in
            settings.backendCatalogs[profileID] = catalog
            let profile = settings.backendProfile(id: profileID)
            let catalogModels = availableModels(in: catalog.models, for: profile)
            var connection = settings.backendConnection(for: profileID)
            if !catalogModels.isEmpty {
                connection.modelID = preferredModel(in: catalogModels, settings: settings, connection: connection)
            }
            if !catalog.voices.isEmpty {
                connection.defaultVoice = preferredVoice(in: catalog.voices, settings: settings, connection: connection)
            }
            settings.backendConnections[profileID] = connection
            if settings.defaultBackendID == profileID {
                if !catalogModels.isEmpty,
                   !catalogModels.contains(where: { $0.id == settings.defaultModelID }) {
                    settings.defaultModelID = preferredModel(in: catalogModels, settings: settings, connection: connection)
                }
                if !catalog.voices.isEmpty,
                   !catalog.voices.contains(where: { $0.id == settings.defaultVoice }) {
                    settings.defaultVoice = preferredVoice(in: catalog.voices, settings: settings, connection: connection)
                }
            }
        }
    }

    private func preferredVoice(
        in voices: [BackendCatalogVoice],
        settings: AppSettings,
        connection: BackendConnectionSettings
    ) -> String {
        if let saved = voices.first(where: { $0.id == settings.defaultVoice })?.id {
            return saved
        }
        if let connected = connection.trimmedDefaultVoice,
           let match = voices.first(where: { $0.id == connected })?.id {
            return match
        }
        return voices[0].id
    }

    private func availableModels(
        in models: [BackendCatalogModel],
        for profile: BackendProfile
    ) -> [BackendCatalogModel] {
        guard profile.engineType == .chatterbox else {
            return models
        }
        return models.filter { ChatterboxModelCatalog.isSupportedModel($0.id) }
    }

    private func preferredModel(
        in models: [BackendCatalogModel],
        settings: AppSettings,
        connection: BackendConnectionSettings
    ) -> String {
        if let saved = models.first(where: { $0.id == settings.defaultModelID })?.id {
            return saved
        }
        if let connected = connection.trimmedModelID,
           let match = models.first(where: { $0.id == connected })?.id {
            return match
        }
        if let loaded = models.first(where: { $0.isLoaded == true })?.id {
            return loaded
        }
        return models[0].id
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: AppSettingsKeys.storageKey)
    }

    private func apply(_ result: AppSettingsNormalizationResult) {
        settingsRecoveryNotes = result.recoveryNotes
        settingsRecoverySummary = result.recoverySummary
        settings = result.settings
    }
}
