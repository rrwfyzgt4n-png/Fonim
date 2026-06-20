import SwiftUI
import VibeVoiceBatchCore

struct VoiceDisplayDescriptor: Equatable {
    var languageCode: String
    var languageName: String
    var countryFlag: String
    var displayName: String
    var genderEmoji: String?

    var compactText: String {
        if let genderEmoji {
            return "\(displayName) \(genderEmoji)"
        }
        return displayName
    }

    var accessibilityText: String {
        [countryFlag, languageName, displayName, genderEmoji]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

enum VoiceDisplayFormatter {
    static let supportedLanguages: [(code: String, name: String)] = [
        ("ar", "Arabic"),
        ("da", "Danish"),
        ("de", "German"),
        ("el", "Greek"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fi", "Finnish"),
        ("fr", "French"),
        ("he", "Hebrew"),
        ("hi", "Hindi"),
        ("it", "Italian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ms", "Malay"),
        ("nl", "Dutch"),
        ("no", "Norwegian"),
        ("pl", "Polish"),
        ("pt", "Portuguese"),
        ("ru", "Russian"),
        ("sv", "Swedish"),
        ("sw", "Swahili"),
        ("tr", "Turkish"),
        ("zh", "Chinese")
    ]

    static func descriptor(
        for voiceID: String,
        displayName fallbackDisplayName: String? = nil,
        languageCode explicitLanguageCode: String? = nil,
        locale: String? = nil,
        countryFlag explicitCountryFlag: String? = nil,
        traits: [String] = []
    ) -> VoiceDisplayDescriptor {
        let trimmedID = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutReferencePrefix = trimmedID.hasPrefix("reference:")
            ? String(trimmedID.dropFirst("reference:".count))
            : trimmedID
        let baseID = (withoutReferencePrefix as NSString).lastPathComponent
        let filenameStem = (baseID as NSString).deletingPathExtension
        let rawParts = filenameStem
            .components(separatedBy: CharacterSet(charactersIn: "_- "))
            .filter { !$0.isEmpty }

        var parts = rawParts
        var inferredLanguageCode: String?
        var explicitGender = genderTrait(in: traits)
        if let first = parts.first?.lowercased(), let kokoro = kokoroVoicePrefix(first) {
            inferredLanguageCode = kokoro.languageCode
            explicitGender = kokoro.gender
            parts.removeFirst()
        } else if let first = parts.first?.lowercased(), isLanguageCode(first) {
            inferredLanguageCode = normalizedLanguageCode(first)
            parts.removeFirst()
        }

        let languageCode = normalizedLanguageCode(
            explicitLanguageCode ??
                languageCodeFromLocale(locale) ??
                inferredLanguageCode ??
                "en"
        )

        if explicitGender == nil,
           let last = parts.last?.lowercased(),
           ["man", "male", "woman", "female"].contains(last) {
            explicitGender = last
            parts.removeLast()
        }

        let fallback = fallbackDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFallback = fallback.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
        let machineFallback = fallback?.contains("_") == true || fallback?.contains("-") == true || fallback?.contains(".") == true
        let displayName: String
        if let cleanFallback, !cleanFallback.isEmpty, !machineFallback {
            displayName = cleanFallback
        } else if parts.isEmpty {
            displayName = filenameStem.isEmpty ? trimmedID : titleCased(filenameStem)
        } else {
            displayName = parts.map(displayToken).joined(separator: " ")
        }

        return VoiceDisplayDescriptor(
            languageCode: languageCode,
            languageName: languageName(for: languageCode),
            countryFlag: explicitCountryFlag ?? countryFlag(for: languageCode),
            displayName: displayName,
            genderEmoji: genderEmoji(explicitGender: explicitGender, displayName: displayName)
        )
    }

    static func languageName(for code: String) -> String {
        let normalized = normalizedLanguageCode(code)
        return supportedLanguages.first { $0.code == normalized }?.name ?? normalized.uppercased()
    }

    static func displayCode(for code: String) -> String {
        normalizedLanguageCode(code).uppercased()
    }

    static func displayText(for voiceID: String, displayName: String? = nil, includeLanguage: Bool = true) -> String {
        let descriptor = descriptor(for: voiceID, displayName: displayName)
        let voice = descriptor.compactText
        return includeLanguage ? "\(descriptor.countryFlag) \(descriptor.languageCode.uppercased()) \(voice)" : voice
    }

    static func countryFlag(for code: String) -> String {
        switch normalizedLanguageCode(code) {
        case "ar": return "🇸🇦"
        case "da": return "🇩🇰"
        case "de": return "🇩🇪"
        case "el": return "🇬🇷"
        case "en": return "🇺🇸"
        case "es": return "🇪🇸"
        case "fi": return "🇫🇮"
        case "fr": return "🇫🇷"
        case "he": return "🇮🇱"
        case "hi": return "🇮🇳"
        case "it": return "🇮🇹"
        case "ja": return "🇯🇵"
        case "ko": return "🇰🇷"
        case "ms": return "🇲🇾"
        case "nl": return "🇳🇱"
        case "no": return "🇳🇴"
        case "pl": return "🇵🇱"
        case "pt": return "🇵🇹"
        case "ru": return "🇷🇺"
        case "sv": return "🇸🇪"
        case "sw": return "🇰🇪"
        case "tr": return "🇹🇷"
        case "zh": return "🇨🇳"
        default: return "🏳️"
        }
    }

    private static func displayToken(_ token: String) -> String {
        let lower = token.lowercased()
        if lower.hasPrefix("spk"), lower.count > 3 {
            let suffix = String(lower.dropFirst(3))
            if suffix.allSatisfy(\.isNumber) {
                return "Speaker \(suffix)"
            }
        }
        return titleCased(token)
    }

    private static func titleCased(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { token in
                token.prefix(1).uppercased() + token.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    private static func isLanguageCode(_ value: String) -> Bool {
        value.count == 2 && value.allSatisfy(\.isLetter)
    }

    private static func normalizedLanguageCode(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "in":
            return "hi"
        case "jp":
            return "ja"
        case "kr":
            return "ko"
        case "sp":
            return "es"
        default:
            return normalized
        }
    }

    private static func languageCodeFromLocale(_ locale: String?) -> String? {
        guard let locale,
              let language = locale.split(separator: "-").first else {
            return nil
        }
        return normalizedLanguageCode(String(language))
    }

    private static func kokoroVoicePrefix(_ value: String) -> (languageCode: String, gender: String?)? {
        guard value.count == 2,
              let family = value.first,
              let genderCode = value.last else {
            return nil
        }
        let languageCode: String
        switch family {
        case "a", "b":
            languageCode = "en"
        case "e":
            languageCode = "es"
        case "f":
            languageCode = "fr"
        case "h":
            languageCode = "hi"
        case "i":
            languageCode = "it"
        case "j":
            languageCode = "ja"
        case "p":
            languageCode = "pt"
        case "z":
            languageCode = "zh"
        default:
            return nil
        }

        let gender: String?
        switch genderCode {
        case "f":
            gender = "female"
        case "m":
            gender = "male"
        default:
            gender = nil
        }
        return (languageCode, gender)
    }

    private static func genderEmoji(explicitGender: String?, displayName: String) -> String? {
        if let explicitGender {
            if ["man", "male"].contains(explicitGender) { return "👨" }
            if ["woman", "female"].contains(explicitGender) { return "👩" }
        }

        let firstName = displayName.split(separator: " ").first.map { String($0).lowercased() } ?? displayName.lowercased()
        if femaleNames.contains(firstName) { return "👩" }
        if maleNames.contains(firstName) { return "👨" }
        return nil
    }

    private static func genderTrait(in traits: [String]) -> String? {
        let normalized = traits.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if normalized.contains(where: { ["male", "man"].contains($0) }) {
            return "male"
        }
        if normalized.contains(where: { ["female", "woman"].contains($0) }) {
            return "female"
        }
        return nil
    }

    private static let femaleNames: Set<String> = [
        "abigail", "alice", "cora", "elena", "emily", "gianna", "jade", "layla", "olivia"
    ]

    private static let maleNames: Set<String> = [
        "adrian", "alexander", "austin", "axel", "carter", "connor", "eli", "everett",
        "gabriel", "henry", "ian", "jeremiah", "julian", "leonardo", "michael", "mike",
        "miles", "ryan", "thomas"
    ]
}

struct LanguageBadge: View {
    let code: String
    var flag: String?
    var compact = false

    var body: some View {
        let palette = LanguagePalette.palette(for: code)
        Text("\(flag ?? VoiceDisplayFormatter.countryFlag(for: code)) \(VoiceDisplayFormatter.displayCode(for: code))")
            .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded))
            .monospaced()
            .foregroundStyle(palette.foreground)
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, compact ? 2 : 3)
            .background(palette.background, in: Capsule())
            .accessibilityLabel(VoiceDisplayFormatter.languageName(for: code))
    }
}

struct VoiceInlineLabel: View {
    let voiceID: String
    var displayName: String?
    var languageCode: String?
    var locale: String?
    var countryFlag: String?
    var traits: [String]
    var compact = false

    init(
        voiceID: String,
        displayName: String? = nil,
        languageCode: String? = nil,
        locale: String? = nil,
        countryFlag: String? = nil,
        traits: [String] = [],
        compact: Bool = false
    ) {
        self.voiceID = voiceID
        self.displayName = displayName
        self.languageCode = languageCode
        self.locale = locale
        self.countryFlag = countryFlag
        self.traits = traits
        self.compact = compact
    }

    init(voice: BackendCatalogVoice, compact: Bool = false) {
        self.init(
            voiceID: voice.id,
            displayName: voice.displayName,
            languageCode: voice.languageCode,
            locale: voice.locale,
            countryFlag: voice.countryFlag,
            traits: voice.traits,
            compact: compact
        )
    }

    var body: some View {
        let descriptor = VoiceDisplayFormatter.descriptor(
            for: voiceID,
            displayName: displayName,
            languageCode: languageCode,
            locale: locale,
            countryFlag: countryFlag,
            traits: traits
        )
        HStack(spacing: compact ? 4 : 6) {
            LanguageBadge(code: descriptor.languageCode, flag: descriptor.countryFlag, compact: compact)
            Text(descriptor.displayName)
                .lineLimit(1)
            if let genderEmoji = descriptor.genderEmoji {
                Text(genderEmoji)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(descriptor.accessibilityText)
    }
}

private enum LanguagePalette {
    static func palette(for code: String) -> (background: Color, foreground: Color) {
        switch VoiceDisplayFormatter.displayCode(for: code).lowercased() {
        case "en":
            return (Color(red: 0.16, green: 0.42, blue: 0.90), .white)
        case "fr":
            return (Color(red: 1.00, green: 0.82, blue: 0.22), .black)
        case "de":
            return (Color(red: 0.48, green: 0.30, blue: 0.16), .white)
        case "ar":
            return (Color(red: 0.10, green: 0.45, blue: 0.33), .white)
        case "da":
            return (Color(red: 0.70, green: 0.12, blue: 0.18), .white)
        case "el":
            return (Color(red: 0.20, green: 0.50, blue: 0.80), .white)
        case "es":
            return (Color(red: 0.95, green: 0.42, blue: 0.18), .white)
        case "fi":
            return (Color(red: 0.12, green: 0.32, blue: 0.70), .white)
        case "he":
            return (Color(red: 0.12, green: 0.46, blue: 0.78), .white)
        case "hi":
            return (Color(red: 0.88, green: 0.46, blue: 0.10), .white)
        case "it":
            return (Color(red: 0.13, green: 0.56, blue: 0.32), .white)
        case "ja":
            return (Color(red: 0.82, green: 0.18, blue: 0.24), .white)
        case "ko":
            return (Color(red: 0.45, green: 0.28, blue: 0.82), .white)
        case "ms":
            return (Color(red: 0.10, green: 0.55, blue: 0.58), .white)
        case "nl":
            return (Color(red: 0.92, green: 0.36, blue: 0.12), .white)
        case "no":
            return (Color(red: 0.18, green: 0.24, blue: 0.60), .white)
        case "pl":
            return (Color(red: 0.75, green: 0.18, blue: 0.32), .white)
        case "pt":
            return (Color(red: 0.03, green: 0.53, blue: 0.58), .white)
        case "ru":
            return (Color(red: 0.36, green: 0.37, blue: 0.74), .white)
        case "sv":
            return (Color(red: 0.18, green: 0.46, blue: 0.78), .white)
        case "sw":
            return (Color(red: 0.16, green: 0.52, blue: 0.24), .white)
        case "tr":
            return (Color(red: 0.78, green: 0.12, blue: 0.18), .white)
        case "zh":
            return (Color(red: 0.78, green: 0.18, blue: 0.48), .white)
        default:
            return (.secondary.opacity(0.22), .secondary)
        }
    }
}
