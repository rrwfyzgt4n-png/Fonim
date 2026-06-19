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

public enum BackendConnectionKind: String, Codable, CaseIterable, Equatable, Sendable {
    case managed
    case installedDockerImage
    case externalService
    case localPython

    public var displayName: String {
        switch self {
        case .managed:
            return "Managed"
        case .installedDockerImage:
            return "Installed Docker Image"
        case .externalService:
            return "External Service"
        case .localPython:
            return "Local Python"
        }
    }
}

public struct BackendConnectionSettings: Codable, Equatable, Sendable {
    public var connectionKind: BackendConnectionKind
    public var dockerImage: String
    public var containerName: String?
    public var serviceBaseURL: String
    public var healthPath: String
    public var generatePath: String
    public var cancelPath: String
    public var modelID: String
    public var defaultVoice: String
    public var notes: String

    public init(
        connectionKind: BackendConnectionKind = .managed,
        dockerImage: String = "",
        containerName: String? = nil,
        serviceBaseURL: String = "",
        healthPath: String = "/health",
        generatePath: String = "/v1/audio/speech",
        cancelPath: String = "",
        modelID: String = "",
        defaultVoice: String = "",
        notes: String = ""
    ) {
        self.connectionKind = connectionKind
        self.dockerImage = dockerImage
        self.containerName = containerName
        self.serviceBaseURL = serviceBaseURL
        self.healthPath = healthPath
        self.generatePath = generatePath
        self.cancelPath = cancelPath
        self.modelID = modelID
        self.defaultVoice = defaultVoice
        self.notes = notes
    }

    public static let kokoroDefaults = BackendConnectionSettings(
        connectionKind: .installedDockerImage,
        dockerImage: "",
        serviceBaseURL: "",
        healthPath: "/health",
        generatePath: "/v1/audio/speech",
        cancelPath: "",
        modelID: "kokoro/default",
        defaultVoice: "af_heart",
        notes: ""
    )

    public static let chatterboxDefaults = BackendConnectionSettings(
        connectionKind: .externalService,
        dockerImage: "",
        serviceBaseURL: "http://127.0.0.1:8004",
        healthPath: "/api/model-info",
        generatePath: "/tts",
        cancelPath: "",
        modelID: ChatterboxModelCatalog.turboID,
        defaultVoice: "Emily.wav",
        notes: "Local Chatterbox TTS service on port 8004."
    )

    public static func defaultSettings(for profileID: String) -> BackendConnectionSettings? {
        switch profileID {
        case BackendProfiles.kokoroTTS.id:
            return .kokoroDefaults
        case BackendProfiles.chatterboxTTS.id:
            return .chatterboxDefaults
        default:
            return nil
        }
    }

    public static var defaultConfigurations: [String: BackendConnectionSettings] {
        [
            BackendProfiles.kokoroTTS.id: .kokoroDefaults,
            BackendProfiles.chatterboxTTS.id: .chatterboxDefaults
        ]
    }

    public var trimmedDockerImage: String? {
        nonEmpty(dockerImage)
    }

    public var trimmedContainerName: String? {
        guard let containerName else { return nil }
        return nonEmpty(containerName)
    }

    public var trimmedServiceBaseURL: String? {
        nonEmpty(serviceBaseURL)
    }

    public var trimmedModelID: String? {
        nonEmpty(modelID)
    }

    public var trimmedDefaultVoice: String? {
        nonEmpty(defaultVoice)
    }

    public var healthCheckURL: URL? {
        endpointURL(path: healthPath)
    }

    public var generateEndpointURL: URL? {
        endpointURL(path: generatePath)
    }

    public var cancelEndpointURL: URL? {
        endpointURL(path: cancelPath)
    }

    private func endpointURL(path: String) -> URL? {
        guard let base = trimmedServiceBaseURL else { return nil }
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return URL(string: base) }
        let separator = base.hasSuffix("/") || trimmedPath.hasPrefix("/") ? "" : "/"
        return URL(string: base + separator + trimmedPath)
    }
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
    public let containerName: String?
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
        containerName: String? = nil,
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
        self.containerName = containerName
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
        progressParser: "KokoroHTTPAdapter.progress",
        logParser: "KokoroHTTPAdapter.log",
        outputFormatSupport: [.wav],
        licenseNotes: "Kokoro support can connect to an installed local service. Model and voice license terms must be reviewed before managed install or redistribution.",
        role: "Fast clean narration preview",
        strengths: [
            "Fast preview target",
            "Simpler generation surface",
            "Good proof point for adapter-based expansion"
        ],
        risks: [
            "Managed install not implemented yet",
            "Runtime must expose an HTTP service before generation",
            "Streaming progress depends on the running Kokoro service contract"
        ]
    )

    public static let chatterboxTTS = BackendProfile(
        id: "chatterbox-tts",
        displayName: "Chatterbox TTS",
        engineType: .chatterbox,
        installMethod: .externalServer,
        runtime: .externalService,
        dockerImage: nil,
        requiredModels: ChatterboxModelCatalog.requiredModels,
        requiredDiskSpaceGB: nil,
        requiredMemoryGB: nil,
        supportedArchitectures: [.appleSilicon, .intel],
        exposedPort: 8004,
        healthCheckURL: BackendConnectionSettings.chatterboxDefaults.healthCheckURL,
        generateEndpoint: BackendConnectionSettings.chatterboxDefaults.generateEndpointURL,
        cancelEndpoint: nil,
        progressParser: "ChatterboxHTTPAdapter.progress",
        logParser: "ChatterboxHTTPAdapter.log",
        outputFormatSupport: [.wav],
        licenseNotes: "Chatterbox support connects to an installed local service. The app keeps Docker or Python details as backend infrastructure.",
        role: "Expressive local narration backend",
        strengths: [
            "Predefined voices and reference voice cloning",
            "Useful expressive controls",
            "Simple local HTTP service integration"
        ],
        risks: [
            "Generation progress is request-based unless the running service exposes streaming status",
            "Runtime must already expose the Chatterbox HTTP API",
            "Model and voice behavior can vary by installed server package"
        ]
    )

    public static let all: [BackendProfile] = [
        vibeVoiceTTS,
        kokoroTTS,
        chatterboxTTS
    ]

    public static func baseProfile(id: String) -> BackendProfile? {
        all.first { $0.id == id }
    }

    public static func resolvedProfile(
        id: String,
        connectionSettings: [String: BackendConnectionSettings]
    ) -> BackendProfile? {
        guard let profile = baseProfile(id: id) else { return nil }
        return profile.applying(connectionSettings[profile.id])
    }

    public static func resolvedProfiles(
        connectionSettings: [String: BackendConnectionSettings]
    ) -> [BackendProfile] {
        all.map { $0.applying(connectionSettings[$0.id]) }
    }
}

public extension BackendProfile {
    func applying(_ connection: BackendConnectionSettings?) -> BackendProfile {
        guard let connection, engineType == .kokoro || engineType == .chatterbox else { return self }

        let runtime: BackendRuntime
        let installMethod: BackendInstallMethod
        let dockerImage: String?
        switch connection.connectionKind {
        case .managed:
            runtime = self.runtime
            installMethod = self.installMethod
            dockerImage = self.dockerImage
        case .installedDockerImage:
            runtime = .docker
            installMethod = .manual
            dockerImage = connection.trimmedDockerImage
        case .externalService:
            runtime = .externalService
            installMethod = .externalServer
            dockerImage = nil
        case .localPython:
            runtime = .localPython
            installMethod = .localPythonEnvironment
            dockerImage = nil
        }

        let defaultModelID = engineType == .chatterbox ? ChatterboxModelCatalog.turboID : "kokoro/default"
        let modelID = connection.trimmedModelID ?? requiredModels.first?.id ?? defaultModelID
        let model = RequiredModel(
            id: modelID,
            displayName: modelDisplayName(for: modelID),
            source: modelID,
            approximateDiskSpaceGB: requiredModels.first?.approximateDiskSpaceGB,
            licenseNotes: requiredModels.first?.licenseNotes
        )
        let appliedModels = engineType == .chatterbox ? ChatterboxModelCatalog.requiredModels : [model]

        return BackendProfile(
            id: id,
            displayName: displayName,
            engineType: engineType,
            installMethod: installMethod,
            runtime: runtime,
            dockerImage: dockerImage,
            containerName: connection.trimmedContainerName,
            requiredModels: appliedModels,
            requiredDiskSpaceGB: requiredDiskSpaceGB,
            requiredMemoryGB: requiredMemoryGB,
            supportedArchitectures: supportedArchitectures,
            exposedPort: exposedPort,
            healthCheckURL: connection.healthCheckURL,
            generateEndpoint: connection.generateEndpointURL,
            cancelEndpoint: connection.cancelEndpointURL,
            progressParser: engineType == .chatterbox ? "ChatterboxProgressParser" : "KokoroProgressParser",
            logParser: engineType == .chatterbox ? "ChatterboxLogParser" : "KokoroLogParser",
            outputFormatSupport: outputFormatSupport,
            licenseNotes: licenseNotes,
            role: role,
            strengths: strengths,
            risks: appliedRisks
        )
    }

    private func modelDisplayName(for modelID: String) -> String {
        if engineType == .kokoro, modelID == "kokoro/default" {
            return "Kokoro Default Voice Model"
        }
        if engineType == .chatterbox {
            return ChatterboxModelCatalog.displayName(for: modelID)
        }
        return modelID
    }

    private var appliedRisks: [String] {
        if engineType == .chatterbox {
            return [
                "Generation progress depends on the Chatterbox server response contract",
                "Voice inventory must be read from the configured runtime",
                "Runtime behavior depends on the installed Chatterbox package or image"
            ]
        }
        return [
            "Generation adapter endpoint mapping still needs confirmation",
            "Voice inventory must be read from the configured runtime",
            "Runtime behavior depends on the installed Kokoro package or image"
        ]
    }
}

private func nonEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
