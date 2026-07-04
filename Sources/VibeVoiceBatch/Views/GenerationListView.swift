import SwiftUI
import VibeVoiceBatchCore

struct GenerationListView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @Binding var selection: WorkstationSelection?

    private var displayModel: GenerationListDisplayModel {
        GenerationListDisplayModel(
            sessions: store.sessions,
            queuedItems: store.queuedGenerations,
            batches: workspaceStore.batches
        )
    }

    var body: some View {
        let model = displayModel

        VStack(spacing: 0) {
            generationHeader(sessionCount: model.sessions.count, queuedCount: model.queuedItems.count)

            Divider()

            ScrollViewReader { proxy in
                List(selection: $selection) {
                    if model.isEmpty {
                        GenerationListEmptyView()
                    } else {
                        ForEach(model.items) { item in
                            switch item {
                            case .queued(let queued):
                                QueuedGenerationListRow(
                                    item: queued,
                                    marker: model.queueMarker(for: queued),
                                    isSelected: selection == .queuedGeneration(queued.id)
                                )
                                .id(queued.id)
                                .tag(WorkstationSelection.queuedGeneration(queued.id) as WorkstationSelection?)
                                .contentShape(Rectangle())
                                .onTapGesture { selectQueued(queued) }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        store.duplicateQueuedGenerationAsNew(queued)
                                        selection = .section(.history)
                                    } label: {
                                        Label("Duplicate", systemImage: "doc.on.doc")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        store.cancelQueuedGeneration(queued)
                                    } label: {
                                        Label("Cancel", systemImage: "xmark.circle")
                                    }
                                }
                                .contextMenu {
                                    queuedGenerationMenu(for: queued)
                                }

                            case .session(let record):
                                GenerationListRow(
                                    record: record,
                                    marker: model.sessionMarker(for: record),
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

    private func generationHeader(sessionCount: Int, queuedCount: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Generations")
                    .font(.headline)
                Text(headerDetail(sessionCount: sessionCount, queuedCount: queuedCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.refreshHistory()
                workspaceStore.refresh()
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

    private func headerDetail(sessionCount: Int, queuedCount: Int) -> String {
        if queuedCount > 0 {
            return "\(queuedCount) queued, \(sessionCount) saved"
        }
        return "\(sessionCount) saved, newest first"
    }

    @ViewBuilder
    private func queuedGenerationMenu(for item: QueuedGenerationItem) -> some View {
        Button {
            store.duplicateQueuedGenerationAsNew(item)
            selection = .section(.history)
        } label: {
            Label("Duplicate as New", systemImage: "doc.on.doc")
        }

        Button(role: .destructive) {
            store.cancelQueuedGeneration(item)
        } label: {
            Label(item.status == .running ? "Stop Generation" : "Cancel Queued Item", systemImage: "xmark.circle")
        }
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

    private func selectQueued(_ item: QueuedGenerationItem) {
        store.selectedQueueItemID = item.id
        store.selectedSessionID = nil
        selection = .queuedGeneration(item.id)
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
            proxy.scrollTo(sessionID, anchor: .center)
        }
        store.clearPendingScrollRequest()
    }
}

private struct GenerationListDisplayModel {
    let sessions: [SessionRecord]
    let queuedItems: [QueuedGenerationItem]
    let items: [GenerationListItem]
    private let sessionMarkers: [String: ScriptSectionMarker]
    private let queueMarkers: [String: ScriptSectionMarker]

    init(
        sessions: [SessionRecord],
        queuedItems: [QueuedGenerationItem],
        batches: [NarrationBatch]
    ) {
        var markersByBatchItemID: [String: ScriptSectionMarker] = [:]
        var markersBySessionID: [String: ScriptSectionMarker] = [:]

        for batch in batches {
            let total = batch.items.count
            for item in batch.items {
                let marker = ScriptSectionMarker(
                    batchID: batch.id,
                    batchCreatedAt: batch.createdAt,
                    position: item.position,
                    total: total
                )
                markersByBatchItemID[item.id] = marker
                if let generationSessionID = item.generationSessionID {
                    markersBySessionID[generationSessionID] = marker
                }
            }
        }

        var queueMarkers: [String: ScriptSectionMarker] = [:]
        for item in queuedItems {
            if let batchItemID = item.batchItemID, let marker = markersByBatchItemID[batchItemID] {
                queueMarkers[item.id] = marker
            }
        }

        self.sessionMarkers = markersBySessionID
        self.queueMarkers = queueMarkers
        let activeQueuedItems = queuedItems
            .filter { !$0.status.isTerminal }
            .sorted { lhs, rhs in
                Self.newestQueuedFirst(lhs, rhs)
            }
        let sortedSessions = sessions.sorted { lhs, rhs in
            Self.newestSessionFirst(lhs, rhs)
        }
        self.queuedItems = activeQueuedItems
        self.sessions = sortedSessions
        self.items = (activeQueuedItems.map(GenerationListItem.queued) + sortedSessions.map(GenerationListItem.session))
            .sorted { lhs, rhs in
                if lhs.sortDate == rhs.sortDate {
                    return lhs.stableID > rhs.stableID
                }
                return lhs.sortDate > rhs.sortDate
            }
    }

    var isEmpty: Bool {
        queuedItems.isEmpty && sessions.isEmpty
    }

    func sessionMarker(for record: SessionRecord) -> ScriptSectionMarker? {
        sessionMarkers[record.id]
    }

    func queueMarker(for item: QueuedGenerationItem) -> ScriptSectionMarker? {
        queueMarkers[item.id]
    }

    private static func newestQueuedFirst(_ lhs: QueuedGenerationItem, _ rhs: QueuedGenerationItem) -> Bool {
        let lhsDate = lhs.startedAt ?? lhs.createdAt
        let rhsDate = rhs.startedAt ?? rhs.createdAt
        if lhsDate == rhsDate {
            return lhs.id > rhs.id
        }
        return lhsDate > rhsDate
    }

    private static func newestSessionFirst(_ lhs: SessionRecord, _ rhs: SessionRecord) -> Bool {
        if lhs.metadata.createdAt == rhs.metadata.createdAt {
            return lhs.id > rhs.id
        }
        return lhs.metadata.createdAt > rhs.metadata.createdAt
    }
}

private enum GenerationListItem: Identifiable {
    case queued(QueuedGenerationItem)
    case session(SessionRecord)

    var id: String {
        stableID
    }

    var stableID: String {
        switch self {
        case .queued(let item):
            return "queued-\(item.id)"
        case .session(let record):
            return "session-\(record.id)"
        }
    }

    var sortDate: Date {
        switch self {
        case .queued(let item):
            return item.startedAt ?? item.createdAt
        case .session(let record):
            return record.metadata.createdAt
        }
    }
}

private struct ScriptSectionMarker: Equatable {
    let batchID: String
    let batchCreatedAt: Date
    let position: Int
    let total: Int

    var displayText: String {
        "\(position + 1)/\(total)"
    }

    var accessibilityText: String {
        "Section \(position + 1) of \(total)"
    }
}

private struct QueuedGenerationListRow: View {
    let item: QueuedGenerationItem
    let marker: ScriptSectionMarker?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusTint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(isSelected || item.status == .running ? .semibold : .regular)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    VoiceInlineLabel(voiceID: item.voice, compact: true)
                    Text("\(TextMetrics.wordCount(in: item.sourceText)) words")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let marker {
                ScriptSectionCapsule(marker: marker)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .accessibilityLabel(accessibilityLabel)
    }

    private var title: String {
        let trimmed = item.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = trimmed.components(separatedBy: .newlines).first, !firstLine.isEmpty {
            return firstLine
        }
        return item.status.displayName
    }

    private var accessibilityLabel: String {
        let section = marker.map { ", \($0.accessibilityText)" } ?? ""
        return "\(item.status.displayName), \(VoiceDisplayFormatter.displayText(for: item.voice)), \(TextMetrics.wordCount(in: item.sourceText)) words\(section)"
    }

    private var statusIcon: String {
        switch item.status {
        case .running:
            return "waveform.circle"
        case .queued:
            return "clock"
        case .paused:
            return "pause.circle"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "xmark.octagon"
        case .cancelled:
            return "xmark.circle"
        }
    }

    private var statusTint: Color {
        switch item.status {
        case .running:
            return .blue
        case .queued:
            return .secondary
        case .paused:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }
}

private struct GenerationListRow: View {
    let record: SessionRecord
    let marker: ScriptSectionMarker?
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

            if let marker {
                ScriptSectionCapsule(marker: marker)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let section = marker.map { ", \($0.accessibilityText)" } ?? ""
        return "\(record.metadata.status.displayName), \(VoiceDisplayFormatter.displayText(for: record.metadata.voice)), \(record.metadata.inputWordCount) words\(section)"
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

private struct ScriptSectionCapsule: View {
    let marker: ScriptSectionMarker

    var body: some View {
        Text(marker.displayText)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .accessibilityLabel(marker.accessibilityText)
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
