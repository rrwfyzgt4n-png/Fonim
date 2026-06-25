import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct FonimInfoView: View {
    @EnvironmentObject private var store: AppStore
    @State private var reference = MediaRuntimeCatalog.bundled.randomReadableReference(for: 3_843)

    private let runtimeCatalog = MediaRuntimeCatalog.bundled

    private var summary: GeneratedAudioLibrarySummary {
        GeneratedAudioLibrarySummary(sessions: store.sessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            HStack(spacing: 12) {
                InfoMetricCard(title: "Generated Audio", value: generatedDurationText)
                InfoMetricCard(title: "Generations", value: "\(summary.generatedSessionCount)")
                InfoMetricCard(title: "Known Durations", value: "\(summary.sessionsWithKnownDurationCount)")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(equivalenceSentence)
                    .font(.title3.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                if summary.missingDurationCount > 0 {
                    Text("\(summary.missingDurationCount) generated session\(summary.missingDurationCount == 1 ? "" : "s") without audio duration metadata are not included.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("New Comparison") {
                    pickReference()
                }
            }
        }
        .padding(28)
        .frame(width: 560)
        .onAppear {
            store.refreshHistory()
            pickReference()
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 78, height: 78)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Fonim")
                    .font(.largeTitle.weight(.semibold))
                Text("Local narration workstation")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generatedDurationText: String {
        summary.hasGeneratedAudioDuration ?
            SessionFormatters.longDuration(summary.totalAudioDurationSeconds) :
            "0 seconds"
    }

    private var equivalenceSentence: String {
        guard summary.hasGeneratedAudioDuration else {
            return "No generated audio duration has been recorded yet."
        }
        return "\(generatedDurationText), or about \(reference.equivalentText(for: summary.totalAudioDurationSeconds))."
    }

    private func pickReference() {
        reference = runtimeCatalog.randomReadableReference(
            for: summary.totalAudioDurationSeconds,
            excluding: reference
        )
    }
}

private struct InfoMetricCard: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
