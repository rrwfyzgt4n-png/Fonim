import Foundation
import VibeVoiceBatchCore

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var projects: [NarrationProject] = []
    @Published private(set) var scripts: [NarrationScript] = []
    @Published private(set) var batches: [NarrationBatch] = []
    @Published private(set) var isRefreshing = false
    @Published var alertMessage: String?

    private let fileStore: WorkspaceFileStore

    init(fileStore: WorkspaceFileStore = WorkspaceFileStore()) {
        self.fileStore = fileStore
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        do {
            let snapshot = try fileStore.loadSnapshot()
            projects = snapshot.projects
            scripts = snapshot.scripts
            batches = snapshot.batches
        } catch {
            alertMessage = "Could not load workspace: \(error.localizedDescription)"
        }
        isRefreshing = false
    }

    func scripts(for project: NarrationProject) -> [NarrationScript] {
        scripts.filter { project.scriptIDs.contains($0.id) }
    }

    func batches(for project: NarrationProject) -> [NarrationBatch] {
        batches.filter { project.batchIDs.contains($0.id) }
    }
}
