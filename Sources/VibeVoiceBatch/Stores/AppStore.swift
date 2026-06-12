import AppKit
import AVFoundation
import Foundation
import VibeVoiceBatchCore

final class AppStore: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var sessions: [SessionRecord] = []
    @Published var selectedSessionID: String?
    @Published var editorText = ""
    @Published var selectedVoice = AppDefaults.defaultVoice
    @Published var cfgScale = AppDefaults.defaultCFGScale
    @Published var hasUnsavedEditorText = false
    @Published private(set) var isGenerating = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var activeSessionID: String?
    @Published var pendingScrollSessionID: String?
    @Published private(set) var generationTicker = GenerationTickerState.idle
    @Published private(set) var isPlayingWAV = false
    @Published private(set) var playingSessionID: String?
    @Published var statusMessage = "Ready"
    @Published var alertMessage: String?
    @Published private var liveLogBySessionID: [String: String] = [:]

    private let fileStore = SessionFileStore()
    private let runner = DockerGenerationRunner()
    private var activeTask: Task<Void, Never>?
    private var elapsedTimer: Timer?
    private var activeStartedAt: Date?
    private var audioPlayer: AVAudioPlayer?

    var selectedSession: SessionRecord? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    var canGenerate: Bool {
        !isGenerating && !editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSaveDraft: Bool {
        !isGenerating && !editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refreshHistory() {
        do {
            sessions = try fileStore.loadSessions()
        } catch {
            alertMessage = "Could not load history: \(error.localizedDescription)"
        }
    }

    func updateEditorText(_ value: String) {
        editorText = value
        hasUnsavedEditorText = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        selectedSessionID = nil
    }

    func newDocument() {
        if hasUnsavedEditorText, !editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = saveDraft(selectAfterSave: false, messagePrefix: "Saved previous text as draft")
        }

        editorText = ""
        selectedVoice = AppDefaults.defaultVoice
        cfgScale = AppDefaults.defaultCFGScale
        hasUnsavedEditorText = false
        selectedSessionID = nil
        statusMessage = "New blank editor"
        if !isGenerating {
            generationTicker = .idle
        }
    }

    @discardableResult
    func saveDraft(selectAfterSave: Bool = true, messagePrefix: String = "Draft saved") -> SessionRecord? {
        let text = editorText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "No text to save"
            return nil
        }

        do {
            let record = try fileStore.createDraft(text: text, voice: selectedVoice, cfgScale: cfgScale)
            hasUnsavedEditorText = false
            refreshHistory()
            if selectAfterSave {
                selectedSessionID = record.id
                pendingScrollSessionID = record.id
            }
            statusMessage = "\(messagePrefix): \(record.id)"
            return record
        } catch {
            alertMessage = "Could not save draft: \(error.localizedDescription)"
            return nil
        }
    }

    func generate() {
        let text = editorText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "No text to generate"
            return
        }
        guard !isGenerating else { return }

        do {
            let workspace = try fileStore.createGenerationSession(
                text: text,
                voice: selectedVoice,
                cfgScale: cfgScale
            )
            selectedSessionID = nil
            activeSessionID = workspace.record.id
            hasUnsavedEditorText = false
            isGenerating = true
            elapsedSeconds = 0
            activeStartedAt = Date()
            liveLogBySessionID[workspace.record.id] = ""
            generationTicker = .started(voice: selectedVoice, cfgScale: cfgScale)

            var initialLog = """
            Session: \(workspace.record.id)
            Created: \(ISO8601DateFormatter().string(from: workspace.record.metadata.createdAt))
            Command: \(workspace.command.displayCommand)

            """

            try fileStore.stageInput(text)
            initialLog += "Staged input.txt for Docker.\n"

            if let recovered = try fileStore.recoverExistingGeneratedWAV(reason: "pre_run") {
                initialLog += "Recovered existing generated WAV before run: \(recovered.path)\n"
            }

            initialLog += "\nStarting Docker generation...\n\n"
            liveLogBySessionID[workspace.record.id] = initialLog
            try fileStore.replaceLog(initialLog, in: workspace.record.folderURL)
            refreshHistory()
            pendingScrollSessionID = workspace.record.id
            generationTicker = generationTicker.ingesting(logText: initialLog, elapsed: 0)
            startElapsedTimer()

            let fileStore = self.fileStore
            let runner = self.runner

            activeTask = Task.detached(priority: .userInitiated) { [weak self] in
                let result: DockerRunResult
                do {
                    result = try runner.run(command: workspace.command) { chunk in
                        try? fileStore.appendLog(chunk, to: workspace.record.folderURL)
                        DispatchQueue.main.async {
                            self?.appendLiveLog(chunk, sessionID: workspace.record.id)
                        }
                    }
                } catch {
                    let failureText = "\nCould not start Docker: \(error.localizedDescription)\n"
                    try? fileStore.appendLog(failureText, to: workspace.record.folderURL)
                    DispatchQueue.main.async {
                        self?.appendLiveLog(failureText, sessionID: workspace.record.id)
                    }
                    let failedResult = DockerRunResult(exitCode: -1, wasCancelled: false, elapsedSeconds: Date().timeIntervalSince(workspace.record.metadata.createdAt))
                    self?.finishGeneration(workspace: workspace, result: failedResult)
                    return
                }

                self?.finishGeneration(workspace: workspace, result: result)
            }
        } catch {
            alertMessage = "Could not start generation: \(error.localizedDescription)"
            isGenerating = false
            stopElapsedTimer()
            generationTicker = generationTicker.finished(message: "Could not start Docker", elapsed: elapsedSeconds, phase: .failed)
        }
    }

    func cancelGeneration() {
        guard isGenerating else { return }
        statusMessage = "Cancelling generation..."
        runner.cancel()
    }

    func duplicateAsNew(_ record: SessionRecord) {
        editorText = record.inputText
        selectedVoice = record.metadata.voice
        cfgScale = record.metadata.cfgScale
        hasUnsavedEditorText = !record.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        selectedSessionID = nil
        statusMessage = "Duplicated \(record.id) as new unsaved text"
    }

    func archiveDeleteSession(_ record: SessionRecord) {
        do {
            let destination = try fileStore.archiveDeletedSession(record)
            if selectedSessionID == record.id {
                selectedSessionID = nil
            }
            refreshHistory()
            statusMessage = "Moved deleted session to \(destination.lastPathComponent)"
        } catch {
            alertMessage = "Could not delete session: \(error.localizedDescription)"
        }
    }

    func openSessionFolder(_ record: SessionRecord) {
        NSWorkspace.shared.open(record.folderURL)
    }

    func playWAV(_ record: SessionRecord) {
        if isPlaying(record) {
            stopWAVPlayback(status: "Stopped playback")
            return
        }

        guard let outputURL = record.outputURL else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: outputURL)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            playingSessionID = record.id
            isPlayingWAV = true
            statusMessage = "Playing \(record.id)"
        } catch {
            alertMessage = "Could not play WAV: \(error.localizedDescription)"
        }
    }

    func isPlaying(_ record: SessionRecord) -> Bool {
        isPlayingWAV && playingSessionID == record.id
    }

    func logText(for record: SessionRecord) -> String {
        liveLogBySessionID[record.id] ?? record.logText
    }

    func clearPendingScrollRequest() {
        pendingScrollSessionID = nil
    }

    private func appendLiveLog(_ chunk: String, sessionID: String) {
        liveLogBySessionID[sessionID, default: ""] += chunk
        if sessionID == activeSessionID {
            generationTicker = generationTicker.ingesting(
                logText: liveLogBySessionID[sessionID, default: ""],
                elapsed: elapsedSeconds
            )
        }
        if sessionID == selectedSessionID {
            objectWillChange.send()
        }
    }

    private func finishGeneration(workspace: GenerationWorkspace, result: DockerRunResult) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            var metadata = workspace.record.metadata
            let completedAt = Date()
            metadata.completedAt = completedAt
            let currentLogText = (try? String(contentsOf: workspace.record.logURL, encoding: .utf8)) ?? ""
            let dockerSummary = GenerationOutputParser.latestSummary(in: currentLogText)
            metadata.generationTimeSeconds = dockerSummary?.generationTimeSeconds ?? result.elapsedSeconds

            var finalLog = "\nDocker process exited with code \(result.exitCode).\n"

            do {
                if result.wasCancelled {
                    metadata.status = .cancelled
                    if let recovered = try self.fileStore.recoverExistingGeneratedWAV(reason: "cancelled_\(workspace.record.id)") {
                        finalLog += "Recovered generated staging WAV after cancellation: \(recovered.path)\n"
                    }
                    finalLog += "Generation cancelled.\n"
                } else if result.exitCode == 0, let outputURL = try self.fileStore.moveGeneratedWAVToSession(folderURL: workspace.record.folderURL) {
                    metadata.status = .completed
                    metadata.outputFile = outputURL.path
                    if let duration = try WaveAudioInspector.durationSeconds(for: outputURL) {
                        metadata.audioDurationSeconds = duration
                        if let summaryRTF = dockerSummary?.rtf {
                            metadata.rtf = summaryRTF
                        } else if duration > 0 {
                            metadata.rtf = result.elapsedSeconds / duration
                        }
                    } else if let summaryDuration = dockerSummary?.audioDurationSeconds {
                        metadata.audioDurationSeconds = summaryDuration
                        metadata.rtf = dockerSummary?.rtf ?? (summaryDuration > 0 ? result.elapsedSeconds / summaryDuration : nil)
                    }
                    finalLog += "Completed: \(outputURL.path)\n"
                } else {
                    metadata.status = .failed
                    if let recovered = try self.fileStore.recoverExistingGeneratedWAV(reason: "failed_\(workspace.record.id)") {
                        finalLog += "Recovered generated staging WAV after failure: \(recovered.path)\n"
                    }
                    finalLog += "FAILED: no completed output.wav was produced.\n"
                }

                try self.fileStore.appendLog(finalLog, to: workspace.record.folderURL)
                try self.fileStore.writeMetadata(metadata, in: workspace.record.folderURL)
            } catch {
                finalLog += "Finalization error: \(error.localizedDescription)\n"
                try? self.fileStore.appendLog(finalLog, to: workspace.record.folderURL)
                metadata.status = .failed
                metadata.completedAt = completedAt
                try? self.fileStore.writeMetadata(metadata, in: workspace.record.folderURL)
            }

            DispatchQueue.main.async {
                self.appendLiveLog(finalLog, sessionID: workspace.record.id)
                self.isGenerating = false
                self.activeTask = nil
                self.activeSessionID = nil
                self.elapsedSeconds = result.elapsedSeconds
                let logText = self.liveLogBySessionID[workspace.record.id, default: ""]
                self.generationTicker = self.generationTicker
                    .ingesting(logText: logText, elapsed: result.elapsedSeconds)
                    .finished(
                    message: metadata.status.displayName,
                    elapsed: result.elapsedSeconds,
                    phase: metadata.status.tickerPhase
                    )
                self.stopElapsedTimer()
                self.refreshHistory()
                self.pendingScrollSessionID = workspace.record.id
                self.statusMessage = metadata.status.displayName
            }
        }
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let activeStartedAt = self.activeStartedAt else { return }
            let elapsed = Date().timeIntervalSince(activeStartedAt)
            self.elapsedSeconds = elapsed
            if self.isGenerating {
                self.generationTicker = self.generationTicker.ticking(elapsed: elapsed)
            }
        }
        elapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        activeStartedAt = nil
    }

    private func stopWAVPlayback(status: String? = nil) {
        audioPlayer?.stop()
        audioPlayer = nil
        playingSessionID = nil
        isPlayingWAV = false
        if let status {
            statusMessage = status
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.stopWAVPlayback(status: flag ? "Playback finished" : "Playback stopped")
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.stopWAVPlayback(status: "Playback failed")
            if let error {
                self.alertMessage = "Could not play WAV: \(error.localizedDescription)"
            }
        }
    }
}

private extension SessionStatus {
    var tickerPhase: GenerationTickerState.Phase {
        switch self {
        case .completed: .completed
        case .failed: .failed
        case .cancelled: .cancelled
        case .running: .running
        case .draft: .idle
        }
    }
}
