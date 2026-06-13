import Foundation

public actor JobQueue {
    private var adaptersByBackendID: [String: any EngineAdapter]
    private var queuedJobs: [String: GenerationJob] = [:]

    public init(adapters: [any EngineAdapter] = []) {
        self.adaptersByBackendID = Dictionary(uniqueKeysWithValues: adapters.map { ($0.profile.id, $0) })
    }

    public func register(adapter: any EngineAdapter) {
        adaptersByBackendID[adapter.profile.id] = adapter
    }

    public func queuedJobIDs() -> [String] {
        Array(queuedJobs.keys)
    }

    public func submit(
        _ job: GenerationJob,
        events: @escaping (GenerationEvent) -> Void = { _ in }
    ) async throws -> GenerationRecord {
        guard let adapter = adaptersByBackendID[job.backendID] else {
            throw BackendError.backendUnavailable(
                GenerationErrorRecord(
                    title: "Backend not available",
                    explanation: "The selected backend is not registered with the job queue.",
                    recoverySuggestion: "Open Settings and choose an available backend.",
                    technicalDetails: "Missing backend id: \(job.backendID)"
                )
            )
        }

        queuedJobs[job.id] = job
        events(.status("Queued"))
        defer {
            queuedJobs[job.id] = nil
        }
        return try await adapter.generate(job, events: events)
    }

    public func cancel(jobID: String) async {
        queuedJobs[jobID] = nil
        for adapter in adaptersByBackendID.values {
            await adapter.cancel(jobID: jobID)
        }
    }
}
