import SwiftUI
import VibeVoiceBatchCore

struct SessionDetailView: View {
    @EnvironmentObject private var store: AppStore
    let record: SessionRecord

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding()

            Divider()

            TabView {
                textPane
                    .tabItem {
                        Label("Input", systemImage: "text.alignleft")
                    }

                logPane
                    .tabItem {
                        Label("Log", systemImage: "terminal")
                    }

                metadataPane
                    .tabItem {
                        Label("Metadata", systemImage: "curlybraces")
                    }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle(record.id)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        StatusBadge(status: record.metadata.status)
                        Text(record.metadata.voice)
                        Text("cfg \(record.metadata.cfgScale)")
                    }
                    .font(.callout)

                    Text(SessionFormatters.displayDateFormatter.string(from: record.metadata.createdAt))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 14) {
                        MetricLabel(title: "Words", value: "\(record.metadata.inputWordCount)")
                        MetricLabel(title: "Generation", value: SessionFormatters.duration(record.metadata.generationTimeSeconds))
                        MetricLabel(title: "Audio", value: SessionFormatters.duration(record.metadata.audioDurationSeconds))
                        MetricLabel(title: "RTF", value: SessionFormatters.rtf(record.metadata.rtf))
                    }
                }

                Spacer()

                HStack {
                    Button {
                        store.openSessionFolder(record)
                    } label: {
                        Label("Open Session Folder", systemImage: "folder")
                    }

                    Button {
                        store.playWAV(record)
                    } label: {
                        Label("Play WAV", systemImage: "play.circle")
                    }
                    .disabled(record.outputURL == nil)

                    Button {
                        store.duplicateAsNew(record)
                    } label: {
                        Label("Duplicate as New", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }

    private var textPane: some View {
        ScrollView {
            Text(record.inputText.isEmpty ? "No input text saved." : record.inputText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var logPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(store.logText(for: record).isEmpty ? "No log yet." : store.logText(for: record))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .id("log-bottom")
            }
            .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
            .onChange(of: store.logText(for: record)) { _ in
                proxy.scrollTo("log-bottom", anchor: .bottom)
            }
        }
    }

    private var metadataPane: some View {
        ScrollView {
            Text(record.metadataJSON)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetricLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
        }
    }
}
