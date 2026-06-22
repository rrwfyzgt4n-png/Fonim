import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VibeVoiceBatchCore

struct ProjectsView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @State private var selectedProjectID: String?

    private var selectedProject: NarrationProject? {
        guard let selectedProjectID else { return workspaceStore.projects.first }
        return workspaceStore.projects.first { $0.id == selectedProjectID } ?? workspaceStore.projects.first
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Projects",
                    subtitle: "Scripts, batches, and filed generation outputs."
                )
                .padding([.horizontal, .top])

                if workspaceStore.projects.isEmpty {
                    EmptyWorkspaceView(
                        systemImage: "folder",
                        title: "No Projects",
                        message: "No project records are saved."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedProjectID) {
                        ForEach(workspaceStore.projects) { project in
                            ProjectRow(
                                project: project,
                                isSelected: selectedProject?.id == project.id
                            )
                            .tag(Optional(project.id))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedProjectID = project.id
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 300, idealWidth: 360)

            ProjectDetailPane(project: selectedProject)
                .frame(minWidth: 460)
        }
        .onAppear {
            appStore.refreshHistory()
            workspaceStore.refresh()
            ensureProjectSelection()
        }
        .onChange(of: workspaceStore.projects) { _ in
            ensureProjectSelection()
        }
        .navigationTitle("Projects")
    }

    private func ensureProjectSelection() {
        guard !workspaceStore.projects.isEmpty else {
            selectedProjectID = nil
            return
        }
        if let selectedProjectID,
           workspaceStore.projects.contains(where: { $0.id == selectedProjectID }) {
            return
        }
        selectedProjectID = workspaceStore.projects.first?.id
    }
}

private struct ProjectRow: View {
    let project: NarrationProject
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(project.title)
                    .lineLimit(1)
                Text("\(project.scriptIDs.count) scripts  \(project.batchIDs.count) batches  \(project.generationSessionIDs.count) outputs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            WorkspaceStatusBadge(status: project.status)
        }
        .padding(.vertical, 3)
    }
}

private struct ProjectDetailPane: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    let project: NarrationProject?

    private var scripts: [NarrationScript] {
        guard let project else { return [] }
        return workspaceStore.scripts(for: project)
    }

    private var batches: [NarrationBatch] {
        guard let project else { return [] }
        return workspaceStore.batches(for: project)
    }

    private var filedOutputs: [SessionRecord] {
        guard let project else { return [] }
        return project.generationSessionIDs.compactMap { appStore.session(id: $0) }
    }

    var body: some View {
        if let project {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(project)
                    metrics(project)
                    filedOutputsSection
                    sourceSections
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            EmptyWorkspaceView(
                systemImage: "folder",
                title: "No Project Selected",
                message: "Select a project to inspect filed outputs."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ project: NarrationProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                WorkspaceStatusBadge(status: project.status)
            }

            Text(project.notes.isEmpty ? "No notes." : project.notes)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack {
                Button {
                    rebatchProject(project)
                } label: {
                    Label("Re-batch Current Settings", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(scripts.isEmpty)
                .help("Create and queue a new batch from this project's scripts using the current generation settings.")

                Spacer()

                if !scripts.isEmpty {
                    VoiceInlineLabel(voiceID: appStore.selectedVoice, compact: true)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private func metrics(_ project: NarrationProject) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            GridRow {
                ProjectMetric(title: "Scripts", value: "\(scripts.count)")
                ProjectMetric(title: "Batches", value: "\(batches.count)")
                ProjectMetric(title: "Filed Outputs", value: "\(filedOutputs.count)")
            }
            GridRow {
                ProjectMetric(title: "Audio", value: SessionFormatters.duration(totalDuration))
                ProjectMetric(title: "Disk", value: totalOutputSize.formattedByteCount)
                ProjectMetric(title: "Updated", value: SessionFormatters.displayDateFormatter.string(from: project.updatedAt))
            }
        }
    }

    private var filedOutputsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filed Outputs")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if filedOutputs.isEmpty {
                EmptyWorkspaceView(
                    systemImage: "archivebox",
                    title: "No Filed Outputs",
                    message: "Use Outputs to file completed generations into this project."
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(spacing: 8) {
                    ForEach(filedOutputs) { record in
                        ProjectOutputRow(record: record)
                    }
                }
            }
        }
    }

    private var sourceSections: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
            GridRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scripts")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(scripts.isEmpty ? "No scripts filed." : scripts.map(\.title).joined(separator: "\n"))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Batches")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(batches.isEmpty ? "No batches filed." : batches.map(\.title).joined(separator: "\n"))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var totalDuration: Double? {
        let durations = filedOutputs.compactMap(\.metadata.audioDurationSeconds)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +)
    }

    private var totalOutputSize: UInt64 {
        filedOutputs.reduce(0) { total, record in
            guard let outputURL = record.outputURL,
                  let values = try? outputURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = values.fileSize else {
                return total
            }
            return total + UInt64(max(0, fileSize))
        }
    }

    private func rebatchProject(_ project: NarrationProject) {
        let settings = GenerationSettings(
            cfgScale: appStore.cfgScale,
            ddpmInferenceSteps: appStore.ddpmInferenceSteps
        )
        guard let result = workspaceStore.createProjectRebatch(
            project: project,
            scripts: scripts,
            backendID: appStore.selectedBackendProfile.id,
            modelID: appStore.selectedModelID,
            voice: appStore.selectedVoice,
            settings: settings
        ) else {
            return
        }
        appStore.queueImportedScripts(result.scripts, batch: result.batch)
    }
}

private struct ProjectOutputRow: View {
    @EnvironmentObject private var appStore: AppStore
    let record: SessionRecord

    var body: some View {
        WorkspaceCard {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.id)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        VoiceInlineLabel(voiceID: record.metadata.voice, compact: true)
                        Text(SessionFormatters.duration(record.metadata.audioDurationSeconds))
                        Text(SessionFormatters.rtf(record.metadata.rtf))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()

                Button {
                    appStore.quickLookOutputFile(record)
                } label: {
                    Image(systemName: "eye")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Quick Look")
                .accessibilityLabel("Quick Look output")
                .disabled(record.outputURL == nil)

                Button {
                    appStore.revealOutputFile(record)
                } label: {
                    Image(systemName: "finder")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
                .accessibilityLabel("Reveal output in Finder")
                .disabled(record.outputURL == nil)
            }
        }
    }
}

private struct ProjectMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(1)
        }
    }
}

struct ScriptsView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @State private var importPreview: ScriptImportPreview?
    @State private var projectTitle = ""
    @State private var selectedProjectID = ""

    private var activeScripts: [NarrationScript] {
        workspaceStore.activeScripts
    }

    var body: some View {
        WorkspaceListShell(
            title: "Scripts",
            subtitle: "Import text, split it into generation chunks, and keep script records.",
            isEmpty: false,
            emptySystemImage: "doc.text",
            emptyTitle: "No Scripts",
            emptyMessage: "Import a text file to create script chunks."
        ) {
            scriptImportControls

            if activeScripts.isEmpty {
                EmptyWorkspaceView(
                    systemImage: "doc.text",
                    title: "No Scripts",
                    message: "Import a text file to create script chunks."
                )
            } else {
                ForEach(activeScripts) { script in
                    WorkspaceCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(script.title)
                                    .font(.headline)
                                Spacer()
                                WorkspaceStatusBadge(status: script.status)
                            }

                            Text("\(script.inputWordCount) words  \(script.generationSessionIDs.count) generations")
                                .foregroundStyle(.secondary)

                            Text(script.text)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .sheet(item: $importPreview) { preview in
            ScriptImportSheet(
                preview: preview,
                onCancel: { importPreview = nil },
                onSave: { shouldQueue in
                    saveImport(preview, shouldQueue: shouldQueue)
                }
            )
        }
        .navigationTitle("Scripts")
    }

    private var scriptImportControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    chooseTextFile()
                } label: {
                    Label("Import TXT", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Text("\(activeScripts.count) active scripts")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Project name", text: $projectTitle)
                    .textFieldStyle(.roundedBorder)

                Button {
                    if let project = workspaceStore.createProject(title: projectTitle) {
                        selectedProjectID = project.id
                        projectTitle = ""
                    }
                } label: {
                    Label("Create Project", systemImage: "folder.badge.plus")
                }
                .disabled(projectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !workspaceStore.projects.isEmpty {
                    Picker("File into", selection: $selectedProjectID) {
                        Text("No Project").tag("")
                        ForEach(workspaceStore.projects) { project in
                            Text(project.title).tag(project.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)
                }
            }
        }
    }

    private func chooseTextFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .utf8PlainText, .text]
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let title = url.deletingPathExtension().lastPathComponent
            importPreview = ScriptImportPreview(
                sourceURL: url,
                title: title,
                chunks: ScriptChunker.chunks(from: text, baseTitle: title)
            )
        } catch {
            workspaceStore.alertMessage = AppErrorPresenter.message(for: error, fallbackTitle: "Could not read text file")
        }
    }

    private func saveImport(_ preview: ScriptImportPreview, shouldQueue: Bool) {
        let result = workspaceStore.importScriptBatch(
            projectID: selectedProjectID.isEmpty ? nil : selectedProjectID,
            title: preview.title,
            chunks: preview.chunks,
            backendID: appStore.selectedBackendProfile.id,
            modelID: appStore.selectedModelID,
            voice: appStore.selectedVoice,
            settings: GenerationSettings(
                cfgScale: appStore.cfgScale,
                ddpmInferenceSteps: appStore.ddpmInferenceSteps
            )
        )
        importPreview = nil
        guard let result else { return }
        if shouldQueue {
            appStore.queueImportedScripts(result.scripts, batch: result.batch)
        } else {
            appStore.statusMessage = "Imported \(result.scripts.count) scripts"
        }
    }
}

struct BatchesView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore

    private var orderedQueueItems: [QueuedGenerationItem] {
        appStore.queuedGenerations.filter { !$0.status.isTerminal }.sorted { lhs, rhs in
            let lhsRank = queueRank(lhs.status)
            let rhsRank = queueRank(rhs.status)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            switch lhs.status {
            case .running:
                return (lhs.startedAt ?? lhs.createdAt) > (rhs.startedAt ?? rhs.createdAt)
            case .queued, .paused:
                return lhs.createdAt > rhs.createdAt
            case .completed, .failed, .cancelled:
                return (lhs.completedAt ?? lhs.createdAt) > (rhs.completedAt ?? rhs.createdAt)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Batches",
                    subtitle: "Queued generation work, with the active item first."
                )

                BatchQueueSummaryStrip(items: orderedQueueItems)
                BatchQueueControlRow(items: orderedQueueItems)
                ImportedBatchCleanupSection(batches: workspaceStore.uncompletedBatches)

                if orderedQueueItems.isEmpty {
                    EmptyWorkspaceView(
                        systemImage: "tray.full",
                        title: "No Queued Generations",
                        message: "Queued generation work will appear here."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Generation Queue")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(orderedQueueItems) { item in
                            QueueItemCard(item: item)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Batches")
    }

    private func queueRank(_ status: QueuedGenerationStatus) -> Int {
        switch status {
        case .running:
            return 0
        case .queued:
            return 1
        case .paused:
            return 2
        case .failed, .cancelled:
            return 3
        case .completed:
            return 4
        }
    }
}

private struct BatchQueueSummaryStrip: View {
    let items: [QueuedGenerationItem]

    private var runningCount: Int {
        items.filter { $0.status == .running }.count
    }

    private var waitingCount: Int {
        items.filter { $0.status == .queued }.count
    }

    private var pausedCount: Int {
        items.filter { $0.status == .paused }.count
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                BatchQueueMetric(title: "Running", value: "\(runningCount)")
                BatchQueueMetric(title: "Waiting", value: "\(waitingCount)")
                BatchQueueMetric(title: "Paused", value: "\(pausedCount)")
                Spacer(minLength: 0)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: 10, alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                BatchQueueMetric(title: "Running", value: "\(runningCount)")
                BatchQueueMetric(title: "Waiting", value: "\(waitingCount)")
                BatchQueueMetric(title: "Paused", value: "\(pausedCount)")
            }
        }
    }
}

private struct ImportedBatchCleanupSection: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    let batches: [NarrationBatch]

    var body: some View {
        if !batches.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Imported Batches")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(batches) { batch in
                    WorkspaceCard {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(batch.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text("\(batch.items.count) script chunks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            WorkspaceStatusBadge(status: batch.status)

                            Button(role: .destructive) {
                                appStore.cancelQueuedGenerations(batchID: batch.id)
                                workspaceStore.deleteUncompletedBatch(batch)
                            } label: {
                                Label("Delete Batch", systemImage: "trash")
                            }
                            .disabled(batch.status == .completed)
                            .help("Delete this uncompleted imported batch and remove its queued script chunks")
                        }
                    }
                }
            }
        }
    }
}

private struct BatchQueueControlRow: View {
    @EnvironmentObject private var appStore: AppStore
    let items: [QueuedGenerationItem]

    private var hasWaitingItems: Bool {
        items.contains { $0.status == .queued }
    }

    private var hasPausedItems: Bool {
        items.contains { $0.status == .paused }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                appStore.pauseGenerationQueue()
            } label: {
                Label("Pause Queue", systemImage: "pause.circle")
            }
            .disabled(!hasWaitingItems)
            .help(hasWaitingItems ? "Pause queued generations after the current run" : "No waiting generations to pause")

            Button {
                appStore.resumeGenerationQueue()
            } label: {
                Label("Resume Queue", systemImage: "play.circle")
            }
            .disabled(!hasPausedItems)
            .help(hasPausedItems ? "Resume paused queued generations" : "No paused generations to resume")

            Spacer(minLength: 0)

            Text("Stop still applies to the running generation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.bordered)
    }
}

private struct BatchQueueMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(minWidth: 96, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct QueueItemCard: View {
    @EnvironmentObject private var appStore: AppStore
    let item: QueuedGenerationItem

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.status.systemImage)
                        .foregroundStyle(item.status.tint)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(item.voice)  CFG \(item.cfgScale)  \(item.ddpmInferenceSteps) steps  \(TextMetrics.wordCount(in: item.sourceText)) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(item.status.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .foregroundStyle(item.status.tint)
                        .background(item.status.tint.opacity(0.14), in: Capsule())
                }

                progressView

                HStack(spacing: 10) {
                    Text(statusLine)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(role: .destructive) {
                        appStore.cancelQueuedGeneration(item)
                    } label: {
                        Image(systemName: item.status == .running ? "stop.circle.fill" : "xmark.circle")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .disabled(item.status != .queued && item.status != .paused && item.status != .running)
                    .help(item.status == .running ? "Stop Generation" : "Remove from Queue")
                    .accessibilityLabel(item.status == .running ? "Stop generation" : "Remove queued generation")

                    Button {
                        appStore.retryQueuedGeneration(item)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!item.status.isTerminal)
                    .help("Retry")
                    .accessibilityLabel("Retry queued generation")

                    Button {
                        appStore.duplicateQueuedGenerationAsNew(item)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help("Duplicate as New")
                    .accessibilityLabel("Duplicate queued generation as new")
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var progressView: some View {
        if item.status == .running {
            if let fraction = item.progressFraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
            }
        } else if let fraction = item.progressFraction {
            ProgressView(value: fraction)
        }
    }

    private var title: String {
        let trimmed = item.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled generation" }
        return String(trimmed.prefix(72))
    }

    private var statusLine: String {
        var parts = [item.statusMessage]
        parts.append("Elapsed \(SessionFormatters.duration(item.elapsedSeconds))")
        if let remaining = item.estimatedRemainingSeconds {
            parts.append("Remaining \(SessionFormatters.duration(remaining))")
        }
        if let current = item.currentStep, let total = item.totalSteps {
            parts.append("\(current)/\(total)")
        }
        if let sessionID = item.sessionID {
            parts.append(sessionID)
        }
        if let errorMessage = item.errorMessage, item.status == .failed {
            parts.append(errorMessage)
        }
        return parts.joined(separator: "  ")
    }
}

struct VoicesView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @State private var selectedBackendID: String?
    @State private var selectedItemID: String?

    private var selectedBackend: BackendProfile {
        settingsStore.backendProfile(id: selectedBackendID ?? appStore.selectedBackendProfile.id)
    }

    private var modelID: String {
        settingsStore.modelOptions(for: selectedBackend).first?.id ?? selectedBackend.requiredModels.first?.id ?? AppDefaults.modelPath
    }

    private var voiceItems: [VoiceLibraryItem] {
        let catalog = settingsStore.voiceOptions(for: selectedBackend).map { voice in
            VoiceLibraryItem.catalog(voice, backend: selectedBackend, modelID: modelID)
        }
        let saved = workspaceStore.voicePresets
            .filter { !$0.isBuiltIn && $0.backendID == selectedBackend.id }
            .map(VoiceLibraryItem.preset)
        return catalog + saved
    }

    private var selectedItem: VoiceLibraryItem? {
        guard let selectedItemID else { return voiceItems.first }
        return voiceItems.first { $0.id == selectedItemID } ?? voiceItems.first
    }

    var body: some View {
        HSplitView {
            sidebarPane
            VoiceLibraryDetailPane(
                item: selectedItem,
                selectedBackend: selectedBackend,
                saveProfile: saveVoiceProfile
            )
            .frame(minWidth: 440)
        }
        .onAppear {
            ensureVoiceSelection()
        }
        .onChange(of: workspaceStore.voicePresets) { _ in
            ensureVoiceSelection()
        }
        .onChange(of: selectedBackendID) { _ in
            ensureVoiceSelection(reset: true)
        }
        .navigationTitle("Voices")
    }

    private var sidebarPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Voices",
                subtitle: "Backend-scoped voice catalogs, samples, and saved profiles."
            )
            .padding([.horizontal, .top])

            backendPicker
            voiceList
            footer
        }
        .frame(minWidth: 300, idealWidth: 360)
    }

    private var backendPicker: some View {
        Picker("Backend", selection: backendSelectionBinding) {
            ForEach(BackendProfiles.all) { profile in
                Text(profile.displayName).tag(profile.id)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var voiceList: some View {
        if voiceItems.isEmpty {
            EmptyWorkspaceView(
                systemImage: "waveform",
                title: "No Voices",
                message: "No voices are available for this backend yet."
            )
        } else {
            List(selection: $selectedItemID) {
                Section("Available") {
                    ForEach(voiceItems.filter { !$0.isSavedProfile }) { item in
                        VoiceLibraryRow(item: item, isSelected: selectedItemID == item.id)
                            .tag(Optional(item.id))
                            .contentShape(Rectangle())
                            .onTapGesture { selectedItemID = item.id }
                    }
                }

                savedProfilesSection
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var savedProfilesSection: some View {
        let savedProfiles = voiceItems.filter(\.isSavedProfile)
        if !savedProfiles.isEmpty {
            Section("Saved Profiles") {
                ForEach(savedProfiles) { item in
                    VoiceLibraryRow(item: item, isSelected: selectedItemID == item.id)
                        .tag(Optional(item.id))
                        .contentShape(Rectangle())
                        .onTapGesture { selectedItemID = item.id }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if let preset = item.preset {
                                Button {
                                    duplicateVoicePreset(preset)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if let preset = item.preset {
                                Button(role: .destructive) {
                                    deleteVoicePreset(preset)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(VoiceLibrarySummary.label(settingsStore: settingsStore))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                guard let selectedItem else { return }
                saveVoiceProfile(selectedItem)
            } label: {
                Label("Save Voice Profile", systemImage: "plus")
            }
            .disabled(selectedItem == nil)
        }
        .padding([.horizontal, .bottom])
    }

    private var backendSelectionBinding: Binding<String> {
        Binding(
            get: { selectedBackendID ?? appStore.selectedBackendProfile.id },
            set: {
                selectedBackendID = $0
                selectedItemID = nil
            }
        )
    }

    private func ensureVoiceSelection(reset: Bool = false) {
        if selectedBackendID == nil {
            selectedBackendID = appStore.selectedBackendProfile.id
        }
        guard !voiceItems.isEmpty else {
            selectedItemID = nil
            return
        }
        if !reset,
           let selectedItemID,
           voiceItems.contains(where: { $0.id == selectedItemID }) {
            return
        }
        selectedItemID = voiceItems.first?.id
    }

    private func saveVoiceProfile(_ item: VoiceLibraryItem) {
        let descriptor = VoiceDisplayFormatter.descriptor(
            for: item.voiceID,
            displayName: item.displayName,
            languageCode: item.explicitLanguageCode,
            locale: item.locale,
            countryFlag: item.countryFlag,
            traits: item.traits
        )
        if let preset = workspaceStore.saveCurrentVoicePreset(
            voiceID: item.voiceID,
            title: descriptor.compactText,
            backendID: item.backendID,
            modelID: item.modelID,
            locale: descriptor.languageCode,
            traits: item.traits
        ) {
            selectedItemID = "preset:\(preset.id)"
            appStore.statusMessage = "Saved voice profile: \(preset.displayName)"
        }
    }

    private func duplicateVoicePreset(_ preset: NarrationVoicePreset) {
        if let copy = workspaceStore.duplicateVoicePreset(preset) {
            selectedItemID = "preset:\(copy.id)"
            appStore.statusMessage = "Duplicated voice: \(copy.displayName)"
        }
    }

    private func deleteVoicePreset(_ preset: NarrationVoicePreset) {
        let deletedID = "preset:\(preset.id)"
        workspaceStore.deleteVoicePreset(preset)
        if selectedItemID == deletedID {
            selectedItemID = voiceItems.first?.id
        }
        appStore.statusMessage = "Deleted voice: \(preset.displayName)"
    }
}

private struct VoiceLibraryItem: Identifiable, Equatable {
    enum Source: Equatable {
        case catalog
        case savedProfile(NarrationVoicePreset)
    }

    let id: String
    let backendID: String
    let backendName: String
    let modelID: String
    let modelIDs: [String]
    let voiceID: String
    let displayName: String
    let locale: String?
    let explicitLanguageCode: String?
    let countryFlag: String?
    let catalogTraits: [String]
    let sourceType: BackendCatalogVoiceSource?
    let source: Source

    static func catalog(_ voice: BackendCatalogVoice, backend: BackendProfile, modelID: String) -> VoiceLibraryItem {
        VoiceLibraryItem(
            id: "catalog:\(backend.id):\(voice.id)",
            backendID: backend.id,
            backendName: backend.displayName,
            modelID: modelID,
            modelIDs: voice.modelIDs,
            voiceID: voice.id,
            displayName: voice.displayName,
            locale: voice.locale,
            explicitLanguageCode: voice.languageCode,
            countryFlag: voice.countryFlag,
            catalogTraits: voice.traits,
            sourceType: voice.sourceType,
            source: .catalog
        )
    }

    static func preset(_ preset: NarrationVoicePreset) -> VoiceLibraryItem {
        VoiceLibraryItem(
            id: "preset:\(preset.id)",
            backendID: preset.backendID,
            backendName: backendName(preset.backendID),
            modelID: preset.modelID,
            modelIDs: [preset.modelID],
            voiceID: preset.voiceID,
            displayName: preset.displayName,
            locale: preset.locale,
            explicitLanguageCode: preset.locale,
            countryFlag: nil,
            catalogTraits: preset.traits,
            sourceType: .savedProfile,
            source: .savedProfile(preset)
        )
    }

    var isSavedProfile: Bool {
        if case .savedProfile = source { return true }
        return false
    }

    var preset: NarrationVoicePreset? {
        if case .savedProfile(let preset) = source { return preset }
        return nil
    }

    var traits: [String] {
        preset?.traits ?? catalogTraits
    }

    var languageCode: String {
        VoiceDisplayFormatter
            .descriptor(
                for: voiceID,
                displayName: displayName,
                languageCode: explicitLanguageCode,
                locale: locale,
                countryFlag: countryFlag,
                traits: traits
            )
            .languageCode
    }

    var sourceDescription: String {
        if isSavedProfile {
            return "Saved profile"
        }
        switch sourceType {
        case .predefined:
            return "Predefined voice"
        case .reference:
            return "Reference voice"
        case .custom:
            return "Custom voice"
        case .catalog:
            return "Backend catalog"
        case .savedProfile:
            return "Saved profile"
        case nil:
            return "Backend catalog"
        }
    }

    static func backendName(_ backendID: String) -> String {
        BackendProfiles.all.first { $0.id == backendID }?.displayName ?? backendID
    }
}

private struct VoiceLibraryRow: View {
    let item: VoiceLibraryItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isSavedProfile ? "person.wave.2" : "waveform")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                VoiceInlineLabel(
                    voiceID: item.voiceID,
                    displayName: item.displayName,
                    languageCode: item.explicitLanguageCode,
                    locale: item.locale,
                    countryFlag: item.countryFlag,
                    traits: item.traits,
                    compact: true
                )
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(item.isSavedProfile ? "Saved profile" : item.backendName)
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
        .padding(.vertical, 3)
    }
}

private struct VoiceLibraryDetailPane: View {
    @EnvironmentObject private var appStore: AppStore
    let item: VoiceLibraryItem?
    let selectedBackend: BackendProfile
    let saveProfile: (VoiceLibraryItem) -> Void

    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: 16) {
                    WorkspaceCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .firstTextBaseline) {
                                VoiceInlineLabel(
                                    voiceID: item.voiceID,
                                    displayName: item.displayName,
                                    languageCode: item.explicitLanguageCode,
                                    locale: item.locale,
                                    countryFlag: item.countryFlag,
                                    traits: item.traits
                                )
                                    .font(.title3.weight(.semibold))
                                if item.isSavedProfile {
                                    Text("Saved")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(.blue.opacity(0.14), in: Capsule())
                                }
                                Spacer()
                            }

                            DetailGrid {
                                DetailGridRow("Backend", item.backendName)
                                DetailGridRow("Model", item.modelID)
                                DetailGridRow("Voice ID", item.voiceID)
                                DetailGridRow("Language", VoiceDisplayFormatter.languageName(for: item.languageCode))
                                DetailGridRow("Source", item.sourceDescription)
                            }

                            HStack {
                                Button {
                                    copyVoiceID(item.voiceID)
                                } label: {
                                    Label("Copy Voice ID", systemImage: "doc.on.clipboard")
                                }

                                Button {
                                    copyVoiceSummary(item)
                                } label: {
                                    Label("Copy Summary", systemImage: "list.clipboard")
                                }

                                Button {
                                    saveProfile(item)
                                } label: {
                                    Label("Save Voice Profile", systemImage: "plus")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }

                    sampleSection(item)
                    cloneSection
                    savedNotesSection(item)
                }
                .padding()
            } else {
                EmptyWorkspaceView(
                    systemImage: "waveform",
                    title: "No Voice Selected",
                    message: "Choose a backend voice to inspect its catalog record."
                )
                .padding()
            }
        }
    }

    private func copyVoiceID(_ voiceID: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(voiceID, forType: .string)
        appStore.statusMessage = "Copied voice ID: \(voiceID)"
    }

    private func copyVoiceSummary(_ item: VoiceLibraryItem) {
        let summary = [
            "Voice: \(VoiceDisplayFormatter.displayText(for: item.voiceID, displayName: item.displayName))",
            "Backend: \(item.backendName)",
            "Model: \(item.modelID)",
            "Voice ID: \(item.voiceID)",
            "Language: \(VoiceDisplayFormatter.languageName(for: item.languageCode))",
            "Source: \(item.sourceDescription)"
        ].joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        appStore.statusMessage = "Copied voice summary"
    }

    private func sampleSection(_ item: VoiceLibraryItem) -> some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sample")
                    .font(.headline)
                Text(VoiceSampleText.sample(for: selectedBackend, voiceID: item.voiceID))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var cloneSection: some View {
        if selectedBackend.engineType == .chatterbox {
            WorkspaceCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Voice Cloning", systemImage: "waveform.badge.plus")
                            .font(.headline)
                        Spacer()
                        Text("Chatterbox Only")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.purple.opacity(0.14), in: Capsule())
                    }
                    Text("Reference voice cloning needs an explicit import flow so consent, source WAV location, and Chatterbox visibility are clear before generation.")
                        .foregroundStyle(.secondary)
                    Button {
                        appStore.statusMessage = "Voice cloning import will be added as a Chatterbox-only flow."
                    } label: {
                        Label("Plan Clone Profile", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func savedNotesSection(_ item: VoiceLibraryItem) -> some View {
        if let preset = item.preset, !preset.notes.isEmpty || !preset.traits.isEmpty {
            WorkspaceCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile Notes")
                        .font(.headline)
                    if !preset.traits.isEmpty {
                        Text(preset.traits.joined(separator: "  "))
                            .foregroundStyle(.secondary)
                    }
                    if !preset.notes.isEmpty {
                        Text(preset.notes)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct PresetsView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @State private var selectedPresetID: String?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Presets",
                    subtitle: "Reusable generation settings."
                )
                .padding([.horizontal, .top])

                if workspaceStore.generationPresets.isEmpty {
                    EmptyWorkspaceView(
                        systemImage: "slider.horizontal.3",
                        title: "No Presets",
                        message: "No generation presets are available."
                    )
                } else {
                    List(selection: $selectedPresetID) {
                        ForEach(workspaceStore.generationPresets) { preset in
                            GenerationPresetRow(
                                preset: preset,
                                isSelected: selectedPresetID == preset.id
                            )
                                .tag(Optional(preset.id))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedPresetID = preset.id
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        duplicateGenerationPreset(preset)
                                    } label: {
                                        Label("Duplicate", systemImage: "doc.on.doc")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: !preset.isBuiltIn) {
                                    Button(role: .destructive) {
                                        deleteGenerationPreset(preset)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .disabled(preset.isBuiltIn)
                                }
                                .contextMenu {
                                    Button {
                                        duplicateGenerationPreset(preset)
                                    } label: {
                                        Label("Duplicate", systemImage: "doc.on.doc")
                                    }

                                    Button(role: .destructive) {
                                        deleteGenerationPreset(preset)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .disabled(preset.isBuiltIn)
                                }
                        }
                    }
                    .listStyle(.sidebar)
                }

                HStack {
                    Text("\(workspaceStore.generationPresets.count) presets")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        if let preset = workspaceStore.saveGenerationPreset(
                            voiceID: appStore.selectedVoice,
                            cfgScale: appStore.cfgScale,
                            ddpmInferenceSteps: appStore.ddpmInferenceSteps,
                            outputFormat: settingsStore.settings.exportFormat
                        ) {
                            selectedPresetID = preset.id
                            appStore.statusMessage = "Saved generation preset: \(preset.displayName)"
                        }
                    } label: {
                        Label("Save Current Preset", systemImage: "plus")
                    }
                }
                .padding([.horizontal, .bottom])
            }
            .frame(minWidth: 280, idealWidth: 340)

            GenerationPresetDetailPane(preset: selectedPreset)
                .frame(minWidth: 380)
        }
        .onAppear(perform: ensureGenerationPresetSelection)
        .onChange(of: workspaceStore.generationPresets) { _ in
            ensureGenerationPresetSelection()
        }
        .navigationTitle("Presets")
    }

    private var selectedPreset: NarrationGenerationPreset? {
        guard let selectedPresetID else { return workspaceStore.generationPresets.first }
        return workspaceStore.generationPresets.first { $0.id == selectedPresetID }
    }

    private func ensureGenerationPresetSelection() {
        guard !workspaceStore.generationPresets.isEmpty else {
            selectedPresetID = nil
            return
        }
        if let selectedPresetID,
           workspaceStore.generationPresets.contains(where: { $0.id == selectedPresetID }) {
            return
        }
        selectedPresetID = workspaceStore.generationPresets.first?.id
    }

    private func duplicateGenerationPreset(_ preset: NarrationGenerationPreset) {
        if let copy = workspaceStore.duplicateGenerationPreset(preset) {
            selectedPresetID = copy.id
            appStore.statusMessage = "Duplicated preset: \(copy.displayName)"
        }
    }

    private func deleteGenerationPreset(_ preset: NarrationGenerationPreset) {
        guard !preset.isBuiltIn else {
            workspaceStore.deleteGenerationPreset(preset)
            return
        }
        let deletedID = preset.id
        workspaceStore.deleteGenerationPreset(preset)
        if selectedPresetID == deletedID {
            selectedPresetID = workspaceStore.generationPresets.first?.id
        }
        appStore.statusMessage = "Deleted preset: \(preset.displayName)"
    }
}

private struct GenerationPresetRow: View {
    let preset: NarrationGenerationPreset
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(preset.displayName)
                        .lineLimit(1)
                    if preset.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("CFG \(preset.settings.cfgScale)  \(preset.settings.ddpmInferenceSteps.map(String.init) ?? "--") steps")
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

private struct GenerationPresetDetailPane: View {
    @EnvironmentObject private var appStore: AppStore
    let preset: NarrationGenerationPreset?

    var body: some View {
        ScrollView {
            if let preset {
                VStack(alignment: .leading, spacing: 16) {
                    WorkspaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(preset.displayName)
                                    .font(.title3.weight(.semibold))
                                if preset.isBuiltIn {
                                    Text("Built-in")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .foregroundStyle(.secondary)
                                        .background(.secondary.opacity(0.14), in: Capsule())
                                }
                                Spacer()
                                Button {
                                    appStore.applyGenerationPreset(preset)
                                } label: {
                                    Label("Apply", systemImage: "checkmark.circle")
                                }
                            }

                            DetailGrid {
                                DetailGridRow("Backend", backendName(preset.backendID))
                                DetailGridRow("Model", preset.modelID)
                                DetailGridRow("Voice", preset.voiceID.map { VoiceDisplayFormatter.displayText(for: $0) } ?? "Current")
                                DetailGridRow("CFG", preset.settings.cfgScale)
                                DetailGridRow("DDPM steps", preset.settings.ddpmInferenceSteps.map(String.init) ?? "n/a")
                                DetailGridRow("Format", preset.outputFormat.rawValue.uppercased())
                                DetailGridRow("Updated", SessionFormatters.displayDateFormatter.string(from: preset.updatedAt))
                            }
                        }
                    }

                    if !preset.notes.isEmpty {
                        WorkspaceCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notes")
                                    .font(.headline)
                                Text(preset.notes)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            } else {
                EmptyWorkspaceView(
                    systemImage: "slider.horizontal.3",
                    title: "No Preset Selected",
                    message: "Choose a generation preset from the list."
                )
                .padding()
            }
        }
    }
}

private struct DetailGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            content
        }
    }
}

private struct DetailGridRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

struct BackendsView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var operationsStore = BackendOperationsStore()

    private var backend: BackendProfile {
        appStore.selectedBackendProfile
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Backends",
                    subtitle: "Managed local generation engines."
                )

                WorkspaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(backend.displayName, systemImage: "server.rack")
                                .font(.headline)
                            Spacer()
                            Text(appStore.backendStatus.state.displayName)
                                .foregroundStyle(.secondary)
                        }
                        Text(backend.role)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Show Details") {
                                appStore.showBackendDetails()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Profiles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(BackendProfiles.all) { profile in
                        WorkspaceCard {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: profile.runtime == .docker ? "shippingbox" : "server.rack")
                                    .foregroundStyle(profile.id == settingsStore.settings.defaultBackendID ? .blue : .secondary)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(profile.displayName)
                                            .font(.headline)
                                        if profile.id == settingsStore.settings.defaultBackendID {
                                            Text("Selected")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .foregroundStyle(.blue)
                                                .background(.blue.opacity(0.14), in: Capsule())
                                        }
                                    }
                                    Text(profile.role)
                                        .foregroundStyle(.secondary)
                                    Text("\(profile.runtime.displayName)  \(profile.requiredModels.first?.displayName ?? "No model")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    appStore.selectBackend(profile.id)
                                } label: {
                                    Label("Use", systemImage: "checkmark.circle")
                                }
                                .disabled(profile.id == settingsStore.settings.defaultBackendID)
                            }
                        }
                    }
                }

                WorkspaceCard {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        GridRow {
                            Text("Runtime").foregroundStyle(.secondary)
                            Text(backend.runtime.displayName)
                        }
                        GridRow {
                            Text("Image").foregroundStyle(.secondary)
                            Text(backend.dockerImage ?? "Not required")
                        }
                        GridRow {
                            Text("Project data").foregroundStyle(.secondary)
                            Text(operationsStore.diskUsage.projectRootBytes.formattedByteCount)
                        }
                        GridRow {
                            Text("Model cache").foregroundStyle(.secondary)
                            Text(operationsStore.diskUsage.modelCacheBytes.formattedByteCount)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Backends")
    }
}

private struct WorkspaceListShell<Content: View>: View {
    let title: String
    let subtitle: String
    let isEmpty: Bool
    let emptySystemImage: String
    let emptyTitle: String
    let emptyMessage: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: title, subtitle: subtitle)

                if isEmpty {
                    EmptyWorkspaceView(
                        systemImage: emptySystemImage,
                        title: emptyTitle,
                        message: emptyMessage
                    )
                } else {
                    content
                }
            }
            .padding()
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WorkspaceCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            }
    }
}

private struct EmptyWorkspaceView: View {
    let systemImage: String
    let title: String
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
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

private func backendName(_ backendID: String) -> String {
    BackendProfiles.all.first { $0.id == backendID }?.displayName ?? backendID
}

private struct WorkspaceStatusBadge: View {
    let status: WorkspaceItemStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private var tint: Color {
        switch status {
        case .completed: .green
        case .failed: .red
        case .cancelled: .orange
        case .running: .blue
        case .queued, .ready: .purple
        case .draft, .archived: .secondary
        }
    }
}

private extension QueuedGenerationStatus {
    var systemImage: String {
        switch self {
        case .queued: "clock"
        case .paused: "pause.circle"
        case .running: "waveform.circle"
        case .completed: "checkmark.circle"
        case .failed: "xmark.octagon"
        case .cancelled: "pause.circle"
        }
    }

    var tint: Color {
        switch self {
        case .completed: .green
        case .failed: .red
        case .cancelled: .orange
        case .running: .blue
        case .paused: .orange
        case .queued: .purple
        }
    }
}

private extension UInt64 {
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
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
