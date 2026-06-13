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
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
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
    }
}
