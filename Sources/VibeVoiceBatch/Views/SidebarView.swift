import SwiftUI
import VibeVoiceBatchCore

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $store.selectedSessionID) {
                ForEach(store.sessions) { record in
                    HistoryRow(record: record)
                        .tag(record.id as String?)
                }
            }
            .listStyle(.sidebar)

            HStack {
                Text("\(store.sessions.count) sessions")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.refreshHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh History")
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

private struct HistoryRow: View {
    let record: SessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(SessionFormatters.displayDateFormatter.string(from: record.metadata.createdAt))
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                StatusBadge(status: record.metadata.status)
            }

            Text("\(record.metadata.voice)  cfg \(record.metadata.cfgScale)  \(record.metadata.inputWordCount) words")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("gen \(SessionFormatters.duration(record.metadata.generationTimeSeconds))  audio \(SessionFormatters.duration(record.metadata.audioDurationSeconds))  RTF \(SessionFormatters.rtf(record.metadata.rtf))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
    }
}

struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(foregroundStyle)
            .background(backgroundStyle, in: Capsule())
    }

    private var foregroundStyle: Color {
        switch status {
        case .completed: .green
        case .failed: .red
        case .cancelled: .orange
        case .running: .blue
        case .draft: .secondary
        }
    }

    private var backgroundStyle: Color {
        foregroundStyle.opacity(0.14)
    }
}
