import Foundation
import VibeVoiceBatchCore

@MainActor
enum VoiceLibrarySummary {
    static func catalogVoiceCount(settingsStore: SettingsStore) -> Int {
        BackendProfiles.all.reduce(0) { total, profile in
            total + settingsStore.voiceOptions(for: profile).count
        }
    }

    static func label(settingsStore: SettingsStore) -> String {
        "\(catalogVoiceCount(settingsStore: settingsStore)) catalog voices"
    }
}
