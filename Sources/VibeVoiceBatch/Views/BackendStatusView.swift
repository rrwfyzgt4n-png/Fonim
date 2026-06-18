import SwiftUI
import VibeVoiceBatchCore

struct BackendStatusView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            progressArea
            detailRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(statusTint.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusTint)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(statusBadge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusTint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(statusTint.opacity(0.12), in: Capsule())
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)

            if store.backendStatus.technicalDetails != nil || store.backendStatus.recoverySuggestion != nil {
                Button {
                    store.showBackendDetails()
                } label: {
                    Image(systemName: "info.circle")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Show Details")
                .accessibilityLabel("Show backend details")
            }

            Button {
                store.refreshBackendStatus()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshingBackendStatus || store.isGenerating || store.isPreparingGeneration)
            .help("Refresh Backend Status")
            .accessibilityLabel("Refresh backend status")
        }
    }

    @ViewBuilder
    private var progressArea: some View {
        if let fraction = progressFraction {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(statusTint)
        } else if showsIndeterminateProgress {
            ProgressView()
                .progressViewStyle(.linear)
        }
    }

    private var detailRow: some View {
        let metrics = [
            StatusMetricData(label: "Elapsed", value: elapsedText),
            StatusMetricData(label: "Remaining", value: remainingText),
            StatusMetricData(label: "Estimated", value: estimatedTotalText),
            StatusMetricData(label: "Runtime", value: runtimeText),
            StatusMetricData(label: "Progress", value: progressText)
        ]

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                ForEach(metrics) { metric in
                    StatusMetric(label: metric.label, value: metric.value)
                }
                Spacer(minLength: 0)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 12, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(metrics) { metric in
                    StatusMetric(label: metric.label, value: metric.value)
                }
            }
        }
        .font(.caption)
        .padding(.top, 1)
    }

    private var title: String {
        if store.isGenerating {
            return "Generating WAV"
        }
        if store.isPreparingGeneration {
            return "Preparing Generation"
        }
        if store.isPlayingWAV {
            return "Playing WAV"
        }
        return store.selectedBackendProfile.displayName
    }

    private var subtitle: String {
        if store.isGenerating || store.isPreparingGeneration {
            return "\(store.selectedVoice)  CFG \(store.cfgScale)  DDPM \(store.ddpmInferenceSteps)"
        }
        if store.isPlayingWAV {
            return store.playingSessionID ?? "Audio output"
        }
        return store.backendStatus.userMessage
    }

    private var statusBadge: String {
        if store.isGenerating || store.isPreparingGeneration {
            return "Running"
        }
        if store.isPlayingWAV {
            return "Playing"
        }
        if store.isRefreshingBackendStatus {
            return "Checking"
        }
        return store.backendStatus.state.displayName
    }

    private var statusIcon: String {
        if store.isGenerating || store.isPreparingGeneration {
            return "waveform"
        }
        if store.isPlayingWAV {
            return "play.circle.fill"
        }
        switch store.backendStatus.state {
        case .ready:
            return "checkmark.circle.fill"
        case .missing, .failed:
            return "exclamationmark.triangle.fill"
        case .stopped:
            return "pause.circle.fill"
        case .installing, .downloadingModel, .starting, .runningJob:
            return "arrow.triangle.2.circlepath"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var statusTint: Color {
        if store.isGenerating || store.isPreparingGeneration {
            return .blue
        }
        if store.isPlayingWAV {
            return .purple
        }
        switch store.backendStatus.state {
        case .ready:
            return .green
        case .runningJob, .installing, .downloadingModel, .starting:
            return .blue
        case .stopped:
            return .orange
        case .missing, .failed:
            return .red
        case .unknown:
            return .secondary
        }
    }

    private var progressFraction: Double? {
        if store.isPlayingWAV {
            return store.playbackProgressFraction
        }
        if store.isGenerating || store.isPreparingGeneration {
            if let fraction = store.estimatedGenerationProgressFraction {
                return clamped(fraction)
            }
            if let fraction = store.activeGenerationProgress?.fractionComplete {
                return clamped(fraction)
            }
        }
        return nil
    }

    private var showsIndeterminateProgress: Bool {
        store.isGenerating ||
            store.isPreparingGeneration ||
            store.isRefreshingBackendStatus ||
            store.backendStatus.state == .starting ||
            store.backendStatus.state == .installing ||
            store.backendStatus.state == .downloadingModel ||
            store.backendStatus.state == .runningJob
    }

    private var elapsedText: String {
        if store.isPlayingWAV {
            return clock(store.playbackElapsedSeconds)
        }
        if store.isGenerating || store.isPreparingGeneration {
            return clock(store.activeGenerationProgress?.elapsedSeconds ?? store.elapsedSeconds)
        }
        return "--:--"
    }

    private var remainingText: String {
        if store.isPlayingWAV {
            let remaining = max(0, store.playbackDurationSeconds - store.playbackElapsedSeconds)
            return clock(remaining)
        }
        if store.isGenerating || store.isPreparingGeneration {
            if let remaining = store.estimatedGenerationRemainingSeconds ?? store.activeGenerationProgress?.estimatedRemainingSeconds {
                return clock(remaining)
            }
        }
        return "--:--"
    }

    private var estimatedTotalText: String {
        if store.isPlayingWAV {
            return clock(store.playbackDurationSeconds)
        }
        if store.isGenerating || store.isPreparingGeneration {
            if let remaining = store.estimatedGenerationRemainingSeconds {
                return clock(store.elapsedSeconds + remaining)
            }
            if let progress = store.activeGenerationProgress,
               let elapsed = progress.elapsedSeconds,
               let remaining = progress.estimatedRemainingSeconds {
                return clock(elapsed + remaining)
            }
        }
        return "--:--"
    }

    private var runtimeText: String {
        "\(runtimeDisplayName) / \(store.backendStatus.state.displayName)"
    }

    private var progressText: String {
        if let fraction = progressFraction {
            return percentText(fraction)
        }
        if store.isGenerating || store.isPreparingGeneration {
            return store.generationPhaseName.capitalized
        }
        return store.statusMessage
    }

    private var accessibilitySummary: String {
        "\(title), \(statusBadge), elapsed \(elapsedText), runtime \(runtimeText), progress \(progressText)"
    }

    private func percentText(_ fraction: Double) -> String {
        String(format: "%.2f%%", clamped(fraction) * 100)
    }

    private func clamped(_ fraction: Double) -> Double {
        min(1, max(0, fraction))
    }

    private func clock(_ seconds: TimeInterval) -> String {
        GenerationTickerState.clock(seconds)
    }

    private var runtimeDisplayName: String {
        switch store.backendStatus.runtime {
        case .docker:
            return "Docker"
        case .localPython:
            return "Local Python"
        case .comfyUI:
            return "ComfyUI"
        case .native:
            return "Native"
        case .externalService:
            return "External Service"
        }
    }
}

private struct StatusMetricData: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

private struct StatusMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(minWidth: 72, alignment: .leading)
    }
}
