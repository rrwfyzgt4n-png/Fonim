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
struct VibeVoiceBatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var store: AppStore

    init() {
        let settingsStore = SettingsStore()
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _store = StateObject(wrappedValue: AppStore(settingsStore: settingsStore))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settingsStore)
                .frame(minWidth: 980, minHeight: 680)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Save Draft") {
                    store.saveDraft()
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button("Generate WAV") {
                    store.generate()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!store.canGenerate)

                Button("Cancel Generation") {
                    store.cancelGeneration()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!store.isGenerating)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .environmentObject(store)
        }
    }
}
