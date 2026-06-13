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
    @EnvironmentObject private var workspaceStore: WorkspaceStore

    var body: some View {
        WorkspaceListShell(
            title: "Batches",
            subtitle: "Queued script groups.",
            isEmpty: workspaceStore.batches.isEmpty,
            emptySystemImage: "tray.full",
            emptyTitle: "No Batches",
            emptyMessage: "No batch records are saved."
        ) {
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
        .navigationTitle("Batches")
    }

    private func completedCount(_ batch: NarrationBatch) -> Int {
        batch.items.filter { $0.status == .completed }.count
    }
}

struct VoicesView: View {
    var body: some View {
        WorkspaceListShell(
            title: "Voices",
            subtitle: "Available narration voices.",
            isEmpty: AppDefaults.availableVoices.isEmpty,
            emptySystemImage: "waveform",
            emptyTitle: "No Voices",
            emptyMessage: "No voices are available."
        ) {
            ForEach(AppDefaults.availableVoices, id: \.self) { voice in
                WorkspaceCard {
                    Label(voice, systemImage: "waveform")
                        .font(.headline)
                }
            }
        }
        .navigationTitle("Voices")
    }
}

struct PresetsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Presets",
                    subtitle: "Default generation profile."
                )

                WorkspaceCard {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        GridRow {
                            Text("Voice").foregroundStyle(.secondary)
                            Text(settingsStore.settings.defaultVoice)
                        }
                        GridRow {
                            Text("CFG").foregroundStyle(.secondary)
                            Text(settingsStore.settings.defaultCFGScale)
                        }
                        GridRow {
                            Text("DDPM steps").foregroundStyle(.secondary)
                            Text("\(settingsStore.settings.defaultDDPMInferenceSteps)")
                        }
                        GridRow {
                            Text("Format").foregroundStyle(.secondary)
                            Text(settingsStore.settings.exportFormat.rawValue.uppercased())
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Presets")
    }
}

struct BackendsView: View {
    @EnvironmentObject private var appStore: AppStore
    @StateObject private var operationsStore = BackendOperationsStore()

    private var backend: BackendProfile {
        BackendProfiles.vibeVoiceTTS
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
