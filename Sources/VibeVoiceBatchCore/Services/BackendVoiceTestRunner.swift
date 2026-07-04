import Foundation

public struct BackendVoiceTestRequest: Equatable {
    public var profile: BackendProfile
    public var modelID: String
    public var voiceID: String
    public var cfgScale: String
    public var ddpmInferenceSteps: Int?
    public var sampleText: String

    public init(
        profile: BackendProfile,
        modelID: String,
        voiceID: String,
        cfgScale: String = AppDefaults.defaultCFGScale,
        ddpmInferenceSteps: Int? = AppDefaults.defaultDDPMInferenceSteps,
        sampleText: String = BackendVoiceTestRequest.defaultSampleText
    ) {
        self.profile = profile
        self.modelID = modelID
        self.voiceID = voiceID
        self.cfgScale = cfgScale
        self.ddpmInferenceSteps = ddpmInferenceSteps
        self.sampleText = sampleText
    }

    public static let defaultSampleText = "This is a short local narration test from the setup assistant."
}

public final class BackendVoiceTestRunner {
    public typealias AdapterFactory = (_ profile: BackendProfile, _ projectRoot: URL) -> any EngineAdapter

    private let projectRoot: URL
    private let backendManager: BackendManager
    private let adapterFactory: AdapterFactory
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.backend-voice-test")
    private var activeQueue: JobQueue?
    private var activeJobID: String?

    public init(
        projectRoot: URL = AppDefaults.projectRoot,
        backendManager: BackendManager? = nil,
        adapterFactory: @escaping AdapterFactory = BackendVoiceTestRunner.defaultAdapterFactory
    ) {
        self.projectRoot = projectRoot
        self.backendManager = backendManager ?? BackendManager(projectRoot: projectRoot)
        self.adapterFactory = adapterFactory
    }

    public func run(
        _ request: BackendVoiceTestRequest,
        events: @escaping (GenerationEvent) -> Void = { _ in }
    ) async throws -> GenerationRecord {
        let health = await backendManager.healthReportAsync(for: request.profile)
        guard health.state.canStartGeneration else {
            throw BackendError.backendUnavailable(
                GenerationErrorRecord(
                    title: "Backend not ready",
                    explanation: health.userMessage,
                    recoverySuggestion: health.recoverySuggestion,
                    technicalDetails: health.technicalDetails
                )
            )
        }

        let adapter = adapterFactory(request.profile, projectRoot)
        let queue = JobQueue(adapters: [adapter])
        let job = GenerationJob(
            id: "setup-test-\(UUID().uuidString)",
            inputText: request.sampleText,
            backendID: request.profile.id,
            modelID: request.modelID,
            voiceID: request.voiceID,
            settings: GenerationSettings(
                cfgScale: request.cfgScale,
                ddpmInferenceSteps: request.ddpmInferenceSteps,
                extraParameters: request.profile.generationExtraParameters
            )
        )

        stateQueue.sync {
            activeQueue = queue
            activeJobID = job.id
        }
        defer {
            stateQueue.sync {
                activeQueue = nil
                activeJobID = nil
            }
        }

        return try await queue.submit(job, events: events)
    }

    public func cancelActiveTest() async {
        let active = stateQueue.sync { (activeQueue, activeJobID) }
        guard let queue = active.0, let jobID = active.1 else { return }
        await queue.cancel(jobID: jobID)
    }

    public static func defaultAdapterFactory(profile: BackendProfile, projectRoot: URL) -> any EngineAdapter {
        EngineAdapterRegistry.default.adapter(for: profile, projectRoot: projectRoot)
    }
}

public extension BackendProfile {
    var generationExtraParameters: [String: String] {
        guard engineType == .kokoro || engineType == .chatterbox else { return [:] }
        var parameters: [String: String] = [:]
        if let generateEndpoint {
            parameters["generate_endpoint"] = generateEndpoint.absoluteString
        }
        if let healthCheckURL {
            parameters["health_url"] = healthCheckURL.absoluteString
        }
        if let dockerImage {
            parameters["docker_image"] = dockerImage
        }
        parameters["backend_display_name"] = displayName
        parameters["response_format"] = "wav"
        if engineType == .kokoro {
            parameters["model"] = requiredModels.first?.id ?? "tts-1"
            parameters["speed"] = "1.0"
        } else if engineType == .chatterbox {
            let modelID = requiredModels.first?.id ?? ChatterboxModelCatalog.turboID
            parameters["model"] = modelID
            parameters["model_repo_id"] = ChatterboxModelCatalog.definition(for: modelID)?
                .configuration["model.repo_id"] ?? modelID
            parameters["output_format"] = "wav"
            parameters["split_text"] = "true"
            parameters["chunk_size"] = "120"
            parameters["temperature"] = "0.8"
            parameters["exaggeration"] = "1.3"
            parameters["cfg_weight"] = "0.5"
            parameters["seed"] = "0"
            parameters["speed_factor"] = "1.0"
            parameters["language"] = "en"
        }
        return parameters
    }
}
