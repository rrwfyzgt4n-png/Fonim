import Foundation
import VibeVoiceBatchCore

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings {
        didSet {
            persist()
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: AppSettingsKeys.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded.normalized
        } else {
            settings = .defaults
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

    func update(_ edit: (inout AppSettings) -> Void) {
        var copy = settings
        edit(&copy)
        settings = copy.normalized
    }

    func resetDefaults() {
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

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: AppSettingsKeys.storageKey)
    }
}
