import Foundation

public enum BackendDiscoveryConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low

    public var displayName: String {
        switch self {
        case .high:
            return "High"
        case .medium:
            return "Medium"
        case .low:
            return "Low"
        }
    }
}

public struct BackendDiscoveryCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var confidence: BackendDiscoveryConfidence
    public var connectionKind: BackendConnectionKind
    public var dockerImage: String?
    public var containerName: String?
    public var serviceBaseURL: String?
    public var healthPath: String
    public var generatePath: String
    public var modelID: String
    public var defaultVoice: String
    public var notes: String
    public var technicalDetails: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        confidence: BackendDiscoveryConfidence,
        connectionKind: BackendConnectionKind,
        dockerImage: String? = nil,
        containerName: String? = nil,
        serviceBaseURL: String? = nil,
        healthPath: String = "/health",
        generatePath: String = "/v1/audio/speech",
        modelID: String = "tts-1",
        defaultVoice: String = "af_heart",
        notes: String = "",
        technicalDetails: String? = nil
    ) {
        self.id = id
        self.title = title
        self.confidence = confidence
        self.connectionKind = connectionKind
        self.dockerImage = dockerImage
        self.containerName = containerName
        self.serviceBaseURL = serviceBaseURL
        self.healthPath = healthPath
        self.generatePath = generatePath
        self.modelID = modelID
        self.defaultVoice = defaultVoice
        self.notes = notes
        self.technicalDetails = technicalDetails
    }

    public var connectionSettings: BackendConnectionSettings {
        BackendConnectionSettings(
            connectionKind: connectionKind,
            dockerImage: dockerImage ?? "",
            containerName: containerName,
            serviceBaseURL: serviceBaseURL ?? "",
            healthPath: healthPath,
            generatePath: generatePath,
            cancelPath: "",
            modelID: modelID,
            defaultVoice: defaultVoice,
            notes: notes
        )
    }
}

public struct BackendDiscoveryReport: Codable, Equatable, Sendable {
    public var profileID: String
    public var generatedAt: Date
    public var candidates: [BackendDiscoveryCandidate]
    public var message: String
    public var technicalDetails: String?

    public init(
        profileID: String,
        generatedAt: Date = Date(),
        candidates: [BackendDiscoveryCandidate],
        message: String,
        technicalDetails: String? = nil
    ) {
        self.profileID = profileID
        self.generatedAt = generatedAt
        self.candidates = candidates
        self.message = message
        self.technicalDetails = technicalDetails
    }
}
