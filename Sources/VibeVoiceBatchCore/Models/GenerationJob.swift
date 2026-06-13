import Foundation

public struct GenerationSettings: Codable, Equatable, Sendable {
    public var cfgScale: String
    public var ddpmInferenceSteps: Int?
    public var temperature: Double?
    public var seed: Int?
    public var sampleRate: Int?
    public var outputFormat: AudioOutputFormat
    public var extraParameters: [String: String]

    public init(
        cfgScale: String = AppDefaults.defaultCFGScale,
        ddpmInferenceSteps: Int? = AppDefaults.defaultDDPMInferenceSteps,
        temperature: Double? = nil,
        seed: Int? = nil,
        sampleRate: Int? = nil,
        outputFormat: AudioOutputFormat = .wav,
        extraParameters: [String: String] = [:]
    ) {
        self.cfgScale = cfgScale
        self.ddpmInferenceSteps = ddpmInferenceSteps
        self.temperature = temperature
        self.seed = seed
        self.sampleRate = sampleRate
        self.outputFormat = outputFormat
        self.extraParameters = extraParameters
    }
}

public struct GenerationJob: Codable, Equatable, Identifiable {
    public let id: String
    public var createdAt: Date
    public var inputText: String
    public var backendID: String
    public var modelID: String
    public var voiceID: String
    public var settings: GenerationSettings
    public var outputDirectory: URL?

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        inputText: String,
        backendID: String = BackendProfiles.vibeVoiceTTS.id,
        modelID: String = AppDefaults.modelPath,
        voiceID: String = AppDefaults.defaultVoice,
        settings: GenerationSettings = GenerationSettings(),
        outputDirectory: URL? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.inputText = inputText
        self.backendID = backendID
        self.modelID = modelID
        self.voiceID = voiceID
        self.settings = settings
        self.outputDirectory = outputDirectory
    }
}

public struct GenerationProgressSnapshot: Codable, Equatable {
    public var jobID: String
    public var fractionComplete: Double?
    public var currentStep: Int?
    public var totalSteps: Int?
    public var elapsedSeconds: Double?
    public var estimatedRemainingSeconds: Double?
    public var message: String

    public init(
        jobID: String,
        fractionComplete: Double? = nil,
        currentStep: Int? = nil,
        totalSteps: Int? = nil,
        elapsedSeconds: Double? = nil,
        estimatedRemainingSeconds: Double? = nil,
        message: String
    ) {
        self.jobID = jobID
        self.fractionComplete = fractionComplete
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.elapsedSeconds = elapsedSeconds
        self.estimatedRemainingSeconds = estimatedRemainingSeconds
        self.message = message
    }
}
