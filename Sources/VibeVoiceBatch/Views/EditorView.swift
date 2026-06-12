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
                    Picker("Voice", selection: $store.selectedVoice) {
                        ForEach(AppDefaults.availableVoices, id: \.self) { voice in
                            Text(voice).tag(voice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
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
        HStack(spacing: 10) {
            Text(store.isGenerating ? store.elapsedTenSecondCounter : "0s")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(store.isGenerating ? .blue : .secondary)
                .frame(minWidth: 48, alignment: .trailing)

            Button {
                store.generate()
            } label: {
                Label("Generate WAV", systemImage: "waveform.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!store.canGenerate)
            .help("Generate WAV")
        }
        .padding(.leading, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generate WAV, elapsed \(store.elapsedTenSecondCounter)")
    }
}
