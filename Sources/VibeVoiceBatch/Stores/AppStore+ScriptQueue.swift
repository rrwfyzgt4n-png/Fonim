import Foundation
import VibeVoiceBatchCore

extension AppStore {
    func queueImportedScripts(_ scripts: [NarrationScript], batch: NarrationBatch?) {
        let batchItemsByScriptID = Dictionary(uniqueKeysWithValues: (batch?.items ?? []).map { ($0.scriptID, $0) })
        var firstQueuedJobID: String?
        for script in scripts {
            let batchItem = batchItemsByScriptID[script.id]
            let queuedBefore = queuedGenerations.count
            enqueueGeneration(
                text: script.text,
                voice: script.defaultVoice,
                cfgScale: script.defaultSettings.cfgScale,
                ddpmInferenceSteps: script.defaultSettings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps,
                backendID: script.defaultBackendID,
                modelID: script.defaultModelID,
                scriptID: script.id,
                batchID: batch?.id,
                batchItemID: batchItem?.id,
                selectQueuedItem: false
            )
            if firstQueuedJobID == nil, queuedGenerations.indices.contains(queuedBefore) {
                firstQueuedJobID = queuedGenerations[queuedBefore].id
            }
        }
        selectedQueueItemID = firstQueuedJobID
        requestSelection(.section(.batches))
        statusMessage = "Queued \(scripts.count) imported scripts"
    }

    func cancelQueuedGenerations(batchID: String) {
        let matchingItems = queuedGenerations.filter { $0.batchID == batchID && !$0.status.isTerminal }
        for item in matchingItems {
            cancelQueuedGeneration(item)
        }
        queuedGenerations.removeAll { $0.batchID == batchID && $0.status != .running }
    }

    func finishWorkspaceQueueItem(_ item: QueuedGenerationItem, record: GenerationRecord) {
        defer {
            if record.status == .completed || record.status == .cancelled {
                queuedGenerations.removeAll { $0.id == item.id }
            }
        }

        guard item.scriptID != nil || item.batchID != nil else { return }
        let workspaceFileStore = WorkspaceFileStore()
        var didUpdateWorkspace = false

        do {
            if record.status == .completed, let scriptID = item.scriptID {
                let script = try workspaceFileStore.appendGenerationSession(record.id, toScript: scriptID)
                if let projectID = script.projectID {
                    _ = try workspaceFileStore.attachGenerationSessions([record.id], toProject: projectID)
                }
                didUpdateWorkspace = true
            }

            if let batchID = item.batchID, let batchItemID = item.batchItemID {
                _ = try workspaceFileStore.recordBatchItemGeneration(
                    batchID: batchID,
                    itemID: batchItemID,
                    sessionID: record.id,
                    status: WorkspaceItemStatus(recordStatus: record.status),
                    error: record.error?.explanation
                )
                didUpdateWorkspace = true
            }
        } catch {
            statusMessage = "Workspace record could not be updated"
        }

        if didUpdateWorkspace {
            NotificationCenter.default.post(name: .fonimWorkspaceDidChange, object: nil)
        }
    }
}

private extension WorkspaceItemStatus {
    init(recordStatus: GenerationRecordStatus) {
        switch recordStatus {
        case .queued:
            self = .queued
        case .running:
            self = .running
        case .completed:
            self = .completed
        case .failed:
            self = .failed
        case .cancelled:
            self = .cancelled
        }
    }
}
