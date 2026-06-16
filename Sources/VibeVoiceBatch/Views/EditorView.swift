import SwiftUI
import VibeVoiceBatchCore

struct EditorView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(TextMetrics.wordCount(in: store.editorText)) words  \(store.editorText.count) characters")
                        .font(.callout)
                }

                Spacer()

                GenerateControl()
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { store.editorText },
                    set: { store.updateEditorText($0) }
                ))
                .font(.system(.body, design: .serif))
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Narration text editor")

                if store.editorText.isEmpty {
                    Text("Narration text")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            }
        }
        .padding(20)
        .navigationTitle(store.hasUnsavedEditorText ? "Unsaved Text" : "New Session")
    }
}

private struct GenerateControl: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Button {
            store.generate()
        } label: {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(width: 46, height: 36)
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(!store.canGenerate)
        .help(store.canGenerate ? "Generate WAV (Command-Return)" : store.backendStatus.userMessage)
        .padding(.leading, 10)
        .accessibilityLabel("Generate WAV")
    }
}
