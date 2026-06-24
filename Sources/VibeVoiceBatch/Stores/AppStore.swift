import Foundation
import VibeVoiceBatchCore

@MainActor
final class AppStore: ObservableObject {
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
    @Published var queuedGenerations: [QueuedGenerationItem] = []
    @Published private(set) var isQueuePaused = false
    @Published var selectedQueueItemID: String?
    @Published var selectedOutputSessionIDs: Set<String> = []
    @Published var statusMessage = "Ready"
    @Published var alertMessage: String?
    @Published private(set) var latestGenerationLogLine = "Ready"
    @Published private(set) var estimatedGenerationProgressFraction: Double?
    @Published private(set) var estimatedGenerationRemainingSeconds: TimeInterval?
    @Published private(set) var generationPhaseName = "idle"
    @Published private(set) var requestedSelection: WorkstationSelection?

    private let settingsStore: SettingsStore
    private let fileStore: SessionFileStore
    private let playbackCoordinator: AppAudioPlaybackCoordinator
    private let outputActionCoordinator: AppOutputActionCoordinator
    private let backendStatusCoordinator: AppBackendStatusCoordinator
    private let generationQueueCoordinator: AppGenerationQueueCoordinator
    private let progressCoordinator = AppGenerationProgressCoordinator()
    private var activeTask: Task<Void, Never>?
    private var activeJobID: String?
    private var elapsedTimer: Timer?
    private var activeStartedAt: Date?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        let fileStore = SessionFileStore()
        let quickLookPreviewer = QuickLookPreviewer()
        let playbackCoordinator = AppAudioPlaybackCoordinator()
        let adapters: [any EngineAdapter] = [
            VibeVoiceDockerAdapter(),
            KokoroHTTPAdapter(),
            ChatterboxHTTPAdapter()
        ]

        self.fileStore = fileStore
        self.playbackCoordinator = playbackCoordinator
        outputActionCoordinator = AppOutputActionCoordinator(
            fileStore: fileStore,
            quickLookPreviewer: quickLookPreviewer
        )
        backendStatusCoordinator = AppBackendStatusCoordinator(adapters: adapters)
        generationQueueCoordinator = AppGenerationQueueCoordinator(adapters: adapters)

        selectedVoice = settingsStore.settings.preferredVoiceID(for: settingsStore.selectedBackendProfile)
        cfgScale = settingsStore.settings.defaultCFGScale
        ddpmInferenceSteps = settingsStore.settings.defaultDDPMInferenceSteps
        backendStatus = BackendStatusSnapshot.unknown(profile: selectedBackendProfile)
        playbackCoordinator.onStateChange = { [weak self] state in
            self?.applyPlaybackState(state)
        }
        playbackCoordinator.onStatus = { [weak self] message in
            self?.statusMessage = message
        }
        playbackCoordinator.onError = { [weak self] message in
            self?.alertMessage = message
        }
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
        settingsStore.generationVoiceOptions(for: selectedBackendProfile)
    }

    var selectedVoiceIsAvailable: Bool {
        availableVoiceOptions.contains { $0.id == selectedVoice }
    }

    func voiceOptions(for profile: BackendProfile) -> [BackendCatalogVoice] {
        settingsStore.voiceOptions(for: profile)
    }

    var availableModelOptions: [BackendCatalogModel] {
        settingsStore.modelOptions(for: selectedBackendProfile)
    }

    var canGenerate: Bool {
        !isPreparingGeneration &&
            backendStatus.profileID == selectedBackendProfile.id &&
            (isGenerating || backendStatus.canStartGeneration) &&
            selectedBackendHasGenerationAdapter &&
            selectedVoiceIsAvailable &&
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
        statusMessage = outputActionCoordinator.revealOutputURL(outputURL)
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
            let result = await backendStatusCoordinator.performOperation(kind, for: profile)
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
            progressCoordinator.resetToIdle()
            syncGenerationProgressState()
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
        isPreparingGeneration = true
        statusMessage = "Checking backend..."
        progressCoordinator.prepareForBackendCheck()
        syncGenerationProgressState()
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
        case .queued, .paused:
            generationQueueCoordinator.cancelQueuedPayload(id: item.id)
            updateQueuedGeneration(id: item.id) { queuedItem in
                queuedItem.status = .cancelled
                queuedItem.statusMessage = item.status == .paused ? "Cancelled while paused" : "Cancelled before start"
                queuedItem.completedAt = Date()
            }
            statusMessage = item.status == .paused ? "Cancelled paused generation" : "Cancelled queued generation"
        case .completed, .failed, .cancelled:
            break
        }
    }

    func pauseGenerationQueue() {
        guard generationQueueCoordinator.pauseQueuedItems(&queuedGenerations) else { return }
        isQueuePaused = true
        statusMessage = "Queue paused"
    }

    func resumeGenerationQueue() {
        guard isQueuePaused || queuedGenerations.contains(where: { $0.status == .paused }) else { return }
        isQueuePaused = false
        _ = generationQueueCoordinator.resumePausedItems(&queuedGenerations)
        statusMessage = "Queue resumed"
        startNextQueuedGenerationIfIdle()
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
            $0.rememberVoice(preset.voiceID, for: preset.backendID)
        }
        backendStatus = BackendStatusSnapshot.unknown(profile: selectedBackendProfile)
        refreshBackendStatus()
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
                $0.rememberVoice(voiceID, for: preset.backendID)
            }
            $0.defaultCFGScale = preset.settings.cfgScale
            $0.defaultDDPMInferenceSteps = preset.settings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps
            $0.exportFormat = preset.outputFormat
            $0.applyGenerationExtraParameters(preset.settings.extraParameters, for: $0.backendProfile(id: preset.backendID))
        }
        backendStatus = BackendStatusSnapshot.unknown(profile: selectedBackendProfile)
        refreshBackendStatus()
        statusMessage = "Applied generation preset: \(preset.displayName)"
    }

    func showBackendDetails() {
        alertMessage = backendStatus.alertMessageWithDetails
    }

    func applyDefaultGenerationSettings() {
        selectedVoice = settingsStore.settings.preferredVoiceID(for: selectedBackendProfile)
        cfgScale = settingsStore.settings.defaultCFGScale
        ddpmInferenceSteps = settingsStore.settings.defaultDDPMInferenceSteps
        statusMessage = "Applied default generation settings"
    }

    func selectVoice(_ voiceID: String) {
        selectedVoice = voiceID
        settingsStore.update {
            $0.defaultVoice = voiceID
            $0.rememberVoice(voiceID, for: selectedBackendProfile.id)
        }
        statusMessage = "Selected voice: \(voiceID)"
    }

    func selectBackend(_ backendID: String) {
        let previousBackendID = settingsStore.settings.defaultBackendID
        let previousVoice = selectedVoice
        settingsStore.update {
            $0.rememberVoice(previousVoice, for: previousBackendID)
            $0.defaultBackendID = backendID
            let profile = $0.backendProfile(id: backendID)
            let catalog = $0.backendCatalog(for: backendID)
            $0.defaultModelID = catalog?.models.first(where: { $0.isLoaded == true })?.id ??
                catalog?.models.first?.id ??
                profile.requiredModels.first?.id ??
                $0.defaultModelID
            let voice = $0.preferredVoiceID(for: profile)
            $0.defaultVoice = voice
            $0.rememberVoice(voice, for: backendID)
            if !profile.outputFormatSupport.contains($0.exportFormat) {
                $0.exportFormat = profile.outputFormatSupport.first ?? .wav
            }
        }
        selectedVoice = settingsStore.settings.preferredVoiceID(for: selectedBackendProfile)
        backendStatus = BackendStatusSnapshot.unknown(profile: selectedBackendProfile)
        refreshBackendStatus()
    }

    func loadVoiceSample(voiceID: String, backendID: String) {
        if backendID != selectedBackendProfile.id {
            selectBackend(backendID)
        }
        selectVoice(voiceID)
        updateEditorText(VoiceSampleText.sample(for: selectedBackendProfile, voiceID: voiceID))
        requestedSelection = .section(.history)
        statusMessage = "Loaded sample text for \(voiceID)"
    }

    func generateVoiceSample(voiceID: String, backendID: String) {
        loadVoiceSample(voiceID: voiceID, backendID: backendID)
        generate()
    }

    func enqueueGeneration(
        text: String,
        voice: String,
        cfgScale: String,
        ddpmInferenceSteps: Int,
        backendID: String? = nil,
        modelID: String? = nil,
        scriptID: String? = nil,
        batchID: String? = nil,
        batchItemID: String? = nil
    ) {
        let backendProfile = backendID.map { settingsStore.backendProfile(id: $0) } ?? selectedBackendProfile
        let enqueued = generationQueueCoordinator.enqueue(
            text: text,
            backendID: backendProfile.id,
            modelID: modelID ?? selectedModelID,
            voice: voice,
            cfgScale: cfgScale,
            ddpmInferenceSteps: ddpmInferenceSteps,
            extraParameters: settingsStore.settings.generationExtraParameters(for: backendProfile),
            scriptID: scriptID,
            batchID: batchID,
            batchItemID: batchItemID
        )
        let job = enqueued.job
        queuedGenerations.append(isQueuePaused ? generationQueueCoordinator.pausedItem(from: enqueued.item) : enqueued.item)
        selectedQueueItemID = job.id
        selectedSessionID = nil
        hasUnsavedEditorText = false
        statusMessage = isQueuePaused ? "Queued while paused" : (isGenerating ? "Queued for generation" : "Queued")
        setLatestGenerationLogLine(statusMessage)
        startNextQueuedGenerationIfIdle()
    }

    private func startNextQueuedGenerationIfIdle() {
        guard !isQueuePaused else { return }
        guard !isGenerating else { return }
        guard let job = generationQueueCoordinator.nextQueuedJob(from: queuedGenerations) else {
            return
        }

        startQueuedGeneration(job)
    }

    private func startQueuedGeneration(_ job: GenerationJob) {
        let queue = generationQueueCoordinator

        selectedSessionID = nil
        activeSessionID = nil
        activeJobID = job.id
        isGenerating = true
        if activeStartedAt == nil {
            elapsedSeconds = 0
            activeStartedAt = Date()
        }
        activeGenerationProgress = nil
        activeStartedAt = Date()
        statusMessage = "Starting queued generation"
        progressCoordinator.startGeneration(
            voice: job.voiceID,
            cfgScale: job.settings.cfgScale,
            ddpmInferenceSteps: job.settings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps
        )
        syncGenerationProgressState()
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
        let queue = generationQueueCoordinator
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
            let destination = try outputActionCoordinator.archiveDeletedSession(record)
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

        let summary = outputActionCoordinator.archiveDeletedSessions(archiveTargets)
        for archivedID in summary.archivedIDs {
            selectedOutputSessionIDs.remove(archivedID)
            if selectedSessionID == archivedID {
                selectedSessionID = nil
            }
        }

        refreshHistory()
        if summary.failures.isEmpty {
            statusMessage = "Archived \(summary.archivedCount) output\(summary.archivedCount == 1 ? "" : "s") to recovered/deleted_sessions. Recover by moving session folders back into history."
        } else {
            alertMessage = "Archived \(summary.archivedCount) output\(summary.archivedCount == 1 ? "" : "s"), but \(summary.failures.count) could not be archived. Files that failed to archive were left in place.\n\n\(summary.failures.joined(separator: "\n"))"
        }
    }

    private func archiveRecoveryLocation(_ destination: URL) -> String {
        "recovered/deleted_sessions/\(destination.lastPathComponent)"
    }

    func openSessionFolder(_ record: SessionRecord) {
        outputActionCoordinator.openSessionFolder(record)
    }

    func revealOutputFile(_ record: SessionRecord) {
        statusMessage = outputActionCoordinator.revealOutputFile(record)
    }

    func revealSelectedOutputFile() {
        guard let record = selectedOutputSessions.first ?? selectedSession else {
            statusMessage = "No output selected"
            return
        }
        revealOutputFile(record)
    }

    func copyOutputPath(_ record: SessionRecord) {
        statusMessage = outputActionCoordinator.copyOutputPath(record)
    }

    func copySelectedOutputPaths() {
        statusMessage = outputActionCoordinator.copyOutputPaths(selectedOutputSessions)
    }

    func quickLookOutputFile(_ record: SessionRecord) {
        statusMessage = outputActionCoordinator.quickLookOutputFile(record)
    }

    func quickLookSelectedOutputFile() {
        guard let record = selectedOutputSessions.first ?? selectedSession else {
            statusMessage = "No output selected"
            return
        }
        quickLookOutputFile(record)
    }

    func shareSelectedOutputFiles() {
        guard !selectedOutputSessions.isEmpty else {
            statusMessage = "No output selected"
            return
        }

        guard outputActionCoordinator.shareOutputFiles(selectedOutputSessions) else {
            copySelectedOutputPaths()
            return
        }

        statusMessage = "Sharing \(selectedOutputSessions.count) output\(selectedOutputSessions.count == 1 ? "" : "s")"
    }

    func playWAV(_ record: SessionRecord) {
        if isPlaying(record) {
            playbackCoordinator.stop(status: "Stopped playback")
            return
        }

        guard let outputURL = record.outputURL else { return }
        playOutputURL(outputURL, sessionID: record.id)
    }

    private func playOutputURL(_ outputURL: URL, sessionID: String) {
        playbackCoordinator.play(outputURL: outputURL, sessionID: sessionID)
    }

    func isPlaying(_ record: SessionRecord) -> Bool {
        playbackCoordinator.isPlaying(sessionID: record.id)
    }

    func logText(for record: SessionRecord) -> String {
        progressCoordinator.logText(for: record)
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
            progressCoordinator.startSession(id: record.id)
            syncGenerationProgressState()
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
            let queueUpdate = progressCoordinator.ingest(
                snapshot: snapshot,
                fallbackElapsedSeconds: elapsedSeconds
            )
            if let elapsed = snapshot.elapsedSeconds {
                elapsedSeconds = max(elapsedSeconds, elapsed)
            }
            syncGenerationProgressState()
            updateQueuedGeneration(id: snapshot.jobID) { item in
                item.status = .running
                apply(queueUpdate, to: &item)
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
        let changedActiveLog = progressCoordinator.appendLog(
            chunk,
            sessionID: sessionID,
            elapsedSeconds: elapsedSeconds
        )
        syncGenerationProgressState()
        if sessionID == selectedSessionID {
            objectWillChange.send()
        }
        if changedActiveLog, let activeJobID {
            updateQueuedGenerationFromLatestProgress(jobID: activeJobID)
        }
    }

    private func setLatestGenerationLogLine(_ line: String) {
        if let queueUpdate = progressCoordinator.setLatestLine(line, elapsedSeconds: elapsedSeconds) {
            if let elapsed = queueUpdate.elapsedSeconds {
                elapsedSeconds = max(elapsedSeconds, elapsed)
            }
            if let activeJobID {
                updateQueuedGeneration(id: activeJobID) { item in
                    item.status = .running
                    apply(queueUpdate, to: &item)
                }
            }
        }
        syncGenerationProgressState()
    }

    private func updateQueuedGenerationFromLatestProgress(jobID: String) {
        guard let queueUpdate = progressCoordinator.setLatestLine(
            latestGenerationLogLine,
            elapsedSeconds: elapsedSeconds
        ) else {
            return
        }
        updateQueuedGeneration(id: jobID) { item in
            item.status = .running
            apply(queueUpdate, to: &item)
        }
        syncGenerationProgressState()
    }

    private func completeGeneration(record: GenerationRecord) {
        let finalElapsed = record.completedAt?.timeIntervalSince(record.createdAt) ?? elapsedSeconds
        let completedJobID = activeJobID
        var completedItem: QueuedGenerationItem?
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
            generationQueueCoordinator.removePayload(id: completedJobID)
            updateQueuedGeneration(id: completedJobID) { item in
                item.status = QueuedGenerationStatus(recordStatus: record.status)
                item.sessionID = record.id
                item.completedAt = record.completedAt ?? Date()
                item.elapsedSeconds = finalElapsed
                item.statusMessage = record.status.displayName
                item.errorMessage = record.error?.explanation
                completedItem = item
            }
        }
        if let completedItem { finishWorkspaceQueueItem(completedItem, record: record) }
        let logText = progressCoordinator.liveLog(sessionID: sessionID, fallback: record.logs)
        progressCoordinator.finish(
            logText: logText,
            elapsedSeconds: finalElapsed,
            status: record.status
        )
        syncGenerationProgressState()
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
            generationQueueCoordinator.removePayload(id: failedJobID)
        }
        stopElapsedTimer()
        progressCoordinator.fail(elapsedSeconds: finalElapsed)
        syncGenerationProgressState()
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
        AppErrorPresenter.message(for: error, fallbackTitle: "Could not start generation")
    }

    private func refreshBackendStatusNow() async -> BackendStatusSnapshot {
        isRefreshingBackendStatus = true
        defer { isRefreshingBackendStatus = false }
        let profile = selectedBackendProfile
        let snapshot = await backendStatusCoordinator.refreshStatus(for: profile)
        backendStatus = snapshot
        statusMessage = snapshot.state == .ready ? "Backend ready" : snapshot.state.displayName
        return snapshot
    }

    private var selectedBackendHasGenerationAdapter: Bool {
        backendStatusCoordinator.hasGenerationAdapter(for: selectedBackendProfile)
    }

    private func apply(_ update: GenerationQueueProgressUpdate, to item: inout QueuedGenerationItem) {
        item.progressFraction = update.progressFraction
        if let currentStep = update.currentStep {
            item.currentStep = currentStep
        }
        if let totalSteps = update.totalSteps {
            item.totalSteps = totalSteps
        }
        if let elapsedSeconds = update.elapsedSeconds {
            item.elapsedSeconds = elapsedSeconds
        }
        if update.shouldUpdateEstimatedRemainingSeconds {
            item.estimatedRemainingSeconds = update.estimatedRemainingSeconds
        }
        item.statusMessage = update.statusMessage
    }

    private func syncGenerationProgressState() {
        latestGenerationLogLine = progressCoordinator.latestLine
        estimatedGenerationProgressFraction = progressCoordinator.estimatedProgressFraction
        estimatedGenerationRemainingSeconds = progressCoordinator.estimatedRemainingSeconds
        generationPhaseName = progressCoordinator.phaseName
        generationTicker = progressCoordinator.ticker
    }

    private func applyPlaybackState(_ state: AppAudioPlaybackCoordinator.State) {
        isPlayingWAV = state.isPlaying
        playingSessionID = state.sessionID
        playbackElapsedSeconds = state.elapsedSeconds
        playbackDurationSeconds = state.durationSeconds
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
                self.progressCoordinator.tick(
                    elapsedSeconds: elapsed,
                    previousElapsedSeconds: previousElapsed,
                    isActive: self.isGenerating || self.isPreparingGeneration
                )
                self.syncGenerationProgressState()
                if self.isGenerating || self.isPreparingGeneration {
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
}
