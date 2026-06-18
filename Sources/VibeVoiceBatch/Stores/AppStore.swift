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
    @Published private(set) var activeGenerationProgress: GenerationProgressSnapshot?
    @Published private(set) var activeSessionID: String?
    @Published var pendingScrollSessionID: String?
    @Published private(set) var generationTicker = GenerationTickerState.idle
    @Published private(set) var isPlayingWAV = false
    @Published private(set) var playingSessionID: String?
    @Published private(set) var playbackElapsedSeconds: TimeInterval = 0
    @Published private(set) var playbackDurationSeconds: TimeInterval = 0
    @Published private(set) var backendStatus = BackendStatusSnapshot.unknown(profile: BackendProfiles.vibeVoiceTTS)
    @Published private(set) var isRefreshingBackendStatus = false
    @Published private(set) var activeBackendOperation: BackendOperationKind?
    @Published private(set) var isPreparingGeneration = false
    @Published private(set) var queuedGenerations: [QueuedGenerationItem] = []
    @Published var selectedQueueItemID: String?
    @Published var selectedOutputSessionIDs: Set<String> = []
    @Published var statusMessage = "Ready"
    @Published var alertMessage: String?
    @Published private(set) var latestGenerationLogLine = "Ready"
    @Published private(set) var estimatedGenerationProgressFraction: Double?
    @Published private(set) var estimatedGenerationRemainingSeconds: TimeInterval?
    @Published private(set) var generationPhaseName = "idle"
    @Published private(set) var requestedSelection: WorkstationSelection?
    @Published private var liveLogBySessionID: [String: String] = [:]

    private let settingsStore: SettingsStore
    private let fileStore = SessionFileStore()
    private let quickLookPreviewer = QuickLookPreviewer()
    private let backendManager = BackendManager()
    private let vibeVoiceAdapter: VibeVoiceDockerAdapter
    private let kokoroAdapter: KokoroHTTPAdapter
    private lazy var jobQueue = JobQueue(adapters: [vibeVoiceAdapter, kokoroAdapter])
    private var activeTask: Task<Void, Never>?
    private var activeJobID: String?
    private var queuedJobPayloads: [String: GenerationJob] = [:]
    private var elapsedTimer: Timer?
    private var activeStartedAt: Date?
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        vibeVoiceAdapter = VibeVoiceDockerAdapter()
        kokoroAdapter = KokoroHTTPAdapter()
        super.init()
        selectedVoice = settingsStore.settings.defaultVoice
        cfgScale = settingsStore.settings.defaultCFGScale
        ddpmInferenceSteps = settingsStore.settings.defaultDDPMInferenceSteps
        backendStatus = BackendStatusSnapshot.unknown(profile: selectedBackendProfile)
    }

    var selectedSession: SessionRecord? {
        guard let selectedSessionID else { return nil }
        return session(id: selectedSessionID)
    }

    func session(id: String) -> SessionRecord? {
        sessions.first { $0.id == id }
    }

    var outputSessions: [SessionRecord] {
        sessions.filter { $0.outputURL != nil }
    }

    var selectedOutputSessions: [SessionRecord] {
        outputSessions.filter { selectedOutputSessionIDs.contains($0.id) }
    }

    var selectedBackendProfile: BackendProfile {
        settingsStore.selectedBackendProfile
    }

    var selectedModelID: String {
        let profile = selectedBackendProfile
        if settingsStore.modelOptions(for: profile).contains(where: { $0.id == settingsStore.settings.defaultModelID }) {
            return settingsStore.settings.defaultModelID
        }
        return settingsStore.modelOptions(for: profile).first?.id ?? settingsStore.settings.defaultModelID
    }

    var availableVoiceOptions: [BackendCatalogVoice] {
        settingsStore.voiceOptions(for: selectedBackendProfile)
    }

    var availableModelOptions: [BackendCatalogModel] {
        settingsStore.modelOptions(for: selectedBackendProfile)
    }

    var canGenerate: Bool {
        !isPreparingGeneration &&
            backendStatus.profileID == selectedBackendProfile.id &&
            (isGenerating || backendStatus.canStartGeneration) &&
            selectedBackendHasGenerationAdapter &&
            !editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSaveDraft: Bool {
        !isGenerating && !editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var playbackProgressFraction: Double? {
        guard playbackDurationSeconds > 0 else { return nil }
        return min(1, max(0, playbackElapsedSeconds / playbackDurationSeconds))
    }

    func refreshHistory() {
        do {
            sessions = try fileStore.loadSessions()
            let validOutputIDs = Set(outputSessions.map(\.id))
            selectedOutputSessionIDs = selectedOutputSessionIDs.intersection(validOutputIDs)
        } catch {
            alertMessage = "Could not load history: \(error.localizedDescription)"
        }
    }

    func revealGenerationRecord(_ record: GenerationRecord, status: String = "Generation complete") {
        refreshHistory()
        selectedSessionID = record.id
        pendingScrollSessionID = record.id
        requestedSelection = .section(.history)
        statusMessage = status
    }

    func playGenerationRecord(_ record: GenerationRecord) {
        refreshHistory()
        if let session = session(id: record.id) {
            playWAV(session)
            return
        }

        guard let exportPath = record.exportPath else {
            statusMessage = "No test WAV available"
            return
        }
        playOutputURL(URL(fileURLWithPath: exportPath), sessionID: record.id)
    }

    func revealGenerationRecordOutput(_ record: GenerationRecord) {
        refreshHistory()
        if let session = session(id: record.id) {
            revealOutputFile(session)
            return
        }

        guard let exportPath = record.exportPath else {
            statusMessage = "No test WAV available"
            return
        }
        let outputURL = URL(fileURLWithPath: exportPath)
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        statusMessage = "Revealed \(outputURL.lastPathComponent)"
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

    func performBackendOperation(_ kind: BackendOperationKind) {
        guard activeBackendOperation == nil, !isGenerating else { return }
        activeBackendOperation = kind
        statusMessage = "\(kind.displayName) is running."
        let profile = selectedBackendProfile
        Task {
            let result = await backendManager.performOperationAsync(kind, for: profile)
            await MainActor.run {
                activeBackendOperation = nil
                statusMessage = result.message
                if result.status == .failed {
                    alertMessage = [
                        result.message,
                        result.recoverySuggestion,
                        result.technicalDetails
                    ]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
                }
                refreshBackendStatus()
            }
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
        requestedSelection = .section(.history)
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

        elapsedSeconds = 0
        activeStartedAt = Date()
        startElapsedTimer()
        estimatedGenerationProgressFraction = nil
        estimatedGenerationRemainingSeconds = nil
        generationPhaseName = "checking backend"
        isPreparingGeneration = true
        statusMessage = "Checking backend..."
        setLatestGenerationLogLine("Checking backend")
        Task {
            let status = await refreshBackendStatusNow()
            guard status.canStartGeneration else {
                isPreparingGeneration = false
                stopElapsedTimer()
                presentBlockedBackend(status)
                return
            }
            guard selectedBackendHasGenerationAdapter else {
                isPreparingGeneration = false
                stopElapsedTimer()
                presentBackendNeedsGenerationAdapter(selectedBackendProfile)
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
        requestedSelection = .section(.history)
    }

    func applyVoicePreset(_ preset: NarrationVoicePreset) {
        selectedVoice = preset.voiceID
        settingsStore.update {
            $0.defaultBackendID = preset.backendID
            $0.defaultModelID = preset.modelID
            $0.defaultVoice = preset.voiceID
        }
        statusMessage = "Applied voice preset: \(preset.displayName)"
    }

    func applyGenerationPreset(_ preset: NarrationGenerationPreset) {
        if let voiceID = preset.voiceID {
            selectedVoice = voiceID
        }
        cfgScale = preset.settings.cfgScale
        ddpmInferenceSteps = preset.settings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps
        settingsStore.update {
            $0.defaultBackendID = preset.backendID
            $0.defaultModelID = preset.modelID
            if let voiceID = preset.voiceID {
                $0.defaultVoice = voiceID
            }
            $0.defaultCFGScale = preset.settings.cfgScale
            $0.defaultDDPMInferenceSteps = preset.settings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps
            $0.exportFormat = preset.outputFormat
        }
        statusMessage = "Applied generation preset: \(preset.displayName)"
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

    func selectBackend(_ backendID: String) {
        settingsStore.update {
            $0.defaultBackendID = backendID
            let profile = $0.backendProfile(id: backendID)
            let catalog = $0.backendCatalog(for: backendID)
            $0.defaultModelID = catalog?.models.first?.id ?? profile.requiredModels.first?.id ?? $0.defaultModelID
            if profile.engineType == .kokoro {
                $0.defaultVoice = catalog?.voices.first?.id ?? $0.backendConnection(for: backendID).trimmedDefaultVoice ?? $0.defaultVoice
            }
            if !profile.outputFormatSupport.contains($0.exportFormat) {
                $0.exportFormat = profile.outputFormatSupport.first ?? .wav
            }
        }
        selectedVoice = settingsStore.settings.defaultVoice
        backendStatus = BackendStatusSnapshot.unknown(profile: selectedBackendProfile)
        refreshBackendStatus()
    }

    private func enqueueGeneration(
        text: String,
        voice: String,
        cfgScale: String,
        ddpmInferenceSteps: Int
    ) {
        let job = GenerationJob(
            inputText: text,
            backendID: selectedBackendProfile.id,
            modelID: selectedModelID,
            voiceID: voice,
            settings: GenerationSettings(
                cfgScale: cfgScale,
                ddpmInferenceSteps: ddpmInferenceSteps,
                extraParameters: selectedBackendProfile.generationExtraParameters
            )
        )
        queuedJobPayloads[job.id] = job
        queuedGenerations.append(QueuedGenerationItem(job: job))
        selectedQueueItemID = job.id
        selectedSessionID = nil
        hasUnsavedEditorText = false
        statusMessage = isGenerating ? "Queued for generation" : "Queued"
        setLatestGenerationLogLine(statusMessage)
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
        if activeStartedAt == nil {
            elapsedSeconds = 0
            activeStartedAt = Date()
        }
        activeGenerationProgress = nil
        estimatedGenerationProgressFraction = nil
        estimatedGenerationRemainingSeconds = nil
        generationPhaseName = "starting"
        activeStartedAt = Date()
        statusMessage = "Starting queued generation"
        setLatestGenerationLogLine("Starting queued generation")
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
        setLatestGenerationLogLine("Cancelling generation")
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
        requestedSelection = .section(.history)
    }

    func archiveDeleteSession(_ record: SessionRecord) {
        do {
            let destination = try fileStore.archiveDeletedSession(record)
            if selectedSessionID == record.id {
                selectedSessionID = nil
            }
            selectedOutputSessionIDs.remove(record.id)
            refreshHistory()
            statusMessage = "Archived \(record.id) to \(archiveRecoveryLocation(destination)). Recover it by moving that folder back into history."
        } catch {
            alertMessage = "Could not archive session. No session files were deleted.\n\n\(error.localizedDescription)"
        }
    }

    func archiveOutputSessions(_ records: [SessionRecord]) {
        let archiveTargets = records.isEmpty ? selectedOutputSessions : records
        guard !archiveTargets.isEmpty else {
            statusMessage = "No outputs selected"
            return
        }

        var archivedCount = 0
        var failures: [String] = []
        for record in archiveTargets {
            do {
                _ = try fileStore.archiveDeletedSession(record)
                selectedOutputSessionIDs.remove(record.id)
                if selectedSessionID == record.id {
                    selectedSessionID = nil
                }
                archivedCount += 1
            } catch {
                failures.append("\(record.id): \(error.localizedDescription)")
            }
        }

        refreshHistory()
        if failures.isEmpty {
            statusMessage = "Archived \(archivedCount) output\(archivedCount == 1 ? "" : "s") to recovered/deleted_sessions. Recover by moving session folders back into history."
        } else {
            alertMessage = "Archived \(archivedCount) output\(archivedCount == 1 ? "" : "s"), but \(failures.count) could not be archived. Files that failed to archive were left in place.\n\n\(failures.joined(separator: "\n"))"
        }
    }

    private func archiveRecoveryLocation(_ destination: URL) -> String {
        "recovered/deleted_sessions/\(destination.lastPathComponent)"
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

    func revealSelectedOutputFile() {
        guard let record = selectedOutputSessions.first ?? selectedSession else {
            statusMessage = "No output selected"
            return
        }
        revealOutputFile(record)
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

    func copySelectedOutputPaths() {
        let paths = selectedOutputSessions.compactMap { $0.outputURL?.path }
        guard !paths.isEmpty else {
            statusMessage = "No output paths selected"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        statusMessage = "Copied \(paths.count) output path\(paths.count == 1 ? "" : "s")"
    }

    func quickLookOutputFile(_ record: SessionRecord) {
        guard let outputURL = record.outputURL else {
            statusMessage = "No WAV file for this session"
            return
        }
        quickLookPreviewer.preview(outputURL)
        statusMessage = "Previewing \(outputURL.lastPathComponent)"
    }

    func quickLookSelectedOutputFile() {
        guard let record = selectedOutputSessions.first ?? selectedSession else {
            statusMessage = "No output selected"
            return
        }
        quickLookOutputFile(record)
    }

    func shareSelectedOutputFiles() {
        let urls = selectedOutputSessions.compactMap(\.outputURL)
        guard !urls.isEmpty else {
            statusMessage = "No output selected"
            return
        }

        guard let contentView = NSApp.keyWindow?.contentView else {
            copySelectedOutputPaths()
            return
        }

        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        statusMessage = "Sharing \(urls.count) output\(urls.count == 1 ? "" : "s")"
    }

    func playWAV(_ record: SessionRecord) {
        if isPlaying(record) {
            stopWAVPlayback(status: "Stopped playback")
            return
        }

        guard let outputURL = record.outputURL else { return }
        playOutputURL(outputURL, sessionID: record.id)
    }

    private func playOutputURL(_ outputURL: URL, sessionID: String) {
        do {
            if isPlayingWAV {
                stopWAVPlayback()
            }
            let player = try AVAudioPlayer(contentsOf: outputURL)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            playingSessionID = sessionID
            playbackElapsedSeconds = player.currentTime
            playbackDurationSeconds = player.duration
            isPlayingWAV = true
            startPlaybackTimer()
            statusMessage = "Playing \(sessionID)"
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

    func clearRequestedSelection() {
        requestedSelection = nil
    }

    private func handleGenerationEvent(_ event: GenerationEvent) {
        switch event {
        case .sessionStarted(let record):
            activeSessionID = record.id
            liveLogBySessionID[record.id] = ""
            setLatestGenerationLogLine("Session created: \(record.id)")
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
            setLatestGenerationLogLine(message)
            if let activeJobID {
                updateQueuedGeneration(id: activeJobID) { item in
                    item.statusMessage = message
                }
            }
        case .progress(let snapshot):
            activeGenerationProgress = snapshot
            if let fraction = snapshot.fractionComplete {
                estimatedGenerationProgressFraction = fraction
            }
            if let remaining = snapshot.estimatedRemainingSeconds {
                estimatedGenerationRemainingSeconds = remaining
            }
            if let elapsed = snapshot.elapsedSeconds {
                elapsedSeconds = max(elapsedSeconds, elapsed)
            }
            generationPhaseName = snapshot.message
            setLatestGenerationLogLine(snapshot.message)
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
            setLatestGenerationLogLine("Output ready: \(output.fileURL.lastPathComponent)")
        }
    }

    private func appendLiveLog(_ chunk: String, sessionID: String) {
        liveLogBySessionID[sessionID, default: ""] += chunk
        if sessionID == activeSessionID {
            if let latestLine = latestTerminalLine(from: liveLogBySessionID[sessionID, default: ""]) {
                setLatestGenerationLogLine(latestLine)
            }
            generationTicker = generationTicker.ingesting(
                logText: liveLogBySessionID[sessionID, default: ""],
                elapsed: elapsedSeconds
            )
        }
        if sessionID == selectedSessionID {
            objectWillChange.send()
        }
    }

    private func setLatestGenerationLogLine(_ line: String) {
        latestGenerationLogLine = line
        updateEstimatedGenerationProgress(from: line)
    }

    private func updateEstimatedGenerationProgress(from line: String) {
        if let estimate = GenerationOutputParser.latestEstimatedProgress(in: line) {
            let phaseName = estimate.displayPhase
            generationPhaseName = phaseName
            estimatedGenerationProgressFraction = estimate.fraction
            if let elapsed = estimate.elapsedSeconds {
                elapsedSeconds = max(elapsedSeconds, elapsed)
            }
            if let elapsed = estimate.elapsedSeconds,
               let estimated = estimate.estimatedSeconds,
               estimated > elapsed {
                estimatedGenerationRemainingSeconds = estimated - elapsed
            } else {
                estimatedGenerationRemainingSeconds = nil
            }
            if let activeJobID {
                updateQueuedGeneration(id: activeJobID) { item in
                    item.status = .running
                    item.progressFraction = estimate.fraction
                    item.elapsedSeconds = estimate.elapsedSeconds ?? item.elapsedSeconds
                    item.estimatedRemainingSeconds = estimatedGenerationRemainingSeconds
                    item.statusMessage = phaseName.capitalized
                }
            }
            return
        }

        if let progress = GenerationOutputParser.latestProgress(in: line) {
            generationPhaseName = "Current Step"
            estimatedGenerationProgressFraction = progress.fraction
            let elapsed = progress.reportedElapsedSeconds ?? elapsedSeconds
            if let reportedElapsed = progress.reportedElapsedSeconds {
                elapsedSeconds = max(elapsedSeconds, reportedElapsed)
            }
            estimatedGenerationRemainingSeconds = progress.estimatedRemainingSeconds(elapsedSeconds: elapsed)
            if let activeJobID {
                updateQueuedGeneration(id: activeJobID) { item in
                    item.status = .running
                    item.progressFraction = progress.fraction
                    item.currentStep = progress.currentStep
                    item.totalSteps = progress.maxSteps
                    item.elapsedSeconds = elapsed
                    item.estimatedRemainingSeconds = estimatedGenerationRemainingSeconds
                    item.statusMessage = "Current Step"
                }
            }
            return
        }

        generationPhaseName = generationPhaseName(for: line)
    }

    private func generationPhaseName(for line: String) -> String {
        let normalized = line.lowercased()
        if normalized.contains("checking backend") { return "Checking Backend" }
        if normalized.contains("queued") { return "Queued" }
        if normalized.contains("session created") { return "Session Created" }
        if normalized.contains("staged input") { return "Staging Input" }
        if normalized.contains("starting generation") { return "Starting Backend" }
        if normalized.contains("using device:") { return "Device Ready" }
        if normalized.contains("found ") && normalized.contains("voice files") { return "Voices Loaded" }
        if normalized.contains("reading script") { return "Reading Script" }
        if normalized.contains("loading processor") { return "Loading Processor" }
        if normalized.contains("loading file") { return "Loading Tokenizer" }
        if normalized.contains("loading configuration") { return "Loading Config" }
        if normalized.contains("model config") { return "Model Config" }
        if normalized.contains("loading weights file") { return "Loading Weights" }
        if normalized.contains("instantiating") { return "Instantiating Model" }
        if normalized.contains("all model checkpoint weights") { return "Weights Loaded" }
        if normalized.contains("some weights") { return "Model Initialized" }
        if normalized.contains("ddpm inference steps") { return "Diffusion Ready" }
        if normalized.contains("language model attention") { return "Attention Ready" }
        if normalized.contains("using voice preset") { return "Voice Loaded" }
        if normalized.contains("generation time") { return "Finalizing" }
        if normalized.contains("saved output") || normalized.contains("output ready") { return "Output Ready" }
        if normalized.contains("completed") { return "Completed" }
        if normalized.contains("failed") { return "Failed" }
        if normalized.contains("cancel") { return "Cancelled" }
        return line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Working" : String(line.prefix(40))
    }

    private func latestTerminalLine(from text: String) -> String? {
        let cleaned = removingANSIEscapeSequences(from: text)
        let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
        guard let line = parts
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .last(where: { !$0.isEmpty }) else {
            return nil
        }
        return String(line.prefix(220))
    }

    private func removingANSIEscapeSequences(from text: String) -> String {
        var output = String.UnicodeScalarView()
        var iterator = text.unicodeScalars.makeIterator()

        while let scalar = iterator.next() {
            if scalar.value == 0x1B {
                while let next = iterator.next() {
                    if next.value >= 0x40, next.value <= 0x7E {
                        break
                    }
                }
                continue
            }

            if scalar.value == 0x09 ||
                scalar.value == 0x0A ||
                scalar.value == 0x0D ||
                scalar.value >= 0x20 {
                output.append(scalar)
            }
        }

        return String(output)
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
        activeGenerationProgress = nil
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
        estimatedGenerationProgressFraction = record.status == .completed ? 1 : estimatedGenerationProgressFraction
        estimatedGenerationRemainingSeconds = nil
        generationPhaseName = record.status.displayName.lowercased()
        setLatestGenerationLogLine(record.status.displayName)
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
        activeGenerationProgress = nil
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
        estimatedGenerationRemainingSeconds = nil
        generationPhaseName = "failed"
        setLatestGenerationLogLine("Failed")
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
        AppErrorPresenter.message(for: error, fallbackTitle: "Could not start generation")
    }

    private func refreshBackendStatusNow() async -> BackendStatusSnapshot {
        isRefreshingBackendStatus = true
        defer { isRefreshingBackendStatus = false }
        let profile = selectedBackendProfile
        let report: BackendHealthReport
        if profile.id == BackendProfiles.vibeVoiceTTS.id,
           let adapter = adapter(for: profile.id) {
            report = await adapter.healthCheck()
        } else if BackendProfiles.baseProfile(id: profile.id) != nil {
            report = await backendManager.healthReportAsync(for: profile)
        } else {
            report = BackendHealthReport(
                profileID: profile.id,
                state: .unknown,
                userMessage: "\(profile.displayName) is registered, but no engine adapter is available.",
                recoverySuggestion: "Choose an installed backend before generating."
            )
        }
        let snapshot = BackendStatusSnapshot(profile: profile, report: report)
        backendStatus = snapshot
        statusMessage = snapshot.state == .ready ? "Backend ready" : snapshot.state.displayName
        return snapshot
    }

    private var selectedBackendHasGenerationAdapter: Bool {
        selectedBackendProfile.id == BackendProfiles.vibeVoiceTTS.id ||
            selectedBackendProfile.id == BackendProfiles.kokoroTTS.id
    }

    private func adapter(for backendID: String) -> (any EngineAdapter)? {
        if vibeVoiceAdapter.profile.id == backendID {
            return vibeVoiceAdapter
        }
        if kokoroAdapter.profile.id == backendID {
            return kokoroAdapter
        }
        return nil
    }

    private func presentBlockedBackend(_ status: BackendStatusSnapshot) {
        statusMessage = status.state.displayName
        alertMessage = status.alertMessage
    }

    private func presentBackendNeedsGenerationAdapter(_ profile: BackendProfile) {
        statusMessage = "Adapter needed"
        alertMessage = [
            "\(profile.displayName) setup can be checked now, but generation is not connected yet.",
            "Next we need the running image or service contract: image name, launch command or port, voices endpoint, generation endpoint, and output format behavior."
        ].joined(separator: "\n\n")
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        if activeStartedAt == nil {
            activeStartedAt = Date()
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let activeStartedAt = self.activeStartedAt else { return }
                let previousElapsed = self.elapsedSeconds
                let elapsed = max(previousElapsed, Date().timeIntervalSince(activeStartedAt))
                self.elapsedSeconds = elapsed
                if let remaining = self.estimatedGenerationRemainingSeconds {
                    let delta = max(0, elapsed - previousElapsed)
                    self.estimatedGenerationRemainingSeconds = max(0, remaining - delta)
                }
                if self.isGenerating || self.isPreparingGeneration {
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

    private func startPlaybackTimer() {
        stopPlaybackTimer(reset: false)
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let audioPlayer = self.audioPlayer else { return }
                self.playbackElapsedSeconds = audioPlayer.currentTime
                self.playbackDurationSeconds = audioPlayer.duration
            }
        }
        playbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPlaybackTimer(reset: Bool) {
        playbackTimer?.invalidate()
        playbackTimer = nil
        if reset {
            playbackElapsedSeconds = 0
            playbackDurationSeconds = 0
        }
    }

    private func stopWAVPlayback(status: String? = nil) {
        audioPlayer?.stop()
        audioPlayer = nil
        playingSessionID = nil
        isPlayingWAV = false
        stopPlaybackTimer(reset: true)
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
