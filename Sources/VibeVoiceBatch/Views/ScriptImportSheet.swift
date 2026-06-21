import SwiftUI
import VibeVoiceBatchCore

struct ScriptImportSheet: View {
    let preview: ScriptImportPreview
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
}
