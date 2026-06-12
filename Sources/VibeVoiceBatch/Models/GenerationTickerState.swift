import Foundation
import VibeVoiceBatchCore

struct GenerationTickerState: Equatable {
    enum Phase: Equatable {
        case idle
        case running
        case completed
        case failed
        case cancelled
    }

    var phase: Phase
    var progress: LiveGenerationProgress?
    var finalSummary: FinalGenerationSummary?
    var elapsedSeconds: TimeInterval
    var message: String
    var voice: String?
    var cfgScale: String?

    static let idle = GenerationTickerState(
        phase: .idle,
        progress: nil,
        finalSummary: nil,
        elapsedSeconds: 0,
        message: "Ready",
        voice: nil,
        cfgScale: nil
    )

    static func started(voice: String, cfgScale: String) -> GenerationTickerState {
        GenerationTickerState(
            phase: .running,
            progress: nil,
            finalSummary: nil,
            elapsedSeconds: 0,
            message: "Starting Docker generation...",
            voice: voice,
            cfgScale: cfgScale
        )
    }

    func ticking(elapsed: TimeInterval) -> GenerationTickerState {
        var copy = self
        copy.elapsedSeconds = elapsed
        return copy
    }

    func ingesting(logText: String, elapsed: TimeInterval) -> GenerationTickerState {
        var copy = ticking(elapsed: elapsed)
        if let progress = GenerationOutputParser.latestProgress(in: logText) {
            copy.progress = progress
            copy.message = "current step (\(progress.currentStep) / \(progress.maxSteps))"
        }
        if let summary = GenerationOutputParser.latestSummary(in: logText) {
            copy.finalSummary = summary
            if let speakerNames = summary.speakerNames {
                copy.voice = speakerNames
            }
        }
        return copy
    }

    func finished(message: String, elapsed: TimeInterval, phase: Phase) -> GenerationTickerState {
        var copy = ticking(elapsed: elapsed)
        copy.phase = phase
        copy.message = message
        return copy
    }

    var displayLine: String {
        let barWidth = 36
        let filledCount: Int
        if phase == .completed {
            filledCount = barWidth
        } else if let progress {
            filledCount = min(barWidth, max(0, Int((progress.fraction * Double(barWidth)).rounded(.down))))
        } else if phase == .running {
            filledCount = min(barWidth, max(1, Int((elapsedSeconds / 10).rounded(.down))))
        } else {
            filledCount = 0
        }

        let bar = "["
            + String(repeating: ".", count: filledCount)
            + String(repeating: " ", count: max(0, barWidth - filledCount))
            + "]"

        return [
            "Status: \(phaseText)",
            "Voice: \(voiceText)",
            "CFG: \(cfgScale ?? "--")",
            bar,
            "Progress: \(progressText)",
            "Elapsed: \(elapsedText)",
            "Remaining: \(remainingText)",
            "Text tokens: \(textTokensText)",
            "Speech tokens: \(speechTokensText)",
            "Current step: \(currentStepText)",
            "DDPM steps: --",
            "Generation time: \(generationTimeText)",
            "Audio duration: \(audioDurationText)",
            "RTF: \(rtfText)",
            "Output: \(outputText)"
        ].joined(separator: " | ")
    }

    var isActive: Bool {
        phase == .running
    }

    var isProblem: Bool {
        phase == .failed || phase == .cancelled
    }

    private var remainingText: String {
        guard phase == .running,
              let progress,
              let remainingSeconds = progress.estimatedRemainingSeconds(elapsedSeconds: elapsedForProgress) else {
            return "--:--"
        }
        return Self.clock(remainingSeconds)
    }

    private var elapsedForProgress: TimeInterval {
        progress?.reportedElapsedSeconds ?? elapsedSeconds
    }

    private var phaseText: String {
        switch phase {
        case .idle: return "Ready"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private var voiceText: String {
        voice ?? finalSummary?.speakerNames ?? "--"
    }

    private var progressText: String {
        if phase == .completed {
            return "100.00%"
        }
        guard let progress else { return "--" }
        return String(format: "%.2f%%", progress.percent)
    }

    private var elapsedText: String {
        Self.clock(elapsedForProgress)
    }

    private var textTokensText: String {
        if let value = finalSummary?.prefilledTextTokens ?? progress?.prefilledTextTokens {
            return "\(value)"
        }
        return "--"
    }

    private var speechTokensText: String {
        if let value = finalSummary?.generatedSpeechTokens ?? progress?.generatedSpeechTokens {
            return "\(value)"
        }
        return "--"
    }

    private var currentStepText: String {
        guard let progress else { return "--" }
        return "\(progress.currentStep) / \(progress.maxSteps)"
    }

    private var generationTimeText: String {
        guard let value = finalSummary?.generationTimeSeconds else { return "--" }
        return String(format: "%.2f seconds", value)
    }

    private var audioDurationText: String {
        guard let value = finalSummary?.audioDurationSeconds else { return "--" }
        return String(format: "%.2f seconds", value)
    }

    private var rtfText: String {
        guard let value = finalSummary?.rtf else { return "--" }
        return String(format: "%.2fx", value)
    }

    private var outputText: String {
        finalSummary?.outputFile ?? "--"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
