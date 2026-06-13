import AppKit
import AVFoundation
import Foundation
import VibeVoiceBatchCore

@MainActor
final class AppStore: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var sessions: [SessionRecord] = []
    @Published var selectedSessionID: String?
    @Published var editorText = ""
    @Published var selectedVoice = AppDefaults.defaultVoice
    @Published var cfgScale = AppDefaults.defaultCFGScale
    @Published var ddpmInferenceSteps = AppDefaults.defaultDDPMInferenceSteps
    @Published var hasUnsavedEditorText = false
    @Published private(set) var isGenerating = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var activeSessionID: String?
    @Published var pendingScrollSessionID: String?
    @Published private(set) var generationTicker = GenerationTickerState.idle
    @Published private(set) var isPlayingWAV = false
    @Published private(set) var playingSessionID: String?
    @Published private(set) var backendStatus = BackendStatusSnapshot.unknown(profile: BackendProfiles.vibeVoiceTTS)
    @Published private(set) var isRefreshingBackendStatus = false
    @Published private(set) var isPreparingGeneration = false
    @Published private(set) var queuedGenerations: [QueuedGenerationItem] = []
    @Published var selectedQueueItemID: String?
    @Published var statusMessage = "Ready"
    @Published var alertMessage: String?
    @Published private var liveLogBySessionID: [String: String] = [:]

    private let settingsStore: SettingsStore
    private let fileStore = SessionFileStore()
    private let quickLookPreviewer = QuickLookPreviewer()
    private let backendAdapter = VibeVoiceDockerAdapter()
    private lazy var jobQueue = JobQueue(adapters: [backendAdapter])
    private var activeTask: Task<Void, Never>?
    private var activeJobID: String?
    private var queuedJobPayloads: [String: GenerationJob] = [:]
    private var elapsedTimer: Timer?
    private var activeStartedAt: Date?
    private var audioPlayer: AVAudioPlayer?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        super.init()
        selectedVoice = settingsStore.settings.defaultVoice
        cfgScale = settingsStore.settings.defaultCFGScale
        ddpmInferenceSteps = settingsStore.settings.defaultDDPMInferenceSteps
    }

    var selectedSession: SessionRecord? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    var outputSessions: [SessionRecord] {
        sessions.filter { $0.outputURL != nil }
    }

    var canGenerate: Bool {
        !isPreparingGeneration &&
            (isGenerating || backendStatus.canStartGeneration) &&
            !editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    func refreshBackendStatus() {
        guard !isRefreshingBackendStatus else { return }
        Task {
            _ = await refreshBackendStatusNow()
        }
    }

    func refreshBackendStatusIfPreferred() {
        if settingsStore.settings.refreshBackendStatusOnLaunch {
            refreshBackendStatus()
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
        applyDefaultGenerationSettings()
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
            let record = try fileStore.createDraft(
                text: text,
                voice: selectedVoice,
                cfgScale: cfgScale,
                ddpmInferenceSteps: ddpmInferenceSteps
            )
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
        guard !isPreparingGeneration else { return }

        let voice = selectedVoice
        let selectedCFGScale = cfgScale
        let selectedDDPMInferenceSteps = ddpmInferenceSteps
        if isGenerating {
            enqueueGeneration(
                text: text,
                voice: voice,
                cfgScale: selectedCFGScale,
                ddpmInferenceSteps: selectedDDPMInferenceSteps
            )
            return
        }

        isPreparingGeneration = true
        statusMessage = "Checking backend..."
        Task {
            let status = await refreshBackendStatusNow()
            guard status.canStartGeneration else {
                isPreparingGeneration = false
                presentBlockedBackend(status)
                return
            }
            isPreparingGeneration = false
            enqueueGeneration(
                text: text,
                voice: voice,
                cfgScale: selectedCFGScale,
                ddpmInferenceSteps: selectedDDPMInferenceSteps
            )
        }
    }

    func cancelQueuedGeneration(_ item: QueuedGenerationItem) {
        switch item.status {
        case .running:
            guard item.id == activeJobID else { return }
            cancelGeneration()
        case .queued:
            queuedJobPayloads[item.id] = nil
            updateQueuedGeneration(id: item.id) { queuedItem in
                queuedItem.status = .cancelled
                queuedItem.statusMessage = "Cancelled before start"
                queuedItem.completedAt = Date()
            }
            statusMessage = "Cancelled queued generation"
        case .completed, .failed, .cancelled:
            break
        }
    }

    func retryQueuedGeneration(_ item: QueuedGenerationItem) {
        enqueueGeneration(
            text: item.sourceText,
            voice: item.voice,
            cfgScale: item.cfgScale,
            ddpmInferenceSteps: item.ddpmInferenceSteps
        )
        statusMessage = "Queued retry"
    }

    func duplicateQueuedGenerationAsNew(_ item: QueuedGenerationItem) {
        editorText = item.sourceText
        selectedVoice = item.voice
        cfgScale = item.cfgScale
        ddpmInferenceSteps = item.ddpmInferenceSteps
        hasUnsavedEditorText = !item.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        selectedSessionID = nil
        statusMessage = "Duplicated queued item as new unsaved text"
    }

    func showBackendDetails() {
        alertMessage = backendStatus.alertMessageWithDetails
    }

    func applyDefaultGenerationSettings() {
        selectedVoice = settingsStore.settings.defaultVoice
        cfgScale = settingsStore.settings.defaultCFGScale
        ddpmInferenceSteps = settingsStore.settings.defaultDDPMInferenceSteps
        statusMessage = "Applied default generation settings"
    }

    private func enqueueGeneration(
        text: String,
        voice: String,
        cfgScale: String,
        ddpmInferenceSteps: Int
    ) {
        let job = GenerationJob(
            inputText: text,
            backendID: BackendProfiles.vibeVoiceTTS.id,
            modelID: AppDefaults.modelPath,
            voiceID: voice,
            settings: GenerationSettings(
                cfgScale: cfgScale,
                ddpmInferenceSteps: ddpmInferenceSteps
            )
        )
        queuedJobPayloads[job.id] = job
        queuedGenerations.append(QueuedGenerationItem(job: job))
        selectedQueueItemID = job.id
        selectedSessionID = nil
        hasUnsavedEditorText = false
        statusMessage = isGenerating ? "Queued for generation" : "Queued"
        startNextQueuedGenerationIfIdle()
    }

    private func startNextQueuedGenerationIfIdle() {
        guard !isGenerating else { return }
        guard let nextItem = queuedGenerations.first(where: { $0.status == .queued }),
              let job = queuedJobPayloads[nextItem.id] else {
            return
        }

        startQueuedGeneration(job)
    }

    private func startQueuedGeneration(_ job: GenerationJob) {
        let queue = jobQueue

        selectedSessionID = nil
        activeSessionID = nil
        activeJobID = job.id
        isGenerating = true
        elapsedSeconds = 0
        activeStartedAt = Date()
        statusMessage = "Starting queued generation"
        updateQueuedGeneration(id: job.id) { item in
            item.status = .running
            item.statusMessage = "Starting"
            item.startedAt = Date()
            item.elapsedSeconds = 0
        }
        backendStatus = backendStatus.replacingState(
            .runningJob,
            userMessage: "\(backendStatus.displayName) is generating audio.",
            recoverySuggestion: "You can cancel the running job from the toolbar."
        )
        generationTicker = .started(
            voice: job.voiceID,
            cfgScale: job.settings.cfgScale,
            ddpmInferenceSteps: job.settings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps
        )
        startElapsedTimer()

        activeTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let record = try await queue.submit(job) { event in
                    Task { @MainActor in
                        self?.handleGenerationEvent(event)
                    }
                }
                self?.completeGeneration(record: record)
            } catch {
                self?.failGenerationStart(error: error)
            }
        }
    }

    func cancelGeneration() {
        guard isGenerating, let activeJobID else { return }
        statusMessage = "Cancelling generation..."
        backendStatus = backendStatus.replacingState(
            .runningJob,
            userMessage: "Cancelling the current generation.",
            recoverySuggestion: "The partial session will stay in history."
        )
        let queue = jobQueue
        Task {
            await queue.cancel(jobID: activeJobID)
        }
    }

    func duplicateAsNew(_ record: SessionRecord) {
        editorText = record.inputText
        selectedVoice = record.metadata.voice
        cfgScale = record.metadata.cfgScale
        ddpmInferenceSteps = record.metadata.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps
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

    func revealOutputFile(_ record: SessionRecord) {
        guard let outputURL = record.outputURL else {
            statusMessage = "No WAV file for this session"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        statusMessage = "Revealed \(outputURL.lastPathComponent)"
    }

    func copyOutputPath(_ record: SessionRecord) {
        guard let outputURL = record.outputURL else {
            statusMessage = "No WAV file for this session"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputURL.path, forType: .string)
        statusMessage = "Copied output path"
    }

    func quickLookOutputFile(_ record: SessionRecord) {
        guard let outputURL = record.outputURL else {
            statusMessage = "No WAV file for this session"
            return
        }
        quickLookPreviewer.preview(outputURL)
        statusMessage = "Previewing \(outputURL.lastPathComponent)"
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

    private func handleGenerationEvent(_ event: GenerationEvent) {
        switch event {
        case .sessionStarted(let record):
            activeSessionID = record.id
            liveLogBySessionID[record.id] = ""
            if let activeJobID {
                updateQueuedGeneration(id: activeJobID) { item in
                    item.sessionID = record.id
                    item.status = .running
                    item.statusMessage = "Session created"
                }
            }
            refreshHistory()
            pendingScrollSessionID = record.id
            backendStatus = backendStatus.replacingState(
                .runningJob,
                userMessage: "\(backendStatus.displayName) is generating audio.",
                recoverySuggestion: "You can cancel the running job from the toolbar."
            )
        case .status(let message):
            statusMessage = message
            if let activeJobID {
                updateQueuedGeneration(id: activeJobID) { item in
                    item.statusMessage = message
                }
            }
        case .progress(let snapshot):
            updateQueuedGeneration(id: snapshot.jobID) { item in
                item.status = .running
                item.progressFraction = snapshot.fractionComplete
                item.currentStep = snapshot.currentStep
                item.totalSteps = snapshot.totalSteps
                item.estimatedRemainingSeconds = snapshot.estimatedRemainingSeconds
                item.elapsedSeconds = snapshot.elapsedSeconds ?? elapsedSeconds
                item.statusMessage = snapshot.message
            }
        case .log(let chunk):
            guard let activeSessionID else { return }
            appendLiveLog(chunk, sessionID: activeSessionID)
        case .output(let output):
            statusMessage = "Output ready: \(output.fileURL.lastPathComponent)"
        }
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

    private func completeGeneration(record: GenerationRecord) {
        let finalElapsed = record.completedAt?.timeIntervalSince(record.createdAt) ?? elapsedSeconds
        let completedJobID = activeJobID
        if activeSessionID == nil {
            activeSessionID = record.id
        }
        let sessionID = record.id
        isGenerating = false
        activeTask = nil
        activeJobID = nil
        activeSessionID = nil
        elapsedSeconds = finalElapsed
        if let completedJobID {
            queuedJobPayloads[completedJobID] = nil
            updateQueuedGeneration(id: completedJobID) { item in
                item.status = QueuedGenerationStatus(recordStatus: record.status)
                item.sessionID = record.id
                item.completedAt = record.completedAt ?? Date()
                item.elapsedSeconds = finalElapsed
                item.statusMessage = record.status.displayName
                item.errorMessage = record.error?.explanation
            }
        }
        let logText = liveLogBySessionID[sessionID, default: record.logs]
        generationTicker = generationTicker
            .ingesting(logText: logText, elapsed: finalElapsed)
            .finished(
                message: record.status.displayName,
                elapsed: finalElapsed,
                phase: record.status.tickerPhase
            )
        stopElapsedTimer()
        refreshHistory()
        pendingScrollSessionID = sessionID
        statusMessage = record.status.displayName
        if queuedGenerations.contains(where: { $0.status == .queued }) {
            startNextQueuedGenerationIfIdle()
        } else {
            refreshBackendStatus()
        }
    }

    private func failGenerationStart(error: Error) {
        let failedJobID = activeJobID
        isGenerating = false
        isPreparingGeneration = false
        activeTask = nil
        activeJobID = nil
        activeSessionID = nil
        let finalElapsed = elapsedSeconds
        if let failedJobID {
            updateQueuedGeneration(id: failedJobID) { item in
                item.status = .failed
                item.completedAt = Date()
                item.elapsedSeconds = finalElapsed
                item.statusMessage = "Failed"
                item.errorMessage = userFacingMessage(for: error)
            }
            queuedJobPayloads[failedJobID] = nil
        }
        stopElapsedTimer()
        generationTicker = generationTicker.finished(
            message: "Failed",
            elapsed: finalElapsed,
            phase: .failed
        )
        refreshHistory()
        alertMessage = userFacingMessage(for: error)
        statusMessage = "Failed"
        if queuedGenerations.contains(where: { $0.status == .queued }) {
            startNextQueuedGenerationIfIdle()
        } else {
            refreshBackendStatus()
        }
    }

    private func updateQueuedGeneration(id: String, mutate: (inout QueuedGenerationItem) -> Void) {
        guard let index = queuedGenerations.firstIndex(where: { $0.id == id }) else { return }
        mutate(&queuedGenerations[index])
    }

    private func userFacingMessage(for error: Error) -> String {
        if let backendError = error as? BackendError {
            switch backendError {
            case .backendUnavailable(let record),
                    .operationUnavailable(let record),
                    .generationFailed(let record):
                return [
                    record.title,
                    record.explanation,
                    record.recoverySuggestion
                ]
                .compactMap { $0 }
                .joined(separator: "\n\n")
            }
        }
        return "Could not start generation: \(error.localizedDescription)"
    }

    private func refreshBackendStatusNow() async -> BackendStatusSnapshot {
        isRefreshingBackendStatus = true
        defer { isRefreshingBackendStatus = false }
        let report = await backendAdapter.healthCheck()
        let snapshot = BackendStatusSnapshot(profile: backendAdapter.profile, report: report)
        backendStatus = snapshot
        statusMessage = snapshot.state == .ready ? "Backend ready" : snapshot.state.displayName
        return snapshot
    }

    private func presentBlockedBackend(_ status: BackendStatusSnapshot) {
        statusMessage = status.state.displayName
        alertMessage = status.alertMessage
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let activeStartedAt = self.activeStartedAt else { return }
                let elapsed = Date().timeIntervalSince(activeStartedAt)
                self.elapsedSeconds = elapsed
                if self.isGenerating {
                    self.generationTicker = self.generationTicker.ticking(elapsed: elapsed)
                    if let activeJobID = self.activeJobID {
                        self.updateQueuedGeneration(id: activeJobID) { item in
                            item.elapsedSeconds = elapsed
                        }
                    }
                }
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

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopWAVPlayback(status: flag ? "Playback finished" : "Playback stopped")
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.stopWAVPlayback(status: "Playback failed")
            if let error {
                self.alertMessage = "Could not play WAV: \(error.localizedDescription)"
            }
        }
    }
}

private extension GenerationRecordStatus {
    var tickerPhase: GenerationTickerState.Phase {
        switch self {
        case .completed: .completed
        case .failed: .failed
        case .cancelled: .cancelled
        case .running: .running
        case .queued: .running
        }
    }

    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

private extension QueuedGenerationStatus {
    init(recordStatus: GenerationRecordStatus) {
        switch recordStatus {
        case .queued:
            self = .queued
        case .running:
            self = .running
        case .completed:
            self = .completed
        case .failed:
            self = .failed
        case .cancelled:
            self = .cancelled
        }
    }
}

private extension BackendStatusSnapshot {
    var alertMessageWithDetails: String {
        [
            alertMessage,
            technicalDetails.map { "Details:\n\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }
}
