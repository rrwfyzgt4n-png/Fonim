import Foundation

public struct VoiceDescriptor: Codable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let locale: String?
    public let traits: [String]

    public init(id: String, displayName: String, locale: String? = nil, traits: [String] = []) {
        self.id = id
        self.displayName = displayName
        self.locale = locale
        self.traits = traits
    }
}

public struct ModelDescriptor: Codable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let role: String

    public init(id: String, displayName: String, role: String) {
        self.id = id
        self.displayName = displayName
        self.role = role
    }
}

public struct EngineOutput: Equatable {
    public var fileURL: URL
    public var format: AudioOutputFormat
    public var sampleRate: Int?

    public init(fileURL: URL, format: AudioOutputFormat, sampleRate: Int? = nil) {
        self.fileURL = fileURL
        self.format = format
        self.sampleRate = sampleRate
    }
}

public struct NormalizedAudioOutput: Equatable {
    public var fileURL: URL
    public var format: AudioOutputFormat
    public var durationSeconds: Double?
    public var sampleRate: Int?

    public init(fileURL: URL, format: AudioOutputFormat, durationSeconds: Double? = nil, sampleRate: Int? = nil) {
        self.fileURL = fileURL
        self.format = format
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
    }
}

public enum GenerationEvent: Equatable {
    case sessionStarted(SessionRecord)
    case status(String)
    case progress(GenerationProgressSnapshot)
    case log(String)
    case output(NormalizedAudioOutput)
}

public enum BackendError: Error, Equatable {
    case backendUnavailable(GenerationErrorRecord)
    case operationUnavailable(GenerationErrorRecord)
    case generationFailed(GenerationErrorRecord)
}

public protocol EngineAdapter {
    var profile: BackendProfile { get }

    func healthCheck() async -> BackendHealthReport
    func listVoices() async throws -> [VoiceDescriptor]
    func listModels() async throws -> [ModelDescriptor]
    func generate(_ job: GenerationJob, events: @escaping (GenerationEvent) -> Void) async throws -> GenerationRecord
    func cancel(jobID: String) async
    func getProgress(jobID: String) async -> GenerationProgressSnapshot?
    func normalizeOutput(_ output: EngineOutput) async throws -> NormalizedAudioOutput
}
