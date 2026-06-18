import AppKit
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
            HStack {
                StatusBadge(status: record.metadata.status)
                VoiceInlineLabel(voiceID: record.metadata.voice)
                Text("cfg \(record.metadata.cfgScale)")
                Text("steps \(stepsText)")
            }
            .font(.callout)

            Text(SessionFormatters.displayDateFormatter.string(from: record.metadata.createdAt))
                .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                MetricLabel(title: "Words", value: "\(record.metadata.inputWordCount)")
                MetricLabel(title: "Generation", value: SessionFormatters.duration(record.metadata.generationTimeSeconds))
                MetricLabel(title: "Audio", value: SessionFormatters.duration(record.metadata.audioDurationSeconds))
                MetricLabel(title: "RTF", value: SessionFormatters.rtf(record.metadata.rtf))
                Spacer(minLength: 0)
            }
        }
    }

    private var stepsText: String {
        record.metadata.ddpmInferenceSteps.map(String.init) ?? "--"
    }

    private var textPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            CopyPaneHeader(title: "Input") {
                copyToPasteboard(record.inputText)
            }

            ScrollView {
                Text(record.inputText.isEmpty ? "No input text saved." : record.inputText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var logPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            CopyPaneHeader(title: "Log") {
                copyToPasteboard(store.logText(for: record))
            }

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
    }

    private var metadataPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            CopyPaneHeader(title: "Metadata") {
                copyToPasteboard(record.metadataJSON)
            }

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

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        store.statusMessage = "Copied \(record.id)"
    }
}

private struct CopyPaneHeader: View {
    let title: String
    let copy: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Button {
                copy()
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
        }
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

struct MissingHistorySelectionView: View {
    let sessionID: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.folder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Session Not Found")
                .font(.headline)
            Text(sessionID)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
