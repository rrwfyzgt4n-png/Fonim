import SwiftUI
import VibeVoiceBatchCore

struct BackendStatusView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(tint)
                    .imageScale(.large)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                        Text(stateText)
                            .font(.caption)
                            .foregroundStyle(tint)
                    }

                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                if store.backendStatus.technicalDetails != nil || store.backendStatus.recoverySuggestion != nil {
                    Button {
                        store.showBackendDetails()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Show Details")
                    .accessibilityLabel("Show backend details")
                }

                Button {
                    store.refreshBackendStatus()
                } label: {
                    Image(systemName: store.isRefreshingBackendStatus ? "hourglass" : "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshingBackendStatus || store.isGenerating)
                .help("Refresh Backend Status")
                .accessibilityLabel("Refresh backend status")
            }

            if showsActivityProgress {
                HStack(spacing: 10) {
                    if let progressFraction {
                        ProgressView(value: progressFraction)
                            .frame(width: 150)
                    } else {
                        ProgressView()
                            .frame(width: 150)
                    }

                    Text(tickerLine)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: showsActivityProgress ? 70 : 44)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(stateText), \(detailText), \(tickerLine)")
    }

    private var showsActivityProgress: Bool {
        store.isGenerating || store.isPlayingWAV
    }

    private var title: String {
        if store.isGenerating {
            return "Generating WAV"
        }
        if store.isPlayingWAV {
            return "Playing WAV"
        }
        return store.backendStatus.displayName
    }

    private var stateText: String {
        if store.isGenerating {
            return "Running"
        }
        if store.isPlayingWAV {
            return "Playing"
        }
        return store.backendStatus.state.displayName
    }

    private var detailText: String {
        if store.isGenerating {
            return generationDetailText
        }
        if store.isPlayingWAV {
            return playbackDetailText
        }
        return store.backendStatus.userMessage
    }

    private var tickerLine: String {
        if store.isGenerating {
            return generationTickerLine
        }
        if store.isPlayingWAV {
            return playbackTickerLine
        }
        return store.backendStatus.userMessage
    }

    private var progressFraction: Double? {
        if store.isGenerating {
            return store.activeGenerationProgress?.fractionComplete
        }
        if store.isPlayingWAV {
            return store.playbackProgressFraction
        }
        return nil
    }

    private var generationDetailText: String {
        let progress = store.activeGenerationProgress
        let percent = progress?.fractionComplete.map { String(format: "%.2f%%", $0 * 100) } ?? "waiting for progress"
        let step = stepText(progress)
        let elapsed = GenerationTickerState.clock(progress?.elapsedSeconds ?? store.elapsedSeconds)
        let remaining = progress?.estimatedRemainingSeconds.map(GenerationTickerState.clock) ?? "--:--"
        return "\(percent)  \(step)  elapsed \(elapsed)  remaining \(remaining)"
    }

    private var generationTickerLine: String {
        let progress = store.activeGenerationProgress
        let fraction = progress?.fractionComplete ?? 0
        let percent = String(format: "%5.2f%%", fraction * 100)
        let elapsed = GenerationTickerState.clock(progress?.elapsedSeconds ?? store.elapsedSeconds)
        let remaining = progress?.estimatedRemainingSeconds.map(GenerationTickerState.clock) ?? "--:--"
        let step = stepText(progress)
        let tokens = tokenText
        return "\(progressBar(fraction: fraction)) \(percent)  elapsed \(elapsed)  remaining \(remaining)  \(step)  \(tokens)"
    }

    private var playbackDetailText: String {
        let elapsed = GenerationTickerState.clock(store.playbackElapsedSeconds)
        let duration = GenerationTickerState.clock(store.playbackDurationSeconds)
        let session = store.playingSessionID ?? "output.wav"
        return "\(session)  \(elapsed) / \(duration)"
    }

    private var playbackTickerLine: String {
        let fraction = store.playbackProgressFraction ?? 0
        let percent = String(format: "%5.2f%%", fraction * 100)
        let elapsed = GenerationTickerState.clock(store.playbackElapsedSeconds)
        let duration = GenerationTickerState.clock(store.playbackDurationSeconds)
        return "\(progressBar(fraction: fraction)) \(percent)  playing \(elapsed) / \(duration)"
    }

    private var tokenText: String {
        guard let progress = store.generationTicker.progress else {
            return "text tokens --  speech tokens --"
        }
        return "text tokens \(progress.prefilledTextTokens)  speech tokens \(progress.generatedSpeechTokens)"
    }

    private func stepText(_ progress: GenerationProgressSnapshot?) -> String {
        guard let currentStep = progress?.currentStep,
              let totalSteps = progress?.totalSteps else {
            return "step -- / --"
        }
        return "step \(currentStep) / \(totalSteps)"
    }

    private func progressBar(fraction: Double) -> String {
        let width = 28
        let filled = min(width, max(0, Int((fraction * Double(width)).rounded(.down))))
        return "["
            + String(repeating: ".", count: filled)
            + String(repeating: " ", count: max(0, width - filled))
            + "]"
    }

    private var iconName: String {
        if store.isPlayingWAV {
            return "play.circle.fill"
        }
        switch store.backendStatus.state {
        case .ready:
            return "checkmark.circle.fill"
        case .runningJob:
            return "waveform.circle.fill"
        case .missing:
            return "xmark.octagon.fill"
        case .stopped:
            return "pause.circle.fill"
        case .installing, .downloadingModel, .starting:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    private var tint: Color {
        if store.isPlayingWAV {
            return .purple
        }
        switch store.backendStatus.state {
        case .ready:
            return .green
        case .runningJob, .installing, .downloadingModel, .starting:
            return .blue
        case .missing, .failed:
            return .red
        case .stopped:
            return .orange
        case .unknown:
            return .secondary
        }
    }
}
