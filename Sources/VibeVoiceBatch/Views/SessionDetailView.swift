import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct SessionDetailView: View {
    @EnvironmentObject private var store: AppStore
    let record: SessionRecord
    @State private var selectedPane: SessionDetailPane = .input
    @State private var loadedLogSessionID: String?
    @State private var loadedLogText = ""
    @State private var isLoadingLog = false

    var body: some View {
        content
            .navigationTitle(record.id)
            .onChange(of: selectedPane) { pane in
                FonimTelemetry.detailPaneChanged(sessionID: record.id, pane: pane.rawValue)
            }
            .task(id: logLoadTaskID) {
                await loadLogIfNeeded()
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
                .padding()

            Divider()

            Picker("Session Detail", selection: $selectedPane) {
                ForEach(SessionDetailPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.systemImage)
                        .tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])

            Group {
                switch selectedPane {
                case .input:
                    textPane
                case .log:
                    logPane
                case .metadata:
                    metadataPane
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var logLoadTaskID: String {
        "\(record.id)-\(selectedPane.rawValue)"
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

            LargePlainTextView(
                text: record.inputText,
                placeholder: "No input text saved.",
                telemetryKind: "session-input"
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var logPane: some View {
        return VStack(alignment: .leading, spacing: 8) {
            CopyPaneHeader(title: "Log") {
                copyToPasteboard(currentLogText)
            }

            LargeLogTextView(text: logDisplayText)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var currentLogText: String {
        if record.id == store.activeSessionID {
            return store.cachedLogText(for: record)
        }

        guard loadedLogSessionID == record.id else {
            return record.logText
        }

        return loadedLogText
    }

    private var logDisplayText: String {
        let text = currentLogText
        if !text.isEmpty {
            return text
        }
        if isLoadingLog {
            return "Loading log..."
        }
        return "No log yet."
    }

    @MainActor
    private func loadLogIfNeeded() async {
        guard selectedPane == .log else {
            isLoadingLog = false
            return
        }
        guard record.id != store.activeSessionID else {
            isLoadingLog = false
            return
        }
        guard loadedLogSessionID != record.id else {
            isLoadingLog = false
            return
        }

        let requestedSessionID = record.id
        isLoadingLog = true
        let logURL = record.logURL
        FonimTelemetry.sessionLogLoadStarted(sessionID: requestedSessionID)
        let text = await Task.detached(priority: .utility) {
            (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        }.value

        guard !Task.isCancelled, selectedPane == .log else { return }
        loadedLogSessionID = requestedSessionID
        loadedLogText = text
        isLoadingLog = false
        FonimTelemetry.sessionLogLoadFinished(sessionID: requestedSessionID, characterCount: text.count)
    }

    private var metadataPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            CopyPaneHeader(title: "Metadata") {
                copyToPasteboard(record.metadataJSON)
            }

            LargePlainTextView(
                text: record.metadataJSON,
                placeholder: "No metadata saved.",
                style: .metadata,
                telemetryKind: "session-metadata"
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        store.statusMessage = "Copied \(record.id)"
    }
}

private enum SessionDetailPane: String, CaseIterable, Identifiable {
    case input
    case log
    case metadata

    var id: String { rawValue }

    var title: String {
        switch self {
        case .input:
            return "Input"
        case .log:
            return "Log"
        case .metadata:
            return "Metadata"
        }
    }

    var systemImage: String {
        switch self {
        case .input:
            return "text.alignleft"
        case .log:
            return "terminal"
        case .metadata:
            return "curlybraces"
        }
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
