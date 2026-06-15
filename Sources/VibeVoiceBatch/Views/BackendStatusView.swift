import SwiftUI
import VibeVoiceBatchCore

struct BackendStatusView: View {
    @EnvironmentObject private var store: AppStore

    private let terminalHeight: CGFloat = 82

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(headerLine)
                    .foregroundStyle(terminalAccent)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 12)

                if store.backendStatus.technicalDetails != nil || store.backendStatus.recoverySuggestion != nil {
                    Button {
                        store.showBackendDetails()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(terminalDim)
                    .help("Show Details")
                    .accessibilityLabel("Show backend details")
                }

                Button {
                    store.refreshBackendStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(terminalDim)
                .disabled(store.isRefreshingBackendStatus || store.isGenerating)
                .help("Refresh Backend Status")
                .accessibilityLabel("Refresh backend status")
            }

            Text(primaryLine)
                .foregroundStyle(terminalText)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Text(tickerLine)
                .foregroundStyle(terminalAccent)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: terminalHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(terminalAccent.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: terminalAccent.opacity(0.10), radius: 8, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headerLine), \(primaryLine), \(tickerLine)")
    }

    private var headerLine: String {
        if store.isGenerating {
            return "> GENERATING_WAV  RUNNING  voice=\(store.selectedVoice)  cfg=\(store.cfgScale)  ddpm=\(store.ddpmInferenceSteps)"
        }
        if store.isPreparingGeneration {
            return "> GENERATING_WAV  PREPARING  voice=\(store.selectedVoice)  cfg=\(store.cfgScale)  ddpm=\(store.ddpmInferenceSteps)"
        }
        if store.isPlayingWAV {
            return "> PLAYING_WAV  PLAYING  session=\(store.playingSessionID ?? "output.wav")"
        }
        return "> BACKEND  \(store.backendStatus.state.displayName.uppercased())  \(store.backendStatus.displayName)"
    }

    private var primaryLine: String {
        if store.isGenerating || store.isPreparingGeneration {
            return generationPrimaryLine
        }
        if store.isPlayingWAV {
            return playbackPrimaryLine
        }
        return store.backendStatus.userMessage
    }

    private var tickerLine: String {
        if store.isGenerating || store.isPreparingGeneration {
            return generationTickerLine
        }
        if store.isPlayingWAV {
            return playbackTickerLine
        }
        return "\(idleIndicator) \(store.statusMessage)"
    }

    private var generationPrimaryLine: String {
        if store.isPreparingGeneration, !store.isGenerating {
            return "elapsed=\(clock(store.elapsedSeconds))  phase=\(store.generationPhaseName)  status=preparing_backend"
        }

        guard let progress = store.activeGenerationProgress else {
            return "elapsed=\(clock(store.elapsedSeconds))  phase=\(store.generationPhaseName)  backend=\(displayGenerationLine)"
        }

        let percent = percentText(progress.fractionComplete)
        let elapsed = clock(progress.elapsedSeconds ?? store.elapsedSeconds)
        let remaining = progress.estimatedRemainingSeconds.map(clock) ?? "--:--"
        let step = stepText(progress)
        return "progress=\(percent)  elapsed=\(elapsed)  remaining=\(remaining)  \(step)"
    }

    private var generationTickerLine: String {
        guard let progress = store.activeGenerationProgress,
              let fraction = progress.fractionComplete else {
            return "\(activitySweepBar(elapsed: store.elapsedSeconds)) \(spinnerFrame(elapsed: store.elapsedSeconds)) elapsed=\(clock(store.elapsedSeconds))  \(tokenText)"
        }

        return "\(progressBar(fraction: fraction)) \(percentText(fraction))  \(stepText(progress))  \(tokenText)"
    }

    private var playbackPrimaryLine: String {
        let elapsed = clock(store.playbackElapsedSeconds)
        let duration = clock(store.playbackDurationSeconds)
        return "playback=\(percentText(store.playbackProgressFraction))  elapsed=\(elapsed)  duration=\(duration)"
    }

    private var playbackTickerLine: String {
        let fraction = store.playbackProgressFraction ?? 0
        return "\(progressBar(fraction: fraction)) \(percentText(fraction))  playing \(clock(store.playbackElapsedSeconds)) / \(clock(store.playbackDurationSeconds))"
    }

    private var tokenText: String {
        guard let progress = store.generationTicker.progress else {
            return "text_tokens=--  speech_tokens=--"
        }
        return "text_tokens=\(progress.prefilledTextTokens)  speech_tokens=\(progress.generatedSpeechTokens)"
    }

    private var displayGenerationLine: String {
        let line = store.latestGenerationLogLine
        if line.hasPrefix("VibeVoiceBatch progress:") {
            return "generation heartbeat"
        }
        return line
    }

    private var idleIndicator: String {
        switch store.backendStatus.state {
        case .ready:
            return "[............................] ready"
        case .missing, .failed:
            return "[!!!!!!!!!!!!!!!!!!!!!!!!!!!!] attention"
        case .stopped:
            return "[----------------------------] stopped"
        case .installing, .downloadingModel, .starting, .runningJob:
            return scannerBar(elapsed: store.elapsedSeconds)
        case .unknown:
            return "[????????????????????????????] unknown"
        }
    }

    private func stepText(_ progress: GenerationProgressSnapshot?) -> String {
        guard let currentStep = progress?.currentStep,
              let totalSteps = progress?.totalSteps else {
            return "step=--/--"
        }
        return "step=\(currentStep)/\(totalSteps)"
    }

    private func progressBar(fraction: Double) -> String {
        let width = 28
        let filled = min(width, max(0, Int((fraction * Double(width)).rounded(.down))))
        return "["
            + String(repeating: ".", count: filled)
            + String(repeating: " ", count: max(0, width - filled))
            + "]"
    }

    private func scannerBar(elapsed: TimeInterval) -> String {
        let width = 28
        let position = Int((elapsed * 4).rounded(.down)) % width
        let body = (0..<width).map { index in
            if index == position { return spinnerFrame(elapsed: elapsed) }
            return index < position ? "." : " "
        }.joined()
        return "[\(body)]"
    }

    private func activitySweepBar(elapsed: TimeInterval) -> String {
        let width = 32
        let cycle = max(1, (width - 1) * 2)
        let raw = Int((elapsed * 8).rounded(.down)) % cycle
        let position = raw < width ? raw : cycle - raw
        let body = (0..<width).map { index in
            let distance = abs(index - position)
            if distance == 0 { return "|" }
            if distance == 1 { return "." }
            return " "
        }.joined()
        return "[\(body)]"
    }

    private func spinnerFrame(elapsed: TimeInterval) -> String {
        let frames = ["|", "/", "-", "\\"]
        let index = Int((elapsed * 4).rounded(.down)) % frames.count
        return frames[index]
    }

    private func percentText(_ fraction: Double?) -> String {
        guard let fraction else { return "--.--%" }
        return String(format: "%5.2f%%", min(1, max(0, fraction)) * 100)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        GenerationTickerState.clock(seconds)
    }

    private var terminalAccent: Color {
        if store.isGenerating || store.isPreparingGeneration {
            return Color(red: 0.18, green: 0.72, blue: 1.0)
        }
        if store.isPlayingWAV {
            return Color(red: 0.36, green: 1.0, blue: 0.52)
        }
        switch store.backendStatus.state {
        case .ready:
            return Color(red: 0.36, green: 1.0, blue: 0.52)
        case .runningJob, .installing, .downloadingModel, .starting:
            return Color(red: 0.18, green: 0.72, blue: 1.0)
        case .missing, .failed:
            return Color(red: 1.0, green: 0.32, blue: 0.28)
        case .stopped:
            return Color(red: 1.0, green: 0.72, blue: 0.24)
        case .unknown:
            return Color(red: 0.60, green: 0.75, blue: 0.82)
        }
    }

    private var terminalText: Color {
        Color(red: 0.78, green: 0.95, blue: 0.86)
    }

    private var terminalDim: Color {
        Color(red: 0.48, green: 0.66, blue: 0.62)
    }
}
