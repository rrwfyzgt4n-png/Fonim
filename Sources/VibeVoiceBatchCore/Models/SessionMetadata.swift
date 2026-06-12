import Foundation

public struct SessionMetadata: Codable, Equatable, Identifiable {
    public var sessionID: String
    public var createdAt: Date
    public var completedAt: Date?
    public var status: SessionStatus
    public var voice: String
    public var cfgScale: String
    public var dockerImage: String
    public var dockerCommand: String
    public var inputWordCount: Int
    public var inputCharacterCount: Int
    public var generationTimeSeconds: Double?
    public var audioDurationSeconds: Double?
    public var rtf: Double?
    public var outputFile: String?

    public var id: String { sessionID }

    public init(
        sessionID: String,
        createdAt: Date,
        completedAt: Date? = nil,
        status: SessionStatus,
        voice: String,
        cfgScale: String,
        dockerImage: String = AppDefaults.dockerImage,
        dockerCommand: String,
        inputWordCount: Int,
        inputCharacterCount: Int,
        generationTimeSeconds: Double? = nil,
        audioDurationSeconds: Double? = nil,
        rtf: Double? = nil,
        outputFile: String? = nil
    ) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.status = status
        self.voice = voice
        self.cfgScale = cfgScale
        self.dockerImage = dockerImage
        self.dockerCommand = dockerCommand
        self.inputWordCount = inputWordCount
        self.inputCharacterCount = inputCharacterCount
        self.generationTimeSeconds = generationTimeSeconds
        self.audioDurationSeconds = audioDurationSeconds
        self.rtf = rtf
        self.outputFile = outputFile
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case status
        case voice
        case cfgScale = "cfg_scale"
        case dockerImage = "docker_image"
        case dockerCommand = "docker_command"
        case inputWordCount = "input_word_count"
        case inputCharacterCount = "input_character_count"
        case generationTimeSeconds = "generation_time_seconds"
        case audioDurationSeconds = "audio_duration_seconds"
        case rtf
        case outputFile = "output_file"
    }
}
