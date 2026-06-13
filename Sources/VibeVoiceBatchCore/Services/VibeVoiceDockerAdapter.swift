import Foundation

public final class VibeVoiceDockerAdapter: EngineAdapter {
    public let profile: BackendProfile
    private let projectRoot: URL
    private let backendManager: BackendManager

    public init(
        profile: BackendProfile = BackendProfiles.vibeVoiceTTS,
        projectRoot: URL = AppDefaults.projectRoot,
        backendManager: BackendManager? = nil
    ) {
        self.profile = profile
        self.projectRoot = projectRoot
        self.backendManager = backendManager ?? BackendManager(projectRoot: projectRoot)
    }

    public func healthCheck() async -> BackendHealthReport {
        backendManager.healthReport(for: profile)
    }

    public func listVoices() async throws -> [VoiceDescriptor] {
        AppDefaults.availableVoices.map { voice in
            VoiceDescriptor(id: voice, displayName: voice, traits: voiceTraits(for: voice))
        }
    }

    public func listModels() async throws -> [ModelDescriptor] {
        [
            ModelDescriptor(
                id: AppDefaults.modelPath,
                displayName: "VibeVoice Realtime 0.5B",
                role: profile.role
            )
        ]
    }

    public func generate(
        _ job: GenerationJob,
        events: @escaping (GenerationEvent) -> Void
    ) async throws -> GenerationRecord {
        throw BackendError.operationUnavailable(
            GenerationErrorRecord(
                title: "Adapter generation is not connected yet",
                explanation: "The VibeVoice Docker adapter profile is available, but the current generation path has not been fully migrated behind JobQueue.",
                recoverySuggestion: "Use the existing Generate WAV flow while the next architecture pass moves it behind the adapter.",
                technicalDetails: "Job id: \(job.id), command: \(makeDockerCommand(for: job).displayCommand)"
            )
        )
    }

    public func cancel(jobID: String) async {
        // The current cancellation path is owned by DockerGenerationRunner until Phase 2 migration.
    }

    public func getProgress(jobID: String) async -> GenerationProgressSnapshot? {
        nil
    }

    public func normalizeOutput(_ output: EngineOutput) async throws -> NormalizedAudioOutput {
        let duration = output.format == .wav ? try WaveAudioInspector.durationSeconds(for: output.fileURL) : nil
        return NormalizedAudioOutput(
            fileURL: output.fileURL,
            format: output.format,
            durationSeconds: duration,
            sampleRate: output.sampleRate
        )
    }

    public func makeDockerCommand(for job: GenerationJob) -> DockerRunCommand {
        DockerCommandBuilder.make(
            sessionID: job.id,
            voice: job.voiceID,
            cfgScale: job.settings.cfgScale,
            ddpmInferenceSteps: job.settings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps,
            projectRoot: projectRoot
        )
    }

    private func voiceTraits(for voice: String) -> [String] {
        var traits: [String] = []
        if voice.hasSuffix("_man") {
            traits.append("man")
        }
        if voice.hasSuffix("_woman") {
            traits.append("woman")
        }
        if let language = voice.split(separator: "-").first {
            traits.append(String(language))
        }
        return traits
    }
}
