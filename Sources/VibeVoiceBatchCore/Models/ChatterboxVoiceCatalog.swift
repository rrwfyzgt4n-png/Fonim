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
            BackendCatalogVoice(
                id: voice.filename,
                displayName: voice.displayName,
                backendID: "chatterbox-tts",
                modelIDs: [
                    ChatterboxModelCatalog.turboID,
                    ChatterboxModelCatalog.originalID
                ],
                locale: "en",
                languageCode: "en",
                traits: traits(forDisplayName: voice.displayName),
                sourceType: .predefined,
                rawRuntimeID: voice.filename
            )
        }
    }

    public static var voiceDescriptors: [VoiceDescriptor] {
        predefinedVoices.map { voice in
            VoiceDescriptor(id: voice.filename, displayName: voice.displayName, locale: "en", traits: traits(forDisplayName: voice.displayName))
        }
    }

    public static func traits(forDisplayName displayName: String) -> [String] {
        let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if femaleNames.contains(normalized) {
            return ["female"]
        }
        if maleNames.contains(normalized) {
            return ["male"]
        }
        return []
    }

    public static func voice(_ voice: BackendCatalogVoice, supportsOutputLanguage languageCode: String) -> Bool {
        let outputLanguage = normalizedLanguageCode(languageCode)
        if let voiceLanguage = normalizedVoiceLanguage(voice) {
            return voiceLanguage == outputLanguage
        }
        return outputLanguage == "en"
    }

    private static func normalizedVoiceLanguage(_ voice: BackendCatalogVoice) -> String? {
        if let languageCode = voice.languageCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !languageCode.isEmpty {
            return normalizedLanguageCode(languageCode)
        }
        if let locale = voice.locale?.trimmingCharacters(in: .whitespacesAndNewlines),
           let language = locale.split(separator: "-").first {
            return normalizedLanguageCode(String(language))
        }
        return nil
    }

    private static func normalizedLanguageCode(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "jp": return "ja"
        case "kr": return "ko"
        case "sp": return "es"
        case "in": return "hi"
        case "": return "en"
        default: return normalized
        }
    }

    private static let femaleNames: Set<String> = [
        "abigail", "alice", "cora", "elena", "emily", "gianna", "jade", "layla", "olivia"
    ]

    private static let maleNames: Set<String> = [
        "adrian", "alexander", "austin", "axel", "connor", "eli", "everett", "gabriel",
        "henry", "ian", "jeremiah", "julian", "leonardo", "michael", "miles", "ryan", "thomas"
    ]
}
