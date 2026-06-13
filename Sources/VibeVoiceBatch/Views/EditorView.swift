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

            TextEditor(text: Binding(
                get: { store.editorText },
                set: { store.updateEditorText($0) }
            ))
            .font(.system(.body, design: .serif))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            }
        }
        .padding()
        .navigationTitle(store.hasUnsavedEditorText ? "Unsaved Text" : "New Session")
    }
}

private struct GenerateControl: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Button {
            store.generate()
        } label: {
            Label("Generate WAV", systemImage: "waveform.circle.fill")
                .labelStyle(.iconOnly)
                .font(.title2)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(width: 44, height: 34)
        .disabled(!store.canGenerate)
        .help(store.canGenerate ? "Generate WAV" : store.backendStatus.userMessage)
        .padding(.leading, 8)
        .accessibilityLabel("Generate WAV")
    }
}
