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
                        SidebarSectionRow(
                            section: .projects,
                            detail: "\(workspaceStore.projects.count)",
                            isSelected: selection == .section(.projects)
                        )
                            .tag(WorkstationSelection.section(.projects) as WorkstationSelection?)
                            .contentShape(Rectangle())
                            .onTapGesture { selectSection(.projects) }
                        SidebarSectionRow(
                            section: .scripts,
                            detail: "\(workspaceStore.scripts.count)",
                            isSelected: selection == .section(.scripts)
                        )
                            .tag(WorkstationSelection.section(.scripts) as WorkstationSelection?)
                            .contentShape(Rectangle())
                            .onTapGesture { selectSection(.scripts) }
                        SidebarSectionRow(
                            section: .batches,
                            detail: batchesDetail,
                            isSelected: selection == .section(.batches)
                        )
                            .tag(WorkstationSelection.section(.batches) as WorkstationSelection?)
                            .contentShape(Rectangle())
                            .onTapGesture { selectSection(.batches) }
                    }

                    Section("Library") {
                        SidebarSectionRow(
                            section: .voices,
                            detail: "\(workspaceStore.voicePresets.count)",
                            isSelected: selection == .section(.voices)
                        )
                            .tag(WorkstationSelection.section(.voices) as WorkstationSelection?)
                            .contentShape(Rectangle())
                            .onTapGesture { selectSection(.voices) }
                        SidebarSectionRow(
                            section: .presets,
                            detail: "\(workspaceStore.generationPresets.count)",
                            isSelected: selection == .section(.presets)
                        )
                            .tag(WorkstationSelection.section(.presets) as WorkstationSelection?)
                            .contentShape(Rectangle())
                            .onTapGesture { selectSection(.presets) }
                    }

                    Section("Generation") {
                        SidebarSectionRow(
                            section: .outputs,
                            detail: "\(store.outputSessions.count)",
                            isSelected: selection == .section(.outputs)
                        )
                            .tag(WorkstationSelection.section(.outputs) as WorkstationSelection?)
                            .contentShape(Rectangle())
                            .onTapGesture { selectSection(.outputs) }
                        SidebarSectionRow(
                            section: .history,
                            detail: "\(store.sessions.count)",
                            isSelected: selection == .section(.history)
                        )
                            .tag(WorkstationSelection.section(.history) as WorkstationSelection?)
                            .contentShape(Rectangle())
                            .onTapGesture { selectSection(.history) }

                        ForEach(store.sessions) { record in
                            HistoryRow(
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
                        SidebarSectionRow(
                            section: .backends,
                            detail: store.backendStatus.state.displayName,
                            isSelected: selection == .section(.backends)
                        )
                            .tag(WorkstationSelection.section(.backends) as WorkstationSelection?)
                            .contentShape(Rectangle())
                            .onTapGesture { selectSection(.backends) }
                        SidebarSectionRow(
                            section: .settings,
                            detail: nil,
                            isSelected: selection == .section(.settings)
                        )
                            .tag(WorkstationSelection.section(.settings) as WorkstationSelection?)
                            .contentShape(Rectangle())
                            .onTapGesture { selectSection(.settings) }
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
                        .frame(width: 24, height: 24)
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

    private func selectSection(_ section: WorkstationSection) {
        selection = .section(section)
        store.selectedSessionID = nil
    }

    private func selectHistory(_ record: SessionRecord) {
        selection = .historySession(record.id)
        store.selectedSessionID = record.id
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
        .background(selectionBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.16))
        }
    }
}

private struct HistoryRow: View {
    let record: SessionRecord
    let isSelected: Bool

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

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .imageScale(.small)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.16))
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
