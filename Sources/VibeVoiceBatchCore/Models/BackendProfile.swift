import Foundation

public enum EngineType: String, Codable, CaseIterable, Equatable, Sendable {
    case vibeVoiceTTS
    case kokoro
    case comfyUITTS
    case f5TTS
    case chatterbox
    case cosyVoice
    case custom
}

public enum BackendRuntime: String, Codable, CaseIterable, Equatable, Sendable {
    case docker
    case localPython
    case comfyUI
    case native
    case externalService
}

public enum BackendInstallMethod: String, Codable, CaseIterable, Equatable, Sendable {
    case managedDockerImage
    case localPythonEnvironment
    case externalServer
    case bundledNative
    case manual
}

public enum SystemArchitecture: String, Codable, CaseIterable, Equatable, Sendable {
    case appleSilicon
    case intel
    case universal
}

public enum AudioOutputFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case wav
    case aiff
    case flac
    case mp3
    case m4a
}

public struct RequiredModel: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let source: String
    public let approximateDiskSpaceGB: Double?
    public let licenseNotes: String?

    public init(
        id: String,
        displayName: String,
        source: String,
        approximateDiskSpaceGB: Double? = nil,
        licenseNotes: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.source = source
        self.approximateDiskSpaceGB = approximateDiskSpaceGB
        self.licenseNotes = licenseNotes
    }
}

public struct BackendProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let engineType: EngineType
    public let installMethod: BackendInstallMethod
    public let runtime: BackendRuntime
    public let dockerImage: String?
    public let requiredModels: [RequiredModel]
    public let requiredDiskSpaceGB: Double?
    public let requiredMemoryGB: Double?
    public let supportedArchitectures: [SystemArchitecture]
    public let exposedPort: Int?
    public let healthCheckURL: URL?
    public let generateEndpoint: URL?
    public let cancelEndpoint: URL?
    public let progressParser: String
    public let logParser: String
    public let outputFormatSupport: [AudioOutputFormat]
    public let licenseNotes: String
    public let role: String
    public let strengths: [String]
    public let risks: [String]

    public init(
        id: String,
        displayName: String,
        engineType: EngineType,
        installMethod: BackendInstallMethod,
        runtime: BackendRuntime,
        dockerImage: String? = nil,
        requiredModels: [RequiredModel],
        requiredDiskSpaceGB: Double? = nil,
        requiredMemoryGB: Double? = nil,
        supportedArchitectures: [SystemArchitecture],
        exposedPort: Int? = nil,
        healthCheckURL: URL? = nil,
        generateEndpoint: URL? = nil,
        cancelEndpoint: URL? = nil,
        progressParser: String,
        logParser: String,
        outputFormatSupport: [AudioOutputFormat],
        licenseNotes: String,
        role: String,
        strengths: [String],
        risks: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.engineType = engineType
        self.installMethod = installMethod
        self.runtime = runtime
        self.dockerImage = dockerImage
        self.requiredModels = requiredModels
        self.requiredDiskSpaceGB = requiredDiskSpaceGB
        self.requiredMemoryGB = requiredMemoryGB
        self.supportedArchitectures = supportedArchitectures
        self.exposedPort = exposedPort
        self.healthCheckURL = healthCheckURL
        self.generateEndpoint = generateEndpoint
        self.cancelEndpoint = cancelEndpoint
        self.progressParser = progressParser
        self.logParser = logParser
        self.outputFormatSupport = outputFormatSupport
        self.licenseNotes = licenseNotes
        self.role = role
        self.strengths = strengths
        self.risks = risks
    }
}

public enum BackendProfiles {
    public static let vibeVoiceTTS = BackendProfile(
        id: "vibevoice-tts",
        displayName: "VibeVoice TTS",
        engineType: .vibeVoiceTTS,
        installMethod: .managedDockerImage,
        runtime: .docker,
        dockerImage: AppDefaults.dockerImage,
        requiredModels: [
            RequiredModel(
                id: AppDefaults.modelPath,
                displayName: "VibeVoice Realtime 0.5B",
                source: AppDefaults.modelPath,
                approximateDiskSpaceGB: nil,
                licenseNotes: "Model license and use terms must be reviewed before redistribution."
            )
        ],
        requiredDiskSpaceGB: nil,
        requiredMemoryGB: 22,
        supportedArchitectures: [.appleSilicon, .intel],
        exposedPort: nil,
        healthCheckURL: nil,
        generateEndpoint: nil,
        cancelEndpoint: nil,
        progressParser: "GenerationOutputParser.latestProgress",
        logParser: "GenerationOutputParser.latestSummary",
        outputFormatSupport: [.wav],
        licenseNotes: "Docker Desktop licensing and model licensing are external requirements. The app must explain them before managed install.",
        role: "Long-form expressive narration",
        strengths: [
            "Longer scripts",
            "Richer voice behavior",
            "Reproducible Docker runtime"
        ],
        risks: [
            "Heavier setup",
            "Slower generation",
            "Model-specific runtime fragility"
        ]
    )

    public static let kokoroTTS = BackendProfile(
        id: "kokoro-tts",
        displayName: "Kokoro TTS",
        engineType: .kokoro,
        installMethod: .manual,
        runtime: .localPython,
        dockerImage: nil,
        requiredModels: [
            RequiredModel(
                id: "kokoro/default",
                displayName: "Kokoro Default Voice Model",
                source: "kokoro",
                approximateDiskSpaceGB: nil,
                licenseNotes: "Model and voice license terms must be reviewed before managed install or redistribution."
            )
        ],
        requiredDiskSpaceGB: nil,
        requiredMemoryGB: nil,
        supportedArchitectures: [.appleSilicon, .intel],
        exposedPort: nil,
        healthCheckURL: nil,
        generateEndpoint: nil,
        cancelEndpoint: nil,
        progressParser: "UnavailableEngineAdapter",
        logParser: "UnavailableEngineAdapter",
        outputFormatSupport: [.wav],
        licenseNotes: "Kokoro support is a backend profile placeholder until installer/runtime integration is implemented.",
        role: "Fast clean narration preview",
        strengths: [
            "Fast preview target",
            "Simpler generation surface",
            "Good proof point for adapter-based expansion"
        ],
        risks: [
            "Managed install not implemented yet",
            "Voice inventory not connected yet",
            "Generation adapter is not active yet"
        ]
    )

    public static let all: [BackendProfile] = [
        vibeVoiceTTS,
        kokoroTTS
    ]
}
