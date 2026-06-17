import SwiftUI
import VibeVoiceBatchCore

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @Binding var selection: WorkstationSelection?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Workspace") {
                    sidebarRow(.projects, detail: "\(workspaceStore.projects.count)")
                    sidebarRow(.scripts, detail: "\(workspaceStore.scripts.count)")
                    sidebarRow(.batches, detail: batchesDetail)
                }

                Section("Library") {
                    sidebarRow(.voices, detail: "\(workspaceStore.voicePresets.count)")
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
