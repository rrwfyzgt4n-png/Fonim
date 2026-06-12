import SwiftUI
import VibeVoiceBatchCore

struct EditorView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voice")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Voice", text: $store.selectedVoice)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("CFG Scale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("CFG Scale", text: $store.cfgScale)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(TextMetrics.wordCount(in: store.editorText)) words  \(store.editorText.count) characters")
                        .font(.callout)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(store.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if store.isGenerating {
                        Text("Elapsed \(SessionFormatters.duration(store.elapsedSeconds))")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
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
