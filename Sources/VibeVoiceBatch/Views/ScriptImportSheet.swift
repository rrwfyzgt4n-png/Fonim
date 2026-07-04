import SwiftUI
import VibeVoiceBatchCore

struct ScriptImportSheet: View {
    let preview: ScriptImportPreview
    let projectName: String
    let backendName: String
    let modelID: String
    let voiceID: String
    let settingsSummary: String
    let onCancel: () -> Void
    let onSave: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Script")
                    .font(.title2.weight(.semibold))
                Text("\(preview.chunks.count) chunks  \(preview.totalWordCount) words")
                    .foregroundStyle(.secondary)
            }

            importSummary

            List(preview.chunks.indices, id: \.self) { index in
                let chunk = preview.chunks[index]
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(index + 1). \(chunk.title)")
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(chunk.wordCount) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(chunk.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 260)

            HStack {
                Text(preview.sourceURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save Scripts") {
                    onSave(false)
                }
                .disabled(preview.chunks.isEmpty)
                Button("Save and Queue") {
                    onSave(true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(preview.chunks.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 480)
    }

    private var importSummary: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                summaryLabel("Project")
                Text(projectName)
                summaryLabel("Settings")
                Text(settingsSummary)
            }
            GridRow {
                summaryLabel("Backend")
                Text(backendName)
                summaryLabel("Model")
                Text(modelID)
            }
            GridRow {
                summaryLabel("Voice")
                VoiceInlineLabel(voiceID: voiceID, compact: true)
                summaryLabel("Material")
                Text(preview.materialDescription)
            }
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func summaryLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
    }
}
