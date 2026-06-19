import Foundation

public final class UnavailableEngineAdapter: EngineAdapter {
    public let profile: BackendProfile
    private let explanation: String
    private let recoverySuggestion: String

    public init(
        profile: BackendProfile,
        explanation: String? = nil,
        recoverySuggestion: String? = nil
    ) {
        self.profile = profile
        self.explanation = explanation ?? "\(profile.displayName) is registered, but no generation connector is active for this runtime yet."
        self.recoverySuggestion = recoverySuggestion ?? "Choose a backend with an active connector, or configure this backend through the setup assistant before generating."
    }

    public func healthCheck() async -> BackendHealthReport {
        BackendHealthReport(
            profileID: profile.id,
            state: .unknown,
            userMessage: explanation,
            recoverySuggestion: recoverySuggestion
        )
    }

    public func listVoices() async throws -> [VoiceDescriptor] {
        []
    }

    public func listModels() async throws -> [ModelDescriptor] {
        profile.requiredModels.map { model in
            ModelDescriptor(id: model.id, displayName: model.displayName, role: profile.role)
        }
    }

    public func generate(
        _ job: GenerationJob,
        events: @escaping (GenerationEvent) -> Void
    ) async throws -> GenerationRecord {
        events(.status("Backend unavailable"))
        throw BackendError.operationUnavailable(
            GenerationErrorRecord(
                title: "\(profile.displayName) is not ready",
                explanation: explanation,
                recoverySuggestion: recoverySuggestion,
                technicalDetails: "Backend id: \(job.backendID), model id: \(job.modelID)"
            )
        )
    }

    public func cancel(jobID: String) async {}

    public func getProgress(jobID: String) async -> GenerationProgressSnapshot? {
        nil
    }

    public func normalizeOutput(_ output: EngineOutput) async throws -> NormalizedAudioOutput {
        throw BackendError.operationUnavailable(
            GenerationErrorRecord(
                title: "Output normalization unavailable",
                explanation: "\(profile.displayName) does not have an output normalizer yet.",
                recoverySuggestion: recoverySuggestion
            )
        )
    }
}
