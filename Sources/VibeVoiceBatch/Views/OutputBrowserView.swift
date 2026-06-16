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
                projectSummary(for: record),
                record.inputText
            ]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
        }

        return filtered.sorted(by: sortMode.comparator)
    }

    private var selectedOutputs: [SessionRecord] {
        store.selectedOutputSessions.sorted(by: sortMode.comparator)
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryStrip
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

            Divider()

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
            SummaryMetric(title: "Outputs", value: "\(outputs.count)")
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

            Button {
                showingProjectFiling = true
            } label: {
                Label("File into Project", systemImage: "folder.badge.plus")
            }
            .disabled(selectedOutputs.isEmpty || workspaceStore.projects.isEmpty)
            .help(workspaceStore.projects.isEmpty ? "Create a project before filing outputs" : "File selected outputs into a project")

            Button(role: .destructive) {
                store.archiveOutputSessions(selectedOutputs)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .disabled(selectedOutputs.isEmpty)
            .help("Move selected sessions to recovered/deleted_sessions")
        }
    }

    private var outputTable: some View {
        Table(outputs, selection: $store.selectedOutputSessionIDs) {
            TableColumn("Date") { record in
                Text(SessionFormatters.displayDateFormatter.string(from: record.metadata.createdAt))
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 190)

            TableColumn("Project") { record in
                Text(projectSummary(for: record))
                    .foregroundStyle(projectSummary(for: record) == "Unfiled" ? .secondary : .primary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 170)

            TableColumn("Voice") { record in
                Text(record.metadata.voice)
                    .lineLimit(1)
            }
            .width(min: 110, ideal: 150)

            TableColumn("Backend") { record in
                Text(backendSummary(for: record))
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 170)

            TableColumn("Duration") { record in
                Text(SessionFormatters.duration(record.metadata.audioDurationSeconds))
                    .monospacedDigit()
            }
            .width(min: 76, ideal: 90)

            TableColumn("Generation") { record in
                Text(SessionFormatters.duration(record.metadata.generationTimeSeconds))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)

            TableColumn("RTF") { record in
                Text(SessionFormatters.rtf(record.metadata.rtf))
                    .monospacedDigit()
            }
            .width(min: 58, ideal: 72)

            TableColumn("Size") { record in
                Text(outputSize(record).formattedByteCount)
                    .monospacedDigit()
            }
            .width(min: 76, ideal: 90)

            TableColumn("Status") { record in
                StatusBadge(status: record.metadata.status)
            }
            .width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: String.self) { selection in
            outputMenu(for: records(for: selection))
        } primaryAction: { selection in
            if let record = records(for: selection).first {
                store.quickLookOutputFile(record)
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Newest First"
        case .oldest: "Oldest First"
        case .longest: "Longest Audio"
        case .largest: "Largest File"
        case .voice: "Voice"
        case .project: "Project"
        }
    }

    var comparator: (SessionRecord, SessionRecord) -> Bool {
        switch self {
        case .newest:
            return { $0.metadata.createdAt > $1.metadata.createdAt }
        case .oldest:
            return { $0.metadata.createdAt < $1.metadata.createdAt }
        case .longest:
            return { ($0.metadata.audioDurationSeconds ?? 0) > ($1.metadata.audioDurationSeconds ?? 0) }
        case .largest:
            return { Self.outputByteCount($0) > Self.outputByteCount($1) }
        case .voice:
            return { $0.metadata.voice.localizedCaseInsensitiveCompare($1.metadata.voice) == .orderedAscending }
        case .project:
            return { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        }
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
