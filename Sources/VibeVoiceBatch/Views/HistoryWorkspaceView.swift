import SwiftUI
import VibeVoiceBatchCore

struct HistoryWorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var sortMode = HistorySortMode.newest

    private var records: [SessionRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = store.sessions.filter { record in
            guard !query.isEmpty else { return true }
            return [
                record.id,
                record.metadata.voice,
                record.metadata.cfgScale,
                record.metadata.dockerImage,
                record.metadata.status.rawValue,
                record.inputText
            ]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
        }

        return filtered.sorted(by: sortMode.compare)
    }

    var body: some View {
        HSplitView {
            historyListPane
                .frame(minWidth: 310, idealWidth: 370)

            detailPane
                .frame(minWidth: 520)
        }
        .navigationTitle(navigationTitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search history")
        .onAppear {
            store.refreshHistory()
        }
    }

    private var historyListPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HistorySummaryStrip(
                sessionsCount: store.sessions.count,
                outputCount: store.outputSessions.count,
                draftCount: store.sessions.filter { $0.metadata.status == .draft }.count
            )
            .padding([.horizontal, .top], 14)
            .padding(.bottom, 10)

            HStack {
                Picker("Sort", selection: $sortMode) {
                    ForEach(HistorySortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 170)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
                List(selection: $store.selectedSessionID) {
                    Section {
                        CurrentTextHistoryRow(isSelected: store.selectedSessionID == nil)
                            .id("current-editor")
                            .tag(String?.none)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.selectedSessionID = nil
                            }
                    }

                    Section("Sessions") {
                        if records.isEmpty {
                            HistoryEmptyRow(hasSearch: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            ForEach(records) { record in
                                HistorySessionRow(
                                    record: record,
                                    isSelected: store.selectedSessionID == record.id
                                )
                                .id(record.id)
                                .tag(Optional(record.id))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    store.selectedSessionID = record.id
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        store.duplicateAsNew(record)
                                    } label: {
                                        Label("Duplicate", systemImage: "doc.on.doc")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        store.archiveDeleteSession(record)
                                    } label: {
                                        Label("Archive", systemImage: "archivebox")
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        store.duplicateAsNew(record)
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
                                    } label: {
                                        Label("Archive", systemImage: "archivebox")
                                    }
                                }
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

    @ViewBuilder
    private var detailPane: some View {
        if let selectedSession = store.selectedSession {
            SessionDetailView(record: selectedSession)
        } else if let selectedSessionID = store.selectedSessionID {
            MissingHistorySelectionView(sessionID: selectedSessionID)
        } else {
            EditorView()
        }
    }

    private var navigationTitle: String {
        if store.selectedSession != nil {
            return "History"
        }
        return store.hasUnsavedEditorText ? "Unsaved Text" : "New Session"
    }

    private func scrollToPendingSession(using proxy: ScrollViewProxy) {
        guard let sessionID = store.pendingScrollSessionID else { return }
        store.selectedSessionID = sessionID
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(sessionID, anchor: .center)
        }
        store.clearPendingScrollRequest()
    }
}

private enum HistorySortMode: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case voice
    case status
    case words
    case audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Newest First"
        case .oldest: "Oldest First"
        case .voice: "Voice"
        case .status: "Status"
        case .words: "Word Count"
        case .audio: "Audio Duration"
        }
    }

    func compare(_ lhs: SessionRecord, _ rhs: SessionRecord) -> Bool {
        switch self {
        case .newest:
            return lhs.metadata.createdAt > rhs.metadata.createdAt
        case .oldest:
            return lhs.metadata.createdAt < rhs.metadata.createdAt
        case .voice:
            return lhs.metadata.voice.localizedCaseInsensitiveCompare(rhs.metadata.voice) == .orderedAscending
        case .status:
            return lhs.metadata.status.rawValue.localizedCaseInsensitiveCompare(rhs.metadata.status.rawValue) == .orderedAscending
        case .words:
            return lhs.metadata.inputWordCount > rhs.metadata.inputWordCount
        case .audio:
            return (lhs.metadata.audioDurationSeconds ?? 0) > (rhs.metadata.audioDurationSeconds ?? 0)
        }
    }
}

private struct HistorySummaryStrip: View {
    let sessionsCount: Int
    let outputCount: Int
    let draftCount: Int

    var body: some View {
        HStack(spacing: 18) {
            HistoryMetric(title: "Sessions", value: "\(sessionsCount)")
            HistoryMetric(title: "Outputs", value: "\(outputCount)")
            HistoryMetric(title: "Drafts", value: "\(draftCount)")
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct HistoryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
    }
}

private struct CurrentTextHistoryRow: View {
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Current Text")
                    .lineLimit(1)
                Text("Editor and generation controls")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .imageScale(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HistorySessionRow: View {
    let record: SessionRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusTint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(SessionFormatters.displayDateFormatter.string(from: record.metadata.createdAt))
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .imageScale(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        "\(record.metadata.voice)  \(record.metadata.inputWordCount) words  \(SessionFormatters.duration(record.metadata.audioDurationSeconds))"
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

private struct HistoryEmptyRow: View {
    let hasSearch: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: hasSearch ? "magnifyingglass" : "clock.arrow.circlepath")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(hasSearch ? "No Matching Sessions" : "No Sessions Yet")
                .font(.headline)
            Text(hasSearch ? "Try a different search." : "Saved drafts and generated WAV sessions will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

private struct MissingHistorySelectionView: View {
    let sessionID: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.folder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Session Not Found")
                .font(.headline)
            Text(sessionID)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
