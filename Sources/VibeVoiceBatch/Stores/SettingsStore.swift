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

    func update(_ edit: (inout AppSettings) -> Void) {
        var copy = settings
        edit(&copy)
        settings = copy.normalized
    }

    func resetDefaults() {
        settings = .defaults
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: AppSettingsKeys.storageKey)
    }
}
