import SwiftUI
import VibeVoiceBatchCore

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @Binding var selection: WorkstationSelection?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    Section("Workspace") {
                        SidebarSectionRow(section: .projects, detail: "\(workspaceStore.projects.count)")
                            .tag(WorkstationSelection.section(.projects) as WorkstationSelection?)
                        SidebarSectionRow(section: .scripts, detail: "\(workspaceStore.scripts.count)")
                            .tag(WorkstationSelection.section(.scripts) as WorkstationSelection?)
                        SidebarSectionRow(section: .batches, detail: batchesDetail)
                            .tag(WorkstationSelection.section(.batches) as WorkstationSelection?)
                    }

                    Section("Library") {
                        SidebarSectionRow(section: .voices, detail: "\(AppDefaults.availableVoices.count)")
                            .tag(WorkstationSelection.section(.voices) as WorkstationSelection?)
                        SidebarSectionRow(section: .presets, detail: "Defaults")
                            .tag(WorkstationSelection.section(.presets) as WorkstationSelection?)
                    }

                    Section("Generation") {
                        SidebarSectionRow(section: .outputs, detail: "\(store.outputSessions.count)")
                            .tag(WorkstationSelection.section(.outputs) as WorkstationSelection?)
                        SidebarSectionRow(section: .history, detail: "\(store.sessions.count)")
                            .tag(WorkstationSelection.section(.history) as WorkstationSelection?)

                        ForEach(store.sessions) { record in
                            HistoryRow(record: record)
                                .id(record.id)
                                .tag(WorkstationSelection.historySession(record.id) as WorkstationSelection?)
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
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        store.duplicateAsNew(record)
                                        selection = .section(.history)
                                    } label: {
                                        Label("Duplicate as New", systemImage: "doc.on.doc")
                                    }

                                    Button(role: .destructive) {
                                        store.archiveDeleteSession(record)
                                        selection = .section(.history)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }

                    Section("System") {
                        SidebarSectionRow(section: .backends, detail: store.backendStatus.state.displayName)
                            .tag(WorkstationSelection.section(.backends) as WorkstationSelection?)
                        SidebarSectionRow(section: .settings, detail: nil)
                            .tag(WorkstationSelection.section(.settings) as WorkstationSelection?)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: store.pendingScrollSessionID) { sessionID in
                    guard let sessionID else { return }
                    selection = .historySession(sessionID)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(sessionID, anchor: .center)
                    }
                    store.clearPendingScrollRequest()
                }
            }

            HStack {
                Text("\(workspaceStore.projects.count) projects  \(store.queuedGenerations.count) queued  \(store.sessions.count) sessions")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    workspaceStore.refresh()
                    store.refreshHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh Workspace")
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var batchesDetail: String {
        let queuedCount = store.queuedGenerations.filter { !$0.status.isTerminal }.count
        if queuedCount > 0 {
            return "\(queuedCount) active"
        }
        return "\(workspaceStore.batches.count)"
    }
}

private struct SidebarSectionRow: View {
    let section: WorkstationSection
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(section.title)
                .lineLimit(1)

            Spacer()

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct HistoryRow: View {
    let record: SessionRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.metadata.status.sidebarSystemImage)
                .foregroundStyle(record.metadata.status.sidebarTint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(SessionFormatters.displayDateFormatter.string(from: record.metadata.createdAt))
                    .lineLimit(1)

                Text("\(record.metadata.voice)  \(record.metadata.inputWordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
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

private extension SessionStatus {
    var sidebarSystemImage: String {
        switch self {
        case .completed: "checkmark.circle"
        case .failed: "xmark.octagon"
        case .cancelled: "pause.circle"
        case .running: "waveform.circle"
        case .draft: "doc.text"
        }
    }

    var sidebarTint: Color {
        switch self {
        case .completed: .green
        case .failed: .red
        case .cancelled: .orange
        case .running: .blue
        case .draft: .secondary
        }
    }
}
