import Foundation

public struct LiveGenerationProgress: Equatable {
    public let prefilledTextTokens: Int
    public let generatedSpeechTokens: Int
    public let currentStep: Int
    public let maxSteps: Int
    public let reportedElapsedSeconds: TimeInterval?

    public var fraction: Double {
        guard maxSteps > 0 else { return 0 }
        return min(1, max(0, Double(currentStep) / Double(maxSteps)))
    }

    public var percent: Double {
        fraction * 100
    }

    public func estimatedRemainingSeconds(elapsedSeconds: TimeInterval) -> TimeInterval? {
        guard currentStep > 0, maxSteps > currentStep else { return nil }
        return elapsedSeconds * Double(maxSteps - currentStep) / Double(currentStep)
    }
}

public struct FinalGenerationSummary: Equatable {
    public var inputFile: String?
    public var outputFile: String?
    public var speakerNames: String?
    public var prefilledTextTokens: Int?
    public var generatedSpeechTokens: Int?
    public var totalTokens: Int?
    public var generationTimeSeconds: Double?
    public var audioDurationSeconds: Double?
    public var rtf: Double?

    public var isEmpty: Bool {
        inputFile == nil &&
            outputFile == nil &&
            speakerNames == nil &&
            prefilledTextTokens == nil &&
            generatedSpeechTokens == nil &&
            totalTokens == nil &&
            generationTimeSeconds == nil &&
            audioDurationSeconds == nil &&
            rtf == nil
    }
}

public enum GenerationOutputParser {
    public static func latestProgress(in logText: String) -> LiveGenerationProgress? {
        let suffix = String(logText.suffix(64_000))
        let pattern = #"Prefilled\s+(\d+)\s+text tokens,\s+generated\s+(\d+)\s+speech tokens,\s+current step\s+\(\s*(\d+)\s*/\s*(\d+)\s*\)"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(suffix.startIndex..<suffix.endIndex, in: suffix)
        guard let match = regex.matches(in: suffix, range: range).last,
              let prefilledTextTokens = int(at: 1, in: suffix, match: match),
              let generatedSpeechTokens = int(at: 2, in: suffix, match: match),
              let currentStep = int(at: 3, in: suffix, match: match),
              let maxSteps = int(at: 4, in: suffix, match: match) else {
            return nil
        }

        return LiveGenerationProgress(
            prefilledTextTokens: prefilledTextTokens,
            generatedSpeechTokens: generatedSpeechTokens,
            currentStep: currentStep,
            maxSteps: maxSteps,
            reportedElapsedSeconds: reportedElapsedSeconds(after: match, in: suffix)
        )
    }

    public static func latestSummary(in logText: String) -> FinalGenerationSummary? {
        let suffix = String(logText.suffix(64_000))
        var summary = FinalGenerationSummary()

        summary.inputFile = lastString(pattern: #"Input file:\s+(.+)"#, in: suffix)
        summary.outputFile = lastString(pattern: #"Output file:\s+(.+)"#, in: suffix)
        summary.speakerNames = lastString(pattern: #"Speaker names:\s+(.+)"#, in: suffix)
        summary.prefilledTextTokens = lastInt(pattern: #"Prefilling text tokens:\s+(\d+)"#, in: suffix)
        summary.generatedSpeechTokens = lastInt(pattern: #"Generated speech tokens:\s+(\d+)"#, in: suffix)
        summary.totalTokens = lastInt(pattern: #"Total tokens:\s+(\d+)"#, in: suffix)
        summary.generationTimeSeconds = lastDouble(pattern: #"Generation time:\s+([\d.]+)\s+seconds"#, in: suffix)
        summary.audioDurationSeconds = lastDouble(pattern: #"Audio duration:\s+([\d.]+)\s+seconds"#, in: suffix)
        summary.rtf = lastDouble(pattern: #"RTF \(Real Time Factor\):\s+([\d.]+)x"#, in: suffix)

        return summary.isEmpty ? nil : summary
    }

    private static func reportedElapsedSeconds(after match: NSTextCheckingResult, in text: String) -> TimeInterval? {
        guard let matchedRange = Range(match.range, in: text) else { return nil }
        let tail = String(text[matchedRange.upperBound...].prefix(160))
        guard let value = lastString(pattern: #"\[\s*([0-9:.]+)\s*\]"#, in: tail) else {
            return nil
        }
        return parseClock(value)
    }

    private static func lastString(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.matches(in: text, range: range).last,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lastInt(pattern: String, in text: String) -> Int? {
        lastString(pattern: pattern, in: text).flatMap(Int.init)
    }

    private static func lastDouble(pattern: String, in text: String) -> Double? {
        lastString(pattern: pattern, in: text).flatMap(Double.init)
    }

    private static func int(at index: Int, in text: String, match: NSTextCheckingResult) -> Int? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[range])
    }

    private static func parseClock(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }

        if parts.count == 3 {
            return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
        }
        if parts.count == 2 {
            return TimeInterval(parts[0] * 60 + parts[1])
        }
        return TimeInterval(parts[0])
    }
}
