import AppKit
import SwiftUI
import VibeVoiceBatchCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct FonimApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var store: AppStore
    @StateObject private var workspaceStore: WorkspaceStore

    init() {
        let settingsStore = SettingsStore()
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _store = StateObject(wrappedValue: AppStore(settingsStore: settingsStore))
        _workspaceStore = StateObject(wrappedValue: WorkspaceStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(workspaceStore)
                .frame(minWidth: 980, minHeight: 680)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                OpenFonimInfoButton()
            }

            CommandGroup(replacing: .newItem) {
                Button("New Text") {
                    store.newDocument()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Save Draft") {
                    store.saveDraft()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!store.canSaveDraft)

                Divider()

                Button("Generate WAV") {
                    store.generate()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!store.canGenerate)

                Button("Stop Generation") {
                    store.cancelGeneration()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!store.isGenerating)
            }

            CommandMenu("Narration") {
                Button("Apply Default Generation Settings") {
                    store.applyDefaultGenerationSettings()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Button("Refresh History") {
                    store.refreshHistory()
                    workspaceStore.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Refresh Backend Status") {
                    store.refreshBackendStatus()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.isRefreshingBackendStatus || store.isGenerating)

                Divider()

                OpenBackendSetupButton()
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .environmentObject(store)
        }

        Window("Setup Assistant", id: "backend-setup") {
            BackendSetupAssistantView()
                .environmentObject(settingsStore)
                .environmentObject(store)
        }
        .defaultSize(width: 960, height: 680)
        .windowResizability(.contentSize)

        Window("About Fonim", id: "fonim-info") {
            FonimInfoView()
                .environmentObject(store)
        }
        .defaultSize(width: 560, height: 360)
        .windowResizability(.contentSize)
    }
}

private struct OpenFonimInfoButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Fonim") {
            openWindow(id: "fonim-info")
        }
    }
}

private struct OpenBackendSetupButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Backend Setup Assistant") {
            openWindow(id: "backend-setup")
        }
    }
}
