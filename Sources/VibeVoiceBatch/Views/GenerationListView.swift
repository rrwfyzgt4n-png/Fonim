import SwiftUI
import VibeVoiceBatchCore

struct GenerationListView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: WorkstationSelection?

    private var orderedSessions: [SessionRecord] {
        store.sessions.sorted {
            if $0.metadata.createdAt == $1.metadata.createdAt {
                return $0.id < $1.id
            }
            return $0.metadata.createdAt < $1.metadata.createdAt
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            generationHeader

            Divider()

            ScrollViewReader { proxy in
                List(selection: $selection) {
                    if orderedSessions.isEmpty {
                        GenerationListEmptyView()
                    } else {
                        ForEach(orderedSessions) { record in
                            GenerationListRow(
                                record: record,
                                isSelected: selection == .historySession(record.id)
                            )
                            .id(record.id)
                            .tag(WorkstationSelection.historySession(record.id) as WorkstationSelection?)
                            .contentShape(Rectangle())
                            .onTapGesture { selectHistory(record) }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    store.duplicateAsNew(record)
                                    selection = .section(.history)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.archiveDeleteSession(record)
                                    selection = .section(.history)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                            }
                            .contextMenu {
                                generationMenu(for: record)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .onAppear {
                    scrollToPendingSession(using: proxy)
                }
                .onChange(of: store.pendingScrollSessionID) { sessionID in
                    guard sessionID != nil else { return }
                    scrollToPendingSession(using: proxy)
                }
            }
        }
    }

    private var generationHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Generations")
                    .font(.headline)
                Text("\(store.sessions.count) sessions, oldest first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.refreshHistory()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Refresh Generations")
            .accessibilityLabel("Refresh generations")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func generationMenu(for record: SessionRecord) -> some View {
        Button {
            store.duplicateAsNew(record)
            selection = .section(.history)
        } label: {
            Label("Duplicate as New", systemImage: "doc.on.doc")
        }

        if record.outputURL != nil {
            Button {
                store.playWAV(record)
            } label: {
                Label(store.isPlaying(record) ? "Stop WAV" : "Play WAV", systemImage: store.isPlaying(record) ? "stop.circle" : "play.circle")
            }

            Button {
                store.revealOutputFile(record)
            } label: {
                Label("Reveal WAV", systemImage: "finder")
            }
        }

        Button {
            store.openSessionFolder(record)
        } label: {
            Label("Open Session Folder", systemImage: "folder")
        }

        Divider()

        Button(role: .destructive) {
            store.archiveDeleteSession(record)
            selection = .section(.history)
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
    }

    private func selectHistory(_ record: SessionRecord) {
        selection = .historySession(record.id)
        store.selectedSessionID = record.id
    }

    private func scrollToPendingSession(using proxy: ScrollViewProxy) {
        guard let sessionID = store.pendingScrollSessionID else { return }
        selection = .historySession(sessionID)
        store.selectedSessionID = sessionID
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(sessionID, anchor: .bottom)
        }
        store.clearPendingScrollRequest()
    }
}

private struct GenerationListRow: View {
    let record: SessionRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusTint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(SessionFormatters.displayDateFormatter.string(from: record.metadata.createdAt))
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    VoiceInlineLabel(voiceID: record.metadata.voice, compact: true)
                    Text("\(record.metadata.inputWordCount) words")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        "\(record.metadata.status.displayName), \(VoiceDisplayFormatter.displayText(for: record.metadata.voice)), \(record.metadata.inputWordCount) words"
    }

    private var statusIcon: String {
        switch record.metadata.status {
        case .completed: "checkmark.circle"
        case .failed: "xmark.octagon"
        case .cancelled: "pause.circle"
        case .running: "waveform.circle"
        case .draft: "doc.text"
        }
    }

    private var statusTint: Color {
        switch record.metadata.status {
        case .completed: .green
        case .failed: .red
        case .cancelled: .orange
        case .running: .blue
        case .draft: .secondary
        }
    }
}

private struct GenerationListEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Generations")
                .font(.headline)
            Text("Saved drafts and completed outputs will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
