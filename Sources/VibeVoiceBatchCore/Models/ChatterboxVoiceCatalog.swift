import Foundation

public struct ChatterboxPredefinedVoice: Codable, Equatable, Identifiable, Sendable {
    public var id: String { filename }
    public let displayName: String
    public let filename: String

    public init(displayName: String, filename: String? = nil) {
        self.displayName = displayName
        self.filename = filename ?? "\(displayName).wav"
    }
}

public enum ChatterboxVoiceCatalog {
    public static let predefinedVoices: [ChatterboxPredefinedVoice] = [
        ChatterboxPredefinedVoice(displayName: "Abigail"),
        ChatterboxPredefinedVoice(displayName: "Adrian"),
        ChatterboxPredefinedVoice(displayName: "Alexander"),
        ChatterboxPredefinedVoice(displayName: "Alice"),
        ChatterboxPredefinedVoice(displayName: "Austin"),
        ChatterboxPredefinedVoice(displayName: "Axel"),
        ChatterboxPredefinedVoice(displayName: "Connor"),
        ChatterboxPredefinedVoice(displayName: "Cora"),
        ChatterboxPredefinedVoice(displayName: "Elena"),
        ChatterboxPredefinedVoice(displayName: "Eli"),
        ChatterboxPredefinedVoice(displayName: "Emily"),
        ChatterboxPredefinedVoice(displayName: "Everett"),
        ChatterboxPredefinedVoice(displayName: "Gabriel"),
        ChatterboxPredefinedVoice(displayName: "Gianna"),
        ChatterboxPredefinedVoice(displayName: "Henry"),
        ChatterboxPredefinedVoice(displayName: "Ian"),
        ChatterboxPredefinedVoice(displayName: "Jade"),
        ChatterboxPredefinedVoice(displayName: "Jeremiah"),
        ChatterboxPredefinedVoice(displayName: "Jordan"),
        ChatterboxPredefinedVoice(displayName: "Julian"),
        ChatterboxPredefinedVoice(displayName: "Layla"),
        ChatterboxPredefinedVoice(displayName: "Leonardo"),
        ChatterboxPredefinedVoice(displayName: "Michael"),
        ChatterboxPredefinedVoice(displayName: "Miles"),
        ChatterboxPredefinedVoice(displayName: "Olivia"),
        ChatterboxPredefinedVoice(displayName: "Ryan"),
        ChatterboxPredefinedVoice(displayName: "Taylor"),
        ChatterboxPredefinedVoice(displayName: "Thomas")
    ]

    public static var catalogVoices: [BackendCatalogVoice] {
        predefinedVoices.map { voice in
            BackendCatalogVoice(id: voice.filename, displayName: voice.displayName)
        }
    }

    public static var voiceDescriptors: [VoiceDescriptor] {
        predefinedVoices.map { voice in
            VoiceDescriptor(id: voice.filename, displayName: voice.displayName, locale: "en")
        }
    }
}
