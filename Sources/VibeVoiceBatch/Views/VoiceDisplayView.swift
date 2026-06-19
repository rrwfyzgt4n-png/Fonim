import SwiftUI

struct VoiceDisplayDescriptor: Equatable {
    var languageCode: String
    var languageName: String
    var displayName: String
    var genderEmoji: String?

    var compactText: String {
        if let genderEmoji {
            return "\(displayName) \(genderEmoji)"
        }
        return displayName
    }

    var accessibilityText: String {
        [languageName, displayName, genderEmoji]
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

    static func descriptor(for voiceID: String, displayName fallbackDisplayName: String? = nil) -> VoiceDisplayDescriptor {
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
        var languageCode = "en"
        if let first = parts.first?.lowercased(), isLanguageCode(first) {
            languageCode = first
            parts.removeFirst()
        }

        var explicitGender: String?
        if let last = parts.last?.lowercased(), ["man", "male", "woman", "female"].contains(last) {
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
            displayName: displayName,
            genderEmoji: genderEmoji(explicitGender: explicitGender, displayName: displayName)
        )
    }

    static func languageName(for code: String) -> String {
        supportedLanguages.first { $0.code == code.lowercased() }?.name ?? code.uppercased()
    }

    static func displayText(for voiceID: String, displayName: String? = nil, includeLanguage: Bool = true) -> String {
        let descriptor = descriptor(for: voiceID, displayName: displayName)
        let voice = descriptor.compactText
        return includeLanguage ? "\(descriptor.languageCode.uppercased()) \(voice)" : voice
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
    var compact = false

    var body: some View {
        let palette = LanguagePalette.palette(for: code)
        Text(code.uppercased())
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
    var compact = false

    var body: some View {
        let descriptor = VoiceDisplayFormatter.descriptor(for: voiceID, displayName: displayName)
        HStack(spacing: compact ? 4 : 6) {
            LanguageBadge(code: descriptor.languageCode, compact: compact)
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
        switch code.lowercased() {
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
