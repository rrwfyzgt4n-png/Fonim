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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Voices",
                    subtitle: "Reusable voice profiles across backends."
                )

                HStack {
                    Button {
                        if let preset = workspaceStore.saveCurrentVoicePreset(voiceID: appStore.selectedVoice) {
                            appStore.statusMessage = "Saved voice preset: \(preset.displayName)"
                        }
                    } label: {
                        Label("Save Current Voice", systemImage: "plus")
                    }

                    Spacer()

                    Text("\(workspaceStore.voicePresets.count) voices")
                        .foregroundStyle(.secondary)
                }

                if workspaceStore.voicePresets.isEmpty {
                    EmptyWorkspaceView(
                        systemImage: "waveform",
                        title: "No Voices",
                        message: "No voice presets are available."
                    )
                } else {
                    ForEach(workspaceStore.voicePresets) { preset in
                        VoicePresetCard(preset: preset)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Voices")
    }
}

struct PresetsView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Presets",
                    subtitle: "Reusable generation settings."
                )

                WorkspaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Current Editor Settings")
                                .font(.headline)
                            Spacer()
                            Button {
                                if let preset = workspaceStore.saveGenerationPreset(
                                    voiceID: appStore.selectedVoice,
                                    cfgScale: appStore.cfgScale,
                                    ddpmInferenceSteps: appStore.ddpmInferenceSteps,
                                    outputFormat: settingsStore.settings.exportFormat
                                ) {
                                    appStore.statusMessage = "Saved generation preset: \(preset.displayName)"
                                }
                            } label: {
                                Label("Save Current Preset", systemImage: "plus")
                            }
                        }

                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                            GridRow {
                                Text("Voice").foregroundStyle(.secondary)
                                Text(appStore.selectedVoice)
                            }
                            GridRow {
                                Text("CFG").foregroundStyle(.secondary)
                                Text(appStore.cfgScale)
                            }
                            GridRow {
                                Text("DDPM steps").foregroundStyle(.secondary)
                                Text("\(appStore.ddpmInferenceSteps)")
                            }
                            GridRow {
                                Text("Format").foregroundStyle(.secondary)
                                Text(settingsStore.settings.exportFormat.rawValue.uppercased())
                            }
                        }
                    }
                }

                if workspaceStore.generationPresets.isEmpty {
                    EmptyWorkspaceView(
                        systemImage: "slider.horizontal.3",
                        title: "No Presets",
                        message: "No generation presets are available."
                    )
                } else {
                    ForEach(workspaceStore.generationPresets) { preset in
                        GenerationPresetCard(preset: preset)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Presets")
    }
}

private struct VoicePresetCard: View {
    @EnvironmentObject private var appStore: AppStore
    let preset: NarrationVoicePreset

    var body: some View {
        WorkspaceCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(preset.displayName)
                            .font(.headline)
                        if preset.isBuiltIn {
                            Text("Built-in")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .foregroundStyle(.secondary)
                                .background(.secondary.opacity(0.14), in: Capsule())
                        }
                    }

                    Text("\(backendName(preset.backendID))  \(preset.voiceID)")
                        .foregroundStyle(.secondary)

                    if !preset.traits.isEmpty {
                        Text(preset.traits.joined(separator: "  "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    appStore.applyVoicePreset(preset)
                } label: {
                    Label("Apply", systemImage: "checkmark.circle")
                }
            }
        }
    }
}

private struct GenerationPresetCard: View {
    @EnvironmentObject private var appStore: AppStore
    let preset: NarrationGenerationPreset

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(preset.displayName)
                                .font(.headline)
                            if preset.isBuiltIn {
                                Text("Built-in")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .foregroundStyle(.secondary)
                                    .background(.secondary.opacity(0.14), in: Capsule())
                            }
                        }
                        Text(backendName(preset.backendID))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        appStore.applyGenerationPreset(preset)
                    } label: {
                        Label("Apply", systemImage: "checkmark.circle")
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("Voice").foregroundStyle(.secondary)
                        Text(preset.voiceID ?? "Current")
                    }
                    GridRow {
                        Text("CFG").foregroundStyle(.secondary)
                        Text(preset.settings.cfgScale)
                    }
                    GridRow {
                        Text("DDPM steps").foregroundStyle(.secondary)
                        Text(preset.settings.ddpmInferenceSteps.map(String.init) ?? "--")
                    }
                    GridRow {
                        Text("Format").foregroundStyle(.secondary)
                        Text(preset.outputFormat.rawValue.uppercased())
                    }
                }
            }
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
