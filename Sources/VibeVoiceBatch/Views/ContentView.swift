import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @Environment(\.openWindow) private var openWindow
    @State private var selection: WorkstationSelection? = .section(.history)
    @State private var didOfferSetupAssistant = false
    @State private var showingOutputProjectFiling = false
    @SceneStorage("local.vibevoice.batch.showInspector") private var showInspector = true

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationTitle("Narration")
                .navigationSplitViewColumnWidth(min: 170, ideal: 220, max: 320)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    BackendStatusView()
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                    detailView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if showInspector {
                    Divider()
                    InspectorPanelView(selection: selection, selectedSession: selectedToolbarSession)
                }
            }
        }
        .toolbar {
            contextualToolbar
            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help(showInspector ? "Hide Inspector" : "Show Inspector")
            }
        }
        .sheet(isPresented: $showingOutputProjectFiling) {
            FileOutputsToProjectSheet(records: store.selectedOutputSessions)
                .environmentObject(store)
                .environmentObject(workspaceStore)
        }
        .onAppear {
            store.refreshHistory()
            workspaceStore.refresh()
            store.refreshBackendStatusIfPreferred()
            if !settingsStore.settings.hasCompletedSetupAssistant, !didOfferSetupAssistant {
                didOfferSetupAssistant = true
                openWindow(id: "backend-setup")
            }
        }
        .onChange(of: store.requestedSelection) { requestedSelection in
            guard let requestedSelection else { return }
            selection = requestedSelection
            store.clearRequestedSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fonimWorkspaceDidChange)) { _ in
            workspaceStore.refresh()
        }
        .alert("Fonim", isPresented: alertBinding) {
            Button("Copy Details") {
                copyAlertDetails()
            }
            Button("OK", role: .cancel) {
                store.alertMessage = nil
                workspaceStore.alertMessage = nil
            }
        } message: {
            Text(currentAlertMessage)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .section(.history) {
        case .section(.projects):
            ProjectsView()
        case .section(.scripts):
            ScriptsView()
        case .section(.batches):
            BatchesView()
        case .section(.voices):
            VoicesView()
        case .section(.presets):
            PresetsView()
        case .section(.outputs):
            OutputBrowserView()
        case .section(.history), .queuedGeneration:
            GenerationWorkspaceView(selection: $selection)
        case .section(.backends):
            BackendsView()
        case .historySession:
            GenerationWorkspaceView(selection: $selection)
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { store.alertMessage != nil || workspaceStore.alertMessage != nil },
            set: {
                if !$0 {
                    store.alertMessage = nil
                    workspaceStore.alertMessage = nil
                }
            }
        )
    }

    private var currentAlertMessage: String {
        store.alertMessage ?? workspaceStore.alertMessage ?? ""
    }

    private func copyAlertDetails() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentAlertMessage, forType: .string)
        store.statusMessage = "Copied error details"
    }

    @ToolbarContentBuilder
    private var contextualToolbar: some ToolbarContent {
        switch (selection ?? .section(.history)).toolbarKind {
        case .editor:
            editorToolbar
        case .session:
            sessionToolbar
        case .outputs:
            outputsToolbar
        case .backends:
            backendToolbar
        case .workspace:
            workspaceToolbar
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                store.newDocument()
            } label: {
                Label("New Generation", systemImage: "doc.badge.plus")
            }
            .keyboardShortcut("n", modifiers: [.command])
            .help("New Generation")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.saveDraft()
            } label: {
                Label("Save Draft", systemImage: "tray.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(!store.canSaveDraft)
            .help("Save Draft")

            Button {
                store.generate()
            } label: {
                Label("Generate", systemImage: "waveform.circle.fill")
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!store.canGenerate)
            .help(store.canGenerate ? "Generate WAV" : store.backendStatus.userMessage)

            Button(role: .destructive) {
                store.cancelGeneration()
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(!store.isGenerating)
            .help("Stop Generation")
        }
    }

    @ToolbarContentBuilder
    private var sessionToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                if let session = selectedToolbarSession {
                    store.openSessionFolder(session)
                }
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(selectedToolbarSession == nil)
            .help("Open Session Folder")

            Button {
                if let session = selectedToolbarSession {
                    store.playWAV(session)
                }
            } label: {
                Label(playWAVTitle, systemImage: playWAVSystemImage)
            }
            .disabled(selectedToolbarSession?.outputURL == nil)
            .help("Play WAV")

            Button {
                if let session = selectedToolbarSession {
                    store.duplicateAsNew(session)
                }
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(selectedToolbarSession == nil)
            .help("Duplicate as New")
        }
    }

    @ToolbarContentBuilder
    private var outputsToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(role: .destructive) {
                store.archiveOutputSessions(store.selectedOutputSessions)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .disabled(store.selectedOutputSessions.isEmpty)
            .help("Archive selected outputs to recovered/deleted_sessions so they can be restored later")

            Button {
                showingOutputProjectFiling = true
            } label: {
                Label("File into Project", systemImage: "folder.badge.plus")
            }
            .disabled(store.selectedOutputSessions.isEmpty || workspaceStore.projects.isEmpty)
            .help(workspaceStore.projects.isEmpty ? "Create a project before filing outputs" : "File selected outputs into a project")

            Button {
                store.shareSelectedOutputFiles()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(store.selectedOutputSessions.isEmpty)
            .help("Share selected WAV files")

            Button {
                store.revealSelectedOutputFile()
            } label: {
                Label("Reveal", systemImage: "finder")
            }
            .disabled(store.selectedOutputSessions.isEmpty)
            .help("Reveal the first selected WAV in Finder")

            Button {
                store.quickLookSelectedOutputFile()
            } label: {
                Label("Quick Look", systemImage: "eye")
            }
            .disabled(store.selectedOutputSessions.isEmpty)
            .help("Preview the first selected WAV")
        }
    }

    @ToolbarContentBuilder
    private var backendToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.refreshBackendStatus()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshingBackendStatus || store.isGenerating)
            .help(store.isRefreshingBackendStatus ? "Backend status is already refreshing" : "Refresh backend status")

            Button {
                store.performBackendOperation(.install)
            } label: {
                Label("Install", systemImage: store.activeBackendOperation == .install ? "hourglass" : "square.and.arrow.down")
            }
            .disabled(store.activeBackendOperation != nil || store.isGenerating)
            .help("Install or pull the selected backend image")

            Button {
                store.performBackendOperation(.prepare)
            } label: {
                Label("Prepare", systemImage: store.activeBackendOperation == .prepare ? "hourglass" : "play.circle")
            }
            .disabled(store.activeBackendOperation != nil || store.isGenerating)
            .help("Prepare the selected backend for generation")

            Button {
                openWindow(id: "backend-setup")
            } label: {
                Label("Setup Assistant", systemImage: "checklist")
            }
        }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if isBatchesSelection {
                Button {
                    store.pauseGenerationQueue()
                } label: {
                    Label("Pause Queue", systemImage: "pause.circle")
                }
                .disabled(!store.queuedGenerations.contains(where: { $0.status == .queued }))
                .help("Pause queued generations after the current run")

                Button {
                    store.resumeGenerationQueue()
                } label: {
                    Label("Resume Queue", systemImage: "play.circle")
                }
                .disabled(!store.queuedGenerations.contains(where: { $0.status == .paused }))
                .help("Resume paused queued generations")
            }

            Button {
                workspaceStore.refresh()
                store.refreshHistory()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(workspaceStore.isRefreshing)
        }
    }

    private var isBatchesSelection: Bool {
        if case .section(.batches) = selection ?? .section(.history) {
            return true
        }
        return false
    }

    private var playWAVTitle: String {
        guard let session = selectedToolbarSession else { return "Play WAV" }
        return store.isPlaying(session) ? "Stop WAV" : "Play WAV"
    }

    private var playWAVSystemImage: String {
        guard let session = selectedToolbarSession else { return "play.circle" }
        return store.isPlaying(session) ? "stop.circle" : "play.circle"
    }

    private var selectedToolbarSession: SessionRecord? {
        guard case .historySession(let sessionID) = selection else { return nil }
        return store.session(id: sessionID)
    }
}
