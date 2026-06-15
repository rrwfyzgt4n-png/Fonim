import Foundation
import VibeVoiceBatchCore

@main
struct VibeVoiceBatchCoreChecks {
    static func main() async throws {
        try checkDraftCreatesPermanentSessionFiles()
        try checkSessionIDsNeverCollide()
        try checkRecoverExistingGeneratedWAVMovesToRecovered()
        try checkMoveGeneratedWAVToSessionUsesOutputWAV()
        try checkReadsPCMDuration()
        try checkParsesLiveProgressAndFinalSummary()
        try checkDockerCommandIncludesDDPMControls()
        try await checkBackendProfilesAndAdapterContracts()
        try checkBackendStatusSnapshots()
        try checkBackendSetupReport()
        try checkKokoroDiscoveryReport()
        try checkKokoroCatalogReport()
        try checkBackendManagerOperations()
        try checkWorkspaceDataModel()
        try checkWorkspacePresets()
        try checkAppSettingsNormalizeInvalidValues()
        try await checkVibeVoiceAdapterGeneratesThroughSessionStore()
        try await checkKokoroHTTPAdapterGeneratesThroughSessionStore()
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

        let estimatedProgressText = "VibeVoiceBatch progress: phase=generation elapsed=00:12 estimated=02:00 progress=10.00%"
        guard let estimatedProgress = GenerationOutputParser.latestEstimatedProgress(in: estimatedProgressText) else {
            throw CheckError("Expected estimated generation progress")
        }
        precondition(estimatedProgress.phase == "generation")
        precondition(estimatedProgress.fraction == 0.10)
        precondition(estimatedProgress.elapsedSeconds == 12)
        precondition(estimatedProgress.estimatedSeconds == 120)

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
        precondition(BackendProfiles.kokoroTTS.requiredModels.first?.id == "kokoro/default")
        precondition(BackendProfiles.kokoroTTS.progressParser == "KokoroHTTPAdapter.progress")
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

        let manager = BackendManager(projectRoot: FileManager.default.temporaryDirectory)
        precondition(manager.registeredProfiles().contains(profile))
        precondition(manager.registeredProfiles().contains(BackendProfiles.kokoroTTS))

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
                modelID: "kokoro/default"
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
        precondition(kokoroServiceStatus.state == .ready)
        precondition(kokoroServiceStatus.userMessage.contains("health check"))
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
                        {"voices":[{"id":"af_heart","name":"af_heart"},{"id":"am_adam","name":"am_adam"}]}
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
        precondition(catalog.message.contains("Loaded 2 models and 2 voices"))
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
        precondition(FileManager.default.fileExists(atPath: root.projectsDirectory.path))

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
            settings: GenerationSettings(cfgScale: "1.9", ddpmInferenceSteps: 9),
            outputFormat: .wav,
            now: createdAt
        )
        precondition(!generationPreset.isBuiltIn)
        precondition(generationPreset.voicePresetID == voicePreset.id)
        precondition(generationPreset.settings.cfgScale == "1.9")
        precondition(generationPreset.settings.ddpmInferenceSteps == 9)
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
        let normalized = settings.normalized
        precondition(normalized.defaultBackendID == BackendProfiles.vibeVoiceTTS.id)
        precondition(normalized.defaultModelID == AppDefaults.modelPath)
        precondition(normalized.defaultVoice == AppDefaults.defaultVoice)
        precondition(normalized.defaultCFGScale == AppDefaults.defaultCFGScale)
        precondition(normalized.defaultDDPMInferenceSteps == AppDefaults.defaultDDPMInferenceSteps)
        precondition(normalized.outputFolderPath == AppDefaults.projectRoot.historyDirectory.path)
        precondition(normalized.exportFormat == .wav)

        let kokoroSettings = AppSettings(
            defaultBackendID: BackendProfiles.kokoroTTS.id,
            defaultModelID: "wrong-model",
            exportFormat: .mp3
        ).normalized
        precondition(kokoroSettings.defaultBackendID == BackendProfiles.kokoroTTS.id)
        precondition(kokoroSettings.defaultModelID == "kokoro/default")
        precondition(kokoroSettings.exportFormat == .wav)

        let configuredKokoro = AppSettings(
            defaultBackendID: BackendProfiles.kokoroTTS.id,
            defaultModelID: "kokoro/custom",
            backendConnections: [
                BackendProfiles.kokoroTTS.id: BackendConnectionSettings(
                    connectionKind: .installedDockerImage,
                    dockerImage: "kokoro-local",
                    serviceBaseURL: "http://127.0.0.1:8880",
                    healthPath: "/health",
                    modelID: "kokoro/custom",
                    defaultVoice: "af_heart"
                )
            ]
        ).normalized
        let kokoroProfile = configuredKokoro.selectedBackendProfile
        precondition(kokoroProfile.runtime == .docker)
        precondition(kokoroProfile.installMethod == .manual)
        precondition(kokoroProfile.dockerImage == "kokoro-local")
        precondition(kokoroProfile.healthCheckURL?.absoluteString == "http://127.0.0.1:8880/health")
        precondition(configuredKokoro.defaultModelID == "kokoro/custom")

        let catalogBackedKokoro = AppSettings(
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
        ).normalized
        precondition(catalogBackedKokoro.defaultModelID == "tts-1")
        precondition(catalogBackedKokoro.defaultVoice == "af_heart")
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
        let adapter = KokoroHTTPAdapter(profile: profile, projectRoot: root, fileStore: fileStore, client: client)
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
                    "docker_image": image
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
                return snapshot.message == "sending request to Kokoro"
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
