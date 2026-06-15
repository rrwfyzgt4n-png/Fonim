import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct ProjectsView: View {
    @EnvironmentObject private var workspaceStore: WorkspaceStore

    var body: some View {
        WorkspaceListShell(
            title: "Projects",
            subtitle: "Scripts, batches, and generation records.",
            isEmpty: workspaceStore.projects.isEmpty,
            emptySystemImage: "folder",
            emptyTitle: "No Projects",
            emptyMessage: "No project records are saved."
        ) {
            ForEach(workspaceStore.projects) { project in
                WorkspaceCard {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(project.title)
                                .font(.headline)
                            Text("\(project.scriptIDs.count) scripts  \(project.batchIDs.count) batches")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        WorkspaceStatusBadge(status: project.status)
                    }
                }
            }
        }
        .navigationTitle("Projects")
    }
}

struct ScriptsView: View {
    @EnvironmentObject private var workspaceStore: WorkspaceStore

    var body: some View {
        WorkspaceListShell(
            title: "Scripts",
            subtitle: "Editable narration sources.",
            isEmpty: workspaceStore.scripts.isEmpty,
            emptySystemImage: "doc.text",
            emptyTitle: "No Scripts",
            emptyMessage: "No script records are saved."
        ) {
            ForEach(workspaceStore.scripts) { script in
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
        .navigationTitle("Scripts")
    }
}

struct BatchesView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Batches",
                    subtitle: "Generation queue and saved script groups."
                )

                if appStore.queuedGenerations.isEmpty && workspaceStore.batches.isEmpty {
                    EmptyWorkspaceView(
                        systemImage: "tray.full",
                        title: "No Batches",
                        message: "Queued generation work will appear here."
                    )
                }

                if !appStore.queuedGenerations.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Generation Queue")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(appStore.queuedGenerations) { item in
                            QueueItemCard(item: item)
                        }
                    }
                }

                if !workspaceStore.batches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Saved Batches")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(workspaceStore.batches) { batch in
                            WorkspaceCard {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(batch.title)
                                            .font(.headline)
                                        Text("\(batch.items.count) items  \(completedCount(batch)) completed")
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    WorkspaceStatusBadge(status: batch.status)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Batches")
    }

    private func completedCount(_ batch: NarrationBatch) -> Int {
        batch.items.filter { $0.status == .completed }.count
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
                    Button {
                        appStore.cancelQueuedGeneration(item)
                    } label: {
                        Image(systemName: "stop.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(item.status != .queued && item.status != .running)
                    .help("Cancel")

                    Button {
                        appStore.retryQueuedGeneration(item)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!item.status.isTerminal)
                    .help("Retry")

                    Button {
                        appStore.duplicateQueuedGenerationAsNew(item)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Duplicate as New")
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
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @State private var selectedPresetID: String?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Voices",
                    subtitle: "Reusable voice profiles across backends."
                )
                .padding([.horizontal, .top])

                if workspaceStore.voicePresets.isEmpty {
                    EmptyWorkspaceView(
                        systemImage: "waveform",
                        title: "No Voices",
                        message: "No voice presets are available."
                    )
                } else {
                    List(selection: $selectedPresetID) {
                        ForEach(workspaceStore.voicePresets) { preset in
                            VoicePresetRow(
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
                                        duplicateVoicePreset(preset)
                                    } label: {
                                        Label("Duplicate", systemImage: "doc.on.doc")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: !preset.isBuiltIn) {
                                    Button(role: .destructive) {
                                        deleteVoicePreset(preset)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .disabled(preset.isBuiltIn)
                                }
                                .contextMenu {
                                    Button {
                                        duplicateVoicePreset(preset)
                                    } label: {
                                        Label("Duplicate", systemImage: "doc.on.doc")
                                    }

                                    Button(role: .destructive) {
                                        deleteVoicePreset(preset)
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
                    Text("\(workspaceStore.voicePresets.count) voices")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        if let preset = workspaceStore.saveCurrentVoicePreset(voiceID: appStore.selectedVoice) {
                            selectedPresetID = preset.id
                            appStore.statusMessage = "Saved voice preset: \(preset.displayName)"
                        }
                    } label: {
                        Label("Save Current Voice", systemImage: "plus")
                    }
                }
                .padding([.horizontal, .bottom])
            }
            .frame(minWidth: 260, idealWidth: 320)

            VoicePresetDetailPane(preset: selectedPreset)
                .frame(minWidth: 360)
        }
        .onAppear(perform: ensureVoiceSelection)
        .onChange(of: workspaceStore.voicePresets) { _ in
            ensureVoiceSelection()
        }
        .navigationTitle("Voices")
    }

    private var selectedPreset: NarrationVoicePreset? {
        guard let selectedPresetID else { return workspaceStore.voicePresets.first }
        return workspaceStore.voicePresets.first { $0.id == selectedPresetID }
    }

    private func ensureVoiceSelection() {
        guard !workspaceStore.voicePresets.isEmpty else {
            selectedPresetID = nil
            return
        }
        if let selectedPresetID,
           workspaceStore.voicePresets.contains(where: { $0.id == selectedPresetID }) {
            return
        }
        selectedPresetID = workspaceStore.voicePresets.first?.id
    }

    private func duplicateVoicePreset(_ preset: NarrationVoicePreset) {
        if let copy = workspaceStore.duplicateVoicePreset(preset) {
            selectedPresetID = copy.id
            appStore.statusMessage = "Duplicated voice: \(copy.displayName)"
        }
    }

    private func deleteVoicePreset(_ preset: NarrationVoicePreset) {
        guard !preset.isBuiltIn else {
            workspaceStore.deleteVoicePreset(preset)
            return
        }
        let deletedID = preset.id
        workspaceStore.deleteVoicePreset(preset)
        if selectedPresetID == deletedID {
            selectedPresetID = workspaceStore.voicePresets.first?.id
        }
        appStore.statusMessage = "Deleted voice: \(preset.displayName)"
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

private struct VoicePresetRow: View {
    let preset: NarrationVoicePreset
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
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
                Text(preset.voiceID)
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

private struct VoicePresetDetailPane: View {
    @EnvironmentObject private var appStore: AppStore
    let preset: NarrationVoicePreset?

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
                                    appStore.applyVoicePreset(preset)
                                } label: {
                                    Label("Apply", systemImage: "checkmark.circle")
                                }
                            }

                            DetailGrid {
                                DetailGridRow("Backend", backendName(preset.backendID))
                                DetailGridRow("Model", preset.modelID)
                                DetailGridRow("Voice", preset.voiceID)
                                DetailGridRow("Locale", preset.locale ?? "n/a")
                                DetailGridRow("Updated", SessionFormatters.displayDateFormatter.string(from: preset.updatedAt))
                            }
                        }
                    }

                    if !preset.traits.isEmpty {
                        WorkspaceCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Traits")
                                    .font(.headline)
                                Text(preset.traits.joined(separator: "  "))
                                    .foregroundStyle(.secondary)
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
                    systemImage: "waveform",
                    title: "No Voice Selected",
                    message: "Choose a voice preset from the list."
                )
                .padding()
            }
        }
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
                                DetailGridRow("Voice", preset.voiceID ?? "Current")
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
                            Button("Refresh Status") {
                                appStore.refreshBackendStatus()
                            }
                            Button("Show Details") {
                                appStore.showBackendDetails()
                            }
                            Button("Prepare") {
                                operationsStore.run(.prepare, profile: backend) { result in
                                    appStore.statusMessage = result.message
                                    appStore.refreshBackendStatus()
                                }
                            }
                            .disabled(operationsStore.isRunning || appStore.isGenerating)
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

struct SettingsLandingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Settings",
                subtitle: "App preferences."
            )

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Settings")
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
