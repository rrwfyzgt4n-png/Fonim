import SwiftUI
import VibeVoiceBatchCore

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationTitle("History")
                .frame(minWidth: 340, idealWidth: 390)
        } detail: {
            if let session = store.selectedSession {
                SessionDetailView(record: session)
            } else {
                EditorView()
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
                    Label("Play WAV", systemImage: "play.circle")
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
        }
        .onAppear {
            store.refreshHistory()
        }
        .alert("VibeVoice Batch", isPresented: alertBinding) {
            Button("OK", role: .cancel) {
                store.alertMessage = nil
            }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )
    }
}
