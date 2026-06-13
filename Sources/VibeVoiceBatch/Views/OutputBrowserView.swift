import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct OutputBrowserView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var selectedOutputID: String?

    private var outputs: [SessionRecord] {
        let records = store.outputSessions
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return records }
        return records.filter { record in
            [
                record.id,
                record.metadata.voice,
                record.metadata.cfgScale,
                record.metadata.outputFile ?? "",
                record.inputText
            ]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedOutput: SessionRecord? {
        guard let selectedOutputID else { return outputs.first }
        return outputs.first { $0.id == selectedOutputID } ?? outputs.first
    }

    var body: some View {
        HStack(spacing: 0) {
            outputList
                .frame(minWidth: 320, idealWidth: 380)

            Divider()

            outputDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Outputs")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search outputs")
        .onAppear {
            store.refreshHistory()
            if selectedOutputID == nil {
                selectedOutputID = outputs.first?.id
            }
            store.selectedSessionID = selectedOutputID
        }
        .onChange(of: selectedOutputID) { sessionID in
            store.selectedSessionID = sessionID
        }
        .onChange(of: store.outputSessions) { records in
            guard selectedOutputID == nil || !records.contains(where: { $0.id == selectedOutputID }) else { return }
            selectedOutputID = records.first?.id
        }
    }

    private var outputList: some View {
        List(selection: $selectedOutputID) {
            ForEach(outputs) { record in
                OutputListRow(record: record)
                    .tag(record.id as String?)
                    .contextMenu {
                        outputMenu(record)
                    }
                    .onDrag {
                        outputProvider(for: record)
                    }
            }
        }
        .overlay {
            if outputs.isEmpty {
                EmptyOutputBrowserView()
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var outputDetail: some View {
        if let record = selectedOutput {
            VStack(alignment: .leading, spacing: 16) {
                OutputHeader(record: record)

                HStack(spacing: 10) {
                    Button {
                        store.playWAV(record)
                    } label: {
                        Label(
                            store.isPlaying(record) ? "Stop WAV" : "Play WAV",
                            systemImage: store.isPlaying(record) ? "stop.circle" : "play.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        store.revealOutputFile(record)
                    } label: {
                        Label("Reveal WAV", systemImage: "finder")
                    }

                    Button {
                        store.quickLookOutputFile(record)
                    } label: {
                        Label("Quick Look", systemImage: "eye")
                    }
                    .disabled(record.outputURL == nil)

                    Button {
                        store.copyOutputPath(record)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.clipboard")
                    }

                    Spacer()

                    Button {
                        store.duplicateAsNew(record)
                    } label: {
                        Label("Duplicate as New", systemImage: "doc.on.doc")
                    }
                }

                OutputMetadataGrid(record: record)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Input")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ScrollView {
                        Text(record.inputText.isEmpty ? "No input text saved." : record.inputText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
            .onDrag {
                outputProvider(for: record)
            }
        } else {
            EmptyOutputBrowserView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func outputMenu(_ record: SessionRecord) -> some View {
        Button {
            store.playWAV(record)
        } label: {
            Label(store.isPlaying(record) ? "Stop WAV" : "Play WAV", systemImage: store.isPlaying(record) ? "stop.circle" : "play.circle")
        }

        Button {
            store.revealOutputFile(record)
        } label: {
            Label("Reveal WAV", systemImage: "finder")
        }

        Button {
            store.quickLookOutputFile(record)
        } label: {
            Label("Quick Look", systemImage: "eye")
        }

        Button {
            store.copyOutputPath(record)
        } label: {
            Label("Copy Path", systemImage: "doc.on.clipboard")
        }

        Divider()

        Button {
            store.duplicateAsNew(record)
        } label: {
            Label("Duplicate as New", systemImage: "doc.on.doc")
        }
    }

    private func outputProvider(for record: SessionRecord) -> NSItemProvider {
        guard let outputURL = record.outputURL,
              let provider = NSItemProvider(contentsOf: outputURL) else {
            return NSItemProvider()
        }
        return provider
    }
}

private struct OutputListRow: View {
    let record: SessionRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .foregroundStyle(.blue)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.outputURL?.lastPathComponent ?? "output.wav")
                    .lineLimit(1)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(SessionFormatters.duration(record.metadata.audioDurationSeconds))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var summary: String {
        "\(record.metadata.voice)  \(record.metadata.inputWordCount) words  \(SessionFormatters.displayDateFormatter.string(from: record.metadata.createdAt))"
    }
}

private struct OutputHeader: View {
    let record: SessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title2)
                Text(record.outputURL?.lastPathComponent ?? "output.wav")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                StatusBadge(status: record.metadata.status)
                Text(record.metadata.voice)
                Text("cfg \(record.metadata.cfgScale)")
                Text("steps \(record.metadata.ddpmInferenceSteps.map(String.init) ?? "--")")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Text(record.id)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private struct OutputMetadataGrid: View {
    let record: SessionRecord

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
            GridRow {
                OutputMetric(title: "Created", value: SessionFormatters.displayDateFormatter.string(from: record.metadata.createdAt))
                OutputMetric(title: "Audio", value: SessionFormatters.duration(record.metadata.audioDurationSeconds))
                OutputMetric(title: "Generation", value: SessionFormatters.duration(record.metadata.generationTimeSeconds))
            }
            GridRow {
                OutputMetric(title: "RTF", value: SessionFormatters.rtf(record.metadata.rtf))
                OutputMetric(title: "Words", value: "\(record.metadata.inputWordCount)")
                OutputMetric(title: "Characters", value: "\(record.metadata.inputCharacterCount)")
            }
        }
    }
}

private struct OutputMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .textSelection(.enabled)
        }
    }
}

private struct EmptyOutputBrowserView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Outputs")
                .font(.headline)
            Text("Completed WAV generations will appear here.")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}
