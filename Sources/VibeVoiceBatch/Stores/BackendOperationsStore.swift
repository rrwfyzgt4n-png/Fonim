import Foundation
import VibeVoiceBatchCore

@MainActor
final class BackendOperationsStore: ObservableObject {
    @Published private(set) var activeOperation: BackendOperationKind?
    @Published private(set) var latestResult: BackendOperationResult?
    @Published private(set) var diskUsage: BackendDiskUsageReport

    private let backendManager: BackendManager

    init(backendManager: BackendManager = BackendManager()) {
        self.backendManager = backendManager
        diskUsage = backendManager.diskUsageReport()
    }

    var isRunning: Bool {
        activeOperation != nil
    }

    func refreshDiskUsage() {
        diskUsage = backendManager.diskUsageReport()
    }

    func run(_ kind: BackendOperationKind, profile: BackendProfile, completion: ((BackendOperationResult) -> Void)? = nil) {
        guard activeOperation == nil else { return }
        activeOperation = kind
        latestResult = BackendOperationResult(
            profileID: profile.id,
            kind: kind,
            status: .skipped,
            startedAt: Date(),
            message: "\(kind.displayName) is running."
        )

        Task {
            let result = await backendManager.performOperationAsync(kind, for: profile)
            latestResult = result
            activeOperation = nil
            refreshDiskUsage()
            completion?(result)
        }
    }
}
