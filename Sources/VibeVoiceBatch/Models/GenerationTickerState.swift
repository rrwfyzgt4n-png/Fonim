import Foundation

struct GenerationTickerState: Equatable {
    enum Phase: Equatable {
        case idle
        case running
        case completed
        case failed
        case cancelled
    }

    var phase: Phase
    var progress: GenerationProgressLine?
    var elapsedSeconds: TimeInterval
    var message: String

    static let idle = GenerationTickerState(
        phase: .idle,
        progress: nil,
        elapsedSeconds: 0,
        message: "Ready"
    )

    static func started() -> GenerationTickerState {
        GenerationTickerState(
            phase: .running,
            progress: nil,
            elapsedSeconds: 0,
            message: "Starting Docker generation..."
        )
    }

    func ticking(elapsed: TimeInterval) -> GenerationTickerState {
        var copy = self
        copy.elapsedSeconds = elapsed
        return copy
    }

    func ingesting(logText: String, elapsed: TimeInterval) -> GenerationTickerState {
        var copy = ticking(elapsed: elapsed)
        if let progress = GenerationProgressLine.latest(in: logText) {
            copy.progress = progress
            copy.message = progress.summary
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
            filledCount = min(barWidth, max(1, Int(elapsedSeconds.rounded(.down))))
        } else {
            filledCount = 0
        }

        let bar = "["
            + String(repeating: ".", count: filledCount)
            + String(repeating: " ", count: max(0, barWidth - filledCount))
            + "]"

        let percentText: String
        if phase == .completed {
            percentText = "100%"
        } else if let progress {
            percentText = "\(Int(progress.percent.rounded()))%"
        } else {
            percentText = "--%"
        }

        return "\(bar) \(percentText) live \(Self.clock(elapsedSeconds)) remaining \(remainingText)  \(message)"
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
              let remainingSeconds = progress.estimatedRemainingSeconds(elapsedSeconds: elapsedSeconds) else {
            return "--:--"
        }
        return Self.clock(remainingSeconds)
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

struct GenerationProgressLine: Equatable {
    let textTokens: Int
    let speechTokens: Int
    let currentStep: Int
    let totalSteps: Int
    let percent: Double
    let reportedElapsedSeconds: TimeInterval?

    var fraction: Double {
        guard totalSteps > 0 else { return 0 }
        return min(1, max(0, Double(currentStep) / Double(totalSteps)))
    }

    var summary: String {
        "Prefilled \(textTokens) text tokens, generated \(speechTokens) speech tokens, current step (\(currentStep) / \(totalSteps))"
    }

    func estimatedRemainingSeconds(elapsedSeconds: TimeInterval) -> TimeInterval? {
        guard currentStep > 0, totalSteps > currentStep else { return nil }
        return elapsedSeconds * Double(totalSteps - currentStep) / Double(currentStep)
    }

    static func latest(in logText: String) -> GenerationProgressLine? {
        let suffix = String(logText.suffix(16_000))
        let pattern = #"Prefilled\s+(\d+)\s+text tokens,\s+generated\s+(\d+)\s+speech tokens,\s+current step\s+\(\s*(\d+)\s*/\s*(\d+)\s*\):\s*([0-9]+(?:\.[0-9]+)?)%.*?\[\s*([0-9:.]+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(suffix.startIndex..<suffix.endIndex, in: suffix)
        guard let match = regex.matches(in: suffix, range: range).last else {
            return nil
        }

        func int(at index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: suffix) else { return nil }
            return Int(suffix[range])
        }

        func double(at index: Int) -> Double? {
            guard let range = Range(match.range(at: index), in: suffix) else { return nil }
            return Double(suffix[range])
        }

        func string(at index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: suffix) else { return nil }
            return String(suffix[range])
        }

        guard let textTokens = int(at: 1),
              let speechTokens = int(at: 2),
              let currentStep = int(at: 3),
              let totalSteps = int(at: 4),
              let percent = double(at: 5) else {
            return nil
        }

        return GenerationProgressLine(
            textTokens: textTokens,
            speechTokens: speechTokens,
            currentStep: currentStep,
            totalSteps: totalSteps,
            percent: percent,
            reportedElapsedSeconds: string(at: 6).flatMap(parseClock)
        )
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
