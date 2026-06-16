import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct OutputBrowserView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @State private var searchText = ""
    @State private var sortMode = OutputSortMode.newest
    @State private var showingProjectFiling = false

    private var outputs: [SessionRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = store.outputSessions.filter { record in
            guard !query.isEmpty else { return true }
            return [
                record.id,
                record.metadata.voice,
                record.metadata.cfgScale,
                record.metadata.dockerImage,
                record.metadata.status.rawValue,
                backendSummary(for: record),
                projectSummary(for: record),
                record.inputText
            ]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
        }

        return filtered.sorted { lhs, rhs in
            sortMode.compare(lhs, rhs, projectName: projectSummary)
        }
    }

    private var selectedOutputs: [SessionRecord] {
        store.selectedOutputSessions.sorted { lhs, rhs in
            sortMode.compare(lhs, rhs, projectName: projectSummary)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryStrip
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

            if outputs.isEmpty {
                EmptyOutputsHousekeepingView(hasSearch: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                outputTable
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .navigationTitle("Outputs")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search outputs")
        .sheet(isPresented: $showingProjectFiling) {
            FileOutputsToProjectSheet(records: selectedOutputs)
                .environmentObject(store)
                .environmentObject(workspaceStore)
        }
        .onAppear {
            store.refreshHistory()
            workspaceStore.refresh()
            if store.selectedOutputSessionIDs.isEmpty, let first = outputs.first {
                store.selectedOutputSessionIDs = [first.id]
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 18) {
            SummaryMetric(title: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Outputs" : "Matched", value: "\(outputs.count)")
            SummaryMetric(title: "Selected", value: "\(selectedOutputs.count)")
            SummaryMetric(title: "Duration", value: SessionFormatters.duration(totalDuration(outputs)))
            SummaryMetric(title: "Disk", value: totalSize(outputs).formattedByteCount)

            Divider()
                .frame(height: 28)

            Picker("Sort", selection: $sortMode) {
                ForEach(OutputSortMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 170)

            Spacer()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var outputTable: some View {
        VStack(spacing: 8) {
            Table(outputs, selection: $store.selectedOutputSessionIDs) {
                TableColumn("Date") { record in
                    OutputTableText(SessionFormatters.displayDateFormatter.string(from: record.metadata.createdAt))
                }
                .width(min: 150, ideal: 190)

                TableColumn("Project") { record in
                    OutputTableText(
                        projectSummary(for: record),
                        style: projectSummary(for: record) == "Unfiled" ? .secondary : .primary
                    )
                }
                .width(min: 130, ideal: 180)

                TableColumn("Voice") { record in
                    OutputTableText(record.metadata.voice)
                }
                .width(min: 120, ideal: 160)

                TableColumn("Backend") { record in
                    OutputTableText(backendSummary(for: record))
                }
                .width(min: 130, ideal: 180)

                TableColumn("Duration") { record in
                    OutputTableText(SessionFormatters.duration(record.metadata.audioDurationSeconds), monospaced: true)
                }
                .width(min: 78, ideal: 92)

                TableColumn("Generation") { record in
                    OutputTableText(SessionFormatters.duration(record.metadata.generationTimeSeconds), monospaced: true)
                }
                .width(min: 92, ideal: 112)

                TableColumn("RTF") { record in
                    OutputTableText(SessionFormatters.rtf(record.metadata.rtf), monospaced: true)
                }
                .width(min: 60, ideal: 74)

                TableColumn("Size") { record in
                    OutputTableText(outputSize(record).formattedByteCount, monospaced: true)
                }
                .width(min: 78, ideal: 94)

                TableColumn("Status") { record in
                    StatusBadge(status: record.metadata.status)
                        .padding(.vertical, 6)
                }
                .width(min: 92, ideal: 112)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: String.self) { selection in
                outputMenu(for: records(for: selection))
            } primaryAction: { selection in
                if let record = records(for: selection).first {
                    store.quickLookOutputFile(record)
                }
            }

            if selectedOutputs.isEmpty {
                OutputSelectionHint()
            }
        }
    }

    @ViewBuilder
    private func outputMenu(for records: [SessionRecord]) -> some View {
        Button {
            if let record = records.first {
                store.revealOutputFile(record)
            }
        } label: {
            Label("Reveal in Finder", systemImage: "finder")
        }
        .disabled(records.first?.outputURL == nil)

        Button {
            if let record = records.first {
                store.quickLookOutputFile(record)
            }
        } label: {
            Label("Quick Look", systemImage: "eye")
        }
        .disabled(records.first?.outputURL == nil)

        Button {
            store.copySelectedOutputPaths()
        } label: {
            Label("Copy Path", systemImage: "doc.on.clipboard")
        }
        .disabled(records.isEmpty)

        Button {
            store.shareSelectedOutputFiles()
        } label: {
            Label("Share WAV", systemImage: "square.and.arrow.up")
        }
        .disabled(records.isEmpty)

        Divider()

        Button {
            showingProjectFiling = true
        } label: {
            Label("File into Project", systemImage: "folder.badge.plus")
        }
        .disabled(records.isEmpty || workspaceStore.projects.isEmpty)

        Button(role: .destructive) {
            store.archiveOutputSessions(records)
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        .disabled(records.isEmpty)
    }

    private func records(for selection: Set<String>) -> [SessionRecord] {
        let selected = outputs.filter { selection.contains($0.id) }
        return selected.isEmpty ? selectedOutputs : selected
    }

    private func projectSummary(for record: SessionRecord) -> String {
        let projects = workspaceStore.projects(containingGenerationSession: record.id)
        guard !projects.isEmpty else { return "Unfiled" }
        return projects.map(\.title).joined(separator: ", ")
    }

    private func backendSummary(for record: SessionRecord) -> String {
        if record.metadata.dockerImage.isEmpty {
            return "Local service"
        }
        return record.metadata.dockerImage
    }

    private func totalDuration(_ records: [SessionRecord]) -> Double? {
        let durations = records.compactMap(\.metadata.audioDurationSeconds)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +)
    }

    private func totalSize(_ records: [SessionRecord]) -> UInt64 {
        records.reduce(0) { $0 + outputSize($1) }
    }

    private func outputSize(_ record: SessionRecord) -> UInt64 {
        guard let outputURL = record.outputURL,
              let values = try? outputURL.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return 0
        }
        return UInt64(max(0, fileSize))
    }
}

private enum OutputSortMode: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case longest
    case largest
    case voice
    case project
    case backend
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Newest First"
        case .oldest: "Oldest First"
        case .longest: "Longest Audio"
        case .largest: "Largest File"
        case .voice: "Voice"
        case .project: "Project"
        case .backend: "Backend"
        case .status: "Status"
        }
    }

    func compare(_ lhs: SessionRecord, _ rhs: SessionRecord, projectName: (SessionRecord) -> String) -> Bool {
        switch self {
        case .newest:
            return lhs.metadata.createdAt > rhs.metadata.createdAt
        case .oldest:
            return lhs.metadata.createdAt < rhs.metadata.createdAt
        case .longest:
            return (lhs.metadata.audioDurationSeconds ?? 0) > (rhs.metadata.audioDurationSeconds ?? 0)
        case .largest:
            return Self.outputByteCount(lhs) > Self.outputByteCount(rhs)
        case .voice:
            return lhs.metadata.voice.localizedCaseInsensitiveCompare(rhs.metadata.voice) == .orderedAscending
        case .project:
            return projectName(lhs).localizedCaseInsensitiveCompare(projectName(rhs)) == .orderedAscending
        case .backend:
            return backendName(lhs).localizedCaseInsensitiveCompare(backendName(rhs)) == .orderedAscending
        case .status:
            return lhs.metadata.status.rawValue.localizedCaseInsensitiveCompare(rhs.metadata.status.rawValue) == .orderedAscending
        }
    }

    private func backendName(_ record: SessionRecord) -> String {
        record.metadata.dockerImage.isEmpty ? "Local service" : record.metadata.dockerImage
    }

    private static func outputByteCount(_ record: SessionRecord) -> UInt64 {
        guard let outputURL = record.outputURL,
              let values = try? outputURL.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return 0
        }
        return UInt64(max(0, fileSize))
    }
}

private struct SummaryMetric: View {
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

private struct OutputTableText: View {
    let value: String
    let style: HierarchicalShapeStyle
    let monospaced: Bool

    init(_ value: String, style: HierarchicalShapeStyle = .primary, monospaced: Bool = false) {
        self.value = value
        self.style = style
        self.monospaced = monospaced
    }

    var body: some View {
        if monospaced {
            baseText.monospacedDigit()
        } else {
            baseText
        }
    }

    private var baseText: some View {
        Text(value)
            .foregroundStyle(style)
            .font(.callout)
            .lineLimit(1)
            .padding(.vertical, 6)
    }
}

private struct OutputSelectionHint: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
            Text("Select one or more outputs to file, share, reveal, preview, or archive.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct FileOutputsToProjectSheet: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let records: [SessionRecord]
    @State private var selectedProjectID = ""

    private var selectedProject: NarrationProject? {
        workspaceStore.projects.first { $0.id == normalizedProjectID }
    }

    private var normalizedProjectID: String {
        if workspaceStore.projects.contains(where: { $0.id == selectedProjectID }) {
            return selectedProjectID
        }
        return workspaceStore.projects.first?.id ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("File into Project")
                    .font(.title2.weight(.semibold))
                Text("\(records.count) selected output\(records.count == 1 ? "" : "s") will be linked to the project. Files stay in their original session folders.")
                    .foregroundStyle(.secondary)
            }

            if workspaceStore.projects.isEmpty {
                EmptyStateView(
                    title: "No Projects",
                    systemImage: "folder.badge.plus",
                    message: "Create a project before filing outputs."
                )
            } else {
                Form {
                    Picker("Project", selection: projectBinding) {
                        ForEach(workspaceStore.projects) { project in
                            Text(project.title).tag(project.id)
                        }
                    }
                    .pickerStyle(.menu)

                    LabeledContent("Outputs", value: "\(records.count)")
                    if let selectedProject {
                        LabeledContent("Current filed outputs", value: "\(selectedProject.generationSessionIDs.count)")
                    }
                }
                .formStyle(.grouped)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("File Outputs") {
                    fileOutputs()
                }
                .buttonStyle(.borderedProminent)
                .disabled(records.isEmpty || selectedProject == nil)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            workspaceStore.refresh()
            selectedProjectID = normalizedProjectID
        }
    }

    private var projectBinding: Binding<String> {
        Binding(
            get: { normalizedProjectID },
            set: { selectedProjectID = $0 }
        )
    }

    private func fileOutputs() {
        guard let selectedProject else { return }
        let sessionIDs = records.map(\.id)
        if workspaceStore.fileGenerationSessions(sessionIDs, into: selectedProject) != nil {
            store.statusMessage = "Filed \(sessionIDs.count) output\(sessionIDs.count == 1 ? "" : "s") into \(selectedProject.title)"
            dismiss()
        }
    }
}

private struct EmptyOutputsHousekeepingView: View {
    let hasSearch: Bool

    var body: some View {
        EmptyStateView(
            title: hasSearch ? "No Matching Outputs" : "No Outputs",
            systemImage: hasSearch ? "magnifyingglass" : "archivebox",
            message: hasSearch ? "Try a different search." : "Completed WAV generations will appear here for cleanup, sharing, and project filing."
        )
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 360)
    }
}

private extension UInt64 {
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
