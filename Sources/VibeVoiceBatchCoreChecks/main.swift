import Foundation
import VibeVoiceBatchCore

@main
struct VibeVoiceBatchCoreChecks {
    static func main() async throws {
        try checkDraftCreatesPermanentSessionFiles()
        try checkSessionIDsNeverCollide()
        try checkRecoverExistingGeneratedWAVMovesToRecovered()
        try checkMoveGeneratedWAVToSessionUsesOutputWAV()
        try checkOutputWAVCannotBeOverwritten()
        try checkArchiveDeletedSessionMovesToRecovery()
        try checkArchiveDeletedSessionNeverOverwritesRecoveryFolder()
        try checkReadsPCMDuration()
        try checkGeneratedAudioLibrarySummary()
        try checkParsesLiveProgressAndFinalSummary()
        try checkDockerCommandIncludesDDPMControls()
        try await checkBackendProfilesAndAdapterContracts()
        try checkBackendStatusSnapshots()
        try checkBackendSetupReport()
        try checkAssistantStageLockingAndCheckPresentation()
        try checkWorkstationToolbarPolicy()
        try checkOutputsInspectorAggregation()
        try checkBackendScopedVoiceCatalogMetadata()
        try checkKokoroDiscoveryReport()
        try checkKokoroCatalogReport()
        try checkChatterboxCatalogReport()
        try checkBackendManagerFacadePreservesInjectedRuntimeHooks()
        try checkBackendManagerOperations()
        try checkWorkspaceDataModel()
        try checkWorkspaceStoreCleanupInvariants()
        try checkMultiSelectArchiveMovesAllSessions()
        try checkWorkspacePresets()
        try checkAppSpecificErrors()
        try checkAppSettingsNormalizeInvalidValues()
        try checkDockerShimDocumentation()
        try checkAssistantViewDecomposition()
        try checkAppStoreResponsibilitySplit()
        try checkPostRefactorUXPolish()
        try checkAppIdentityAndPackaging()
        try await checkVibeVoiceAdapterGeneratesThroughSessionStore()
        try await checkKokoroHTTPAdapterGeneratesThroughSessionStore()
        try await checkChatterboxHTTPAdapterGeneratesThroughSessionStore()
        try await checkBackendVoiceTestRunnerUsesAdapterQueue()
        try await checkJobQueueCancellationReachesAdapter()
        print("VibeVoiceBatchCoreChecks passed")
    }

    private static func checkDraftCreatesPermanentSessionFiles() throws {
        try withStore { _, store in
            let date = Date(timeIntervalSince1970: 1_718_171_695)
            let record = try store.createDraft(text: "Hello from a draft.", voice: "en-carter", cfgScale: "1.8", now: date)
            precondition(record.metadata.status == .draft)
            precondition(record.metadata.inputWordCount == 4)
            precondition(FileManager.default.fileExists(atPath: record.inputURL.path))
            precondition(FileManager.default.fileExists(atPath: record.logURL.path))
            precondition(FileManager.default.fileExists(atPath: record.metadataURL.path))
            precondition(!FileManager.default.fileExists(atPath: record.folderURL.appendingPathComponent("output.wav").path))
        }
    }

    private static func checkSessionIDsNeverCollide() throws {
        try withStore { _, store in
            let date = Date(timeIntervalSince1970: 1_718_171_695)
            let first = try store.createDraft(text: "One", voice: "en-carter", cfgScale: "1.8", now: date)
            let second = try store.createDraft(text: "Two", voice: "en-carter", cfgScale: "1.8", now: date)
            precondition(first.id != second.id)
            precondition(second.id.hasSuffix("_2"))
        }
    }

    private static func checkRecoverExistingGeneratedWAVMovesToRecovered() throws {
        try withStore { root, store in
            try FileManager.default.createDirectory(at: root.outputsDirectory, withIntermediateDirectories: true)
            let generated = root.generatedWAVFile
            try Data([1, 2, 3]).write(to: generated)
            guard let recovered = try store.recoverExistingGeneratedWAV(reason: "pre_run") else {
                throw CheckError("Expected a recovered WAV")
            }
            precondition(!FileManager.default.fileExists(atPath: generated.path))
            precondition(FileManager.default.fileExists(atPath: recovered.path))
            precondition(recovered.path.contains("/recovered/"))
        }
    }

    private static func checkMoveGeneratedWAVToSessionUsesOutputWAV() throws {
        try withStore { root, store in
            let record = try store.createDraft(text: "Text", voice: "en-carter", cfgScale: "1.8")
            try FileManager.default.createDirectory(at: root.outputsDirectory, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: root.generatedWAVFile)
            guard let output = try store.moveGeneratedWAVToSession(folderURL: record.folderURL) else {
                throw CheckError("Expected session output.wav")
            }
            precondition(output.lastPathComponent == "output.wav")
            precondition(FileManager.default.fileExists(atPath: output.path))
            precondition(!FileManager.default.fileExists(atPath: root.generatedWAVFile.path))
        }
    }

    private static func checkOutputWAVCannotBeOverwritten() throws {
        try withStore { root, store in
            let record = try store.createDraft(text: "Protected output.", voice: "en-carter", cfgScale: "1.8")
            let existingOutput = record.folderURL.appendingPathComponent("output.wav", isDirectory: false)
            try Data([9, 9, 9]).write(to: existingOutput)
            try FileManager.default.createDirectory(at: root.outputsDirectory, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: root.generatedWAVFile)

            var refusedOverwrite = false
            do {
                _ = try store.moveGeneratedWAVToSession(folderURL: record.folderURL)
            } catch {
                refusedOverwrite = true
            }

            precondition(refusedOverwrite)
            let preservedOutput = try Data(contentsOf: existingOutput)
            precondition(preservedOutput == Data([9, 9, 9]))
            precondition(FileManager.default.fileExists(atPath: root.generatedWAVFile.path))
        }
    }

    private static func checkArchiveDeletedSessionMovesToRecovery() throws {
        try withStore { root, store in
            let createdAt = Date(timeIntervalSince1970: 1_718_171_695)
            let archivedAt = Date(timeIntervalSince1970: 1_718_172_000)
            let record = try store.createDraft(
                text: "Recoverable archive text.",
                voice: "en-carter",
                cfgScale: "1.8",
                now: createdAt
            )

            let destination = try store.archiveDeletedSession(record, now: archivedAt)
            precondition(!FileManager.default.fileExists(atPath: record.folderURL.path))
            precondition(destination.path.contains("/recovered/deleted_sessions/"))
            precondition(FileManager.default.fileExists(atPath: destination.appendingPathComponent("input.txt").path))
            precondition(FileManager.default.fileExists(atPath: destination.appendingPathComponent("log.txt").path))
            precondition(FileManager.default.fileExists(atPath: destination.appendingPathComponent("metadata.json").path))
            let activeSessions = try store.loadSessions()
            precondition(activeSessions.isEmpty)

            let recovered = try store.loadRecord(folderURL: destination)
            precondition(recovered.inputText == "Recoverable archive text.")
            precondition(recovered.metadata.sessionID == record.id)
            precondition(FileManager.default.fileExists(atPath: root.recoveredDirectory.appendingPathComponent("deleted_sessions").path))
        }
    }

    private static func checkArchiveDeletedSessionNeverOverwritesRecoveryFolder() throws {
        try withStore { root, store in
            let createdAt = Date(timeIntervalSince1970: 1_718_171_695)
            let archivedAt = Date(timeIntervalSince1970: 1_718_172_000)
            let record = try store.createDraft(
                text: "Archive collision.",
                voice: "en-carter",
                cfgScale: "1.8",
                now: createdAt
            )
            let deletedRoot = root.recoveredDirectory.appendingPathComponent("deleted_sessions", isDirectory: true)
            try FileManager.default.createDirectory(at: deletedRoot, withIntermediateDirectories: true)
            let occupiedName = "\(SessionFormatters.sessionIDDateFormatter.string(from: archivedAt))_\(record.id)"
            let occupied = deletedRoot.appendingPathComponent(occupiedName, isDirectory: true)
            try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
            let marker = occupied.appendingPathComponent("do-not-overwrite.txt", isDirectory: false)
            try Data("keep".utf8).write(to: marker)

            let destination = try store.archiveDeletedSession(record, now: archivedAt)
            precondition(destination.lastPathComponent == "\(occupiedName)_2")
            precondition(FileManager.default.fileExists(atPath: marker.path))
            let markerText = try String(contentsOf: marker, encoding: .utf8)
            precondition(markerText == "keep")
            precondition(FileManager.default.fileExists(atPath: destination.appendingPathComponent("input.txt").path))
        }
    }

    private static func checkMultiSelectArchiveMovesAllSessions() throws {
        try withStore { _, store in
            let createdAt = Date(timeIntervalSince1970: 1_718_171_695)
            let archivedAt = Date(timeIntervalSince1970: 1_718_172_000)
            let first = try store.createDraft(text: "First output.", voice: "en-carter", cfgScale: "1.8", now: createdAt)
            let second = try store.createDraft(text: "Second output.", voice: "en-mike", cfgScale: "1.6", now: createdAt)

            let destinations = try [first, second].map {
                try store.archiveDeletedSession($0, now: archivedAt)
            }

            let activeSessions = try store.loadSessions()
            precondition(activeSessions.isEmpty)
            precondition(destinations.count == 2)
            precondition(Set(destinations.map(\.lastPathComponent)).count == 2)
            for destination in destinations {
                precondition(destination.path.contains("/recovered/deleted_sessions/"))
                precondition(FileManager.default.fileExists(atPath: destination.appendingPathComponent("input.txt").path))
                precondition(FileManager.default.fileExists(atPath: destination.appendingPathComponent("metadata.json").path))
            }
        }
    }

    private static func checkReadsPCMDuration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("duration-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        try makePCM16MonoWav(durationSeconds: 2.0, sampleRate: 8_000).write(to: url)
        guard let duration = try WaveAudioInspector.durationSeconds(for: url) else {
            throw CheckError("Expected WAV duration")
        }
        precondition(abs(duration - 2.0) < 0.001)
    }

    private static func checkGeneratedAudioLibrarySummary() throws {
        try withStore { _, store in
            let firstDate = Date(timeIntervalSince1970: 1_718_171_695)
            _ = try completedOutputRecord(
                store: store,
                text: "First finished output.",
                voice: "en-carter_man",
                backendImage: "vibevoice-cpu",
                audioDuration: 3_600,
                outputBytes: Data([1, 2, 3]),
                now: firstDate
            )
            _ = try completedOutputRecord(
                store: store,
                text: "Second finished output.",
                voice: "en-mike_man",
                backendImage: "vibevoice-cpu",
                audioDuration: 243,
                outputBytes: Data([4, 5, 6]),
                now: firstDate.addingTimeInterval(2)
            )

            let missingDuration = try store.createDraft(
                text: "Completed before duration metadata existed.",
                voice: "en-carter_man",
                cfgScale: "1.8",
                now: firstDate.addingTimeInterval(4)
            )
            var metadata = missingDuration.metadata
            metadata.status = .completed
            metadata.completedAt = firstDate.addingTimeInterval(5)
            try store.writeMetadata(metadata, in: missingDuration.folderURL)

            let durationFallback = try store.createDraft(
                text: "Completed with WAV but without duration metadata.",
                voice: "en-carter_man",
                cfgScale: "1.8",
                now: firstDate.addingTimeInterval(6)
            )
            let fallbackOutput = durationFallback.folderURL.appendingPathComponent("output.wav", isDirectory: false)
            try makePCM16MonoWav(durationSeconds: 2.0, sampleRate: 8_000).write(to: fallbackOutput)
            var fallbackMetadata = durationFallback.metadata
            fallbackMetadata.status = .completed
            fallbackMetadata.completedAt = firstDate.addingTimeInterval(7)
            fallbackMetadata.outputFile = fallbackOutput.path
            try store.writeMetadata(fallbackMetadata, in: durationFallback.folderURL)

            let summary = GeneratedAudioLibrarySummary(sessions: try store.loadSessions())
            precondition(summary.generatedSessionCount == 4)
            precondition(summary.sessionsWithKnownDurationCount == 3)
            precondition(summary.totalAudioDurationSeconds == 3_845)
            precondition(summary.missingDurationCount == 1)
            precondition(summary.hasGeneratedAudioDuration)
            precondition(SessionFormatters.longDuration(summary.totalAudioDurationSeconds) == "1 hour 4 minutes and 5 seconds")
            precondition(GeneratedAudioReference.defaultReferences.count >= 20)
            precondition(GeneratedAudioReference.defaultReferences.contains { $0.title == "The Wizard of Oz" && $0.durationSeconds == 6_120 })

            let heyJude = GeneratedAudioReference(title: "Hey Jude", creator: "The Beatles", durationSeconds: 431)
            precondition(heyJude.equivalentText(for: summary.totalAudioDurationSeconds) == "9 plays of Hey Jude by The Beatles")
        }
    }

    private static func checkParsesLiveProgressAndFinalSummary() throws {
        let progressText = "noise\rPrefilled 70 text tokens, generated 80 speech tokens, current step (298 / 8192):   4%| | 298/8192 [00:27]"
        guard let progress = GenerationOutputParser.latestProgress(in: progressText) else {
            throw CheckError("Expected live progress")
        }
        precondition(progress.prefilledTextTokens == 70)
        precondition(progress.generatedSpeechTokens == 80)
        precondition(progress.currentStep == 298)
        precondition(progress.maxSteps == 8192)
        precondition(abs(progress.percent - 3.6376953125) < 0.0001)
        precondition(progress.reportedElapsedSeconds == 27)

        let coloredProgressText = "\u{001B}[32mPrefilled 12 text tokens, generated 34 speech tokens, current step (50 / 100):  50%| | 50/100 [00:10]\u{001B}[0m"
        guard let coloredProgress = GenerationOutputParser.latestProgress(in: coloredProgressText) else {
            throw CheckError("Expected ANSI-wrapped live progress")
        }
        precondition(coloredProgress.currentStep == 50)
        precondition(coloredProgress.maxSteps == 100)
        precondition(coloredProgress.reportedElapsedSeconds == 10)

        let estimatedProgressText = "Fonim progress: phase=generation elapsed=00:12 estimated=02:00 progress=10.00%"
        guard let estimatedProgress = GenerationOutputParser.latestEstimatedProgress(in: estimatedProgressText) else {
            throw CheckError("Expected estimated generation progress")
        }
        precondition(estimatedProgress.phase == "generation")
        precondition(estimatedProgress.fraction == 0.10)
        precondition(estimatedProgress.elapsedSeconds == 12)
        precondition(estimatedProgress.estimatedSeconds == 120)

        let legacyEstimatedText = "VibeVoiceBatch progress: phase=generation elapsed=00:14 estimated=02:20 progress=10.00%"
        guard let legacyEstimatedProgress = GenerationOutputParser.latestEstimatedProgress(in: legacyEstimatedText) else {
            throw CheckError("Expected legacy estimated generation progress")
        }
        precondition(legacyEstimatedProgress.elapsedSeconds == 14)

        let preciseEstimatedText = "Fonim progress: phase=generation elapsed=01:54 estimated=08:21 progress=22.78%"
        guard let preciseEstimatedProgress = GenerationOutputParser.latestEstimatedProgress(in: preciseEstimatedText) else {
            throw CheckError("Expected precise estimated generation progress")
        }
        precondition(preciseEstimatedProgress.phase == "generation")
        precondition(abs(preciseEstimatedProgress.fraction - 0.2278) < 0.0001)
        precondition(preciseEstimatedProgress.elapsedSeconds == 114)
        precondition(preciseEstimatedProgress.estimatedSeconds == 501)

        let chatterboxText = """
        2026-06-18T20:43:44Z Received /tts request: mode='predefined', format='wav'
        2026-06-18T20:43:45Z Text chunking complete. Generated 18 chunk(s).
        2026-06-18T20:43:46Z Synthesizing chunk 3/18...
        2026-06-18T20:43:47Z 10%|#         | 100/1000 [02:21<22:44, 1.52s/it]
        """
        guard let chatterboxProgress = GenerationOutputParser.latestChatterboxProgress(in: chatterboxText) else {
            throw CheckError("Expected Chatterbox progress")
        }
        precondition(chatterboxProgress.chunkIndex == 3)
        precondition(chatterboxProgress.chunkCount == 18)
        precondition(chatterboxProgress.currentStep == 100)
        precondition(chatterboxProgress.totalSteps == 1000)
        precondition(chatterboxProgress.reportedElapsedSeconds == 141)
        precondition(chatterboxProgress.displayMessage.contains("chunk 3/18"))
        precondition(chatterboxProgress.fraction > 0.11 && chatterboxProgress.fraction < 0.12)

        let chatterboxMelText = chatterboxText + "\nS3 Token -> Mel Inference...\n100%|##########| 2/2 [00:09<00:00, 4.50s/it]\n"
        guard let chatterboxMel = GenerationOutputParser.latestChatterboxProgress(in: chatterboxMelText) else {
            throw CheckError("Expected Chatterbox mel progress")
        }
        precondition(chatterboxMel.phase == "Mel inference")
        precondition(chatterboxMel.currentStep == 2)
        precondition(chatterboxMel.totalSteps == 2)
        precondition(chatterboxMel.fraction > chatterboxProgress.fraction)

        let kokoroText = """
        2026-06-19T08:00:01Z POST /v1/audio/speech
        2026-06-19T08:00:02Z Processing chunk 2/5
        2026-06-19T08:00:04Z 40%|####      | 400/1000 [00:08<00:12, 50.00it/s]
        """
        guard let kokoroProgress = GenerationOutputParser.latestKokoroProgress(in: kokoroText) else {
            throw CheckError("Expected Kokoro progress")
        }
        precondition(kokoroProgress.chunkIndex == 2)
        precondition(kokoroProgress.chunkCount == 5)
        precondition(kokoroProgress.currentStep == 400)
        precondition(kokoroProgress.totalSteps == 1000)
        precondition(kokoroProgress.reportedElapsedSeconds == 8)
        precondition(kokoroProgress.displayMessage.contains("chunk 2/5"))

        let summaryText = """
        Input file: /app/input.txt
        Output file: /app/outputs/input_generated.wav
        Speaker names: en-mike_man
        CFG scale: 1.8
        DDPM inference steps: 8
        Prefilling text tokens: 389
        Generated speech tokens: 930
        Total tokens: 1467
        Generation time: 329.40 seconds
        Audio duration: 123.47 seconds
        RTF (Real Time Factor): 2.67x
        """
        guard let summary = GenerationOutputParser.latestSummary(in: summaryText) else {
            throw CheckError("Expected final summary")
        }
        precondition(summary.inputFile == "/app/input.txt")
        precondition(summary.outputFile == "/app/outputs/input_generated.wav")
        precondition(summary.speakerNames == "en-mike_man")
        precondition(summary.cfgScale == "1.8")
        precondition(summary.ddpmInferenceSteps == 8)
        precondition(summary.prefilledTextTokens == 389)
        precondition(summary.generatedSpeechTokens == 930)
        precondition(summary.totalTokens == 1467)
        precondition(summary.generationTimeSeconds == 329.40)
        precondition(summary.audioDurationSeconds == 123.47)
        precondition(summary.rtf == 2.67)
    }

    private static func checkDockerCommandIncludesDDPMControls() throws {
        try withStore { root, _ in
            let command = DockerCommandBuilder.make(
                sessionID: "session",
                voice: "en-carter_man",
                cfgScale: "1.8",
                ddpmInferenceSteps: 8,
                projectRoot: root
            )
            precondition(command.arguments.contains("--ddpm_inference_steps"))
            precondition(command.arguments.contains("8"))
            precondition(command.displayCommand.contains("docker_overrides/realtime_model_inference_from_file.py:/app/demo/realtime_model_inference_from_file.py:ro"))
        }
    }

    private static func checkBackendProfilesAndAdapterContracts() async throws {
        let profile = BackendProfiles.vibeVoiceTTS
        precondition(profile.id == "vibevoice-tts")
        precondition(profile.runtime == .docker)
        precondition(profile.engineType == .vibeVoiceTTS)
        precondition(profile.outputFormatSupport == [.wav])
        precondition(BackendProfiles.all.contains(BackendProfiles.kokoroTTS))
        precondition(BackendProfiles.kokoroTTS.engineType == .kokoro)
        precondition(BackendProfiles.kokoroTTS.requiredModels.first?.id == "tts-1")
        precondition(BackendProfiles.kokoroTTS.progressParser == "KokoroHTTPAdapter.progress")
        precondition(BackendProfiles.all.contains(BackendProfiles.chatterboxTTS))
        precondition(BackendProfiles.chatterboxTTS.engineType == .chatterbox)
        precondition(BackendProfiles.chatterboxTTS.requiredModels.map(\.id) == [
            ChatterboxModelCatalog.turboID,
            ChatterboxModelCatalog.originalID
        ])
        precondition(BackendProfiles.chatterboxTTS.healthCheckURL?.absoluteString == "http://127.0.0.1:8004/api/model-info")
        precondition(BackendConnectionSettings.defaultConfigurations[BackendProfiles.chatterboxTTS.id]?.generatePath == "/tts")
        let connectedKokoro = BackendProfiles.kokoroTTS.applying(
            BackendConnectionSettings(
                connectionKind: .installedDockerImage,
                dockerImage: "kokoro-local",
                serviceBaseURL: "http://127.0.0.1:8880",
                modelID: "tts-1",
                defaultVoice: "af_heart"
            )
        )
        precondition(connectedKokoro.generationExtraParameters["generate_endpoint"] == "http://127.0.0.1:8880/v1/audio/speech")
        precondition(connectedKokoro.generationExtraParameters["docker_image"] == "kokoro-local")
        let connectedChatterbox = BackendProfiles.chatterboxTTS.applying(
            BackendConnectionSettings(
                connectionKind: .externalService,
                serviceBaseURL: "http://127.0.0.1:8004",
                healthPath: "/api/model-info",
                generatePath: "/tts",
                modelID: "chatterbox",
                defaultVoice: "Emily.wav"
            )
        )
        precondition(connectedChatterbox.generationExtraParameters["generate_endpoint"] == "http://127.0.0.1:8004/tts")
        precondition(connectedChatterbox.generationExtraParameters["temperature"] == "0.8")

        let manager = BackendManager(projectRoot: FileManager.default.temporaryDirectory)
        precondition(manager.registeredProfiles().contains(profile))
        precondition(manager.registeredProfiles().contains(BackendProfiles.kokoroTTS))
        precondition(manager.registeredProfiles().contains(BackendProfiles.chatterboxTTS))

        let adapter = VibeVoiceDockerAdapter(projectRoot: FileManager.default.temporaryDirectory)
        let job = GenerationJob(
            id: "adapter-check",
            inputText: "Hello architecture.",
            backendID: profile.id,
            modelID: AppDefaults.modelPath,
            voiceID: "en-carter_man",
            settings: GenerationSettings(cfgScale: "1.8", ddpmInferenceSteps: 8)
        )
        let command = adapter.makeDockerCommand(for: job)
        precondition(command.arguments.contains("--speaker_name"))
        precondition(command.arguments.contains("en-carter_man"))
        precondition(command.arguments.contains("--cfg_scale"))
        precondition(command.arguments.contains("1.8"))
        precondition(command.arguments.contains("--ddpm_inference_steps"))
        precondition(command.arguments.contains("8"))

        let kokoroAdapter = KokoroHTTPAdapter(projectRoot: FileManager.default.temporaryDirectory)
        let kokoroHealth = await kokoroAdapter.healthCheck()
        precondition(kokoroHealth.profileID == BackendProfiles.kokoroTTS.id)
        precondition(kokoroHealth.state == .unknown)
        let chatterboxAdapter = ChatterboxHTTPAdapter(projectRoot: FileManager.default.temporaryDirectory)
        let chatterboxHealth = await chatterboxAdapter.healthCheck()
        precondition(chatterboxHealth.profileID == BackendProfiles.chatterboxTTS.id)
    }

    private static func checkBackendStatusSnapshots() throws {
        let profile = BackendProfiles.vibeVoiceTTS

        let missingManager = BackendManager(
            projectRoot: FileManager.default.temporaryDirectory,
            dockerExecutableResolver: { nil }
        )
        let missing = missingManager.statusSnapshot(for: profile)
        precondition(missing.state == .missing)
        precondition(!missing.canStartGeneration)
        precondition(missing.userMessage.contains("Docker Desktop"))
        precondition(missing.recoverySuggestion == "Install Docker Desktop, then refresh backend status.")

        let stoppedManager = BackendManager(
            projectRoot: FileManager.default.temporaryDirectory,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { _, _ in
                BackendProcessResult(exitCode: 1, combinedOutput: "Cannot connect to the Docker daemon")
            }
        )
        let stopped = stoppedManager.statusSnapshot(for: profile)
        precondition(stopped.state == .stopped)
        precondition(!stopped.canStartGeneration)
        precondition(stopped.technicalDetails?.contains("Docker daemon") == true)

        let readyManager = BackendManager(
            projectRoot: FileManager.default.temporaryDirectory,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { _, arguments in
                precondition(arguments.contains("info"))
                return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
            }
        )
        let ready = readyManager.statusSnapshot(for: profile)
        precondition(ready.state == .ready)
        precondition(ready.canStartGeneration)
        precondition(ready.userMessage.contains(profile.displayName))

        let running = ready.replacingState(
            .runningJob,
            userMessage: "Generating audio.",
            recoverySuggestion: "Cancel if needed."
        )
        precondition(running.state == .runningJob)
        precondition(!running.canStartGeneration)
        precondition(running.alertMessage.contains("Generating audio."))

        let unconfiguredKokoro = BackendManager(
            projectRoot: FileManager.default.temporaryDirectory
        ).statusSnapshot(for: BackendProfiles.kokoroTTS)
        precondition(unconfiguredKokoro.state == .unknown)
        precondition(unconfiguredKokoro.userMessage.contains("runtime connection details"))
        precondition(!unconfiguredKokoro.userMessage.contains("not been implemented"))

        let futureProfile = BackendProfile(
            id: "future-tts",
            displayName: "Future TTS",
            engineType: .custom,
            installMethod: .localPythonEnvironment,
            runtime: .localPython,
            requiredModels: [
                RequiredModel(
                    id: "future/model",
                    displayName: "Future Model",
                    source: "future/model",
                    approximateDiskSpaceGB: nil,
                    licenseNotes: nil
                )
            ],
            supportedArchitectures: [.universal],
            healthCheckURL: URL(string: "http://127.0.0.1:7777/health"),
            generateEndpoint: URL(string: "http://127.0.0.1:7777/generate"),
            progressParser: "FutureProgressParser",
            logParser: "FutureLogParser",
            outputFormatSupport: [.wav],
            licenseNotes: "Test profile.",
            role: "Future engine",
            strengths: [],
            risks: []
        )
        let futureManager = BackendManager(
            projectRoot: FileManager.default.temporaryDirectory,
            httpRunner: { url in
                precondition(url.absoluteString == "http://127.0.0.1:7777/health")
                return BackendHTTPResult(statusCode: 200, body: "{\"status\":\"ready\"}")
            }
        )
        let futureStatus = futureManager.statusSnapshot(for: futureProfile)
        precondition(futureStatus.state == .ready)
        precondition(futureStatus.canStartGeneration)
    }

    private static func checkBackendSetupReport() throws {
        let profile = BackendProfiles.vibeVoiceTTS
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchSetupChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let missingManager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { nil }
        )
        let missing = missingManager.setupReport(for: profile)
        precondition(!missing.isReady)
        precondition(missing.checks.contains { $0.id == "docker-runtime" && $0.state == .failed })

        let readyManager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { _, arguments in
                if arguments.contains("inspect") {
                    return BackendProcessResult(exitCode: 0, combinedOutput: "image")
                }
                return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
            }
        )
        let ready = readyManager.setupReport(for: profile)
        precondition(ready.checks.contains { $0.id == "docker-runtime" && $0.state == .passed })
        precondition(ready.checks.contains { $0.id == "docker-image-\(profile.id)" && $0.state == .passed })
        precondition(ready.checks.contains { $0.id == "health-\(profile.id)" && $0.state == .passed })

        let kokoroProfile = BackendProfiles.kokoroTTS.applying(
            BackendConnectionSettings(
                connectionKind: .installedDockerImage,
                dockerImage: "kokoro-local",
                modelID: "tts-1"
            )
        )
        let kokoroManager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { _, arguments in
                if arguments.contains("inspect") {
                    return BackendProcessResult(exitCode: 0, combinedOutput: "kokoro image")
                }
                return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
            }
        )
        let kokoroStatus = kokoroManager.statusSnapshot(for: kokoroProfile)
        precondition(kokoroStatus.state == .stopped)
        precondition(kokoroStatus.userMessage.contains("no Kokoro service address"))
        let kokoroReport = kokoroManager.setupReport(for: kokoroProfile)
        precondition(kokoroReport.checks.contains { $0.id == "docker-image-\(kokoroProfile.id)" && $0.state == .passed })

        let kokoroServiceProfile = BackendProfiles.kokoroTTS.applying(
            BackendConnectionSettings(
                connectionKind: .installedDockerImage,
                dockerImage: "kokoro-local",
                serviceBaseURL: "http://127.0.0.1:8880",
                modelID: "tts-1",
                defaultVoice: "af_heart"
            )
        )
        let kokoroServiceManager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { _, arguments in
                if arguments.contains("inspect") {
                    return BackendProcessResult(exitCode: 0, combinedOutput: "kokoro image")
                }
                return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
            },
            httpRunner: { url in
                precondition(url.absoluteString == "http://127.0.0.1:8880/health")
                return BackendHTTPResult(statusCode: 200, body: "{\"status\":\"ready\"}")
            }
        )
        let kokoroServiceStatus = kokoroServiceManager.statusSnapshot(for: kokoroServiceProfile)
        precondition(kokoroServiceStatus.state == .stopped)
        precondition(kokoroServiceStatus.userMessage.contains("service is not running"))

        let kokoroReadyManager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { _, arguments in
                if arguments.contains("inspect") {
                    return BackendProcessResult(exitCode: 0, combinedOutput: "kokoro image")
                }
                if arguments.contains("ps") {
                    return BackendProcessResult(
                        exitCode: 0,
                        combinedOutput: "vibevoice_batch_kokoro_tts\tkokoro-local\t0.0.0.0:8880->8880/tcp\tUp 1 minute\n"
                    )
                }
                return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
            },
            httpRunner: { url in
                precondition(url.absoluteString == "http://127.0.0.1:8880/health")
                return BackendHTTPResult(statusCode: 200, body: "{\"status\":\"ready\"}")
            }
        )
        let kokoroReadyStatus = kokoroReadyManager.statusSnapshot(for: kokoroServiceProfile)
        precondition(kokoroReadyStatus.state == .ready)
        precondition(kokoroReadyStatus.userMessage.contains("health check"))

        let baseKokoroReport = BackendManager(projectRoot: root).setupReport(for: BackendProfiles.kokoroTTS)
        precondition(baseKokoroReport.checks.contains { check in
            check.id == "runtime-\(BackendProfiles.kokoroTTS.id)" &&
                check.message.contains("runtime connection details") &&
                !check.message.contains("not been implemented")
        })
    }

    private static func checkAssistantStageLockingAndCheckPresentation() throws {
        let locking = BackendSetupStageLockingPolicy(
            selectedStage: .checks,
            highestUnlockedStage: .checks
        )
        precondition(locking.isUnlocked(.welcome))
        precondition(locking.isUnlocked(.backend))
        precondition(locking.isUnlocked(.checks))
        precondition(!locking.isUnlocked(.install))
        precondition(locking.lockedStages == [.install, .models, .test, .confirm])
        precondition(locking.isCompleted(.welcome))
        precondition(locking.isCompleted(.backend))
        precondition(!locking.isCompleted(.checks))
        precondition(BackendSetupStage.welcome.next == .backend)
        precondition(BackendSetupStage.confirm.next == nil)
        precondition(BackendSetupStage.install.previous == .checks)

        let emptyPresentation = BackendSetupCheckListPresentation(report: nil, isChecking: false)
        precondition(emptyPresentation.state == .empty)
        precondition(!emptyPresentation.usesScrollableResults)
        precondition(emptyPresentation.minimumHeight == 300)

        let checkingPresentation = BackendSetupCheckListPresentation(report: nil, isChecking: true)
        precondition(checkingPresentation.state == .checking)
        precondition(!checkingPresentation.usesScrollableResults)

        let report = BackendSetupReport(
            profileID: BackendProfiles.vibeVoiceTTS.id,
            checks: [
                BackendSetupCheck(id: "runtime", title: "Runtime", state: .passed, message: "Ready"),
                BackendSetupCheck(id: "image", title: "Image", state: .failed, message: "Missing")
            ]
        )
        let resultsPresentation = BackendSetupCheckListPresentation(report: report, isChecking: false)
        precondition(resultsPresentation.state == .results(count: 2))
        precondition(resultsPresentation.usesScrollableResults)
    }

    private static func checkWorkstationToolbarPolicy() throws {
        precondition(WorkstationSelection.section(.history).toolbarKind == .editor)
        precondition(WorkstationSelection.historySession("session").toolbarKind == .session)
        precondition(WorkstationSelection.section(.outputs).toolbarKind == .outputs)
        precondition(WorkstationSelection.section(.backends).toolbarKind == .backends)
        precondition(WorkstationSelection.section(.projects).toolbarKind == .workspace)
        precondition(WorkstationSelection.section(.scripts).toolbarKind == .workspace)
        precondition(WorkstationSelection.section(.batches).toolbarKind == .workspace)
        precondition(WorkstationSelection.section(.voices).toolbarKind == .workspace)
        precondition(WorkstationSelection.section(.presets).toolbarKind == .workspace)
        precondition(WorkstationSelection.historySession("abc").id == "history-abc")
        precondition(WorkstationSection.allCases.map(\.title) == [
            "Projects",
            "Scripts",
            "Batches",
            "Voices",
            "Presets",
            "History",
            "Outputs",
            "Backends"
        ])
    }

    private static func checkOutputsInspectorAggregation() throws {
        try withStore { _, store in
            let date = Date(timeIntervalSince1970: 1_718_171_695)
            let first = try completedOutputRecord(
                store: store,
                text: "First output",
                voice: "en-carter",
                backendImage: "vibevoice-cpu",
                audioDuration: 2.5,
                outputBytes: Data([1, 2, 3, 4]),
                now: date
            )
            let second = try completedOutputRecord(
                store: store,
                text: "Second output",
                voice: "af_heart",
                backendImage: "",
                audioDuration: 3.5,
                outputBytes: Data([5, 6]),
                now: date.addingTimeInterval(10)
            )
            let summary = OutputHousekeepingSummary(
                selectedRecords: [first, second],
                totalOutputCount: 3,
                projectTitlesBySessionID: [
                    first.id: ["Novel"],
                    second.id: []
                ],
                fileSizeBySessionID: [
                    first.id: 4,
                    second.id: 2
                ]
            )

            precondition(summary.selectedCount == 2)
            precondition(summary.totalOutputCount == 3)
            precondition(summary.totalAudioDurationSeconds == 6.0)
            precondition(summary.totalFileSizeBytes == 6)
            precondition(summary.filedCount == 1)
            precondition(summary.unfiledCount == 1)
            precondition(summary.voices == ["af_heart", "en-carter"])
            precondition(summary.backends == ["Local service", "vibevoice-cpu"])
            precondition(summary.projectTitles == ["Novel"])
            precondition(summary.filingSummary == "Novel")
            precondition(summary.archiveEligibility == "Ready")
            precondition(summary.outputFileNames == ["output.wav", "output.wav"])

            let emptySummary = OutputHousekeepingSummary(selectedRecords: [], totalOutputCount: 3)
            precondition(emptySummary.filingSummary == "No selection")
            precondition(emptySummary.archiveEligibility == "No selection")
        }
    }

    private static func checkKokoroDiscoveryReport() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchDiscoveryChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let image = "ghcr.io/remsky/kokoro-fastapi-cpu:latest"
        let manager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { _, arguments in
                if arguments.contains("info") {
                    return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
                }
                if arguments.contains("images") {
                    return BackendProcessResult(exitCode: 0, combinedOutput: "\(image)\tbcf38f9bf7f0\t5.41GB\n")
                }
                if arguments.contains("ps") {
                    return BackendProcessResult(
                        exitCode: 0,
                        combinedOutput: "kokoro-fastapi\t\(image)\t0.0.0.0:8880->8880/tcp, [::]:8880->8880/tcp\tUp 12 hours\n"
                    )
                }
                return BackendProcessResult(exitCode: 0, combinedOutput: "")
            }
        )

        let discovery = manager.discoveryReport(for: BackendProfiles.kokoroTTS)
        precondition(discovery.candidates.count == 1)
        let candidate = try unwrap(discovery.candidates.first, "Expected Kokoro discovery candidate")
        precondition(candidate.title == "kokoro-fastapi")
        precondition(candidate.confidence == .high)
        precondition(candidate.dockerImage == image)
        precondition(candidate.serviceBaseURL == "http://127.0.0.1:8880")
        precondition(candidate.connectionSettings.healthCheckURL?.absoluteString == "http://127.0.0.1:8880/health")
    }

    private static func checkBackendScopedVoiceCatalogMetadata() throws {
        let settings = AppSettings.defaults

        let vibeVoices = settings.voiceOptions(for: BackendProfiles.vibeVoiceTTS)
        precondition(vibeVoices.count == AppDefaults.availableVoices.count)
        precondition(vibeVoices.allSatisfy { $0.backendID == BackendProfiles.vibeVoiceTTS.id })
        precondition(!vibeVoices.contains { $0.id == "Emily.wav" })
        let spanish = try unwrap(vibeVoices.first { $0.id == "sp-spk0_woman" }, "Expected Spanish VibeVoice voice")
        precondition(spanish.languageCode == "es")
        precondition(spanish.traits.contains("female"))
        let japanese = try unwrap(vibeVoices.first { $0.id == "jp-spk1_woman" }, "Expected Japanese VibeVoice voice")
        precondition(japanese.languageCode == "ja")
        let korean = try unwrap(vibeVoices.first { $0.id == "kr-spk0_woman" }, "Expected Korean VibeVoice voice")
        precondition(korean.languageCode == "ko")
        let hindi = try unwrap(vibeVoices.first { $0.id == "in-samuel_man" }, "Expected Hindi VibeVoice voice")
        precondition(hindi.languageCode == "hi")
        precondition(hindi.traits.contains("male"))

        let kokoroVoices = settings.voiceOptions(for: BackendProfiles.kokoroTTS)
        precondition(kokoroVoices.count == KokoroVoiceCatalog.fallbackVoices.count)
        precondition(kokoroVoices.allSatisfy { $0.backendID == BackendProfiles.kokoroTTS.id })
        precondition(!kokoroVoices.contains { $0.id == "en-carter_man" })
        let heart = try unwrap(kokoroVoices.first { $0.id == "af_heart" }, "Expected Kokoro Heart voice")
        precondition(heart.displayName == "Heart")
        precondition(heart.locale == "en-US")
        precondition(heart.languageCode == "en")
        precondition(heart.traits.contains("female"))
        let siwis = try unwrap(kokoroVoices.first { $0.id == "ff_siwis" }, "Expected Kokoro French voice")
        precondition(siwis.languageCode == "fr")
        let contaminatedKokoroSettings = AppSettings(
            defaultBackendID: BackendProfiles.kokoroTTS.id,
            defaultVoice: "Abigail.wav",
            backendConnections: [
                BackendProfiles.kokoroTTS.id: BackendConnectionSettings(
                    connectionKind: .installedDockerImage,
                    dockerImage: "ghcr.io/remsky/kokoro-fastapi-cpu:latest",
                    serviceBaseURL: "http://127.0.0.1:8880",
                    modelID: "tts-1",
                    defaultVoice: "Abigail.wav"
                )
            ]
        )
        let contaminatedKokoroVoices = contaminatedKokoroSettings.voiceOptions(for: contaminatedKokoroSettings.selectedBackendProfile)
        precondition(contaminatedKokoroVoices.count == KokoroVoiceCatalog.fallbackVoices.count)
        precondition(!contaminatedKokoroVoices.contains { $0.id == "Abigail.wav" })
        let repairedKokoroSettings = contaminatedKokoroSettings.normalizationResult().settings
        precondition(repairedKokoroSettings.defaultVoice == "af_heart")
        let partialKokoroSettings = AppSettings(
            backendCatalogs: [
                BackendProfiles.kokoroTTS.id: BackendCatalogReport(
                    profileID: BackendProfiles.kokoroTTS.id,
                    models: [],
                    voices: [
                        BackendCatalogVoice(
                            id: "am_adam",
                            displayName: "Runtime Adam",
                            backendID: BackendProfiles.kokoroTTS.id,
                            locale: "en-US",
                            languageCode: "en",
                            traits: ["male"],
                            sourceType: .predefined
                        )
                    ],
                    message: "Partial Kokoro runtime catalog"
                )
            ]
        )
        let mergedKokoroVoices = partialKokoroSettings.voiceOptions(for: BackendProfiles.kokoroTTS)
        precondition(mergedKokoroVoices.count == KokoroVoiceCatalog.fallbackVoices.count)
        precondition(mergedKokoroVoices.first { $0.id == "am_adam" }?.displayName == "Runtime Adam")

        let chatterboxVoices = settings.voiceOptions(for: BackendProfiles.chatterboxTTS)
        precondition(chatterboxVoices.count == 28)
        precondition(chatterboxVoices.allSatisfy { $0.backendID == BackendProfiles.chatterboxTTS.id })
        precondition(!chatterboxVoices.contains { $0.id == "en-carter_man" })
        let emily = try unwrap(chatterboxVoices.first { $0.id == "Emily.wav" }, "Expected Chatterbox Emily voice")
        precondition(emily.displayName == "Emily")
        precondition(emily.languageCode == "en")
        precondition(emily.sourceType == .predefined)
        precondition(emily.traits.contains("female"))
        precondition(emily.modelIDs.contains(ChatterboxModelCatalog.turboID))
        precondition(emily.modelIDs.contains(ChatterboxModelCatalog.originalID))
        precondition(!emily.modelIDs.contains(ChatterboxModelCatalog.multilingualID))
        precondition(ChatterboxVoiceCatalog.voice(emily, supportsOutputLanguage: "en"))
        precondition(!ChatterboxVoiceCatalog.voice(emily, supportsOutputLanguage: "hi"))
        let hindiChatterboxVoice = BackendCatalogVoice(
            id: "Meera.wav",
            displayName: "Meera",
            backendID: BackendProfiles.chatterboxTTS.id,
            locale: "hi",
            languageCode: "hi",
            sourceType: .predefined
        )
        precondition(ChatterboxVoiceCatalog.voice(hindiChatterboxVoice, supportsOutputLanguage: "hi"))
        precondition(!ChatterboxVoiceCatalog.voice(hindiChatterboxVoice, supportsOutputLanguage: "en"))
        let partialChatterboxSettings = AppSettings(
            backendCatalogs: [
                BackendProfiles.chatterboxTTS.id: BackendCatalogReport(
                    profileID: BackendProfiles.chatterboxTTS.id,
                    models: [],
                    voices: [
                        BackendCatalogVoice(
                            id: "Emily.wav",
                            displayName: "Runtime Emily",
                            backendID: BackendProfiles.chatterboxTTS.id,
                            locale: "en",
                            languageCode: "en",
                            traits: ["female"],
                            sourceType: .predefined
                        )
                    ],
                    message: "Partial Chatterbox runtime catalog"
                )
            ]
        )
        let mergedChatterboxVoices = partialChatterboxSettings.voiceOptions(for: BackendProfiles.chatterboxTTS)
        precondition(mergedChatterboxVoices.count == 28)
        precondition(mergedChatterboxVoices.first { $0.id == "Emily.wav" }?.displayName == "Runtime Emily")
    }

    private static func checkKokoroCatalogReport() throws {
        let profile = BackendProfiles.kokoroTTS.applying(
            BackendConnectionSettings(
                connectionKind: .installedDockerImage,
                dockerImage: "ghcr.io/remsky/kokoro-fastapi-cpu:latest",
                serviceBaseURL: "http://127.0.0.1:8880",
                modelID: "tts-1",
                defaultVoice: "af_heart"
            )
        )
        let manager = BackendManager(
            httpRunner: { url in
                switch url.path {
                case "/v1/models":
                    return BackendHTTPResult(
                        statusCode: 200,
                        body: """
                        {"object":"list","data":[{"id":"tts-1","owned_by":"kokoro"},{"id":"tts-1-hd","owned_by":"kokoro"}]}
                        """
                    )
                case "/v1/audio/voices":
                    return BackendHTTPResult(
                        statusCode: 200,
                        body: """
                        {"voices":{"af_heart":{"name":"Heart","language":"en","gender":"female"},"am_adam":{"display_name":"Adam","language":"en","gender":"male"}}}
                        """
                    )
                default:
                    return BackendHTTPResult(statusCode: 404, body: "{}")
                }
            }
        )

        let catalog = manager.catalogReport(for: profile)
        precondition(catalog.models.map(\.id) == ["tts-1", "tts-1-hd"])
        precondition(catalog.voices.map(\.id) == ["af_heart", "am_adam"])
        precondition(catalog.voices.map(\.displayName) == ["Heart", "Adam"])
        precondition(catalog.voices.first?.backendID == BackendProfiles.kokoroTTS.id)
        precondition(catalog.voices.first?.languageCode == "en")
        precondition(catalog.voices.first?.traits.contains("female") == true)
        precondition(catalog.message.contains("Loaded 2 models and 2 voices"))
    }

    private static func checkChatterboxCatalogReport() throws {
        let profile = BackendProfiles.chatterboxTTS.applying(
            BackendConnectionSettings(
                connectionKind: .externalService,
                serviceBaseURL: "http://127.0.0.1:8004",
                healthPath: "/api/model-info",
                generatePath: "/tts",
                modelID: "chatterbox",
                defaultVoice: "Emily.wav"
            )
        )
        let manager = BackendManager(
            httpRunner: { url in
                switch url.path {
                case "/api/model-info":
                    return BackendHTTPResult(
                        statusCode: 200,
                        body: """
                        {"loaded":true,"type":"original","class_name":"ChatterboxTTS","device":"cpu","sample_rate":24000,"turbo_available_in_package":true,"multilingual_available_in_package":true}
                        """
                    )
                case "/get_predefined_voices":
                    return BackendHTTPResult(
                        statusCode: 200,
                        body: """
                        [{"display_name":"Emily","filename":"Emily.wav"},{"display_name":"Michael","filename":"Michael.wav"}]
                        """
                    )
                case "/get_reference_files":
                    return BackendHTTPResult(
                        statusCode: 200,
                        body: """
                        ["Gianna.wav"]
                        """
                    )
                default:
                    return BackendHTTPResult(statusCode: 404, body: "{}")
                }
            }
        )

        let catalog = manager.catalogReport(for: profile)
        precondition(catalog.models.map(\.id) == ["chatterbox-turbo", "chatterbox"])
        precondition(catalog.models.first(where: { $0.id == "chatterbox" })?.isLoaded == true)
        precondition(!catalog.models.contains { $0.id == "chatterbox-multilingual" })
        precondition(catalog.models.first(where: { $0.id == "chatterbox-turbo" })?.configuration["model.repo_id"] == "chatterbox-turbo")
        precondition(catalog.voices.map(\.id).contains("Emily.wav"))
        precondition(catalog.voices.map(\.id).contains("Michael.wav"))
        precondition(catalog.voices.first(where: { $0.id == "Emily.wav" })?.backendID == BackendProfiles.chatterboxTTS.id)
        precondition(catalog.voices.first(where: { $0.id == "Emily.wav" })?.languageCode == "en")
        precondition(catalog.voices.first(where: { $0.id == "Emily.wav" })?.traits.contains("female") == true)
        precondition(catalog.voices.first(where: { $0.id == "Emily.wav" })?.sourceType == .predefined)
        precondition(!catalog.voices.map(\.id).contains("reference:Gianna.wav"))
        precondition(catalog.message.contains("Loaded Chatterbox model state and 2 predefined voices"))
        precondition(catalog.technicalDetails?.contains("Reference voices discovered: 1") == true)
    }


    private static func checkBackendManagerFacadePreservesInjectedRuntimeHooks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchFacadeChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let profile = BackendProfiles.kokoroTTS.applying(
            BackendConnectionSettings(
                connectionKind: .installedDockerImage,
                dockerImage: "kokoro-local",
                containerName: "vibevoice_batch_kokoro_tts",
                serviceBaseURL: "http://127.0.0.1:8880",
                modelID: "tts-1",
                defaultVoice: "af_heart"
            )
        )
        let processSpy = BackendProcessSpy { arguments in
            if arguments.contains("info") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
            }
            if arguments.contains("images") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "kokoro-local\timage-id\t1GB\n")
            }
            if arguments.contains("inspect") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "kokoro image")
            }
            if arguments.contains("pull") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "pulled")
            }
            if arguments.contains("ps") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "vibevoice_batch_kokoro_tts\tkokoro-local\t0.0.0.0:8880->8880/tcp\trunning\n")
            }
            return BackendProcessResult(exitCode: 0, combinedOutput: "")
        }
        let urlSpy = BackendURLSpy()
        let manager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { executable, arguments in
                processSpy.run(executable: executable, arguments: arguments)
            },
            httpRunner: { url in
                urlSpy.record(url.absoluteString)
                if url.path == "/v1/models" {
                    return BackendHTTPResult(statusCode: 200, body: "{\"data\":[{\"id\":\"tts-1\",\"owned_by\":\"kokoro\"}]}")
                }
                if url.path == "/v1/audio/voices" {
                    return BackendHTTPResult(statusCode: 200, body: "{\"voices\":[\"af_heart\"]}")
                }
                return BackendHTTPResult(statusCode: 200, body: "{\"status\":\"ready\"}")
            }
        )

        precondition(manager.dockerRuntimeReport().isRunning)
        precondition(manager.statusSnapshot(for: profile).state == .ready)
        precondition(manager.setupReport(for: profile).isReady)
        precondition(manager.discoveryReport(for: profile).candidates.contains { $0.title == "vibevoice_batch_kokoro_tts" })
        precondition(manager.catalogReport(for: profile).voices.map(\.id) == ["af_heart"])
        precondition(manager.performOperation(.install, for: profile).status == .succeeded)
        precondition(processSpy.calls.contains { $0.contains("pull") && $0.contains("kokoro-local") })
        precondition(urlSpy.urls.contains("http://127.0.0.1:8880/health"))
        precondition(urlSpy.urls.contains("http://127.0.0.1:8880/v1/models"))
        precondition(urlSpy.urls.contains("http://127.0.0.1:8880/v1/audio/voices"))
    }

    private static func checkBackendManagerOperations() throws {
        let profile = BackendProfiles.vibeVoiceTTS
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchOperationChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let missingManager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { nil }
        )
        let missingInstall = missingManager.performOperation(.install, for: profile)
        precondition(missingInstall.status == .failed)
        precondition(missingInstall.message.contains("Docker Desktop"))

        let installSpy = BackendProcessSpy { arguments in
            if arguments.contains("info") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
            }
            if arguments.contains("pull") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "Pulled vibevoice-cpu")
            }
            return BackendProcessResult(exitCode: 0, combinedOutput: "")
        }
        let installManager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { executable, arguments in
                installSpy.run(executable: executable, arguments: arguments)
            }
        )
        let install = installManager.performOperation(.install, for: profile)
        precondition(install.status == .succeeded)
        precondition(installSpy.calls.contains { $0.contains("pull") && $0.contains(AppDefaults.dockerImage) })
        precondition(FileManager.default.fileExists(atPath: root.hfCacheDirectory.path))

        let prepareMissingImage = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { _, arguments in
                if arguments.contains("inspect") {
                    return BackendProcessResult(exitCode: 1, combinedOutput: "No such image")
                }
                return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
            }
        )
        let prepare = prepareMissingImage.performOperation(.prepare, for: profile)
        precondition(prepare.status == .failed)
        precondition(prepare.recoverySuggestion?.contains("Install") == true)

        let stopSpy = BackendProcessSpy { arguments in
            if arguments.contains("ps") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "vibevoice_batch_one\nvibevoice_batch_two\n")
            }
            if arguments.contains("stop") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "stopped")
            }
            return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
        }
        let stopManager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { executable, arguments in
                stopSpy.run(executable: executable, arguments: arguments)
            }
        )
        let stop = stopManager.performOperation(.stop, for: profile)
        precondition(stop.status == .succeeded)
        precondition(stop.message.contains("2"))
        precondition(stopSpy.calls.contains { $0.first == "stop" && $0.contains("vibevoice_batch_one") })

        try FileManager.default.createDirectory(at: root.outputsDirectory, withIntermediateDirectories: true)
        try Data([7, 7, 7]).write(to: root.generatedWAVFile)
        let reset = stopManager.performOperation(.reset, for: profile)
        precondition(reset.status == .succeeded)
        precondition(!FileManager.default.fileExists(atPath: root.generatedWAVFile.path))
        let recoveredFiles = try FileManager.default.contentsOfDirectory(
            at: root.recoveredDirectory,
            includingPropertiesForKeys: nil
        )
        precondition(recoveredFiles.contains { $0.lastPathComponent.contains("backend_reset_input_generated.wav") })

        let usage = stopManager.diskUsageReport()
        precondition(usage.projectRootBytes >= usage.recoveredBytes)

        let kokoroProfile = BackendProfiles.kokoroTTS.applying(
            BackendConnectionSettings(
                connectionKind: .installedDockerImage,
                dockerImage: "ghcr.io/remsky/kokoro-fastapi-cpu:latest",
                containerName: "vibevoice_batch_kokoro_tts",
                serviceBaseURL: "http://127.0.0.1:8880",
                modelID: "tts-1",
                defaultVoice: "af_heart"
            )
        )
        precondition(kokoroProfile.containerName == "vibevoice_batch_kokoro_tts")

        let kokoroInstallSpy = BackendProcessSpy { arguments in
            if arguments.contains("info") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
            }
            if arguments.contains("pull") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "Pulled Kokoro")
            }
            return BackendProcessResult(exitCode: 0, combinedOutput: "")
        }
        let kokoroInstallManager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { executable, arguments in
                kokoroInstallSpy.run(executable: executable, arguments: arguments)
            }
        )
        let kokoroInstall = kokoroInstallManager.performOperation(.install, for: kokoroProfile)
        precondition(kokoroInstall.status == .succeeded)
        precondition(kokoroInstallSpy.calls.contains { $0.contains("pull") && $0.contains("ghcr.io/remsky/kokoro-fastapi-cpu:latest") })

        let kokoroPrepareSpy = BackendProcessSpy { arguments in
            if arguments.contains("info") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
            }
            if arguments.contains("inspect") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "kokoro image")
            }
            if arguments.contains("ps") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "")
            }
            if arguments.contains("run") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "started-kokoro")
            }
            return BackendProcessResult(exitCode: 0, combinedOutput: "")
        }
        let kokoroPrepareManager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { executable, arguments in
                kokoroPrepareSpy.run(executable: executable, arguments: arguments)
            },
            httpRunner: { _ in
                if kokoroPrepareSpy.calls.contains(where: { $0.contains("run") }) {
                    return BackendHTTPResult(statusCode: 200, body: "{\"status\":\"ready\"}")
                }
                return BackendHTTPResult(errorDescription: "Connection refused")
            }
        )
        let kokoroPrepare = kokoroPrepareManager.performOperation(.prepare, for: kokoroProfile)
        precondition(kokoroPrepare.status == .succeeded)
        precondition(kokoroPrepareSpy.calls.contains { call in
            call.contains("run") &&
                call.contains("--name") &&
                call.contains("vibevoice_batch_kokoro_tts") &&
                call.contains("-p") &&
                call.contains("8880:8880")
        })

        let staleKokoroSpy = BackendProcessSpy { arguments in
            if arguments.contains("info") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
            }
            if arguments.contains("inspect") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "kokoro image")
            }
            if arguments.first == "ps" {
                return BackendProcessResult(exitCode: 0, combinedOutput: "vibevoice_batch_kokoro_tts\n")
            }
            if arguments.first == "port" {
                return BackendProcessResult(exitCode: 1, combinedOutput: "no public port '8880/tcp' published")
            }
            if arguments.first == "stop" || arguments.first == "rm" || arguments.first == "run" {
                return BackendProcessResult(exitCode: 0, combinedOutput: arguments.joined(separator: " "))
            }
            return BackendProcessResult(exitCode: 0, combinedOutput: "")
        }
        let staleKokoroManager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { executable, arguments in
                staleKokoroSpy.run(executable: executable, arguments: arguments)
            },
            httpRunner: { _ in
                if staleKokoroSpy.calls.contains(where: { $0.first == "run" }) {
                    return BackendHTTPResult(statusCode: 200, body: "{\"status\":\"ready\"}")
                }
                return BackendHTTPResult(errorDescription: "Connection refused")
            }
        )
        let staleKokoroPrepare = staleKokoroManager.performOperation(.prepare, for: kokoroProfile)
        precondition(staleKokoroPrepare.status == .succeeded)
        precondition(staleKokoroSpy.calls.contains { $0.first == "port" && $0.contains("vibevoice_batch_kokoro_tts") })
        precondition(staleKokoroSpy.calls.contains { $0.first == "stop" && $0.contains("vibevoice_batch_kokoro_tts") })
        precondition(staleKokoroSpy.calls.contains { $0.first == "rm" && $0.contains("vibevoice_batch_kokoro_tts") })
        precondition(staleKokoroSpy.calls.contains { $0.first == "run" && $0.contains("8880:8880") })

        let kokoroStopSpy = BackendProcessSpy { arguments in
            if arguments.contains("info") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
            }
            if arguments.contains("ps") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "vibevoice_batch_kokoro_tts\n")
            }
            if arguments.contains("stop") {
                return BackendProcessResult(exitCode: 0, combinedOutput: "vibevoice_batch_kokoro_tts")
            }
            return BackendProcessResult(exitCode: 0, combinedOutput: "")
        }
        let kokoroStopManager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { executable, arguments in
                kokoroStopSpy.run(executable: executable, arguments: arguments)
            }
        )
        let kokoroStop = kokoroStopManager.performOperation(.stop, for: kokoroProfile)
        precondition(kokoroStop.status == .succeeded)
        precondition(kokoroStopSpy.calls.contains { $0.first == "stop" && $0.contains("vibevoice_batch_kokoro_tts") })
    }

    private static func checkWorkspaceDataModel() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchWorkspaceChecks-\(UUID().uuidString)", isDirectory: true)
        let workspaceStore = WorkspaceFileStore(projectRoot: root)
        let sessionStore = SessionFileStore(projectRoot: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let createdAt = Date(timeIntervalSince1970: 1_718_171_695)
        let project = try workspaceStore.createProject(title: "Novel Narration", now: createdAt)
        precondition(project.status == .draft)
        precondition(project.generationSessionIDs.isEmpty)
        precondition(FileManager.default.fileExists(atPath: root.projectsDirectory.path))

        let legacyProjectJSON = """
        {
          "id": "legacy-project",
          "title": "Legacy",
          "created_at": "2024-06-12T03:14:55Z",
          "updated_at": "2024-06-12T03:14:55Z",
          "status": "draft",
          "script_ids": [],
          "batch_ids": [],
          "notes": ""
        }
        """
        let legacyProject = try JSONCodecs.metadataDecoder.decode(NarrationProject.self, from: Data(legacyProjectJSON.utf8))
        precondition(legacyProject.generationSessionIDs.isEmpty)

        let script = try workspaceStore.createScript(
            projectID: project.id,
            title: "Chapter One",
            text: "The first chapter begins here.",
            voice: "en-carter_man",
            settings: GenerationSettings(cfgScale: "1.8", ddpmInferenceSteps: 8),
            now: createdAt
        )
        precondition(script.projectID == project.id)
        precondition(script.inputWordCount == 5)
        let projectAfterScript = try workspaceStore.loadProject(id: project.id)
        precondition(projectAfterScript.scriptIDs == [script.id])

        let collidingScript = try workspaceStore.createScript(
            projectID: project.id,
            title: "Chapter One",
            text: "A different editable source script.",
            now: createdAt
        )
        precondition(collidingScript.id != script.id)
        precondition(collidingScript.id.hasSuffix("_2"))

        let batch = try workspaceStore.createBatch(
            projectID: project.id,
            title: "Morning Batch",
            scriptIDs: [script.id, collidingScript.id],
            now: createdAt
        )
        precondition(batch.items.count == 2)
        precondition(batch.status == .queued)
        let projectAfterBatch = try workspaceStore.loadProject(id: project.id)
        precondition(projectAfterBatch.batchIDs == [batch.id])

        let importedChunks = ScriptChunker.chunks(
            from: "First imported paragraph.\n\n---\n\nSecond imported paragraph.",
            baseTitle: "Imported File"
        )
        precondition(importedChunks.count == 2)
        let timestampedChunks = ScriptChunker.chunks(
            from: """
            # Header

            **[COLD OPEN — not timestamped]**

            Drop this text.

            **[~9:30 — exiting Candiac toward St-Philippe]**

            Keep this narration.

            **[~11:00 — final stretch before the trash truck]**

            Keep this narration too.

            ---

            *[END — not narration]*
            """,
            baseTitle: "Timestamped File"
        )
        precondition(timestampedChunks.count == 2)
        precondition(timestampedChunks[0].title.contains("~9:30"))
        precondition(timestampedChunks[0].text == "Keep this narration.")
        precondition(!timestampedChunks.map(\.text).joined().contains("COLD OPEN"))
        let imported = try workspaceStore.createScriptBatch(
            title: "Imported File",
            chunks: importedChunks,
            backendID: BackendProfiles.kokoroTTS.id,
            modelID: "kokoro",
            voice: "af_sky",
            settings: GenerationSettings(cfgScale: "1.0", ddpmInferenceSteps: 4),
            now: createdAt.addingTimeInterval(20)
        )
        precondition(imported.scripts.count == 2)
        precondition(imported.scripts.first?.defaultBackendID == BackendProfiles.kokoroTTS.id)
        precondition(imported.batch.items.count == 2)
        try workspaceStore.deleteUncompletedBatch(id: imported.batch.id)
        precondition(!FileManager.default.fileExists(atPath: root.batchesDirectory.appendingPathComponent("\(imported.batch.id).json").path))

        let firstRun = try sessionStore.createDraft(
            text: script.text,
            voice: script.defaultVoice,
            cfgScale: script.defaultSettings.cfgScale,
            ddpmInferenceSteps: script.defaultSettings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps,
            now: createdAt
        )
        let secondRun = try sessionStore.createDraft(
            text: script.text,
            voice: script.defaultVoice,
            cfgScale: script.defaultSettings.cfgScale,
            ddpmInferenceSteps: script.defaultSettings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps,
            now: createdAt
        )
        precondition(firstRun.id != secondRun.id)

        let linkedOnce = try workspaceStore.appendGenerationSession(firstRun.id, toScript: script.id, now: createdAt)
        let linkedTwice = try workspaceStore.appendGenerationSession(secondRun.id, toScript: script.id, now: createdAt)
        let linkedDuplicate = try workspaceStore.appendGenerationSession(firstRun.id, toScript: script.id, now: createdAt)
        precondition(linkedOnce.generationSessionIDs == [firstRun.id])
        precondition(linkedTwice.generationSessionIDs == [firstRun.id, secondRun.id])
        precondition(linkedDuplicate.generationSessionIDs == [firstRun.id, secondRun.id])

        let filedProject = try workspaceStore.attachGenerationSessions([firstRun.id, secondRun.id, firstRun.id], toProject: project.id, now: createdAt)
        precondition(filedProject.generationSessionIDs == [firstRun.id, secondRun.id])
        let filedAgain = try workspaceStore.attachGenerationSessions([secondRun.id], toProject: project.id, now: createdAt)
        precondition(filedAgain.generationSessionIDs == [firstRun.id, secondRun.id])
        let beforeDuplicateFiling = try workspaceStore.loadProject(id: project.id)
        let duplicateFiling = try workspaceStore.attachGenerationSessions(
            [secondRun.id, firstRun.id],
            toProject: project.id,
            now: createdAt.addingTimeInterval(60)
        )
        precondition(duplicateFiling.generationSessionIDs == beforeDuplicateFiling.generationSessionIDs)
        precondition(duplicateFiling.updatedAt == beforeDuplicateFiling.updatedAt)
        precondition(FileManager.default.fileExists(atPath: firstRun.folderURL.path))
        precondition(FileManager.default.fileExists(atPath: secondRun.folderURL.path))

        let updatedBatch = try workspaceStore.recordBatchItemGeneration(
            batchID: batch.id,
            itemID: batch.items[0].id,
            sessionID: firstRun.id,
            status: .completed,
            now: createdAt
        )
        precondition(updatedBatch.items[0].generationSessionID == firstRun.id)
        precondition(updatedBatch.status == .queued)

        let updatedScript = try workspaceStore.updateScriptText(
            id: script.id,
            text: "The source script has changed for a future run.",
            now: createdAt.addingTimeInterval(10)
        )
        precondition(updatedScript.text.contains("future run"))
        let preservedHistoryRecord = try sessionStore.loadRecord(folderURL: firstRun.folderURL)
        precondition(preservedHistoryRecord.inputText == "The first chapter begins here.")

        let snapshot = try workspaceStore.loadSnapshot()
        precondition(snapshot.projects.count == 1)
        precondition(snapshot.scripts.count == 2)
        precondition(snapshot.batches.count == 1)

        do {
            _ = try workspaceStore.createScript(projectID: "missing-project", title: "Orphan", text: "Nope")
            throw CheckError("Expected missing project to fail")
        } catch is CocoaError {
            let scriptCount = try workspaceStore.loadScripts().count
            precondition(scriptCount == 2)
        }

        do {
            _ = try workspaceStore.createBatch(projectID: project.id, title: "Broken Batch", scriptIDs: ["missing-script"])
            throw CheckError("Expected missing script to fail")
        } catch is CocoaError {
            let batchCount = try workspaceStore.loadBatches().count
            precondition(batchCount == 1)
        }
    }

    private static func checkWorkspaceStoreCleanupInvariants() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchWorkspaceCleanupChecks-\(UUID().uuidString)", isDirectory: true)
        let workspaceStore = WorkspaceFileStore(projectRoot: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let older = Date(timeIntervalSince1970: 1_718_171_695)
        let newer = older.addingTimeInterval(60)

        let alphaProject = try workspaceStore.createProject(title: "Alpha Project", now: older)
        let betaProject = try workspaceStore.createProject(title: "Beta Project", now: older)
        let newestProject = try workspaceStore.createProject(title: "Newest Project", now: newer)
        precondition(FileManager.default.fileExists(atPath: root.projectsDirectory.appendingPathComponent("\(alphaProject.id).json").path))
        let projectIDs = try workspaceStore.loadProjects().map(\.id)
        precondition(projectIDs == [newestProject.id, betaProject.id, alphaProject.id])

        let duplicateProject = try workspaceStore.createProject(title: "Alpha Project", now: older)
        precondition(duplicateProject.id == "\(alphaProject.id)_2")
        precondition(FileManager.default.fileExists(atPath: root.projectsDirectory.appendingPathComponent("\(duplicateProject.id).json").path))

        let alphaScript = try workspaceStore.createScript(title: "Alpha Script", text: "One.", now: older)
        let betaScript = try workspaceStore.createScript(title: "Beta Script", text: "Two.", now: older)
        let newestScript = try workspaceStore.createScript(title: "Newest Script", text: "Three.", now: newer)
        let scriptIDs = try workspaceStore.loadScripts().map(\.id)
        precondition(scriptIDs.prefix(3) == [newestScript.id, betaScript.id, alphaScript.id])

        let alphaBatch = try workspaceStore.createBatch(title: "Alpha Batch", scriptIDs: [alphaScript.id], now: older)
        let betaBatch = try workspaceStore.createBatch(title: "Beta Batch", scriptIDs: [betaScript.id], now: older)
        let newestBatch = try workspaceStore.createBatch(title: "Newest Batch", scriptIDs: [newestScript.id], now: newer)
        let batchIDs = try workspaceStore.loadBatches().map(\.id)
        precondition(batchIDs == [newestBatch.id, betaBatch.id, alphaBatch.id])

        let voiceOne = try workspaceStore.createVoicePreset(title: "Reusable Voice", voiceID: "en-carter_man", now: older)
        let voiceTwo = try workspaceStore.createVoicePreset(title: "Reusable Voice", voiceID: "en-carter_man", now: older)
        precondition(voiceTwo.id == "\(voiceOne.id)_2")
        precondition(FileManager.default.fileExists(atPath: root.voicePresetsDirectory.appendingPathComponent("\(voiceTwo.id).json").path))

        let presetOne = try workspaceStore.createGenerationPreset(
            title: "Reusable Generation",
            voiceID: voiceOne.voiceID,
            settings: GenerationSettings(cfgScale: "1.8", ddpmInferenceSteps: 8),
            outputFormat: .wav,
            now: older
        )
        let presetTwo = try workspaceStore.createGenerationPreset(
            title: "Reusable Generation",
            voiceID: voiceOne.voiceID,
            settings: GenerationSettings(cfgScale: "1.8", ddpmInferenceSteps: 8),
            outputFormat: .wav,
            now: older
        )
        precondition(presetTwo.id == "\(presetOne.id)_2")
        precondition(FileManager.default.fileExists(atPath: root.generationPresetsDirectory.appendingPathComponent("\(presetTwo.id).json").path))

        let builtIns = try workspaceStore.loadSnapshot()
        let builtInVoice = try unwrap(
            builtIns.voicePresets.first(where: \.isBuiltIn),
            "Expected built-in voice preset"
        )
        do {
            try workspaceStore.deleteVoicePreset(id: builtInVoice.id)
            throw CheckError("Expected protected voice preset deletion to fail")
        } catch let error as WorkspaceError {
            guard case .cannotDeleteBuiltInPreset(.voice, builtInVoice.id, _) = error else {
                throw CheckError("Expected voice protection error")
            }
        }

        let filedOnce = try workspaceStore.attachGenerationSessions(["session-a", "session-b", "session-a"], toProject: alphaProject.id, now: newer)
        precondition(filedOnce.generationSessionIDs == ["session-a", "session-b"])
        let beforeDuplicateFiling = try workspaceStore.loadProject(id: alphaProject.id)
        let filedAgain = try workspaceStore.attachGenerationSessions(["session-b", "session-a"], toProject: alphaProject.id, now: newer.addingTimeInterval(60))
        precondition(filedAgain.generationSessionIDs == beforeDuplicateFiling.generationSessionIDs)
        precondition(filedAgain.updatedAt == beforeDuplicateFiling.updatedAt)
    }

    private static func checkWorkspacePresets() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchPresetChecks-\(UUID().uuidString)", isDirectory: true)
        let workspaceStore = WorkspaceFileStore(projectRoot: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let initial = try workspaceStore.loadSnapshot()
        precondition(initial.voicePresets.contains { $0.id == "builtin_voice_\(AppDefaults.defaultVoice)" })
        precondition(initial.generationPresets.contains { $0.id == "builtin_generation_balanced_narration" })
        precondition(FileManager.default.fileExists(atPath: root.voicePresetsDirectory.path))
        precondition(FileManager.default.fileExists(atPath: root.generationPresetsDirectory.path))

        let createdAt = Date(timeIntervalSince1970: 1_718_171_695)
        let voicePreset = try workspaceStore.createVoicePreset(
            title: "Warm Narrator",
            voiceID: "en-carter_man",
            traits: ["warm", "narration"],
            now: createdAt
        )
        precondition(!voicePreset.isBuiltIn)
        precondition(voicePreset.backendID == BackendProfiles.vibeVoiceTTS.id)
        precondition(voicePreset.modelID == AppDefaults.modelPath)
        precondition(FileManager.default.fileExists(atPath: root.voicePresetsDirectory.appendingPathComponent("\(voicePreset.id).json").path))

        let generationPreset = try workspaceStore.createGenerationPreset(
            title: "Long Form Warm",
            voicePresetID: voicePreset.id,
            voiceID: voicePreset.voiceID,
            settings: GenerationSettings(
                cfgScale: "1.9",
                ddpmInferenceSteps: 9,
                extraParameters: [
                    "temperature": "1.15",
                    "exaggeration": "1.4",
                    "split_text": "false"
                ]
            ),
            outputFormat: .wav,
            now: createdAt
        )
        precondition(!generationPreset.isBuiltIn)
        precondition(generationPreset.voicePresetID == voicePreset.id)
        precondition(generationPreset.settings.cfgScale == "1.9")
        precondition(generationPreset.settings.ddpmInferenceSteps == 9)
        precondition(generationPreset.settings.extraParameters["temperature"] == "1.15")
        precondition(generationPreset.settings.extraParameters["split_text"] == "false")
        precondition(FileManager.default.fileExists(atPath: root.generationPresetsDirectory.appendingPathComponent("\(generationPreset.id).json").path))

        let reloaded = try workspaceStore.loadSnapshot()
        precondition(reloaded.voicePresets.contains { $0.id == voicePreset.id })
        precondition(reloaded.generationPresets.contains { $0.id == generationPreset.id })

        let voiceCopy = try workspaceStore.duplicateVoicePreset(id: voicePreset.id, now: createdAt)
        precondition(voiceCopy.id != voicePreset.id)
        precondition(voiceCopy.voiceID == voicePreset.voiceID)
        precondition(voiceCopy.traits == voicePreset.traits)
        precondition(FileManager.default.fileExists(atPath: root.voicePresetsDirectory.appendingPathComponent("\(voiceCopy.id).json").path))

        let generationCopy = try workspaceStore.duplicateGenerationPreset(id: generationPreset.id, now: createdAt)
        precondition(generationCopy.id != generationPreset.id)
        precondition(generationCopy.voiceID == generationPreset.voiceID)
        precondition(generationCopy.settings == generationPreset.settings)
        precondition(FileManager.default.fileExists(atPath: root.generationPresetsDirectory.appendingPathComponent("\(generationCopy.id).json").path))

        try workspaceStore.deleteVoicePreset(id: voiceCopy.id)
        try workspaceStore.deleteGenerationPreset(id: generationCopy.id)
        precondition(!FileManager.default.fileExists(atPath: root.voicePresetsDirectory.appendingPathComponent("\(voiceCopy.id).json").path))
        precondition(!FileManager.default.fileExists(atPath: root.generationPresetsDirectory.appendingPathComponent("\(generationCopy.id).json").path))
    }

    private static func checkAppSpecificErrors() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchErrorChecks-\(UUID().uuidString)", isDirectory: true)
        let workspaceStore = WorkspaceFileStore(projectRoot: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = try workspaceStore.loadSnapshot()
        let builtInVoice = try unwrap(
            snapshot.voicePresets.first { $0.isBuiltIn },
            "Expected a built-in voice preset"
        )
        let builtInGeneration = try unwrap(
            snapshot.generationPresets.first { $0.isBuiltIn },
            "Expected a built-in generation preset"
        )

        do {
            try workspaceStore.deleteVoicePreset(id: builtInVoice.id)
            throw CheckError("Expected built-in voice deletion to fail")
        } catch let error as WorkspaceError {
            guard case .cannotDeleteBuiltInPreset(let kind, let id, let displayName) = error else {
                throw CheckError("Expected protected voice preset error")
            }
            precondition(kind == .voice)
            precondition(id == builtInVoice.id)
            precondition(displayName == builtInVoice.displayName)
            precondition(error.localizedDescription == "Built-in voice cannot be deleted")
            precondition(error.recoverySuggestion == "Duplicate it first if you want a custom copy.")
            precondition(error.technicalDetails?.contains(builtInVoice.id) == true)
            let message = AppErrorPresenter.message(for: error, includeTechnicalDetails: true)
            precondition(message.contains("Built-in voice cannot be deleted"))
            precondition(message.contains("Duplicate it first"))
            precondition(message.contains("Details:"))
        }

        do {
            try workspaceStore.deleteGenerationPreset(id: builtInGeneration.id)
            throw CheckError("Expected built-in generation preset deletion to fail")
        } catch let error as WorkspaceError {
            guard case .cannotDeleteBuiltInPreset(let kind, let id, let displayName) = error else {
                throw CheckError("Expected protected generation preset error")
            }
            precondition(kind == .generation)
            precondition(id == builtInGeneration.id)
            precondition(displayName == builtInGeneration.displayName)
            precondition(error.localizedDescription == "Built-in generation preset cannot be deleted")
        }

        do {
            let batch = try workspaceStore.createBatch(title: "Empty Batch", scriptIDs: [])
            _ = try workspaceStore.recordBatchItemGeneration(
                batchID: batch.id,
                itemID: "missing-item",
                sessionID: "session",
                status: .failed
            )
            throw CheckError("Expected missing batch item to fail")
        } catch let error as WorkspaceError {
            guard case .missingBatchItem(let batchID, let itemID) = error else {
                throw CheckError("Expected missing batch item error")
            }
            precondition(!batchID.isEmpty)
            precondition(itemID == "missing-item")
            precondition(error.localizedDescription == "Batch item not found")
        }

        let backendError = BackendError.operationUnavailable(
            GenerationErrorRecord(
                title: "Backend action failed",
                explanation: "The selected backend action could not be completed.",
                recoverySuggestion: "Check backend status, then try again.",
                technicalDetails: "backend=kokoro"
            )
        )
        precondition(backendError.localizedDescription == "Backend action failed")
        let backendMessage = AppErrorPresenter.message(for: backendError, includeTechnicalDetails: true)
        precondition(backendMessage.contains("The selected backend action could not be completed."))
        precondition(backendMessage.contains("Check backend status"))
        precondition(backendMessage.contains("backend=kokoro"))
    }

    private static func checkAppSettingsNormalizeInvalidValues() throws {
        let settings = AppSettings(
            defaultBackendID: "missing",
            defaultModelID: "",
            defaultVoice: "missing",
            defaultCFGScale: "9.9",
            defaultDDPMInferenceSteps: 999,
            outputFolderPath: "",
            exportFormat: .mp3
        )
        let invalidResult = settings.normalizationResult()
        let normalized = invalidResult.settings
        precondition(invalidResult.didRecover)
        precondition(invalidResult.needsPersistence)
        precondition(invalidResult.recoveryNotes.contains { $0.reason == .invalidBackend && $0.field == "defaultBackendID" })
        precondition(invalidResult.recoveryNotes.contains { $0.reason == .invalidModel && $0.field == "defaultModelID" })
        precondition(invalidResult.recoveryNotes.contains { $0.reason == .invalidVoice && $0.field == "defaultVoice" })
        precondition(invalidResult.recoveryNotes.contains { $0.reason == .invalidCFGScale && $0.field == "defaultCFGScale" })
        precondition(invalidResult.recoveryNotes.contains { $0.reason == .invalidDDPMInferenceSteps && $0.field == "defaultDDPMInferenceSteps" })
        precondition(invalidResult.recoveryNotes.contains { $0.reason == .emptyOutputFolder && $0.field == "outputFolderPath" })
        precondition(invalidResult.recoveryNotes.contains { $0.reason == .unsupportedExportFormat && $0.field == "exportFormat" })
        precondition(invalidResult.recoverySummary?.contains("default history folder") == true)
        precondition(normalized.defaultBackendID == BackendProfiles.vibeVoiceTTS.id)
        precondition(normalized.defaultModelID == AppDefaults.modelPath)
        precondition(normalized.defaultVoice == AppDefaults.defaultVoice)
        precondition(normalized.defaultCFGScale == AppDefaults.defaultCFGScale)
        precondition(normalized.defaultDDPMInferenceSteps == AppDefaults.defaultDDPMInferenceSteps)
        precondition(normalized.outputFolderPath == AppDefaults.projectRoot.historyDirectory.path)
        precondition(normalized.exportFormat == .wav)

        let kokoroResult = AppSettings(
            defaultBackendID: BackendProfiles.kokoroTTS.id,
            defaultModelID: "wrong-model",
            exportFormat: .mp3
        ).normalizationResult()
        let kokoroSettings = kokoroResult.settings
        precondition(kokoroResult.recoveryNotes.contains { $0.reason == .invalidModel })
        precondition(kokoroResult.recoveryNotes.contains { $0.reason == .unsupportedExportFormat })
        precondition(kokoroSettings.defaultBackendID == BackendProfiles.kokoroTTS.id)
        precondition(kokoroSettings.defaultModelID == "tts-1")
        precondition(kokoroSettings.exportFormat == .wav)

        let configuredKokoroResult = AppSettings(
            defaultBackendID: BackendProfiles.kokoroTTS.id,
            defaultModelID: "kokoro/custom",
            defaultVoice: "af_heart",
            backendConnections: BackendConnectionSettings.defaultConfigurations.merging([
                BackendProfiles.kokoroTTS.id: BackendConnectionSettings(
                    connectionKind: .installedDockerImage,
                    dockerImage: "kokoro-local",
                    serviceBaseURL: "http://127.0.0.1:8880",
                    healthPath: "/health",
                    modelID: "kokoro/custom",
                    defaultVoice: "af_heart"
                )
            ]) { _, new in new }
        ).normalizationResult()
        let configuredKokoro = configuredKokoroResult.settings
        precondition(!configuredKokoroResult.didRecover)
        let kokoroProfile = configuredKokoro.selectedBackendProfile
        precondition(kokoroProfile.runtime == .docker)
        precondition(kokoroProfile.installMethod == .manual)
        precondition(kokoroProfile.dockerImage == "kokoro-local")
        precondition(kokoroProfile.healthCheckURL?.absoluteString == "http://127.0.0.1:8880/health")
        precondition(configuredKokoro.defaultModelID == "kokoro/custom")

        let catalogBackedKokoroResult = AppSettings(
            defaultBackendID: BackendProfiles.kokoroTTS.id,
            defaultModelID: "missing",
            defaultVoice: "missing",
            backendConnections: [
                BackendProfiles.kokoroTTS.id: BackendConnectionSettings(
                    connectionKind: .installedDockerImage,
                    dockerImage: "kokoro-local",
                    serviceBaseURL: "http://127.0.0.1:8880",
                    modelID: "tts-1",
                    defaultVoice: "af_heart"
                )
            ],
            backendCatalogs: [
                BackendProfiles.kokoroTTS.id: BackendCatalogReport(
                    profileID: BackendProfiles.kokoroTTS.id,
                    models: [
                        BackendCatalogModel(id: "tts-1"),
                        BackendCatalogModel(id: "tts-1-hd")
                    ],
                    voices: [
                        BackendCatalogVoice(id: "af_heart"),
                        BackendCatalogVoice(id: "am_adam")
                    ],
                    message: "Loaded"
                )
            ]
        ).normalizationResult()
        let catalogBackedKokoro = catalogBackedKokoroResult.settings
        precondition(catalogBackedKokoroResult.recoveryNotes.contains { $0.reason == .invalidModel })
        precondition(catalogBackedKokoroResult.recoveryNotes.contains { $0.reason == .invalidVoice })
        precondition(catalogBackedKokoro.defaultModelID == "tts-1")
        precondition(catalogBackedKokoro.defaultVoice == "af_heart")

        let chatterboxResult = AppSettings(
            defaultBackendID: BackendProfiles.chatterboxTTS.id,
            defaultModelID: "missing",
            defaultVoice: "",
            backendCatalogs: [
                BackendProfiles.chatterboxTTS.id: BackendCatalogReport(
                    profileID: BackendProfiles.chatterboxTTS.id,
                    models: ChatterboxModelCatalog.catalogModels(loadedModelID: ChatterboxModelCatalog.turboID),
                    voices: [
                        BackendCatalogVoice(id: "Emily.wav", displayName: "Emily"),
                        BackendCatalogVoice(id: "reference:Gianna.wav", displayName: "Gianna (Reference)")
                    ],
                    message: "Loaded"
                )
            ],
            chatterboxTemperature: 9.0,
            chatterboxExaggeration: -1.0,
            chatterboxCFGWeight: 3.0,
            chatterboxSeed: -42,
            chatterboxSpeedFactor: 0.01,
            chatterboxLanguage: "",
            chatterboxChunkSize: 999
        ).normalizationResult()
        let chatterboxSettings = chatterboxResult.settings
        precondition(chatterboxResult.recoveryNotes.contains { $0.reason == .invalidModel })
        precondition(chatterboxResult.recoveryNotes.contains { $0.reason == .invalidVoice })
        precondition(chatterboxResult.recoveryNotes.contains { $0.reason == .invalidChatterboxSetting })
        precondition(chatterboxSettings.defaultModelID == ChatterboxModelCatalog.turboID)
        precondition(chatterboxSettings.defaultVoice == "Emily.wav")
        precondition(chatterboxSettings.chatterboxTemperature == 2.0)
        precondition(chatterboxSettings.chatterboxExaggeration == 0.0)
        precondition(chatterboxSettings.chatterboxCFGWeight == 2.0)
        precondition(chatterboxSettings.chatterboxSeed == 0)
        precondition(chatterboxSettings.chatterboxSpeedFactor == 0.25)
        precondition(chatterboxSettings.chatterboxLanguage == "en")
        precondition(chatterboxSettings.chatterboxChunkSize == 500)

        let chatterboxFallbackResult = AppSettings(
            defaultBackendID: BackendProfiles.chatterboxTTS.id,
            defaultModelID: "chatterbox",
            defaultVoice: AppDefaults.defaultVoice
        ).normalizationResult()
        let chatterboxFallback = chatterboxFallbackResult.settings
        precondition(chatterboxFallback.voiceOptions(for: chatterboxFallback.selectedBackendProfile).count == 28)
        precondition(chatterboxFallback.defaultVoice == "Emily.wav")
        precondition(chatterboxFallbackResult.recoveryNotes.contains { $0.reason == .invalidVoice })

        let multilingualResult = AppSettings(
            defaultBackendID: BackendProfiles.chatterboxTTS.id,
            defaultModelID: ChatterboxModelCatalog.multilingualID,
            defaultVoice: "Emily.wav",
            chatterboxLanguage: "fr"
        ).normalizationResult()
        let multilingualSettings = multilingualResult.settings
        precondition(multilingualResult.recoveryNotes.contains { $0.reason == .invalidModel })
        precondition(multilingualResult.recoveryNotes.contains { $0.reason == .invalidChatterboxSetting })
        precondition(multilingualSettings.defaultModelID == ChatterboxModelCatalog.turboID)
        precondition(multilingualSettings.chatterboxLanguage == "en")
        precondition(multilingualSettings.generationExtraParameters(for: multilingualSettings.selectedBackendProfile)["language"] == "en")
        precondition(multilingualSettings.generationExtraParameters(for: multilingualSettings.selectedBackendProfile)["model_repo_id"] == ChatterboxModelCatalog.turboID)

        var restoredChatterbox = AppSettings(defaultBackendID: BackendProfiles.chatterboxTTS.id)
        restoredChatterbox.applyGenerationExtraParameters(
            [
                "temperature": "1.25",
                "exaggeration": "1.55",
                "cfg_weight": "0.85",
                "seed": "42",
                "speed_factor": "1.10",
                "language": "EN",
                "split_text": "false",
                "chunk_size": "180"
            ],
            for: BackendProfiles.chatterboxTTS
        )
        precondition(restoredChatterbox.chatterboxTemperature == 1.25)
        precondition(restoredChatterbox.chatterboxExaggeration == 1.55)
        precondition(restoredChatterbox.chatterboxCFGWeight == 0.85)
        precondition(restoredChatterbox.chatterboxSeed == 42)
        precondition(restoredChatterbox.chatterboxSpeedFactor == 1.10)
        precondition(restoredChatterbox.chatterboxLanguage == "en")
        precondition(restoredChatterbox.chatterboxSplitText == false)
        precondition(restoredChatterbox.chatterboxChunkSize == 180)

        let validResult = AppSettings.defaults.normalizationResult()
        precondition(!validResult.didRecover)
        precondition(validResult.settings.schemaVersion == AppSettingsKeys.currentSchemaVersion)

        let futureResult = AppSettings(schemaVersion: AppSettingsKeys.currentSchemaVersion + 100).normalizationResult()
        precondition(futureResult.settings.schemaVersion == AppSettingsKeys.currentSchemaVersion)
        precondition(futureResult.recoveryNotes.contains { $0.reason == .futureSchema && $0.field == "schemaVersion" })

        let legacyData = Data(
            """
            {
              "defaultBackendID": "missing",
              "defaultModelID": "",
              "defaultVoice": "missing",
              "defaultCFGScale": "9.9",
              "defaultDDPMInferenceSteps": 999,
              "outputFolderPath": "",
              "exportFormat": "mp3",
              "showAdvancedGenerationControls": true,
              "refreshBackendStatusOnLaunch": true,
              "hasCompletedSetupAssistant": false,
              "setupMode": "simple"
            }
            """.utf8
        )
        let legacyResult = AppSettings.loadResult(from: legacyData)
        precondition(legacyResult.settings.schemaVersion == AppSettingsKeys.currentSchemaVersion)
        precondition(legacyResult.settings.defaultBackendID == BackendProfiles.vibeVoiceTTS.id)
        precondition(legacyResult.recoveryNotes.contains { $0.reason == .schemaMigrated && $0.field == "schemaVersion" })
        precondition(legacyResult.recoveryNotes.contains { $0.reason == .missingBackendConnection })
        precondition(legacyResult.recoveryNotes.contains { $0.reason == .invalidBackend })

        let corruptResult = AppSettings.loadResult(from: Data("{".utf8))
        precondition(corruptResult.settings == .defaults)
        precondition(corruptResult.recoveryNotes == [
            AppSettingsRecoveryNote(
                reason: .decodeFailed,
                field: "settings",
                message: "Saved settings could not be read, so default settings were restored.",
                technicalDetails: corruptResult.recoveryNotes.first?.technicalDetails
            )
        ])
        precondition(corruptResult.recoveryNotes.first?.technicalDetails?.isEmpty == false)
    }

    private static func checkDockerShimDocumentation() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let dockerfile = try String(contentsOf: root.appendingPathComponent("Dockerfile"), encoding: .utf8)
        let backends = try String(contentsOf: root.appendingPathComponent("BACKENDS.md"), encoding: .utf8)
        let packaging = try String(contentsOf: root.appendingPathComponent("PACKAGING.md"), encoding: .utf8)

        precondition(dockerfile.contains("Compatibility shim for the current VibeVoice voice-preset loader"))
        precondition(dockerfile.contains("weights_only=False"))
        precondition(dockerfile.contains("Remove this shim once upstream VibeVoice"))
        precondition(backends.contains("VibeVoice Docker Compatibility Shim"))
        precondition(backends.contains("Risk: `weights_only=False`"))
        precondition(backends.contains("Removal condition"))
        precondition(packaging.contains("Backend Image Compatibility Notes"))
        precondition(packaging.contains("do not hide this workaround"))
    }

    private static func checkAssistantViewDecomposition() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let views = root.appendingPathComponent("Sources/VibeVoiceBatch/Views", isDirectory: true)
        let coordinator = views.appendingPathComponent("BackendSetupAssistantView.swift")
        let coordinatorText = try String(contentsOf: coordinator, encoding: .utf8)
        let coordinatorLineCount = coordinatorText.split(separator: "\n", omittingEmptySubsequences: false).count

        precondition(coordinatorLineCount < 500)
        precondition(coordinatorText.contains("struct BackendSetupAssistantView: View"))
        precondition(!coordinatorText.contains("struct BackendInstallSetupPane"))
        precondition(!coordinatorText.contains("struct ModelsVoicesSetupPane"))
        precondition(!coordinatorText.contains("struct TestVoiceSetupPane"))

        let expectedFiles = [
            "BackendSetupAssistantChrome.swift": "struct AssistantStepRail: View",
            "BackendSetupAssistantWelcomeChecks.swift": "struct WelcomeSetupPane: View",
            "BackendSetupAssistantBackendStep.swift": "struct BackendInstallSetupPane: View",
            "BackendSetupAssistantModelsStep.swift": "struct ModelsVoicesSetupPane: View",
            "BackendSetupAssistantTestStep.swift": "struct TestVoiceSetupPane: View",
        ]

        for (fileName, requiredType) in expectedFiles {
            let fileURL = views.appendingPathComponent(fileName)
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            precondition(text.contains(requiredType))
            precondition(text.contains("import SwiftUI"))
            precondition(text.split(separator: "\n", omittingEmptySubsequences: false).count < 900)
        }
    }

    private static func checkAppStoreResponsibilitySplit() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let appStoreURL = root.appendingPathComponent("Sources/VibeVoiceBatch/Stores/AppStore.swift")
        let appStore = try String(contentsOf: appStoreURL, encoding: .utf8)
        let appStoreLineCount = appStore.split(separator: "\n", omittingEmptySubsequences: false).count

        precondition(appStoreLineCount < 1_000)
        precondition(appStore.contains("final class AppStore: ObservableObject"))
        precondition(!appStore.contains("AVAudioPlayerDelegate"))
        precondition(!appStore.contains("AVAudioPlayer(contentsOf:"))
        precondition(!appStore.contains("NSSharingServicePicker"))
        precondition(!appStore.contains("NSPasteboard.general"))
        precondition(!appStore.contains("GenerationOutputParser"))
        precondition(!appStore.contains("queuedJobPayloads"))
        precondition(!appStore.contains("liveLogBySessionID"))

        let coordinators = root.appendingPathComponent("Sources/VibeVoiceBatch/Coordinators", isDirectory: true)
        let expectedTypes = [
            "AppAudioPlaybackCoordinator.swift": "final class AppAudioPlaybackCoordinator",
            "AppBackendStatusCoordinator.swift": "final class AppBackendStatusCoordinator",
            "AppGenerationProgressCoordinator.swift": "final class AppGenerationProgressCoordinator",
            "AppGenerationQueueCoordinator.swift": "final class AppGenerationQueueCoordinator",
            "AppOutputActionCoordinator.swift": "struct AppOutputActionCoordinator",
        ]

        for (fileName, requiredType) in expectedTypes {
            let text = try String(
                contentsOf: coordinators.appendingPathComponent(fileName),
                encoding: .utf8
            )
            precondition(text.contains(requiredType))
        }
    }

    private static func checkPostRefactorUXPolish() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let views = root.appendingPathComponent("Sources/VibeVoiceBatch/Views", isDirectory: true)
        let sidebar = try String(contentsOf: views.appendingPathComponent("SidebarView.swift"), encoding: .utf8)
        let inspector = try String(contentsOf: views.appendingPathComponent("InspectorPanelView.swift"), encoding: .utf8)
        let status = try String(contentsOf: views.appendingPathComponent("BackendStatusView.swift"), encoding: .utf8)
        let outputs = try String(contentsOf: views.appendingPathComponent("OutputBrowserView.swift"), encoding: .utf8)
        let editor = try String(contentsOf: views.appendingPathComponent("EditorView.swift"), encoding: .utf8)
        let content = try String(contentsOf: views.appendingPathComponent("ContentView.swift"), encoding: .utf8)
        let assistantWelcome = try String(contentsOf: views.appendingPathComponent("BackendSetupAssistantWelcomeChecks.swift"), encoding: .utf8)
        let settings = try String(contentsOf: views.appendingPathComponent("SettingsView.swift"), encoding: .utf8)
        let assistantModels = try String(contentsOf: views.appendingPathComponent("BackendSetupAssistantModelsStep.swift"), encoding: .utf8)
        let workspaceSections = try String(contentsOf: views.appendingPathComponent("WorkspaceSectionViews.swift"), encoding: .utf8)
        let projectRebatchControls = try String(contentsOf: views.appendingPathComponent("ProjectRebatchControls.swift"), encoding: .utf8)
        let voiceDisplay = try String(contentsOf: views.appendingPathComponent("VoiceDisplayView.swift"), encoding: .utf8)
        let scriptImportSheet = try String(contentsOf: views.appendingPathComponent("ScriptImportSheet.swift"), encoding: .utf8)
        let app = try String(contentsOf: root.appendingPathComponent("Sources/VibeVoiceBatch/App/VibeVoiceBatchApp.swift"), encoding: .utf8)
        let support = root.appendingPathComponent("Sources/VibeVoiceBatch/Support", isDirectory: true)
        let voiceLibrarySummary = try String(contentsOf: support.appendingPathComponent("VoiceLibrarySummary.swift"), encoding: .utf8)
        let stores = root.appendingPathComponent("Sources/VibeVoiceBatch/Stores", isDirectory: true)
        let settingsStore = try String(contentsOf: stores.appendingPathComponent("SettingsStore.swift"), encoding: .utf8)
        let workspaceStore = try String(contentsOf: stores.appendingPathComponent("WorkspaceStore.swift"), encoding: .utf8)
        let appStore = try String(contentsOf: stores.appendingPathComponent("AppStore.swift"), encoding: .utf8)
        let appStoreScriptQueue = try String(contentsOf: stores.appendingPathComponent("AppStore+ScriptQueue.swift"), encoding: .utf8)
        let workspaceFileStore = try String(contentsOf: root.appendingPathComponent("Sources/VibeVoiceBatchCore/Services/WorkspaceFileStore.swift"), encoding: .utf8)
        let scriptChunker = try String(contentsOf: root.appendingPathComponent("Sources/VibeVoiceBatchCore/Services/ScriptChunker.swift"), encoding: .utf8)

        precondition(sidebar.contains("Section(\"Generation\")"))
        precondition(sidebar.contains("ForEach(store.sessions)"))
        precondition(sidebar.contains("HistorySidebarRow"))
        precondition(sidebar.contains("workspaceStore.activeScripts.count"))
        precondition(sidebar.contains("generations"))
        precondition(!sidebar.contains("selectionBackground"))

        precondition(inspector.contains("private var inspectorHeader"))
        precondition(inspector.contains("private var inspectorContent"))
        precondition(inspector.contains("backendInspectorContent"))
        precondition(inspector.contains("lockedSessionGenerationSection"))
        precondition(inspector.contains("Archived sessions are read-only"))
        precondition(!inspector.contains("case .section(.history), .historySession:"))
        precondition(inspector.contains("case .section(.outputs):"))
        precondition(inspector.contains("case .section(.voices):\n                voiceLibraryInspectorContent"))
        precondition(inspector.contains("Text(VoiceDisplayFormatter.displayText(for: voice))"))
        precondition(!inspector.contains("case .section(.voices):\n                generationSection"))
        precondition(settings.contains("Text(VoiceDisplayFormatter.displayText(for: voice))"))
        precondition(assistantModels.contains("Text(VoiceDisplayFormatter.displayText(for: voice))"))
        precondition(voiceDisplay.contains("AppDefaults.languageCode(forVibeVoiceVoiceID: filenameStem)"))
        precondition(voiceDisplay.contains("case \"en\": return \"🇺🇸\""))
        precondition(workspaceSections.contains("Copy Voice ID"))
        precondition(!workspaceSections.contains("Label(\"Use Voice\""))
        precondition(!workspaceSections.contains("Label(\"Generate Sample\""))
        precondition(workspaceSections.contains("ProjectRebatchControls(project: project, scripts: scripts)"))
        precondition(projectRebatchControls.contains("ProjectRebatchSettingsSource"))
        precondition(projectRebatchControls.contains("Current Settings"))
        precondition(projectRebatchControls.contains("Generation Preset"))
        precondition(projectRebatchControls.contains("Queue Re-batch"))
        precondition(projectRebatchControls.contains("func rebatchProject"))
        precondition(projectRebatchControls.contains("selectedPreset"))
        precondition(projectRebatchControls.contains("backendID: preset.backendID"))
        precondition(projectRebatchControls.contains("backendID: appStore.selectedBackendProfile.id"))
        precondition(projectRebatchControls.contains("extraParameters: settingsStore.settings.generationExtraParameters"))
        precondition(workspaceSections.contains("Advanced Parameters"))
        precondition(workspaceSections.contains("preset.settings.extraParameters"))
        precondition(workspaceSections.contains("Save Voice Profile"))
        precondition(voiceLibrarySummary.contains("BackendProfiles.all.reduce"))
        precondition(sidebar.contains("VoiceLibrarySummary.catalogVoiceCount"))
        precondition(inspector.contains("Catalog voices"))
        precondition(inspector.contains("Saved voice profiles"))
        precondition(settingsStore.contains("func generationVoiceOptions(for profile: BackendProfile)"))
        precondition(settingsStore.contains("ChatterboxVoiceCatalog.voice($0, supportsOutputLanguage: languageCode)"))
        precondition(!settingsStore.contains("localized.languageCode = languageCode"))
        precondition(appStore.contains("settingsStore.generationVoiceOptions(for: selectedBackendProfile)"))
        precondition(appStore.contains("var selectedVoiceIsAvailable"))
        precondition(appStore.contains("selectedVoiceIsAvailable &&"))
        precondition(appStore.contains("applyGenerationExtraParameters(preset.settings.extraParameters"))
        precondition(inspector.contains("No compatible voices"))
        precondition(inspector.contains("No Chatterbox voice is marked available for the selected language."))

        precondition(status.contains("ViewThatFits(in: .horizontal)"))
        precondition(status.contains("LazyVGrid"))
        precondition(outputs.contains("ViewThatFits(in: .horizontal)"))
        precondition(outputs.contains("private var summaryMetrics"))
        precondition(content.contains("ToolbarItemGroup(placement: .navigation)"))
        precondition(content.contains("Label(\"New Generation\""))
        precondition(content.contains("Label(\"Stop\""))
        precondition(content.contains(".help(\"Stop Generation\")"))
        precondition(app.contains("Button(\"Stop Generation\")"))
        precondition(workspaceSections.contains("private var orderedQueueItems"))
        precondition(workspaceSections.contains("BatchQueueSummaryStrip"))
        precondition(workspaceSections.contains("BatchQueueControlRow"))
        precondition(workspaceSections.contains("Pause Queue"))
        precondition(workspaceSections.contains("Resume Queue"))
        precondition(workspaceSections.contains("Paused"))
        precondition(workspaceSections.contains("Label(\"Import TXT\""))
        precondition(workspaceSections.contains("TextField(\"Project name\""))
        precondition(workspaceSections.contains("Label(\"Create Project\""))
        precondition(workspaceSections.contains("ImportedBatchCleanupSection"))
        precondition(workspaceSections.contains("Delete Batch"))
        precondition(workspaceSections.contains("ScriptChunker.chunks"))
        precondition(scriptImportSheet.contains("Save and Queue"))
        precondition(scriptImportSheet.contains("ScriptImportSheet"))
        precondition(appStoreScriptQueue.contains("queueImportedScripts"))
        precondition(appStoreScriptQueue.contains("finishWorkspaceQueueItem"))
        precondition(appStoreScriptQueue.contains("cancelQueuedGenerations"))
        precondition(appStoreScriptQueue.contains("attachGenerationSessions([record.id], toProject: projectID)"))
        precondition(appStoreScriptQueue.contains("enqueueGeneration"))
        precondition(workspaceStore.contains("var activeScripts"))
        precondition(workspaceStore.contains("func createProject(title: String)"))
        precondition(workspaceStore.contains("func createProjectRebatch"))
        precondition(workspaceStore.contains("func saveGenerationPreset(\n        backendID: String,\n        modelID: String,"))
        precondition(workspaceStore.contains("extraParameters: [String: String] = [:]"))
        precondition(workspaceStore.contains("func deleteUncompletedBatch"))
        precondition(workspaceFileStore.contains("deleteUncompletedBatch"))
        precondition(scriptChunker.contains("timestampMarkerTitle"))
        precondition(workspaceSections.contains("No Queued Generations"))
        precondition(!workspaceSections.contains("Saved Batches"))
        precondition(content.contains("Pause Queue"))
        precondition(content.contains("Resume Queue"))
        precondition(appStore.contains("@Published private(set) var isQueuePaused"))
        precondition(appStore.contains("func pauseGenerationQueue()"))
        precondition(appStore.contains("func resumeGenerationQueue()"))
        precondition(appStore.contains("guard !isQueuePaused else { return }"))

        precondition(editor.contains(".labelStyle(.iconOnly)"))
        precondition(assistantWelcome.contains("AssistantWelcomePoint"))
        precondition(assistantWelcome.contains("BackendModeSummary"))
    }

    private static func checkAppIdentityAndPackaging() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let package = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let contentView = try String(
            contentsOf: root.appendingPathComponent("Sources/VibeVoiceBatch/Views/ContentView.swift"),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: root.appendingPathComponent("Sources/VibeVoiceBatch/App/VibeVoiceBatchApp.swift"),
            encoding: .utf8
        )
        let infoView = try String(
            contentsOf: root.appendingPathComponent("Sources/VibeVoiceBatch/Views/FonimInfoView.swift"),
            encoding: .utf8
        )
        let buildScript = try String(contentsOf: root.appendingPathComponent("script/build_and_run.sh"), encoding: .utf8)
        let packageScript = try String(contentsOf: root.appendingPathComponent("script/package_app.sh"), encoding: .utf8)
        let smokeScript = try String(contentsOf: root.appendingPathComponent("script/smoke_test_release.sh"), encoding: .utf8)
        let packaging = try String(contentsOf: root.appendingPathComponent("PACKAGING.md"), encoding: .utf8)
        let qaChecklist = try String(contentsOf: root.appendingPathComponent("QA_RELEASE_CHECKLIST.md"), encoding: .utf8)
        let iconData = try Data(contentsOf: root.appendingPathComponent("Resources/AppIcon.icns"))

        precondition(package.contains("name: \"Fonim\""))
        precondition(package.contains(".executable(name: \"Fonim\", targets: [\"VibeVoiceBatch\"])"))
        precondition(!package.contains(".executable(name: \"VibeVoiceBatch\", targets: [\"VibeVoiceBatch\"])"))
        precondition(contentView.contains(".alert(\"Fonim\""))
        precondition(app.contains("CommandGroup(replacing: .appInfo)"))
        precondition(app.contains("Window(\"About Fonim\", id: \"fonim-info\")"))
        precondition(app.contains("OpenFonimInfoButton"))
        precondition(infoView.contains("GeneratedAudioLibrarySummary"))
        precondition(infoView.contains("GeneratedAudioReference.defaultReferences"))
        precondition(infoView.contains("pickReference()"))
        precondition(infoView.contains("New Comparison"))
        precondition(iconData.count > 1_000_000)
        precondition(buildScript.contains("APP_NAME=\"Fonim\""))
        precondition(buildScript.contains("PRODUCT_NAME=\"Fonim\""))
        precondition(buildScript.contains("BUNDLE_ID=\"local.vibevoice.batch\""))
        precondition(packageScript.contains("APP_NAME=\"Fonim\""))
        precondition(packageScript.contains("PRODUCT_NAME=\"Fonim\""))
        precondition(packageScript.contains("<string>Fonim</string>"))
        precondition(smokeScript.contains("APP_NAME=\"Fonim\""))
        precondition(packaging.contains("dist/Fonim.app"))
        precondition(qaChecklist.contains("dist/Fonim.app"))
    }

    private static func checkVibeVoiceAdapterGeneratesThroughSessionStore() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchAdapterChecks-\(UUID().uuidString)", isDirectory: true)
        let fileStore = SessionFileStore(projectRoot: root)
        try fileStore.ensureBaseDirectories()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data([9, 9, 9]).write(to: root.generatedWAVFile)

        let runner = FakeDockerRunner()
        runner.chunks = [
            "Prefilled 70 text tokens, generated 80 speech tokens, current step (298 / 8192):   4%| | 298/8192 [00:27]\n",
            "Fonim progress: phase=starting_generation elapsed=00:30 estimated=05:00 progress=10.00%\n",
            """
            Input file: /app/input.txt
            Output file: /app/outputs/input_generated.wav
            Speaker names: en-carter_man
            CFG scale: 1.8
            DDPM inference steps: 8
            Prefilling text tokens: 70
            Generated speech tokens: 80
            Total tokens: 150
            Generation time: 12.00 seconds
            Audio duration: 2.00 seconds
            RTF (Real Time Factor): 6.00x

            """
        ]
        runner.onRun = { _ in
            try? makePCM16MonoWav(durationSeconds: 2.0, sampleRate: 8_000)
                .write(to: root.generatedWAVFile)
        }

        let adapter = VibeVoiceDockerAdapter(projectRoot: root, fileStore: fileStore, runner: runner)
        let job = GenerationJob(
            id: "adapter-job",
            createdAt: Date(timeIntervalSince1970: 1_718_171_695),
            inputText: "Hello adapter.",
            backendID: BackendProfiles.vibeVoiceTTS.id,
            modelID: AppDefaults.modelPath,
            voiceID: "en-carter_man",
            settings: GenerationSettings(cfgScale: "1.8", ddpmInferenceSteps: 8)
        )

        var events: [GenerationEvent] = []
        let record = try await adapter.generate(job) { event in
            events.append(event)
        }

        precondition(record.status == .completed)
        precondition(record.id.contains("en-carter_man_cfg1.8"))
        precondition(record.exportPath?.hasSuffix("/output.wav") == true)
        precondition(record.durationSeconds == 2.0)
        precondition(runner.receivedCommand?.arguments.contains("--speaker_name") == true)
        precondition(runner.receivedCommand?.arguments.contains("en-carter_man") == true)
        precondition(!FileManager.default.fileExists(atPath: root.generatedWAVFile.path))

        let sessions = try fileStore.loadSessions()
        precondition(sessions.count == 1)
        let session = sessions[0]
        precondition(session.metadata.status == .completed)
        precondition(session.metadata.generationTimeSeconds == 12.0)
        precondition(session.metadata.audioDurationSeconds == 2.0)
        precondition(session.metadata.rtf == 6.0)
        precondition(session.outputURL?.lastPathComponent == "output.wav")

        let recoveredFiles = try FileManager.default.contentsOfDirectory(
            at: root.recoveredDirectory,
            includingPropertiesForKeys: nil
        )
        precondition(recoveredFiles.contains { $0.lastPathComponent.hasSuffix("_pre_run_input_generated.wav") })
        precondition(events.contains { event in
            switch event {
            case .sessionStarted:
                return true
            case .status, .progress, .log, .output:
                return false
            }
        })
        precondition(events.contains { event in
            switch event {
            case .progress(let snapshot):
                return snapshot.currentStep == 298
            case .sessionStarted, .status, .log, .output:
                return false
            }
        })
        precondition(events.contains { event in
            switch event {
            case .progress(let snapshot):
                return snapshot.message == "Starting Generation" &&
                    snapshot.fractionComplete == 0.10 &&
                    snapshot.elapsedSeconds == 30 &&
                    snapshot.estimatedRemainingSeconds == 270
            case .sessionStarted, .status, .log, .output:
                return false
            }
        })
        precondition(events.contains { event in
            switch event {
            case .output:
                return true
            case .sessionStarted, .status, .progress, .log:
                return false
            }
        })
    }

    private static func checkKokoroHTTPAdapterGeneratesThroughSessionStore() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchKokoroAdapterChecks-\(UUID().uuidString)", isDirectory: true)
        let fileStore = SessionFileStore(projectRoot: root)
        try fileStore.ensureBaseDirectories()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data([8, 8, 8]).write(to: root.generatedWAVFile)

        let endpoint = URL(string: "http://127.0.0.1:8880/v1/audio/speech")!
        let image = "ghcr.io/remsky/kokoro-fastapi-cpu:latest"
        let profile = BackendProfiles.kokoroTTS.applying(
            BackendConnectionSettings(
                connectionKind: .installedDockerImage,
                dockerImage: image,
                serviceBaseURL: "http://127.0.0.1:8880",
                modelID: "tts-1",
                defaultVoice: "af_heart"
            )
        )
        let client = FakeKokoroSpeechClient(
            response: KokoroSpeechResponse(
                data: makePCM16MonoWav(durationSeconds: 1.5, sampleRate: 8_000),
                contentType: "audio/wav"
            )
        )
        let logFollower = FakeKokoroLogFollower(chunks: [
            """
            POST /v1/audio/speech
            Processing chunk 1/2
            50%|#####     | 500/1000 [00:05<00:05, 100.00it/s]
            """
        ])
        let adapter = KokoroHTTPAdapter(
            profile: profile,
            projectRoot: root,
            fileStore: fileStore,
            client: client,
            logFollower: logFollower
        )
        let job = GenerationJob(
            id: "kokoro-adapter-job",
            createdAt: Date(timeIntervalSince1970: 1_718_171_895),
            inputText: "Hello Kokoro adapter.",
            backendID: profile.id,
            modelID: "tts-1",
            voiceID: "af_heart",
            settings: GenerationSettings(
                cfgScale: "1.0",
                ddpmInferenceSteps: nil,
                extraParameters: [
                    "generate_endpoint": endpoint.absoluteString,
                    "docker_image": image,
                    "speed": "1.15"
                ]
            )
        )

        var events: [GenerationEvent] = []
        let record = try await adapter.generate(job) { event in
            events.append(event)
        }

        precondition(record.status == .completed)
        precondition(record.backendID == profile.id)
        precondition(record.backendDisplayName == "Kokoro TTS")
        precondition(record.modelID == "tts-1")
        precondition(record.voiceID == "af_heart")
        precondition(record.exportPath?.hasSuffix("/output.wav") == true)
        precondition(record.durationSeconds == 1.5)
        precondition(!FileManager.default.fileExists(atPath: root.generatedWAVFile.path))

        precondition(client.requests.count == 1)
        let request = try unwrap(client.requests.first, "Expected Kokoro request")
        precondition(request.endpoint == endpoint)
        precondition(request.modelID == "tts-1")
        precondition(request.voiceID == "af_heart")
        precondition(request.inputText == "Hello Kokoro adapter.")
        precondition(request.responseFormat == "wav")
        precondition(request.speed == 1.15)

        let sessions = try fileStore.loadSessions()
        precondition(sessions.count == 1)
        let session = sessions[0]
        precondition(session.metadata.status == .completed)
        precondition(session.metadata.voice == "af_heart")
        precondition(session.metadata.dockerImage == image)
        precondition(session.metadata.dockerCommand == "POST \(endpoint.absoluteString)")
        precondition(session.metadata.inputWordCount == 3)
        precondition(session.metadata.audioDurationSeconds == 1.5)
        precondition(session.metadata.outputFile?.hasSuffix("/output.wav") == true)
        precondition(session.logText.contains("Runtime: Kokoro HTTP service"))
        precondition(session.logText.contains("Processing chunk 1/2"))
        precondition(session.logText.contains("Saved output:"))
        precondition(session.outputURL?.lastPathComponent == "output.wav")

        let recoveredFiles = try FileManager.default.contentsOfDirectory(
            at: root.recoveredDirectory,
            includingPropertiesForKeys: nil
        )
        precondition(recoveredFiles.contains { $0.lastPathComponent.hasSuffix("_pre_run_kokoro_input_generated.wav") })
        precondition(events.contains { event in
            switch event {
            case .progress(let snapshot):
                return snapshot.message.contains("chunk 1/2")
            case .sessionStarted, .status, .log, .output:
                return false
            }
        })
        precondition(events.contains { event in
            switch event {
            case .output:
                return true
            case .sessionStarted, .status, .progress, .log:
                return false
            }
        })
    }

    private static func checkChatterboxHTTPAdapterGeneratesThroughSessionStore() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchChatterboxAdapterChecks-\(UUID().uuidString)", isDirectory: true)
        let fileStore = SessionFileStore(projectRoot: root)
        try fileStore.ensureBaseDirectories()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data([7, 7, 7]).write(to: root.generatedWAVFile)

        let endpoint = URL(string: "http://127.0.0.1:8004/tts")!
        let profile = BackendProfiles.chatterboxTTS.applying(
            BackendConnectionSettings(
                connectionKind: .externalService,
                serviceBaseURL: "http://127.0.0.1:8004",
                healthPath: "/api/model-info",
                generatePath: "/tts",
                modelID: "chatterbox",
                defaultVoice: "Emily.wav"
            )
        )
        let client = FakeChatterboxSpeechClient(
            response: ChatterboxTTSResponse(
                data: makePCM16MonoWav(durationSeconds: 2.0, sampleRate: 8_000),
                contentType: "audio/wav"
            )
        )
        let logFollower = FakeChatterboxLogFollower(chunks: [
            """
            Received /tts request: mode='predefined', format='wav'
            Text chunking complete. Generated 2 chunk(s).
            Synthesizing chunk 1/2...
            20%|##        | 200/1000 [00:20<01:20, 10.00it/s]
            """
        ])
        let adapter = ChatterboxHTTPAdapter(
            profile: profile,
            projectRoot: root,
            fileStore: fileStore,
            client: client,
            logFollower: logFollower,
            modelSwitcher: FakeChatterboxModelSwitcher()
        )
        let job = GenerationJob(
            id: "chatterbox-adapter-job",
            createdAt: Date(timeIntervalSince1970: 1_718_171_995),
            inputText: "Hello Chatterbox adapter.",
            backendID: profile.id,
            modelID: "chatterbox",
            voiceID: "reference:Gianna.wav",
            settings: GenerationSettings(
                cfgScale: "0.5",
                ddpmInferenceSteps: nil,
                extraParameters: [
                    "generate_endpoint": endpoint.absoluteString,
                    "temperature": "0.7",
                    "exaggeration": "1.2",
                    "cfg_weight": "0.45",
                    "seed": "12",
                    "speed_factor": "1.1",
                    "language": "en",
                    "split_text": "true",
                    "chunk_size": "180",
                    "output_format": "wav"
                ]
            )
        )

        var events: [GenerationEvent] = []
        let record = try await adapter.generate(job) { event in
            events.append(event)
        }

        precondition(record.status == .completed)
        precondition(record.backendID == profile.id)
        precondition(record.backendDisplayName == "Chatterbox TTS")
        precondition(record.modelID == "chatterbox")
        precondition(record.voiceID == "reference:Gianna.wav")
        precondition(record.exportPath?.hasSuffix("/output.wav") == true)
        precondition(record.durationSeconds == 2.0)
        precondition(!FileManager.default.fileExists(atPath: root.generatedWAVFile.path))

        precondition(client.requests.count == 1)
        let request = try unwrap(client.requests.first, "Expected Chatterbox request")
        precondition(request.endpoint == endpoint)
        precondition(request.voiceMode == "clone")
        precondition(request.voiceFilename == "Gianna.wav")
        precondition(request.inputText == "Hello Chatterbox adapter.")
        precondition(request.chunkSize == 180)
        precondition(request.temperature == 0.7)
        precondition(request.exaggeration == 1.2)
        precondition(request.cfgWeight == 0.45)
        precondition(request.seed == 12)
        precondition(request.speedFactor == 1.1)

        let sessions = try fileStore.loadSessions()
        precondition(sessions.count == 1)
        let session = sessions[0]
        precondition(session.metadata.status == .completed)
        precondition(session.metadata.voice == "reference:Gianna.wav")
        precondition(session.metadata.dockerImage == "Chatterbox service")
        precondition(session.metadata.dockerCommand == "POST \(endpoint.absoluteString)")
        precondition(session.metadata.inputWordCount == 3)
        precondition(session.metadata.audioDurationSeconds == 2.0)
        precondition(session.metadata.outputFile?.hasSuffix("/output.wav") == true)
        precondition(session.logText.contains("Runtime: Chatterbox HTTP service"))
        precondition(session.logText.contains("Voice mode: clone"))
        precondition(session.logText.contains("Synthesizing chunk 1/2"))
        precondition(session.outputURL?.lastPathComponent == "output.wav")

        let recoveredFiles = try FileManager.default.contentsOfDirectory(
            at: root.recoveredDirectory,
            includingPropertiesForKeys: nil
        )
        precondition(recoveredFiles.contains { $0.lastPathComponent.hasSuffix("_pre_run_chatterbox_input_generated.wav") })
        precondition(events.contains { event in
            switch event {
            case .progress(let snapshot):
                return snapshot.message == "sending request to Chatterbox"
            case .sessionStarted, .status, .log, .output:
                return false
            }
        })
        precondition(events.contains { event in
            switch event {
            case .progress(let snapshot):
                return snapshot.currentStep == 200 &&
                    snapshot.totalSteps == 1000 &&
                    snapshot.message.contains("chunk 1/2")
            case .sessionStarted, .status, .log, .output:
                return false
            }
        })
        precondition(events.contains { event in
            switch event {
            case .output:
                return true
            case .sessionStarted, .status, .progress, .log:
                return false
            }
        })
    }

    private static func checkBackendVoiceTestRunnerUsesAdapterQueue() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchVoiceTestRunnerChecks-\(UUID().uuidString)", isDirectory: true)
        let fileStore = SessionFileStore(projectRoot: root)
        try fileStore.ensureBaseDirectories()
        defer { try? FileManager.default.removeItem(at: root) }

        let image = "ghcr.io/remsky/kokoro-fastapi-cpu:latest"
        let profile = BackendProfiles.kokoroTTS.applying(
            BackendConnectionSettings(
                connectionKind: .installedDockerImage,
                dockerImage: image,
                serviceBaseURL: "http://127.0.0.1:8880",
                modelID: "tts-1",
                defaultVoice: "af_heart"
            )
        )
        let manager = BackendManager(
            projectRoot: root,
            dockerExecutableResolver: { "/usr/local/bin/docker" },
            processRunner: { _, arguments in
                if arguments.contains("inspect") {
                    return BackendProcessResult(exitCode: 0, combinedOutput: "kokoro image")
                }
                if arguments.contains("ps") {
                    return BackendProcessResult(
                        exitCode: 0,
                        combinedOutput: "vibevoice_batch_kokoro_tts\t\(image)\t0.0.0.0:8880->8880/tcp\tUp 1 minute\n"
                    )
                }
                return BackendProcessResult(exitCode: 0, combinedOutput: "25.0.0")
            },
            httpRunner: { url in
                precondition(url.absoluteString == "http://127.0.0.1:8880/health")
                return BackendHTTPResult(statusCode: 200, body: "{\"status\":\"ready\"}")
            }
        )
        let client = FakeKokoroSpeechClient(
            response: KokoroSpeechResponse(
                data: makePCM16MonoWav(durationSeconds: 1.0, sampleRate: 8_000),
                contentType: "audio/wav"
            )
        )
        var factoryProfileID: String?
        let runner = BackendVoiceTestRunner(
            projectRoot: root,
            backendManager: manager,
            adapterFactory: { profile, projectRoot in
                factoryProfileID = profile.id
                return KokoroHTTPAdapter(profile: profile, projectRoot: projectRoot, fileStore: fileStore, client: client)
            }
        )
        let request = BackendVoiceTestRequest(
            profile: profile,
            modelID: "tts-1",
            voiceID: "af_heart",
            cfgScale: "1.0",
            ddpmInferenceSteps: nil,
            sampleText: "Setup assistant test."
        )

        var events: [GenerationEvent] = []
        let record = try await runner.run(request) { event in
            events.append(event)
        }

        precondition(factoryProfileID == profile.id)
        precondition(record.status == .completed)
        precondition(record.inputText == "Setup assistant test.")
        precondition(record.exportPath?.hasSuffix("/output.wav") == true)
        precondition(client.requests.first?.endpoint.absoluteString == "http://127.0.0.1:8880/v1/audio/speech")
        precondition(client.requests.first?.modelID == "tts-1")
        precondition(client.requests.first?.voiceID == "af_heart")
        precondition(events.contains { event in
            if case .sessionStarted = event { return true }
            return false
        })
        let sessions = try fileStore.loadSessions()
        precondition(sessions.count == 1)
        precondition(sessions[0].metadata.status == .completed)
        precondition(sessions[0].metadata.dockerImage == image)
    }

    private static func checkJobQueueCancellationReachesAdapter() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchCancelChecks-\(UUID().uuidString)", isDirectory: true)
        let fileStore = SessionFileStore(projectRoot: root)
        try fileStore.ensureBaseDirectories()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = BlockingDockerRunner()
        let adapter = VibeVoiceDockerAdapter(projectRoot: root, fileStore: fileStore, runner: runner)
        let queue = JobQueue(adapters: [adapter])
        let job = GenerationJob(
            id: "cancel-job",
            createdAt: Date(timeIntervalSince1970: 1_718_171_795),
            inputText: "Cancel adapter.",
            backendID: BackendProfiles.vibeVoiceTTS.id,
            modelID: AppDefaults.modelPath,
            voiceID: "en-carter_man",
            settings: GenerationSettings(cfgScale: "1.8", ddpmInferenceSteps: 8)
        )

        let task = Task {
            try await queue.submit(job)
        }

        precondition(runner.waitUntilStarted())
        await queue.cancel(jobID: job.id)
        let record = try await task.value

        precondition(runner.didCancel)
        precondition(record.status == .cancelled)
        let sessions = try fileStore.loadSessions()
        precondition(sessions.count == 1)
        precondition(sessions[0].metadata.status == .cancelled)
        precondition(sessions[0].outputURL == nil)
    }

    private static func withStore<T>(_ body: (URL, SessionFileStore) throws -> T) throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceBatchChecks-\(UUID().uuidString)", isDirectory: true)
        let store = SessionFileStore(projectRoot: root)
        try store.ensureBaseDirectories()
        defer { try? FileManager.default.removeItem(at: root) }
        return try body(root, store)
    }

    private static func completedOutputRecord(
        store: SessionFileStore,
        text: String,
        voice: String,
        backendImage: String,
        audioDuration: Double,
        outputBytes: Data,
        now: Date
    ) throws -> SessionRecord {
        let record = try store.createDraft(text: text, voice: voice, cfgScale: "1.8", now: now)
        try outputBytes.write(to: record.folderURL.appendingPathComponent("output.wav", isDirectory: false))
        var metadata = record.metadata
        metadata.status = .completed
        metadata.completedAt = now.addingTimeInterval(1)
        metadata.dockerImage = backendImage
        metadata.audioDurationSeconds = audioDuration
        metadata.outputFile = record.folderURL.appendingPathComponent("output.wav", isDirectory: false).path
        try store.writeMetadata(metadata, in: record.folderURL)
        return try store.loadRecord(folderURL: record.folderURL)
    }

    private static func makePCM16MonoWav(durationSeconds: Double, sampleRate: Int) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = Int(durationSeconds * Double(byteRate))
        let riffSize = 36 + dataSize

        var data = Data()
        data.appendASCII("RIFF")
        data.appendUInt32LE(UInt32(riffSize))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(UInt16(channels))
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(byteRate))
        data.appendUInt16LE(UInt16(blockAlign))
        data.appendUInt16LE(UInt16(bitsPerSample))
        data.appendASCII("data")
        data.appendUInt32LE(UInt32(dataSize))
        data.append(Data(repeating: 0, count: dataSize))
        return data
    }
}

private struct CheckError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private func unwrap<Value>(_ value: Value?, _ message: String) throws -> Value {
    guard let value else {
        throw CheckError(message)
    }
    return value
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private final class FakeDockerRunner: DockerGenerationRunning {
    var chunks: [String] = []
    var result = DockerRunResult(exitCode: 0, wasCancelled: false, elapsedSeconds: 12)
    var onRun: ((DockerRunCommand) -> Void)?
    private(set) var receivedCommand: DockerRunCommand?
    private(set) var didCancel = false

    func run(command: DockerRunCommand, logHandler: @escaping (String) -> Void) throws -> DockerRunResult {
        receivedCommand = command
        for chunk in chunks {
            logHandler(chunk)
        }
        onRun?(command)
        return result
    }

    func cancel() {
        didCancel = true
    }
}

private final class FakeKokoroSpeechClient: KokoroSpeechGenerating, @unchecked Sendable {
    private let response: KokoroSpeechResponse
    private let error: Error?
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.checks.kokoro-client")
    private var recordedRequests: [KokoroSpeechRequest] = []
    private var cancelFlag = false

    init(response: KokoroSpeechResponse, error: Error? = nil) {
        self.response = response
        self.error = error
    }

    var requests: [KokoroSpeechRequest] {
        stateQueue.sync { recordedRequests }
    }

    var didCancel: Bool {
        stateQueue.sync { cancelFlag }
    }

    func generateSpeech(_ request: KokoroSpeechRequest) async throws -> KokoroSpeechResponse {
        stateQueue.sync {
            recordedRequests.append(request)
        }
        if let error {
            throw error
        }
        return response
    }

    func cancel() {
        stateQueue.sync {
            cancelFlag = true
        }
    }
}

private final class FakeKokoroLogFollower: KokoroLogFollowing {
    private let chunks: [String]

    init(chunks: [String]) {
        self.chunks = chunks
    }

    func followLogs(
        since: Date,
        profile: BackendProfile,
        endpoint: URL?,
        onChunk: @escaping (String) -> Void
    ) -> KokoroLogFollowHandle? {
        for chunk in chunks {
            onChunk(chunk)
        }
        return KokoroLogFollowHandle {}
    }
}

private final class FakeChatterboxSpeechClient: ChatterboxSpeechGenerating, @unchecked Sendable {
    private let response: ChatterboxTTSResponse
    private let error: Error?
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.checks.chatterbox-client")
    private var recordedRequests: [ChatterboxTTSRequest] = []
    private var cancelFlag = false

    init(response: ChatterboxTTSResponse, error: Error? = nil) {
        self.response = response
        self.error = error
    }

    var requests: [ChatterboxTTSRequest] {
        stateQueue.sync { recordedRequests }
    }

    var didCancel: Bool {
        stateQueue.sync { cancelFlag }
    }

    func generateSpeech(_ request: ChatterboxTTSRequest) async throws -> ChatterboxTTSResponse {
        stateQueue.sync {
            recordedRequests.append(request)
        }
        if let error {
            throw error
        }
        return response
    }

    func cancel() {
        stateQueue.sync {
            cancelFlag = true
        }
    }
}

private final class FakeChatterboxModelSwitcher: ChatterboxModelSwitching, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.checks.chatterbox-model-switcher")
    private var recordedModelIDs: [String] = []

    var modelIDs: [String] {
        stateQueue.sync { recordedModelIDs }
    }

    func ensureModel(
        _ modelID: String,
        endpoint: URL,
        onLog: @escaping (String) -> Void
    ) async throws {
        stateQueue.sync {
            recordedModelIDs.append(modelID)
        }
        onLog("Chatterbox model ready for test: \(modelID).\n")
    }
}

private final class FakeChatterboxLogFollower: ChatterboxLogFollowing {
    private let chunks: [String]

    init(chunks: [String]) {
        self.chunks = chunks
    }

    func followLogs(
        since: Date,
        profile: BackendProfile,
        endpoint: URL?,
        onChunk: @escaping (String) -> Void
    ) -> ChatterboxLogFollowHandle? {
        for chunk in chunks {
            onChunk(chunk)
        }
        return ChatterboxLogFollowHandle {}
    }
}

private final class BackendURLSpy: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.vibevoice.batch.checks.backend-url-spy")
    private var recordedURLs: [String] = []

    var urls: [String] {
        queue.sync { recordedURLs }
    }

    func record(_ url: String) {
        queue.sync {
            recordedURLs.append(url)
        }
    }
}

private final class BackendProcessSpy: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.vibevoice.batch.checks.backend-process-spy")
    private let handler: @Sendable ([String]) -> BackendProcessResult
    private var recordedCalls: [[String]] = []

    init(handler: @escaping @Sendable ([String]) -> BackendProcessResult) {
        self.handler = handler
    }

    var calls: [[String]] {
        queue.sync { recordedCalls }
    }

    func run(executable: String, arguments: [String]) -> BackendProcessResult {
        queue.sync {
            recordedCalls.append(arguments)
        }
        return handler(arguments)
    }
}

private final class BlockingDockerRunner: DockerGenerationRunning {
    private let started = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.checks.blocking-runner")
    private var cancelFlag = false

    var didCancel: Bool {
        stateQueue.sync { cancelFlag }
    }

    func run(command: DockerRunCommand, logHandler: @escaping (String) -> Void) throws -> DockerRunResult {
        started.signal()
        _ = release.wait(timeout: .now() + 1)
        return DockerRunResult(exitCode: didCancel ? 143 : 0, wasCancelled: didCancel, elapsedSeconds: 1)
    }

    func cancel() {
        stateQueue.sync {
            cancelFlag = true
        }
        release.signal()
    }

    func waitUntilStarted() -> Bool {
        started.wait(timeout: .now() + 1) == .success
    }
}
