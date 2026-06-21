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
    public var cfgScale: String?
    public var ddpmInferenceSteps: Int?
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
            cfgScale == nil &&
            ddpmInferenceSteps == nil &&
            prefilledTextTokens == nil &&
            generatedSpeechTokens == nil &&
            totalTokens == nil &&
            generationTimeSeconds == nil &&
            audioDurationSeconds == nil &&
            rtf == nil
    }
}

public struct EstimatedGenerationProgress: Equatable {
    public var phase: String
    public var fraction: Double
    public var elapsedSeconds: TimeInterval?
    public var estimatedSeconds: TimeInterval?

    public var percent: Double {
        fraction * 100
    }

    public var displayPhase: String {
        phase
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

public struct ChatterboxGenerationProgress: Equatable {
    public var chunkIndex: Int?
    public var chunkCount: Int?
    public var currentStep: Int?
    public var totalSteps: Int?
    public var reportedElapsedSeconds: TimeInterval?
    public var phase: String

    public var fraction: Double {
        guard let currentStep,
              let totalSteps,
              totalSteps > 0 else {
            guard let chunkIndex, let chunkCount, chunkCount > 0 else {
                return 0
            }
            return min(1, max(0, Double(max(0, chunkIndex - 1)) / Double(chunkCount)))
        }

        let stepFraction = min(1, max(0, Double(currentStep) / Double(totalSteps)))
        guard let chunkIndex, let chunkCount, chunkCount > 0 else {
            return stepFraction
        }

        let completedChunks = Double(max(0, chunkIndex - 1))
        let weightedChunkProgress: Double
        if totalSteps <= 10 {
            weightedChunkProgress = 0.90 + (stepFraction * 0.10)
        } else {
            weightedChunkProgress = stepFraction * 0.90
        }
        return min(1, max(0, (completedChunks + weightedChunkProgress) / Double(chunkCount)))
    }

    public var percent: Double {
        fraction * 100
    }

    public var displayMessage: String {
        var parts: [String] = [phase]
        if let chunkIndex, let chunkCount {
            parts.append("chunk \(chunkIndex)/\(chunkCount)")
        }
        if let currentStep, let totalSteps {
            parts.append("step \(currentStep)/\(totalSteps)")
        }
        return parts.joined(separator: " - ")
    }

    public var progressKey: String {
        let chunkIndexText = chunkIndex.map { String($0) } ?? "_"
        let chunkCountText = chunkCount.map { String($0) } ?? "_"
        let currentStepText = currentStep.map { String($0) } ?? "_"
        let totalStepsText = totalSteps.map { String($0) } ?? "_"
        return "\(phase):\(chunkIndexText):\(chunkCountText):\(currentStepText):\(totalStepsText)"
    }

    public func estimatedRemainingSeconds(elapsedSeconds: TimeInterval) -> TimeInterval? {
        guard fraction > 0.01, fraction < 1 else { return nil }
        return max(0, elapsedSeconds * (1 - fraction) / fraction)
    }
}

public struct KokoroGenerationProgress: Equatable {
    public var chunkIndex: Int?
    public var chunkCount: Int?
    public var currentStep: Int?
    public var totalSteps: Int?
    public var reportedElapsedSeconds: TimeInterval?
    public var phase: String
    public var phaseFraction: Double?

    public var fraction: Double {
        if let currentStep,
           let totalSteps,
           totalSteps > 0 {
            let stepFraction = min(1, max(0, Double(currentStep) / Double(totalSteps)))
            guard let chunkIndex, let chunkCount, chunkCount > 0 else {
                return stepFraction
            }
            return min(1, max(0, (Double(max(0, chunkIndex - 1)) + stepFraction) / Double(chunkCount)))
        }

        if let chunkIndex,
           let chunkCount,
           chunkCount > 0 {
            return min(1, max(0, Double(max(0, chunkIndex - 1)) / Double(chunkCount)))
        }

        return min(1, max(0, phaseFraction ?? 0))
    }

    public var displayMessage: String {
        var parts: [String] = [phase]
        if let chunkIndex, let chunkCount {
            parts.append("chunk \(chunkIndex)/\(chunkCount)")
        }
        if let currentStep, let totalSteps {
            parts.append("step \(currentStep)/\(totalSteps)")
        }
        return parts.joined(separator: " - ")
    }

    public var progressKey: String {
        let chunkIndexText = chunkIndex.map { String($0) } ?? "_"
        let chunkCountText = chunkCount.map { String($0) } ?? "_"
        let currentStepText = currentStep.map { String($0) } ?? "_"
        let totalStepsText = totalSteps.map { String($0) } ?? "_"
        let phaseText = phase.replacingOccurrences(of: " ", with: "_")
        return "\(phaseText):\(chunkIndexText):\(chunkCountText):\(currentStepText):\(totalStepsText)"
    }

    public func estimatedRemainingSeconds(elapsedSeconds: TimeInterval) -> TimeInterval? {
        guard fraction > 0.01, fraction < 1 else { return nil }
        return max(0, elapsedSeconds * (1 - fraction) / fraction)
    }
}

public enum GenerationOutputParser {
    public static func latestProgress(in logText: String) -> LiveGenerationProgress? {
        let suffix = normalizedSuffix(logText)
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
        let suffix = normalizedSuffix(logText)
        var summary = FinalGenerationSummary()

        summary.inputFile = lastString(pattern: #"Input file:\s+(.+)"#, in: suffix)
        summary.outputFile = lastString(pattern: #"Output file:\s+(.+)"#, in: suffix)
        summary.speakerNames = lastString(pattern: #"Speaker names:\s+(.+)"#, in: suffix)
        summary.cfgScale = lastString(pattern: #"CFG scale:\s+(.+)"#, in: suffix)
        summary.ddpmInferenceSteps = lastInt(pattern: #"DDPM inference steps:\s+(\d+)"#, in: suffix)
        summary.prefilledTextTokens = lastInt(pattern: #"Prefilling text tokens:\s+(\d+)"#, in: suffix)
        summary.generatedSpeechTokens = lastInt(pattern: #"Generated speech tokens:\s+(\d+)"#, in: suffix)
        summary.totalTokens = lastInt(pattern: #"Total tokens:\s+(\d+)"#, in: suffix)
        summary.generationTimeSeconds = lastDouble(pattern: #"Generation time:\s+([\d.]+)\s+seconds"#, in: suffix)
        summary.audioDurationSeconds = lastDouble(pattern: #"Audio duration:\s+([\d.]+)\s+seconds"#, in: suffix)
        summary.rtf = lastDouble(pattern: #"RTF \(Real Time Factor\):\s+([\d.]+)x"#, in: suffix)

        return summary.isEmpty ? nil : summary
    }

    public static func latestEstimatedProgress(in logText: String) -> EstimatedGenerationProgress? {
        let suffix = normalizedSuffix(logText)
        let pattern = #"(?:Fonim|VibeVoiceBatch) progress:\s+phase=([^\s]+)\s+elapsed=([0-9:.]+)\s+estimated=([0-9:.]+)\s+progress=([\d.]+)%"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(suffix.startIndex..<suffix.endIndex, in: suffix)
        guard let match = regex.matches(in: suffix, range: range).last,
              let phase = string(at: 1, in: suffix, match: match),
              let progressText = string(at: 4, in: suffix, match: match),
              let progress = Double(progressText) else {
            return nil
        }

        let elapsed = string(at: 2, in: suffix, match: match).flatMap(parseClock)
        let estimated = string(at: 3, in: suffix, match: match).flatMap(parseClock)
        return EstimatedGenerationProgress(
            phase: phase,
            fraction: min(1, max(0, progress / 100)),
            elapsedSeconds: elapsed,
            estimatedSeconds: estimated
        )
    }

    public static func latestChatterboxProgress(in logText: String) -> ChatterboxGenerationProgress? {
        let suffix = normalizedSuffix(logText)
        guard suffix.localizedCaseInsensitiveContains("chatterbox") ||
            suffix.localizedCaseInsensitiveContains("synthesizing chunk") ||
            suffix.localizedCaseInsensitiveContains("s3 token") ||
            suffix.localizedCaseInsensitiveContains("/tts request") else {
            return nil
        }

        let chunkMatch = lastMatch(pattern: #"Synthesizing chunk\s+(\d+)\s*/\s*(\d+)"#, in: suffix)
        let chunkIndex = chunkMatch.flatMap { int(at: 1, in: suffix, match: $0) }
        let chunkCountFromChunk = chunkMatch.flatMap { int(at: 2, in: suffix, match: $0) }
        let chunkCount = chunkCountFromChunk ?? lastInt(pattern: #"Text chunking complete\.\s+Generated\s+(\d+)\s+chunk"#, in: suffix)

        let progressSearchText: String
        if let chunkMatch,
           let range = Range(chunkMatch.range, in: suffix) {
            progressSearchText = String(suffix[range.lowerBound...])
        } else {
            progressSearchText = suffix
        }

        let tqdmPattern = #"(\d+(?:\.\d+)?)%\|[^\r\n]*?\|\s*(\d+)\s*/\s*(\d+)\s*\[\s*([0-9:.]+)(?:<\s*([0-9:.?]+))?"#
        let progressMatch = lastMatch(pattern: tqdmPattern, in: progressSearchText)
        let currentStep = progressMatch.flatMap { int(at: 2, in: progressSearchText, match: $0) }
        let totalSteps = progressMatch.flatMap { int(at: 3, in: progressSearchText, match: $0) }
        let elapsed = progressMatch
            .flatMap { string(at: 4, in: progressSearchText, match: $0) }
            .flatMap(parseClock)

        guard chunkIndex != nil || chunkCount != nil || currentStep != nil else {
            return nil
        }

        let phase: String
        if let totalSteps, totalSteps <= 10 {
            phase = "Mel inference"
        } else if currentStep != nil {
            phase = "Speech tokens"
        } else if chunkCount != nil {
            phase = "Preparing chunks"
        } else {
            phase = "Chatterbox generation"
        }

        return ChatterboxGenerationProgress(
            chunkIndex: chunkIndex,
            chunkCount: chunkCount,
            currentStep: currentStep,
            totalSteps: totalSteps,
            reportedElapsedSeconds: elapsed,
            phase: phase
        )
    }

    public static func latestKokoroProgress(in logText: String) -> KokoroGenerationProgress? {
        let suffix = normalizedSuffix(logText)
        guard suffix.localizedCaseInsensitiveContains("kokoro") ||
            suffix.localizedCaseInsensitiveContains("/v1/audio/speech") ||
            suffix.localizedCaseInsensitiveContains("synthes") ||
            suffix.localizedCaseInsensitiveContains("phonem") ||
            suffix.localizedCaseInsensitiveContains("chunk") else {
            return nil
        }

        let chunkMatch = lastMatch(
            pattern: #"(?i)(?:chunk|segment|sentence)\s+(\d+)\s*(?:/|of)\s*(\d+)"#,
            in: suffix
        )
        let chunkIndex = chunkMatch.flatMap { int(at: 1, in: suffix, match: $0) }
        let chunkCountFromChunk = chunkMatch.flatMap { int(at: 2, in: suffix, match: $0) }
        let chunkCount = chunkCountFromChunk ??
            lastInt(pattern: #"(?i)(?:split|chunking)[^\r\n]*?(?:into|generated)\s+(\d+)\s+(?:chunk|segment|sentence)"#, in: suffix)

        let progressSearchText: String
        if let chunkMatch,
           let range = Range(chunkMatch.range, in: suffix) {
            progressSearchText = String(suffix[range.lowerBound...])
        } else {
            progressSearchText = suffix
        }

        let tqdmPattern = #"(\d+(?:\.\d+)?)%\|[^\r\n]*?\|\s*(\d+)\s*/\s*(\d+)\s*\[\s*([0-9:.]+)(?:<\s*([0-9:.?]+))?"#
        let progressMatch = lastMatch(pattern: tqdmPattern, in: progressSearchText)
        let currentStep = progressMatch.flatMap { int(at: 2, in: progressSearchText, match: $0) }
        let totalSteps = progressMatch.flatMap { int(at: 3, in: progressSearchText, match: $0) }
        let elapsed = progressMatch
            .flatMap { string(at: 4, in: progressSearchText, match: $0) }
            .flatMap(parseClock)

        let phase = kokoroPhase(in: suffix)
        guard chunkIndex != nil || chunkCount != nil || currentStep != nil || phase != nil else {
            return nil
        }

        return KokoroGenerationProgress(
            chunkIndex: chunkIndex,
            chunkCount: chunkCount,
            currentStep: currentStep,
            totalSteps: totalSteps,
            reportedElapsedSeconds: elapsed,
            phase: phase?.name ?? (currentStep == nil ? "Kokoro generation" : "Synthesis"),
            phaseFraction: phase?.fraction
        )
    }

    private static func normalizedSuffix(_ text: String) -> String {
        String(removingANSIEscapeSequences(from: text).suffix(64_000))
    }

    private static func removingANSIEscapeSequences(from text: String) -> String {
        var output = String.UnicodeScalarView()
        var iterator = text.unicodeScalars.makeIterator()

        while let scalar = iterator.next() {
            if scalar.value == 0x1B {
                while let next = iterator.next() {
                    if next.value >= 0x40, next.value <= 0x7E {
                        break
                    }
                }
                continue
            }

            if scalar.value == 0x09 ||
                scalar.value == 0x0A ||
                scalar.value == 0x0D ||
                scalar.value >= 0x20 {
                output.append(scalar)
            }
        }

        return String(output)
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
        guard let match = lastMatch(pattern: pattern, in: text),
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lastMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).last
    }

    private static func string(at index: Int, in text: String, match: NSTextCheckingResult) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func kokoroPhase(in text: String) -> (name: String, fraction: Double)? {
        let lower = text.lowercased()
        let phases: [(needle: String, name: String, fraction: Double)] = [
            ("/v1/audio/speech", "Request received", 0.12),
            ("normaliz", "Preparing text", 0.20),
            ("phonem", "Phonemes", 0.30),
            ("token", "Tokens", 0.40),
            ("synthes", "Synthesis", 0.58),
            ("generating", "Generating audio", 0.58),
            ("vocoder", "Vocoder", 0.76),
            ("encode", "Encoding audio", 0.86),
            ("complete", "Audio complete", 0.92),
            ("saved", "Audio complete", 0.92)
        ]
        return phases.last { lower.contains($0.needle) }.map { ($0.name, $0.fraction) }
    }
}
