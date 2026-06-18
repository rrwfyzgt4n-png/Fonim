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
        extraParameters: [String: String]
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
        return (job, QueuedGenerationItem(job: job))
    }

    func nextQueuedJob(from items: [QueuedGenerationItem]) -> GenerationJob? {
        guard let nextItem = items.first(where: { $0.status == .queued }) else {
            return nil
        }
        return queuedJobPayloads[nextItem.id]
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
