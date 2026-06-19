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
            return catalog.models
        }
        return profile.requiredModels.map { model in
            BackendCatalogModel(id: model.id, displayName: model.displayName)
        }
    }

    func voiceOptions(for profile: BackendProfile) -> [BackendCatalogVoice] {
        settings.voiceOptions(for: profile)
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
            var connection = settings.backendConnection(for: profileID)
            if !catalog.models.isEmpty {
                connection.modelID = catalog.models[0].id
            }
            if !catalog.voices.isEmpty {
                connection.defaultVoice = preferredVoice(in: catalog.voices, settings: settings, connection: connection)
            }
            settings.backendConnections[profileID] = connection
            if settings.defaultBackendID == profileID {
                if !catalog.models.isEmpty,
                   !catalog.models.contains(where: { $0.id == settings.defaultModelID }) {
                    settings.defaultModelID = catalog.models[0].id
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
