import Foundation
import VibeVoiceBatchCore

@MainActor
final class AppGenerationQueueCoordinator {
    private let jobQueue: JobQueue
    private var queuedJobPayloads: [String: GenerationJob] = [:]

    init(adapters: [any EngineAdapter]) {
        jobQueue = JobQueue(adapters: adapters)
    }

    func enqueue(
        text: String,
        backendID: String,
        modelID: String,
        voice: String,
        cfgScale: String,
        ddpmInferenceSteps: Int,
        extraParameters: [String: String],
        scriptID: String? = nil,
        batchID: String? = nil,
        batchItemID: String? = nil
    ) -> (job: GenerationJob, item: QueuedGenerationItem) {
        let job = GenerationJob(
            inputText: text,
            backendID: backendID,
            modelID: modelID,
            voiceID: voice,
            settings: GenerationSettings(
                cfgScale: cfgScale,
                ddpmInferenceSteps: ddpmInferenceSteps,
                extraParameters: extraParameters
            )
        )
        queuedJobPayloads[job.id] = job
        return (job, QueuedGenerationItem(job: job, scriptID: scriptID, batchID: batchID, batchItemID: batchItemID))
    }

    func nextQueuedJob(from items: [QueuedGenerationItem]) -> GenerationJob? {
        guard let nextItem = items.first(where: { $0.status == .queued }) else {
            return nil
        }
        return queuedJobPayloads[nextItem.id]
    }

    func pausedItem(from item: QueuedGenerationItem) -> QueuedGenerationItem {
        var paused = item
        paused.status = .paused
        paused.statusMessage = "Paused"
        return paused
    }

    func pauseQueuedItems(_ items: inout [QueuedGenerationItem]) -> Bool {
        var didPause = false
        for index in items.indices where items[index].status == .queued {
            items[index] = pausedItem(from: items[index])
            didPause = true
        }
        return didPause
    }

    func resumePausedItems(_ items: inout [QueuedGenerationItem]) -> Bool {
        var didResume = false
        for index in items.indices where items[index].status == .paused {
            items[index].status = .queued
            items[index].statusMessage = "Waiting"
            didResume = true
        }
        return didResume
    }

    func cancelQueuedPayload(id: String) {
        queuedJobPayloads[id] = nil
    }

    func removePayload(id: String) {
        queuedJobPayloads[id] = nil
    }

    func submit(
        _ job: GenerationJob,
        events: @escaping (GenerationEvent) -> Void
    ) async throws -> GenerationRecord {
        try await jobQueue.submit(job, events: events)
    }

    func cancel(jobID: String) async {
        await jobQueue.cancel(jobID: jobID)
    }
}
