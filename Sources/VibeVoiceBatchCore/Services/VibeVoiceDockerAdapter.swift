import Foundation

public final class VibeVoiceDockerAdapter: EngineAdapter {
    public let profile: BackendProfile
    private let projectRoot: URL
    private let backendManager: BackendManager
    private let fileStore: SessionFileStore
    private let runner: any DockerGenerationRunning
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.vibevoice-adapter")
    private var activeJobID: String?
    private var progressByJobID: [String: GenerationProgressSnapshot] = [:]

    public init(
        profile: BackendProfile = BackendProfiles.vibeVoiceTTS,
        projectRoot: URL = AppDefaults.projectRoot,
        backendManager: BackendManager? = nil,
        fileStore: SessionFileStore? = nil,
        runner: (any DockerGenerationRunning)? = nil
    ) {
        self.profile = profile
        self.projectRoot = projectRoot
        self.backendManager = backendManager ?? BackendManager(projectRoot: projectRoot)
        self.fileStore = fileStore ?? SessionFileStore(projectRoot: projectRoot)
        self.runner = runner ?? DockerGenerationRunner()
    }

    public func healthCheck() async -> BackendHealthReport {
        await backendManager.healthReportAsync(for: profile)
    }

    public func listVoices() async throws -> [VoiceDescriptor] {
        AppDefaults.availableVoices.map { voice in
            VoiceDescriptor(
                id: voice,
                displayName: voice,
                locale: AppDefaults.locale(forVibeVoiceVoiceID: voice),
                traits: voiceTraits(for: voice)
            )
        }
    }

    public func listModels() async throws -> [ModelDescriptor] {
        [
            ModelDescriptor(
                id: AppDefaults.modelPath,
                displayName: "VibeVoice Realtime 0.5B",
                role: profile.role
            )
        ]
    }

    public func generate(
        _ job: GenerationJob,
        events: @escaping (GenerationEvent) -> Void
    ) async throws -> GenerationRecord {
        let startedAt = Date()
        let workspace: GenerationWorkspace
        let ddpmInferenceSteps = job.settings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps

        do {
            workspace = try fileStore.createGenerationSession(
                text: job.inputText,
                voice: job.voiceID,
                cfgScale: job.settings.cfgScale,
                ddpmInferenceSteps: ddpmInferenceSteps,
                now: job.createdAt
            )
        } catch {
            throw BackendError.generationFailed(
                GenerationErrorRecord(
                    title: "Could not create generation session",
                    explanation: "The app could not create a protected history folder for this generation.",
                    recoverySuggestion: "Check that the project folder is writable and try again.",
                    technicalDetails: error.localizedDescription
                )
            )
        }

        stateQueue.sync {
            activeJobID = job.id
            progressByJobID[job.id] = nil
        }
        defer {
            stateQueue.sync {
                activeJobID = nil
                progressByJobID[job.id] = nil
            }
        }

        events(.sessionStarted(workspace.record))
        events(.status("Running"))

        var liveLog = ""
        func emitLog(_ chunk: String) {
            liveLog += chunk
            events(.log(chunk))
            emitProgressIfAvailable(logText: liveLog, jobID: job.id, startedAt: startedAt, events: events)
        }

        do {
            let initialLog = try prepareGeneration(workspace: workspace, job: job)
            emitLog(initialLog)
        } catch {
            let failureText = "\nCould not prepare generation: \(error.localizedDescription)\n"
            try? fileStore.appendLog(failureText, to: workspace.record.folderURL)
            emitLog(failureText)
            let record = finalizeGeneration(
                workspace: workspace,
                job: job,
                result: DockerRunResult(
                    exitCode: -1,
                    wasCancelled: false,
                    elapsedSeconds: Date().timeIntervalSince(startedAt)
                )
            )
            throw BackendError.generationFailed(
                GenerationErrorRecord(
                    title: "Could not prepare generation",
                    explanation: "The backend session was created, but the app could not prepare the staging files needed for generation.",
                    recoverySuggestion: "Open the session details, review the log, and try again.",
                    technicalDetails: "Session: \(record.id). \(error.localizedDescription)"
                )
            )
        }

        let result: DockerRunResult
        do {
            result = try runner.run(command: workspace.command) { [fileStore] chunk in
                try? fileStore.appendLog(chunk, to: workspace.record.folderURL)
                emitLog(chunk)
            }
        } catch {
            let failureText = "\nCould not start Docker: \(error.localizedDescription)\n"
            try? fileStore.appendLog(failureText, to: workspace.record.folderURL)
            emitLog(failureText)
            let failedResult = DockerRunResult(
                exitCode: -1,
                wasCancelled: false,
                elapsedSeconds: Date().timeIntervalSince(startedAt)
            )
            let record = finalizeGeneration(workspace: workspace, job: job, result: failedResult)
            events(.status(record.status.displayName))
            return record
        }

        let record = finalizeGeneration(workspace: workspace, job: job, result: result)
        if let outputPath = record.exportPath {
            let output = EngineOutput(fileURL: URL(fileURLWithPath: outputPath), format: .wav)
            if let normalized = try? await normalizeOutput(output) {
                events(.output(normalized))
            }
        }
        events(.status(record.status.displayName))
        return record
    }

    public func cancel(jobID: String) async {
        let shouldCancel = stateQueue.sync {
            activeJobID == jobID
        }
        if shouldCancel {
            runner.cancel()
        }
    }

    public func getProgress(jobID: String) async -> GenerationProgressSnapshot? {
        stateQueue.sync {
            progressByJobID[jobID]
        }
    }

    public func normalizeOutput(_ output: EngineOutput) async throws -> NormalizedAudioOutput {
        let duration = output.format == .wav ? try WaveAudioInspector.durationSeconds(for: output.fileURL) : nil
        return NormalizedAudioOutput(
            fileURL: output.fileURL,
            format: output.format,
            durationSeconds: duration,
            sampleRate: output.sampleRate
        )
    }

    public func makeDockerCommand(for job: GenerationJob) -> DockerRunCommand {
        DockerCommandBuilder.make(
            sessionID: job.id,
            voice: job.voiceID,
            cfgScale: job.settings.cfgScale,
            ddpmInferenceSteps: job.settings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps,
            projectRoot: projectRoot
        )
    }

    private func prepareGeneration(workspace: GenerationWorkspace, job: GenerationJob) throws -> String {
        var initialLog = """
        Session: \(workspace.record.id)
        Job: \(job.id)
        Created: \(ISO8601DateFormatter().string(from: workspace.record.metadata.createdAt))
        Backend: \(profile.displayName)
        Command: \(workspace.command.displayCommand)

        """

        try fileStore.stageInput(job.inputText)
        initialLog += "Staged input.txt for backend runtime.\n"

        if let recovered = try fileStore.recoverExistingGeneratedWAV(reason: "pre_run") {
            initialLog += "Recovered existing generated WAV before run: \(recovered.path)\n"
        }

        initialLog += "\nStarting generation...\n\n"
        try fileStore.replaceLog(initialLog, in: workspace.record.folderURL)
        return initialLog
    }

    private func emitProgressIfAvailable(
        logText: String,
        jobID: String,
        startedAt: Date,
        events: @escaping (GenerationEvent) -> Void
    ) {
        if let estimate = GenerationOutputParser.latestEstimatedProgress(in: logText) {
            let elapsedSeconds = estimate.elapsedSeconds ?? Date().timeIntervalSince(startedAt)
            let remainingSeconds: TimeInterval?
            if let estimatedSeconds = estimate.estimatedSeconds, estimatedSeconds > elapsedSeconds {
                remainingSeconds = estimatedSeconds - elapsedSeconds
            } else {
                remainingSeconds = nil
            }
            let snapshot = GenerationProgressSnapshot(
                jobID: jobID,
                fractionComplete: estimate.fraction,
                elapsedSeconds: elapsedSeconds,
                estimatedRemainingSeconds: remainingSeconds,
                message: estimate.displayPhase
            )
            stateQueue.sync {
                progressByJobID[jobID] = snapshot
            }
            events(.progress(snapshot))
            return
        }

        guard let progress = GenerationOutputParser.latestProgress(in: logText) else { return }
        let elapsedSeconds = progress.reportedElapsedSeconds ?? Date().timeIntervalSince(startedAt)
        let snapshot = GenerationProgressSnapshot(
            jobID: jobID,
            fractionComplete: progress.fraction,
            currentStep: progress.currentStep,
            totalSteps: progress.maxSteps,
            elapsedSeconds: elapsedSeconds,
            estimatedRemainingSeconds: progress.estimatedRemainingSeconds(elapsedSeconds: elapsedSeconds),
            message: "current step (\(progress.currentStep) / \(progress.maxSteps))"
        )
        stateQueue.sync {
            progressByJobID[jobID] = snapshot
        }
        events(.progress(snapshot))
    }

    private func finalizeGeneration(
        workspace: GenerationWorkspace,
        job: GenerationJob,
        result: DockerRunResult
    ) -> GenerationRecord {
        var metadata = workspace.record.metadata
        let completedAt = Date()
        metadata.completedAt = completedAt
        let currentLogText = (try? String(contentsOf: workspace.record.logURL, encoding: .utf8)) ?? ""
        let dockerSummary = GenerationOutputParser.latestSummary(in: currentLogText)
        metadata.generationTimeSeconds = dockerSummary?.generationTimeSeconds ?? result.elapsedSeconds

        var finalLog = "\nBackend process exited with code \(result.exitCode).\n"

        do {
            if result.wasCancelled {
                metadata.status = .cancelled
                if let recovered = try fileStore.recoverExistingGeneratedWAV(reason: "cancelled_\(workspace.record.id)") {
                    finalLog += "Recovered generated staging WAV after cancellation: \(recovered.path)\n"
                }
                finalLog += "Generation cancelled.\n"
            } else if result.exitCode == 0, let outputURL = try fileStore.moveGeneratedWAVToSession(folderURL: workspace.record.folderURL) {
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
                if let recovered = try fileStore.recoverExistingGeneratedWAV(reason: "failed_\(workspace.record.id)") {
                    finalLog += "Recovered generated staging WAV after failure: \(recovered.path)\n"
                }
                finalLog += "FAILED: no completed output.wav was produced.\n"
            }

            try fileStore.appendLog(finalLog, to: workspace.record.folderURL)
            try fileStore.writeMetadata(metadata, in: workspace.record.folderURL)
        } catch {
            finalLog += "Finalization error: \(error.localizedDescription)\n"
            try? fileStore.appendLog(finalLog, to: workspace.record.folderURL)
            metadata.status = .failed
            metadata.completedAt = completedAt
            try? fileStore.writeMetadata(metadata, in: workspace.record.folderURL)
        }

        let session = (try? fileStore.loadRecord(folderURL: workspace.record.folderURL)) ?? SessionRecord(
            folderURL: workspace.record.folderURL,
            metadata: metadata,
            inputText: job.inputText,
            logText: currentLogText + finalLog,
            metadataJSON: "",
            hasOutputWAV: metadata.outputFile != nil
        )
        return generationRecord(from: session, job: job)
    }

    private func generationRecord(from session: SessionRecord, job: GenerationJob) -> GenerationRecord {
        GenerationRecord(
            id: session.id,
            jobID: job.id,
            inputText: session.inputText,
            createdAt: session.metadata.createdAt,
            completedAt: session.metadata.completedAt,
            status: GenerationRecordStatus(sessionStatus: session.metadata.status),
            backendID: profile.id,
            backendDisplayName: profile.displayName,
            engineType: profile.engineType,
            modelID: job.modelID,
            voiceID: session.metadata.voice,
            settings: job.settings,
            exportPath: session.metadata.outputFile,
            durationSeconds: session.metadata.audioDurationSeconds,
            logs: session.logText,
            error: errorRecord(for: session.metadata.status)
        )
    }

    private func errorRecord(for status: SessionStatus) -> GenerationErrorRecord? {
        switch status {
        case .failed:
            return GenerationErrorRecord(
                title: "Generation failed",
                explanation: "The selected backend could not complete this narration.",
                recoverySuggestion: "Open the session log for details, then duplicate the session as new or retry."
            )
        case .cancelled:
            return GenerationErrorRecord(
                title: "Generation cancelled",
                explanation: "The generation was stopped before a completed output was produced.",
                recoverySuggestion: "Duplicate the session as new if you want to run it again."
            )
        case .draft, .running, .completed:
            return nil
        }
    }

    private func voiceTraits(for voice: String) -> [String] {
        var traits: [String] = []
        if voice.hasSuffix("_man") {
            traits.append("man")
        }
        if voice.hasSuffix("_woman") {
            traits.append("woman")
        }
        if let language = voice.split(separator: "-").first {
            traits.append(String(language))
        }
        return traits
    }
}

private extension GenerationRecordStatus {
    init(sessionStatus: SessionStatus) {
        switch sessionStatus {
        case .draft:
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
