import SwiftUI
import VibeVoiceBatchCore

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @Binding var selection: WorkstationSelection?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    Section("Workspace") {
                        sidebarRow(.projects, detail: "\(workspaceStore.projects.count)")
                        sidebarRow(.scripts, detail: "\(workspaceStore.activeScripts.count)")
                        sidebarRow(.batches, detail: batchesDetail)
                    }

                    Section("Library") {
                        sidebarRow(.voices, detail: "\(VoiceLibrarySummary.catalogVoiceCount(settingsStore: settingsStore))")
                        sidebarRow(.presets, detail: "\(workspaceStore.generationPresets.count)")
                    }

                    Section("Generation") {
                        sidebarRow(.history, detail: "\(store.sessions.count)")

                        ForEach(store.sessions) { record in
                            HistorySidebarRow(
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
                        }

                        sidebarRow(.outputs, detail: "\(store.outputSessions.count)")
                    }

                    Section("System") {
                        sidebarRow(.backends, detail: store.backendStatus.state.displayName)
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

            HStack(spacing: 8) {
                Text("Projects: \(workspaceStore.projects.count)  Queued: \(activeQueueCount)  Generations: \(store.sessions.count)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    workspaceStore.refresh()
                    store.refreshHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("Refresh Workspace")
                .accessibilityLabel("Refresh workspace")
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var batchesDetail: String {
        if activeQueueCount > 0 {
            return "\(activeQueueCount) active"
        }
        return "\(workspaceStore.uncompletedBatches.count)"
    }

    private var activeQueueCount: Int {
        store.queuedGenerations.filter { !$0.status.isTerminal }.count
    }

    private func selectSection(_ section: WorkstationSection) {
        selection = .section(section)
        if section == .history {
            store.selectedSessionID = nil
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
            proxy.scrollTo(sessionID, anchor: .center)
        }
        store.clearPendingScrollRequest()
    }

    private func sidebarRow(_ section: WorkstationSection, detail: String?) -> some View {
        SidebarSectionRow(
            section: section,
            detail: detail,
            isSelected: selection == .section(section)
        )
        .tag(WorkstationSelection.section(section) as WorkstationSelection?)
        .contentShape(Rectangle())
        .onTapGesture { selectSection(section) }
    }
}

private struct SidebarSectionRow: View {
    let section: WorkstationSection
    let detail: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 16)

            Text(section.title)
                .fontWeight(isSelected ? .semibold : .regular)
                .lineLimit(1)

            Spacer()

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 30)
    }
}

private struct HistorySidebarRow: View {
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
