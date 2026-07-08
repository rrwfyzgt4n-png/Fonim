import SwiftUI
import VibeVoiceBatchCore

struct GenerationWorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: WorkstationSelection?

    var body: some View {
        HSplitView {
            GenerationListView(selection: $selection)
                .frame(minWidth: 230, idealWidth: 280, maxWidth: 380)

            generationDetail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var generationDetail: some View {
        switch selection ?? .section(.history) {
        case .section(.history):
            ZStack {
                EditorView()
                prewarmedSessionDetail
            }
        case .queuedGeneration(let itemID):
            if let item = store.queuedGenerations.first(where: { $0.id == itemID }) {
                QueuedGenerationDetailView(item: item)
            } else {
                EditorView()
            }
        case .historySession(let sessionID):
            if let session = store.session(id: sessionID) {
                SessionDetailView(record: session)
            } else {
                MissingHistorySelectionView(sessionID: sessionID)
            }
        case .section(_):
            EditorView()
        }
    }

    @ViewBuilder
    private var prewarmedSessionDetail: some View {
        if let session = store.sessions.first {
            SessionDetailView(record: session, showsNavigationTitle: false)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct QueuedGenerationDetailView: View {
    let item: QueuedGenerationItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.status.displayName)
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Text(SessionFormatters.displayDateFormatter.string(from: item.createdAt))
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        detail("Voice", VoiceDisplayFormatter.displayText(for: item.voice))
                        detail("CFG", item.cfgScale)
                        detail("Steps", "\(item.ddpmInferenceSteps)")
                    }
                    GridRow {
                        detail("Words", "\(TextMetrics.wordCount(in: item.sourceText))")
                        detail("Elapsed", SessionFormatters.duration(item.elapsedSeconds))
                        detail("Remaining", SessionFormatters.duration(item.estimatedRemainingSeconds))
                    }
                }

                Text("Input")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(item.sourceText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
        }
    }
}
