import Foundation
import VibeVoiceBatchCore

@MainActor
final class AppBackendStatusCoordinator {
    private let backendManager: BackendManager
    private let adaptersByBackendID: [String: any EngineAdapter]
    private let supportedBackendIDs: Set<String>

    init(
        backendManager: BackendManager = BackendManager(),
        adapterRegistry: EngineAdapterRegistry = .default,
        profiles: [BackendProfile] = BackendProfiles.all,
        projectRoot: URL = AppDefaults.projectRoot,
        adapters: [any EngineAdapter]? = nil
    ) {
        self.backendManager = backendManager
        let resolvedAdapters = adapters ?? adapterRegistry.adapters(for: profiles, projectRoot: projectRoot)
        adaptersByBackendID = Dictionary(uniqueKeysWithValues: resolvedAdapters.map { ($0.profile.id, $0) })
        supportedBackendIDs = adapterRegistry.supportedBackendIDs(for: profiles)
    }

    func hasGenerationAdapter(for profile: BackendProfile) -> Bool {
        supportedBackendIDs.contains(profile.id)
    }

    func refreshStatus(for profile: BackendProfile) async -> BackendStatusSnapshot {
        let report: BackendHealthReport
        if profile.id == BackendProfiles.vibeVoiceTTS.id,
           let adapter = adaptersByBackendID[profile.id] {
            report = await adapter.healthCheck()
        } else if BackendProfiles.baseProfile(id: profile.id) != nil {
            report = await backendManager.healthReportAsync(for: profile)
        } else {
            report = BackendHealthReport(
                profileID: profile.id,
                state: .unknown,
                userMessage: "\(profile.displayName) is registered, but no engine adapter is available.",
                recoverySuggestion: "Choose an installed backend before generating."
            )
        }

        return BackendStatusSnapshot(profile: profile, report: report)
    }

    func performOperation(_ kind: BackendOperationKind, for profile: BackendProfile) async -> BackendOperationResult {
        await backendManager.performOperationAsync(kind, for: profile)
    }
}
