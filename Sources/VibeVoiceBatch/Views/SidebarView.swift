import SwiftUI
import VibeVoiceBatchCore

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @Binding var selection: WorkstationSelection?

    var body: some View {
        VStack(spacing: 0) {
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
                    sidebarRow(.outputs, detail: "\(store.outputSessions.count)")
                }

                Section("System") {
                    sidebarRow(.backends, detail: store.backendStatus.state.displayName)
                }
            }
            .listStyle(.sidebar)

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
