import SwiftUI
import VibeVoiceBatchCore

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @Environment(\.openWindow) private var openWindow
    @State private var selection: WorkstationSelection? = .section(.history)
    @State private var didOfferSetupAssistant = false
    @SceneStorage("local.vibevoice.batch.showInspector") private var showInspector = true

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationTitle("Narration")
                .frame(minWidth: 280, idealWidth: 330)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    BackendStatusView()
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                    detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showsGenerationTicker {
                        GenerationTickerView()
                            .padding(.horizontal)
                            .padding(.bottom)
                    }
                }

                if showInspector {
                    Divider()
                    InspectorPanelView(selection: selection)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.newDocument()
                } label: {
                    Label("New", systemImage: "doc.badge.plus")
                }
                .help("New")

                Button {
                    store.saveDraft()
                } label: {
                    Label("Save Draft", systemImage: "tray.and.arrow.down")
                }
                .disabled(!store.canSaveDraft)
                .help("Save Draft")

                Button(role: .destructive) {
                    store.cancelGeneration()
                } label: {
                    Label("Cancel", systemImage: "stop.circle")
                }
                .disabled(!store.isGenerating)
                .help("Cancel")
            }

            ToolbarItemGroup {
                Button {
                    if let session = store.selectedSession {
                        store.openSessionFolder(session)
                    }
                } label: {
                    Label("Open Session Folder", systemImage: "folder")
                }
                .disabled(store.selectedSession == nil)
                .help("Open Session Folder")

                Button {
                    if let session = store.selectedSession {
                        store.playWAV(session)
                    }
                } label: {
                    Label(playWAVTitle, systemImage: playWAVSystemImage)
                }
                .disabled(store.selectedSession?.outputURL == nil)
                .help("Play WAV")

                Button {
                    if let session = store.selectedSession {
                        store.duplicateAsNew(session)
                    }
                } label: {
                    Label("Duplicate as New", systemImage: "doc.on.doc")
                }
                .disabled(store.selectedSession == nil)
                .help("Duplicate as New")
            }

            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help(showInspector ? "Hide Inspector" : "Show Inspector")
            }
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
        .onChange(of: selection) { newValue in
            if case .historySession(let sessionID) = newValue {
                store.selectedSessionID = sessionID
            } else {
                store.selectedSessionID = nil
            }
        }
        .alert("VibeVoice Batch", isPresented: alertBinding) {
            Button("OK", role: .cancel) {
                store.alertMessage = nil
                workspaceStore.alertMessage = nil
            }
        } message: {
            Text(store.alertMessage ?? workspaceStore.alertMessage ?? "")
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
        case .section(.history):
            EditorView()
        case .section(.backends):
            BackendsView()
        case .section(.settings):
            SettingsLandingView()
        case .historySession:
            if let session = store.selectedSession {
                SessionDetailView(record: session)
            } else {
                EditorView()
            }
        }
    }

    private var showsGenerationTicker: Bool {
        switch selection ?? .section(.history) {
        case .section(.history), .section(.outputs), .historySession:
            return true
        case .section:
            return store.isGenerating
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

    private var playWAVTitle: String {
        guard let session = store.selectedSession else { return "Play WAV" }
        return store.isPlaying(session) ? "Stop WAV" : "Play WAV"
    }

    private var playWAVSystemImage: String {
        guard let session = store.selectedSession else { return "play.circle" }
        return store.isPlaying(session) ? "stop.circle" : "play.circle"
    }
}
