import SwiftUI
import VibeVoiceBatchCore

struct InspectorPanelView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    let selection: WorkstationSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inspectorHeader
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                inspectorContent
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

    private var inspectorHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: inspectorIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(inspectorTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(inspectorSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch selection ?? .section(.history) {
            case .section(.outputs):
                outputsHousekeepingSection
            case .section(.backends):
                backendInspectorContent
            case .section(.projects), .section(.scripts), .section(.batches):
                metadataSection
            case .section(.voices):
                voiceLibraryInspectorContent
            case .section(.presets):
                generationSection
                backendSection
                exportSection
                metadataSection
            case .section(.history), .historySession:
                generationSection
                backendSection
                exportSection
                metadataSection
            }
        }
    }

    private var backendInspectorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorGroup(title: "Backend Status") {
                InspectorValue(label: "Backend", value: store.selectedBackendProfile.displayName)
                InspectorValue(label: "Runtime", value: store.selectedBackendProfile.runtime.displayName)
                InspectorValue(label: "State", value: store.backendStatus.state.displayName)
                InspectorValue(label: "Message", value: store.backendStatus.userMessage)
                InspectorValue(label: "Image", value: store.selectedBackendProfile.dockerImage ?? "Not required")
            }

            backendSection
            exportSection
        }
    }

    private var voiceLibraryInspectorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorGroup(title: "Voice Library") {
                InspectorValue(label: "Saved profiles", value: "\(workspaceStore.voicePresets.count)")
                InspectorValue(label: "VibeVoice voices", value: "\(settingsStore.voiceOptions(for: BackendProfiles.vibeVoiceTTS).count)")
                InspectorValue(label: "Kokoro voices", value: "\(settingsStore.voiceOptions(for: BackendProfiles.kokoroTTS).count)")
                InspectorValue(label: "Chatterbox voices", value: "\(settingsStore.voiceOptions(for: BackendProfiles.chatterboxTTS).count)")
            }

            InspectorGroup(title: "Catalog Boundaries") {
                InspectorValue(label: "Scope", value: "Backend-specific")
                InspectorValue(label: "Kokoro fallback", value: "\(KokoroVoiceCatalog.fallbackVoices.count) voices")
                InspectorValue(label: "Chatterbox fallback", value: "\(ChatterboxVoiceCatalog.catalogVoices.count) voices")
                InspectorValue(label: "VibeVoice fallback", value: "\(AppDefaults.availableVoiceCatalogVoices.count) voices")
            }

            InspectorGroup(title: "Current Generation Default") {
                InspectorValue(label: "Backend", value: store.selectedBackendProfile.displayName)
                InspectorVoiceValue(label: "Voice", voiceID: settingsStore.settings.preferredVoiceID(for: store.selectedBackendProfile))
            }
        }
    }

    private var inspectorTitle: String {
        switch selection ?? .section(.history) {
        case .section(let section):
            return section.title
        case .historySession:
            return "Session"
        }
    }

    private var inspectorSubtitle: String {
        switch selection ?? .section(.history) {
        case .section(.projects):
            return "\(workspaceStore.projects.count) projects"
        case .section(.scripts):
            return "\(workspaceStore.scripts.count) scripts"
        case .section(.batches):
            return "\(workspaceStore.batches.count) batches"
        case .section(.voices):
            return "Voice defaults and reusable profiles"
        case .section(.presets):
            return "Reusable generation settings"
        case .section(.outputs):
            return "\(store.selectedOutputSessions.count) selected of \(store.outputSessions.count)"
        case .section(.history):
            return store.hasUnsavedEditorText ? "Unsaved editor text" : "Editor defaults"
        case .section(.backends):
            return store.backendStatus.state.displayName
        case .historySession(let sessionID):
            return sessionID
        }
    }

    private var inspectorIcon: String {
        switch selection ?? .section(.history) {
        case .section(let section):
            return section.systemImage
        case .historySession:
            return "doc.text.magnifyingglass"
        }
    }

    private var generationSection: some View {
        InspectorGroup(title: "Generation") {
            Picker("Voice", selection: selectedVoiceBinding) {
                if store.availableVoiceOptions.isEmpty {
                    Text("No compatible voices")
                        .tag(store.selectedVoice)
                } else {
                    ForEach(store.availableVoiceOptions) { voice in
                        Text(VoiceDisplayFormatter.displayText(for: voice))
                            .tag(voice.id)
                    }
                }
            }
            .pickerStyle(.menu)

            if store.availableVoiceOptions.isEmpty {
                Text("No Chatterbox voice is marked available for the selected language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.selectedBackendProfile.engineType == .chatterbox {
                ChatterboxGenerationControls(
                    temperature: settingsBinding(\.chatterboxTemperature),
                    exaggeration: settingsBinding(\.chatterboxExaggeration),
                    cfgWeight: settingsBinding(\.chatterboxCFGWeight),
                    seed: settingsBinding(\.chatterboxSeed),
                    speedFactor: settingsBinding(\.chatterboxSpeedFactor),
                    language: settingsBinding(\.chatterboxLanguage),
                    languageChoices: chatterboxLanguageChoices,
                    splitText: settingsBinding(\.chatterboxSplitText),
                    chunkSize: settingsBinding(\.chatterboxChunkSize)
                )
            } else {
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

    private var chatterboxLanguageChoices: [(code: String, name: String)] {
        let selectedModelID = settingsStore.settings.defaultModelID
        let codes = ChatterboxModelCatalog.languageCodes(for: selectedModelID)
        return codes.map { code in
            VoiceDisplayFormatter.supportedLanguages.first { $0.code == code } ?? (code: code, name: VoiceDisplayFormatter.languageName(for: code))
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
                InspectorVoiceValue(label: "Selected", voiceID: store.selectedVoice)
            }
        case .section(.presets):
            InspectorGroup(title: "Preset Metadata") {
                InspectorValue(label: "Count", value: "\(workspaceStore.generationPresets.count)")
                InspectorVoiceValue(label: "Default voice", voiceID: settingsStore.settings.preferredVoiceID(for: store.selectedBackendProfile))
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
        case .historySession:
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
            InspectorVoiceValue(label: "Voice", voiceID: session.metadata.voice)
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
        let summary = outputSummary(for: selected)
        return VStack(alignment: .leading, spacing: 16) {
            OutputsInspectorHeader(selectedCount: summary.selectedCount, totalCount: summary.totalOutputCount)

            InspectorGroup(title: "Housekeeping") {
                InspectorValue(label: "Outputs", value: "\(summary.totalOutputCount)")
                InspectorValue(label: "Selected", value: "\(summary.selectedCount)")
                InspectorValue(label: "Duration", value: SessionFormatters.duration(summary.totalAudioDurationSeconds))
                InspectorValue(label: "Disk", value: summary.totalFileSizeBytes.formattedByteCount)
                InspectorValue(label: "Archive", value: summary.archiveEligibility)
            }

            InspectorGroup(title: "Filing") {
                InspectorValue(label: "Projects", value: summary.filingSummary)
                InspectorValue(label: "Available projects", value: "\(workspaceStore.projects.count)")
            }

            if selected.isEmpty {
                NoSelectedOutputInspectorCard()
            } else {
                outputActionSection(selected)
                outputBreakdownSection(summary)

                if selected.count == 1, let record = selected.first {
                    singleOutputSection(record)
                } else {
                    multiOutputSection(summary)
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
            .help("Archive selected sessions to recovered/deleted_sessions so they can be restored later")
        }
    }

    private func outputBreakdownSection(_ summary: OutputHousekeepingSummary) -> some View {
        InspectorGroup(title: "Breakdown") {
            OutputInspectorChipGrid(
                items: [
                    OutputInspectorChip(label: "Voices", value: "\(summary.voices.count)"),
                    OutputInspectorChip(label: "Backends", value: "\(summary.backends.count)"),
                    OutputInspectorChip(label: "Filed", value: "\(summary.filedCount)"),
                    OutputInspectorChip(label: "Unfiled", value: "\(summary.unfiledCount)")
                ]
            )
        }
    }

    private func singleOutputSection(_ record: SessionRecord) -> some View {
        InspectorGroup(title: "Selected Output") {
            InspectorValue(label: "Session", value: record.id)
            InspectorValue(label: "Created", value: SessionFormatters.displayDateFormatter.string(from: record.metadata.createdAt))
            InspectorVoiceValue(label: "Voice", voiceID: record.metadata.voice)
            InspectorValue(label: "Backend", value: backendDisplayName(for: record))
            InspectorValue(label: "Generation", value: SessionFormatters.duration(record.metadata.generationTimeSeconds))
            InspectorValue(label: "Audio", value: SessionFormatters.duration(record.metadata.audioDurationSeconds))
            InspectorValue(label: "RTF", value: SessionFormatters.rtf(record.metadata.rtf))
            InspectorValue(label: "Size", value: outputSize(record).formattedByteCount)
            InspectorValue(label: "Path", value: record.outputURL?.path ?? "No WAV")
        }
    }

    private func multiOutputSection(_ summary: OutputHousekeepingSummary) -> some View {
        InspectorGroup(title: "Selected Set") {
            InspectorValue(label: "Voices", value: summary.voices.joined(separator: ", "))
            InspectorValue(label: "Backends", value: summary.backends.joined(separator: ", "))
            InspectorValue(label: "Oldest", value: summary.oldestCreatedAt.map(SessionFormatters.displayDateFormatter.string(from:)) ?? "n/a")
            InspectorValue(label: "Newest", value: summary.newestCreatedAt.map(SessionFormatters.displayDateFormatter.string(from:)) ?? "n/a")
            InspectorValue(label: "Files", value: summary.outputFileNames.joined(separator: "\n"))
        }
    }

    private func outputSize(_ record: SessionRecord) -> UInt64 {
        guard let outputURL = record.outputURL,
              let values = try? outputURL.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return 0
        }
        return UInt64(max(0, fileSize))
    }

    private func outputSummary(for records: [SessionRecord]) -> OutputHousekeepingSummary {
        let projectTitlesByID = Dictionary(uniqueKeysWithValues: records.map { record in
            (record.id, workspaceStore.projects(containingGenerationSession: record.id).map(\.title))
        })
        let fileSizeByID = Dictionary(uniqueKeysWithValues: records.map { record in
            (record.id, outputSize(record))
        })
        return OutputHousekeepingSummary(
            selectedRecords: records,
            totalOutputCount: store.outputSessions.count,
            projectTitlesBySessionID: projectTitlesByID,
            fileSizeBySessionID: fileSizeByID,
            backendName: backendDisplayName
        )
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

    private var selectedVoiceBinding: Binding<String> {
        Binding(
            get: { store.selectedVoice },
            set: { store.selectVoice($0) }
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

private struct ChatterboxGenerationControls: View {
    @Binding var temperature: Double
    @Binding var exaggeration: Double
    @Binding var cfgWeight: Double
    @Binding var seed: Int
    @Binding var speedFactor: Double
    @Binding var language: String
    let languageChoices: [(code: String, name: String)]
    @Binding var splitText: Bool
    @Binding var chunkSize: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle("Split Text", isOn: $splitText)

            Stepper(value: $chunkSize, in: 50...500, step: 10) {
                HStack {
                    Text("Chunk Size")
                    Spacer()
                    Text("\(chunkSize)")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!splitText)

            ChatterboxDoubleStepper("Temperature", value: $temperature, range: 0.05...2.0, step: 0.05)
            ChatterboxDoubleStepper("Exaggeration", value: $exaggeration, range: 0.25...3.0, step: 0.05)
            ChatterboxDoubleStepper("CFG Weight", value: $cfgWeight, range: 0.0...2.0, step: 0.05)
            ChatterboxDoubleStepper("Speed", value: $speedFactor, range: 0.25...4.0, step: 0.05)

            Stepper(value: $seed, in: 0...999_999, step: 1) {
                HStack {
                    Text("Seed")
                    Spacer()
                    Text("\(seed)")
                        .foregroundStyle(.secondary)
                }
            }

            if languageChoices.count <= 1 {
                HStack {
                    Text("Language")
                    Spacer()
                    LanguageBadge(code: languageChoices.first?.code ?? "en", compact: true)
                    Text(languageChoices.first?.name ?? "English")
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("Language", selection: normalizedLanguage) {
                    ForEach(languageChoices, id: \.code) { choice in
                        Text(VoiceDisplayFormatter.languageMenuText(code: choice.code, name: choice.name))
                            .tag(choice.code)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .font(.callout)
        .onAppear {
            normalizeLanguage()
        }
        .onChange(of: languageChoices.map(\.code).joined(separator: ",")) { _ in
            normalizeLanguage()
        }
    }

    private var normalizedLanguage: Binding<String> {
        Binding(
            get: {
                let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return languageChoices.contains(where: { $0.code == normalized }) ? normalized : (languageChoices.first?.code ?? "en")
            },
            set: { language = $0 }
        )
    }

    private func normalizeLanguage() {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !languageChoices.contains(where: { $0.code == normalized }) {
            language = languageChoices.first?.code ?? "en"
        }
    }
}

private struct ChatterboxDoubleStepper: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    init(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) {
        self.label = label
        _value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        Stepper(value: normalizedValue, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.2f", value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var normalizedValue: Binding<Double> {
        Binding(
            get: { min(range.upperBound, max(range.lowerBound, value)) },
            set: { value = min(range.upperBound, max(range.lowerBound, $0)) }
        )
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)

            Text(value)
                .lineLimit(value.contains("\n") ? 5 : 2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}

private struct InspectorVoiceValue: View {
    let label: String
    let voiceID: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)

            VoiceInlineLabel(voiceID: voiceID)
                .frame(maxWidth: .infinity, alignment: .leading)
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
