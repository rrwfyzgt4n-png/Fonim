import SwiftUI
import VibeVoiceBatchCore

struct InspectorPanelView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    let selection: WorkstationSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inspector")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isOutputsSelection {
                        outputsHousekeepingSection
                    } else {
                        generationSection
                        backendSection
                        exportSection
                        metadataSection
                    }
                }
                .padding(14)
            }
        }
        .frame(minWidth: 280, idealWidth: 300, maxWidth: 340)
        .background(.regularMaterial)
    }

    private var isOutputsSelection: Bool {
        if case .section(.outputs) = selection {
            return true
        }
        return false
    }

    private var generationSection: some View {
        InspectorGroup(title: "Generation") {
            Picker("Voice", selection: $store.selectedVoice) {
                ForEach(store.availableVoiceOptions) { voice in
                    Text(voice.displayName).tag(voice.id)
                }
            }
            .pickerStyle(.menu)

            Picker("CFG", selection: $store.cfgScale) {
                ForEach(AppDefaults.availableCFGScales, id: \.self) { cfgScale in
                    Text(cfgScale).tag(cfgScale)
                }
            }
            .pickerStyle(.menu)

            Picker("DDPM Steps", selection: $store.ddpmInferenceSteps) {
                ForEach(AppDefaults.availableDDPMInferenceSteps, id: \.self) { steps in
                    Text("\(steps)").tag(steps)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var backendSection: some View {
        InspectorGroup(title: "Model") {
            Picker("Backend", selection: backendBinding) {
                ForEach(BackendProfiles.all) { profile in
                    Text(profile.displayName).tag(profile.id)
                }
            }
            .pickerStyle(.menu)

            Picker("Model", selection: settingsBinding(\.defaultModelID)) {
                ForEach(store.availableModelOptions) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .pickerStyle(.menu)

            InspectorValue(label: "Status", value: store.backendStatus.state.displayName)
        }
    }

    private var exportSection: some View {
        InspectorGroup(title: "Export") {
            Picker("Format", selection: settingsBinding(\.exportFormat)) {
                ForEach(store.selectedBackendProfile.outputFormatSupport, id: \.self) { format in
                    Text(format.rawValue.uppercased()).tag(format)
                }
            }
            .pickerStyle(.menu)

            InspectorValue(label: "Folder", value: settingsStore.settings.outputFolderPath)
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        switch selection ?? .section(.history) {
        case .section(.projects):
            InspectorGroup(title: "Projects") {
                InspectorValue(label: "Count", value: "\(workspaceStore.projects.count)")
            }
        case .section(.scripts):
            InspectorGroup(title: "Scripts") {
                InspectorValue(label: "Count", value: "\(workspaceStore.scripts.count)")
                InspectorValue(label: "Generations", value: "\(workspaceStore.scripts.reduce(0) { $0 + $1.generationSessionIDs.count })")
            }
        case .section(.batches):
            InspectorGroup(title: "Batches") {
                InspectorValue(label: "Count", value: "\(workspaceStore.batches.count)")
                InspectorValue(label: "Items", value: "\(workspaceStore.batches.reduce(0) { $0 + $1.items.count })")
                InspectorValue(label: "Queued", value: "\(store.queuedGenerations.filter { $0.status == .queued }.count)")
                InspectorValue(label: "Running", value: "\(store.queuedGenerations.filter { $0.status == .running }.count)")
            }
        case .section(.voices):
            InspectorGroup(title: "Voices") {
                InspectorValue(label: "Available", value: "\(workspaceStore.voicePresets.count)")
                InspectorValue(label: "Selected", value: store.selectedVoice)
            }
        case .section(.presets):
            InspectorGroup(title: "Preset Metadata") {
                InspectorValue(label: "Count", value: "\(workspaceStore.generationPresets.count)")
                InspectorValue(label: "Default voice", value: settingsStore.settings.defaultVoice)
                InspectorValue(label: "Default CFG", value: settingsStore.settings.defaultCFGScale)
                InspectorValue(label: "Default steps", value: "\(settingsStore.settings.defaultDDPMInferenceSteps)")
            }
        case .section(.outputs):
            outputsHousekeepingSection
        case .section(.backends):
            InspectorGroup(title: "Backend Metadata") {
                InspectorValue(label: "Backend", value: store.selectedBackendProfile.displayName)
                InspectorValue(label: "Runtime", value: store.selectedBackendProfile.runtime.displayName)
                InspectorValue(label: "Image", value: store.selectedBackendProfile.dockerImage ?? "Not required")
            }
        case .section(.history):
            if let session = store.selectedSession {
                sessionMetadata(session)
            } else {
                editorMetadata
            }
        }
    }

    private func sessionMetadata(_ session: SessionRecord) -> some View {
        InspectorGroup(title: "Session Metadata") {
            InspectorValue(label: "Status", value: session.metadata.status.displayName)
            InspectorValue(label: "Voice", value: session.metadata.voice)
            InspectorValue(label: "CFG", value: session.metadata.cfgScale)
            InspectorValue(label: "Steps", value: session.metadata.ddpmInferenceSteps.map(String.init) ?? "--")
            InspectorValue(label: "Words", value: "\(session.metadata.inputWordCount)")
            InspectorValue(label: "Generation", value: SessionFormatters.duration(session.metadata.generationTimeSeconds))
            InspectorValue(label: "Audio", value: SessionFormatters.duration(session.metadata.audioDurationSeconds))
            InspectorValue(label: "RTF", value: SessionFormatters.rtf(session.metadata.rtf))
        }
    }

    private var editorMetadata: some View {
        InspectorGroup(title: "Text Metadata") {
            InspectorValue(label: "Words", value: "\(TextMetrics.wordCount(in: store.editorText))")
            InspectorValue(label: "Characters", value: "\(store.editorText.count)")
            InspectorValue(label: "Unsaved", value: store.hasUnsavedEditorText ? "Yes" : "No")
        }
    }

    private var outputsHousekeepingSection: some View {
        let selected = store.selectedOutputSessions
        let selectedProjects = projectTitles(for: selected)
        return VStack(alignment: .leading, spacing: 16) {
            OutputsInspectorHeader(selectedCount: selected.count, totalCount: store.outputSessions.count)

            InspectorGroup(title: "Housekeeping") {
                InspectorValue(label: "Outputs", value: "\(store.outputSessions.count)")
                InspectorValue(label: "Selected", value: "\(selected.count)")
                InspectorValue(label: "Duration", value: SessionFormatters.duration(totalDuration(selected)))
                InspectorValue(label: "Disk", value: totalSize(selected).formattedByteCount)
                InspectorValue(label: "Archive", value: selected.isEmpty ? "No selection" : "Ready")
            }

            InspectorGroup(title: "Filing") {
                InspectorValue(label: "Projects", value: filingSummary(for: selected, projectTitles: selectedProjects))
                InspectorValue(label: "Available projects", value: "\(workspaceStore.projects.count)")
            }

            if selected.isEmpty {
                NoSelectedOutputInspectorCard()
            } else {
                outputActionSection(selected)
                outputBreakdownSection(selected)

                if selected.count == 1, let record = selected.first {
                    singleOutputSection(record)
                } else {
                    multiOutputSection(selected)
                }
            }
        }
    }

    private func outputActionSection(_ selected: [SessionRecord]) -> some View {
        InspectorGroup(title: "Actions") {
            Button {
                store.revealSelectedOutputFile()
            } label: {
                Label("Reveal First Selection", systemImage: "finder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(selected.isEmpty)

            Button {
                store.quickLookSelectedOutputFile()
            } label: {
                Label("Quick Look First Selection", systemImage: "eye")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(selected.isEmpty)

            Button {
                store.copySelectedOutputPaths()
            } label: {
                Label("Copy Selected Paths", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(selected.isEmpty)

            Button(role: .destructive) {
                store.archiveOutputSessions(selected)
            } label: {
                Label("Archive Selected", systemImage: "archivebox")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(selected.isEmpty)
            .help("Move selected sessions to recovered/deleted_sessions")
        }
    }

    private func outputBreakdownSection(_ selected: [SessionRecord]) -> some View {
        InspectorGroup(title: "Breakdown") {
            OutputInspectorChipGrid(
                items: [
                    OutputInspectorChip(label: "Voices", value: "\(uniqueVoices(selected).count)"),
                    OutputInspectorChip(label: "Backends", value: "\(uniqueBackends(selected).count)"),
                    OutputInspectorChip(label: "Filed", value: "\(filedCount(selected))"),
                    OutputInspectorChip(label: "Unfiled", value: "\(max(0, selected.count - filedCount(selected)))")
                ]
            )
        }
    }

    private func singleOutputSection(_ record: SessionRecord) -> some View {
        InspectorGroup(title: "Selected Output") {
            InspectorValue(label: "Session", value: record.id)
            InspectorValue(label: "Created", value: SessionFormatters.displayDateFormatter.string(from: record.metadata.createdAt))
            InspectorValue(label: "Voice", value: record.metadata.voice)
            InspectorValue(label: "Backend", value: backendDisplayName(for: record))
            InspectorValue(label: "Generation", value: SessionFormatters.duration(record.metadata.generationTimeSeconds))
            InspectorValue(label: "Audio", value: SessionFormatters.duration(record.metadata.audioDurationSeconds))
            InspectorValue(label: "RTF", value: SessionFormatters.rtf(record.metadata.rtf))
            InspectorValue(label: "Size", value: outputSize(record).formattedByteCount)
            InspectorValue(label: "Path", value: record.outputURL?.path ?? "No WAV")
        }
    }

    private func multiOutputSection(_ selected: [SessionRecord]) -> some View {
        InspectorGroup(title: "Selected Set") {
            InspectorValue(label: "Voices", value: uniqueVoices(selected).joined(separator: ", "))
            InspectorValue(label: "Backends", value: uniqueBackends(selected).joined(separator: ", "))
            InspectorValue(label: "Oldest", value: selected.map(\.metadata.createdAt).min().map(SessionFormatters.displayDateFormatter.string(from:)) ?? "n/a")
            InspectorValue(label: "Newest", value: selected.map(\.metadata.createdAt).max().map(SessionFormatters.displayDateFormatter.string(from:)) ?? "n/a")
            InspectorValue(label: "Files", value: selected.compactMap { $0.outputURL?.lastPathComponent }.joined(separator: "\n"))
        }
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

    private func projectTitles(for records: [SessionRecord]) -> [String] {
        let titles = records.flatMap { record in
            workspaceStore.projects(containingGenerationSession: record.id).map(\.title)
        }
        return Array(Set(titles)).sorted()
    }

    private func filingSummary(for records: [SessionRecord], projectTitles: [String]) -> String {
        guard !records.isEmpty else { return "No selection" }
        guard !projectTitles.isEmpty else { return "Unfiled" }
        return projectTitles.joined(separator: ", ")
    }

    private func filedCount(_ records: [SessionRecord]) -> Int {
        records.filter { !workspaceStore.projects(containingGenerationSession: $0.id).isEmpty }.count
    }

    private func uniqueVoices(_ records: [SessionRecord]) -> [String] {
        Array(Set(records.map(\.metadata.voice))).sorted()
    }

    private func uniqueBackends(_ records: [SessionRecord]) -> [String] {
        Array(Set(records.map(backendDisplayName))).sorted()
    }

    private func backendDisplayName(for record: SessionRecord) -> String {
        record.metadata.dockerImage.isEmpty ? "Local service" : record.metadata.dockerImage
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in settingsStore.update { $0[keyPath: keyPath] = value } }
        )
    }

    private var backendBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.defaultBackendID },
            set: { store.selectBackend($0) }
        )
    }
}

private struct InspectorGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

private struct OutputsInspectorHeader: View {
    let selectedCount: Int
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "archivebox")
                    .foregroundStyle(.blue)
                Text("Outputs")
                    .font(.headline)
                Spacer()
                Text("\(selectedCount)/\(totalCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            Text(selectedCount == 0 ? "Select outputs to inspect, file, share, or archive them." : "\(selectedCount) output\(selectedCount == 1 ? "" : "s") selected for housekeeping.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct NoSelectedOutputInspectorCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "cursorarrow.click")
                    .foregroundStyle(.secondary)
                Text("No Output Selected")
                    .font(.headline)
            }
            Text("Choose one or more rows in Outputs to see file details, filing state, and housekeeping actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct OutputInspectorChip: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct OutputInspectorChipGrid: View {
    let items: [OutputInspectorChip]

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}

private struct InspectorValue: View {
    let label: String
    let value: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Text(label)
                    .foregroundStyle(.secondary)
                Text(value)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
    }
}

private extension BackendRuntime {
    var displayName: String {
        switch self {
        case .docker: "Managed local runtime"
        case .localPython: "Local Python"
        case .comfyUI: "ComfyUI"
        case .native: "Native"
        case .externalService: "External service"
        }
    }
}

private extension UInt64 {
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
