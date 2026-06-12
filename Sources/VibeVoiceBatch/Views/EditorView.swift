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

            GenerationTickerView()
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
        .help("Generate WAV")
        .padding(.leading, 8)
        .accessibilityLabel("Generate WAV")
    }
}

private struct GenerationTickerView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)

            Text(store.generationTicker.displayLine)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(textColor.opacity(store.generationTicker.isActive ? 0.55 : 0.25), lineWidth: 1)
        }
        .accessibilityLabel(store.generationTicker.displayLine)
    }

    private var indicatorColor: Color {
        if store.generationTicker.isProblem {
            return .orange
        }
        return store.generationTicker.isActive ? .green : .gray
    }

    private var textColor: Color {
        if store.generationTicker.isProblem {
            return Color(red: 1.0, green: 0.45, blue: 0.30)
        }
        if store.generationTicker.isActive {
            return Color(red: 0.62, green: 1.0, blue: 0.58)
        }
        return Color(red: 0.70, green: 0.78, blue: 0.68)
    }
}
