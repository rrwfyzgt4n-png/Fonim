import Foundation

public struct KokoroVoiceDefinition: Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var locale: String
    public var traits: [String]

    public init(id: String, displayName: String, locale: String, traits: [String] = []) {
        self.id = id
        self.displayName = displayName
        self.locale = locale
        self.traits = traits
    }
}

public enum KokoroVoiceCatalog {
    public static let fallbackVoices: [KokoroVoiceDefinition] = [
        KokoroVoiceDefinition(id: "af_heart", displayName: "Heart", locale: "en-US", traits: ["female"]),
        KokoroVoiceDefinition(id: "af_alloy", displayName: "Alloy", locale: "en-US", traits: ["female"]),
        KokoroVoiceDefinition(id: "af_aoede", displayName: "Aoede", locale: "en-US", traits: ["female"]),
        KokoroVoiceDefinition(id: "af_bella", displayName: "Bella", locale: "en-US", traits: ["female"]),
        KokoroVoiceDefinition(id: "af_jessica", displayName: "Jessica", locale: "en-US", traits: ["female"]),
        KokoroVoiceDefinition(id: "af_kore", displayName: "Kore", locale: "en-US", traits: ["female"]),
        KokoroVoiceDefinition(id: "af_nicole", displayName: "Nicole", locale: "en-US", traits: ["female"]),
        KokoroVoiceDefinition(id: "af_nova", displayName: "Nova", locale: "en-US", traits: ["female"]),
        KokoroVoiceDefinition(id: "af_river", displayName: "River", locale: "en-US", traits: ["female"]),
        KokoroVoiceDefinition(id: "af_sarah", displayName: "Sarah", locale: "en-US", traits: ["female"]),
        KokoroVoiceDefinition(id: "af_sky", displayName: "Sky", locale: "en-US", traits: ["female"]),
        KokoroVoiceDefinition(id: "am_adam", displayName: "Adam", locale: "en-US", traits: ["male"]),
        KokoroVoiceDefinition(id: "am_echo", displayName: "Echo", locale: "en-US", traits: ["male"]),
        KokoroVoiceDefinition(id: "am_eric", displayName: "Eric", locale: "en-US", traits: ["male"]),
        KokoroVoiceDefinition(id: "am_fenrir", displayName: "Fenrir", locale: "en-US", traits: ["male"]),
        KokoroVoiceDefinition(id: "am_liam", displayName: "Liam", locale: "en-US", traits: ["male"]),
        KokoroVoiceDefinition(id: "am_michael", displayName: "Michael", locale: "en-US", traits: ["male"]),
        KokoroVoiceDefinition(id: "am_onyx", displayName: "Onyx", locale: "en-US", traits: ["male"]),
        KokoroVoiceDefinition(id: "am_puck", displayName: "Puck", locale: "en-US", traits: ["male"]),
        KokoroVoiceDefinition(id: "am_santa", displayName: "Santa", locale: "en-US", traits: ["male"]),
        KokoroVoiceDefinition(id: "bf_alice", displayName: "Alice", locale: "en-GB", traits: ["female"]),
        KokoroVoiceDefinition(id: "bf_emma", displayName: "Emma", locale: "en-GB", traits: ["female"]),
        KokoroVoiceDefinition(id: "bf_isabella", displayName: "Isabella", locale: "en-GB", traits: ["female"]),
        KokoroVoiceDefinition(id: "bf_lily", displayName: "Lily", locale: "en-GB", traits: ["female"]),
        KokoroVoiceDefinition(id: "bm_daniel", displayName: "Daniel", locale: "en-GB", traits: ["male"]),
        KokoroVoiceDefinition(id: "bm_fable", displayName: "Fable", locale: "en-GB", traits: ["male"]),
        KokoroVoiceDefinition(id: "bm_george", displayName: "George", locale: "en-GB", traits: ["male"]),
        KokoroVoiceDefinition(id: "bm_lewis", displayName: "Lewis", locale: "en-GB", traits: ["male"]),
        KokoroVoiceDefinition(id: "ef_dora", displayName: "Dora", locale: "es", traits: ["female"]),
        KokoroVoiceDefinition(id: "em_alex", displayName: "Alex", locale: "es", traits: ["male"]),
        KokoroVoiceDefinition(id: "em_santa", displayName: "Santa", locale: "es", traits: ["male"]),
        KokoroVoiceDefinition(id: "ff_siwis", displayName: "Siwis", locale: "fr", traits: ["female"]),
        KokoroVoiceDefinition(id: "hf_alpha", displayName: "Alpha", locale: "hi", traits: ["female"]),
        KokoroVoiceDefinition(id: "hf_beta", displayName: "Beta", locale: "hi", traits: ["female"]),
        KokoroVoiceDefinition(id: "hm_omega", displayName: "Omega", locale: "hi", traits: ["male"]),
        KokoroVoiceDefinition(id: "if_sara", displayName: "Sara", locale: "it", traits: ["female"]),
        KokoroVoiceDefinition(id: "im_nicola", displayName: "Nicola", locale: "it", traits: ["male"]),
        KokoroVoiceDefinition(id: "jf_alpha", displayName: "Alpha", locale: "ja", traits: ["female"]),
        KokoroVoiceDefinition(id: "jf_gongitsune", displayName: "Gongitsune", locale: "ja", traits: ["female"]),
        KokoroVoiceDefinition(id: "jm_kumo", displayName: "Kumo", locale: "ja", traits: ["male"]),
        KokoroVoiceDefinition(id: "pf_dora", displayName: "Dora", locale: "pt", traits: ["female"]),
        KokoroVoiceDefinition(id: "pm_alex", displayName: "Alex", locale: "pt", traits: ["male"]),
        KokoroVoiceDefinition(id: "pm_santa", displayName: "Santa", locale: "pt", traits: ["male"]),
        KokoroVoiceDefinition(id: "zf_xiaobei", displayName: "Xiaobei", locale: "zh", traits: ["female"]),
        KokoroVoiceDefinition(id: "zf_xiaoni", displayName: "Xiaoni", locale: "zh", traits: ["female"]),
        KokoroVoiceDefinition(id: "zf_xiaoxiao", displayName: "Xiaoxiao", locale: "zh", traits: ["female"]),
        KokoroVoiceDefinition(id: "zm_yunjian", displayName: "Yunjian", locale: "zh", traits: ["male"]),
        KokoroVoiceDefinition(id: "zm_yunxi", displayName: "Yunxi", locale: "zh", traits: ["male"])
    ]

    public static var catalogVoices: [BackendCatalogVoice] {
        fallbackVoices.map { voice in
            BackendCatalogVoice(
                id: voice.id,
                displayName: voice.displayName,
                backendID: "kokoro-tts",
                modelIDs: ["tts-1"],
                locale: voice.locale,
                languageCode: languageCode(forLocale: voice.locale),
                traits: voice.traits,
                sourceType: .predefined,
                rawRuntimeID: voice.id
            )
        }
    }

    public static var voiceDescriptors: [VoiceDescriptor] {
        fallbackVoices.map { voice in
            VoiceDescriptor(id: voice.id, displayName: voice.displayName, locale: voice.locale, traits: voice.traits)
        }
    }

    public static func descriptor(for voiceID: String, displayName: String? = nil) -> VoiceDescriptor {
        if let voice = fallbackVoices.first(where: { $0.id == voiceID }) {
            return VoiceDescriptor(id: voice.id, displayName: displayName ?? voice.displayName, locale: voice.locale, traits: voice.traits)
        }
        return VoiceDescriptor(id: voiceID, displayName: displayName ?? voiceID, locale: locale(for: voiceID), traits: traits(for: voiceID))
    }

    public static func locale(for voiceID: String) -> String? {
        let prefix = voiceID.split(separator: "_").first.map(String.init) ?? ""
        guard prefix.count == 2 else { return nil }
        switch prefix.first {
        case "a":
            return "en-US"
        case "b":
            return "en-GB"
        case "e":
            return "es"
        case "f":
            return "fr"
        case "h":
            return "hi"
        case "i":
            return "it"
        case "j":
            return "ja"
        case "p":
            return "pt"
        case "z":
            return "zh"
        default:
            return nil
        }
    }

    public static func languageCode(forLocale locale: String?) -> String? {
        guard let locale,
              let language = locale.split(separator: "-").first else {
            return nil
        }
        return String(language).lowercased()
    }

    public static func traits(for voiceID: String) -> [String] {
        let prefix = voiceID.split(separator: "_").first.map(String.init) ?? ""
        guard prefix.count == 2 else { return [] }
        if prefix.hasSuffix("f") {
            return ["female"]
        }
        if prefix.hasSuffix("m") {
            return ["male"]
        }
        return []
    }
}
