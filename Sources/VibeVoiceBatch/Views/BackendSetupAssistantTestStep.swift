import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct TestVoiceSetupPane: View {
    let profile: BackendProfile
    let modelID: String
    let voiceID: String
    let backendStatus: BackendStatusSnapshot
    let isTesting: Bool
    let statusMessage: String
    let progress: GenerationProgressSnapshot?
    let logText: String
    let record: GenerationRecord?
    let error: GenerationErrorRecord?
    let canTest: Bool
    let runTest: () -> Void
    let cancelTest: () -> Void
    let playResult: () -> Void
    let revealResult: () -> Void
    let openResult: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(title: "Test Voice", subtitle: "Generate a short sample through the selected backend.")

            TestVoiceProgressPanel(
                profile: profile,
                modelID: modelID,
                voiceID: voiceID,
                backendStatus: backendStatus,
                isTesting: isTesting,
                statusMessage: statusMessage,
                progress: progress,
                record: record,
                error: error
            )

            TestVoiceActionPanel(
                isTesting: isTesting,
                canTest: canTest,
                canUseOutput: canUseOutput,
                canOpenRecord: record != nil,
                runTest: runTest,
                cancelTest: cancelTest,
                playResult: playResult,
                revealResult: revealResult,
                openResult: openResult
            )

            TestVoiceDetailsPanel(
                record: record,
                error: error,
                logText: logText
            )
        }
    }

    private var canUseOutput: Bool {
        record?.status == .completed && record?.exportPath != nil
    }
}

struct TestVoiceProgressPanel: View {
    let profile: BackendProfile
    let modelID: String
    let voiceID: String
    let backendStatus: BackendStatusSnapshot
    let isTesting: Bool
    let statusMessage: String
    let progress: GenerationProgressSnapshot?
    let record: GenerationRecord?
    let error: GenerationErrorRecord?

    var body: some View {
        SetupTaskPanel(
            title: "Generation Status",
            subtitle: statusMessage,
            systemImage: statusIcon,
            state: statusState
        ) {
            VStack(alignment: .leading, spacing: 10) {
                progressView

                SetupDetailGrid(items: [
                    ("Backend", profile.displayName),
                    ("Runtime State", backendStatus.state.displayName),
                    ("Model", modelID),
                    ("Voice", voiceID),
                    ("Elapsed", elapsedText),
                    ("Remaining", remainingText),
                    ("Audio Duration", audioDurationText)
                ])

                if let progress {
                    Text(progress.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private var progressView: some View {
        if let fraction = progressFraction {
            ProgressView(value: fraction)
        } else if isTesting {
            ProgressView()
        } else {
            ProgressView(value: record?.status == .completed ? 1 : 0)
        }
    }

    private var progressFraction: Double? {
        if record?.status == .completed {
            return 1
        }
        guard let fraction = progress?.fractionComplete else { return nil }
        return min(1, max(0, fraction))
    }

    private var statusState: BackendSetupCheckState {
        if isTesting {
            return .checking
        }
        switch record?.status {
        case .completed: return .passed
        case .failed, .cancelled: return .failed
        case .queued, .running: return .checking
        case nil: return error == nil ? .waiting : .failed
        }
    }

    private var statusIcon: String {
        switch statusState {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .checking: return "waveform"
        case .waiting, .warning: return "waveform"
        }
    }

    private var elapsedText: String {
        if let elapsed = progress?.elapsedSeconds {
            return GenerationTickerState.clock(elapsed)
        }
        if let record,
           let completedAt = record.completedAt {
            return GenerationTickerState.clock(completedAt.timeIntervalSince(record.createdAt))
        }
        return "--:--"
    }

    private var remainingText: String {
        progress?.estimatedRemainingSeconds.map(GenerationTickerState.clock) ?? "--:--"
    }

    private var audioDurationText: String {
        record?.durationSeconds.map(SessionFormatters.duration) ?? "--"
    }
}

struct TestVoiceActionPanel: View {
    let isTesting: Bool
    let canTest: Bool
    let canUseOutput: Bool
    let canOpenRecord: Bool
    let runTest: () -> Void
    let cancelTest: () -> Void
    let playResult: () -> Void
    let revealResult: () -> Void
    let openResult: () -> Void

    var body: some View {
        SetupTaskPanel(
            title: "Result Actions",
            subtitle: "Run the test here, then play, reveal, or inspect the archived result.",
            systemImage: "play.circle",
            state: canUseOutput ? .passed : (isTesting ? .checking : .waiting)
        ) {
            HStack {
                Button {
                    isTesting ? cancelTest() : runTest()
                } label: {
                    Label(isTesting ? "Cancel Test" : "Run Test Voice", systemImage: isTesting ? "xmark.circle" : "waveform")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canTest && !isTesting)

                Button {
                    playResult()
                } label: {
                    Label("Play Test", systemImage: "play.fill")
                }
                .disabled(!canUseOutput)

                Button {
                    revealResult()
                } label: {
                    Label("Reveal Test", systemImage: "finder")
                }
                .disabled(!canUseOutput)

                Button {
                    openResult()
                } label: {
                    Label("Open in History", systemImage: "clock.arrow.circlepath")
                }
                .disabled(!canOpenRecord)

                Spacer()
            }
        }
    }
}

struct TestVoiceDetailsPanel: View {
    let record: GenerationRecord?
    let error: GenerationErrorRecord?
    let logText: String

    var body: some View {
        SetupTaskPanel(
            title: "Test Record",
            subtitle: "Logs stay collapsed unless you need implementation details.",
            systemImage: "doc.text.magnifyingglass",
            state: recordState
        ) {
            if let error {
                VStack(alignment: .leading, spacing: 6) {
                    Label(error.title, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error.explanation)
                        .font(.caption)
                    if let recovery = error.recoverySuggestion {
                        Text(recovery)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let details = error.technicalDetails {
                        DisclosureGroup("Error Details") {
                            Text(details)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption)
                    }
                }
            }

            SetupDetailGrid(items: [
                ("Session", record?.id ?? "Not generated yet"),
                ("Status", record?.status.displayName ?? "Not run"),
                ("Output", record?.exportPath ?? "No WAV yet")
            ])

            if !logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("Show Logs") {
                    ScrollView {
                        Text(logText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }
                .font(.caption)
            }
        }
    }

    private var recordState: BackendSetupCheckState {
        switch record?.status {
        case .completed: return .passed
        case .failed, .cancelled: return .failed
        case .queued, .running: return .checking
        case nil: return error == nil ? .waiting : .failed
        }
    }
}
