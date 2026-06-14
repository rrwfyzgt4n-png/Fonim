import SwiftUI
import VibeVoiceBatchCore

struct BackendStatusView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .imageScale(.medium)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(store.backendStatus.displayName)
                        .font(.caption.weight(.semibold))
                    Text(store.backendStatus.state.displayName)
                        .font(.caption)
                        .foregroundStyle(tint)
                }

                Text(store.backendStatus.userMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(store.backendStatus.displayName), \(store.backendStatus.state.displayName), \(store.backendStatus.userMessage)")
    }

    private var iconName: String {
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
