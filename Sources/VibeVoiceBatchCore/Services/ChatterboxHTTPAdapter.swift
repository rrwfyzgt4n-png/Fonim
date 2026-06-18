import Foundation

public struct ChatterboxTTSRequest: Equatable, Sendable {
    public var endpoint: URL
    public var voiceID: String
    public var inputText: String
    public var outputFormat: String
    public var splitText: Bool
    public var chunkSize: Int
    public var temperature: Double
    public var exaggeration: Double
    public var cfgWeight: Double
    public var seed: Int
    public var speedFactor: Double
    public var language: String

    public init(
        endpoint: URL,
        voiceID: String,
        inputText: String,
        outputFormat: String = "wav",
        splitText: Bool = true,
        chunkSize: Int = 120,
        temperature: Double = 0.8,
        exaggeration: Double = 1.3,
        cfgWeight: Double = 0.5,
        seed: Int = 0,
        speedFactor: Double = 1.0,
        language: String = "en"
    ) {
        self.endpoint = endpoint
        self.voiceID = voiceID
        self.inputText = inputText
        self.outputFormat = outputFormat
        self.splitText = splitText
        self.chunkSize = chunkSize
        self.temperature = temperature
        self.exaggeration = exaggeration
        self.cfgWeight = cfgWeight
        self.seed = seed
        self.speedFactor = speedFactor
        self.language = language
    }

    public var voiceMode: String {
        voiceID.hasPrefix("reference:") ? "clone" : "predefined"
    }

    public var voiceFilename: String {
        if voiceID.hasPrefix("reference:") {
            return String(voiceID.dropFirst("reference:".count))
        }
        return voiceID
    }
}

public struct ChatterboxTTSResponse: Equatable, Sendable {
    public var data: Data
    public var contentType: String?
    public var statusCode: Int

    public init(data: Data, contentType: String? = nil, statusCode: Int = 200) {
        self.data = data
        self.contentType = contentType
        self.statusCode = statusCode
    }
}

public enum ChatterboxSpeechClientError: Error, Equatable, LocalizedError {
    case invalidResponse(String)
    case httpFailure(statusCode: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return message
        case .httpFailure(let statusCode, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "Chatterbox returned HTTP \(statusCode)."
            }
            return "Chatterbox returned HTTP \(statusCode): \(detail)"
        }
    }
}

public protocol ChatterboxSpeechGenerating: AnyObject {
    func generateSpeech(_ request: ChatterboxTTSRequest) async throws -> ChatterboxTTSResponse
    func cancel()
}

public final class ChatterboxSpeechClient: ChatterboxSpeechGenerating, @unchecked Sendable {
    private let session: URLSession
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.chatterbox-client")
    private var activeTask: URLSessionDataTask?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func generateSpeech(_ request: ChatterboxTTSRequest) async throws -> ChatterboxTTSResponse {
        var urlRequest = URLRequest(url: request.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("audio/wav", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 1_800

        var payload: [String: Any] = [
            "text": request.inputText,
            "voice_mode": request.voiceMode,
            "output_format": request.outputFormat,
            "split_text": request.splitText,
            "chunk_size": request.chunkSize,
            "temperature": request.temperature,
            "exaggeration": request.exaggeration,
            "cfg_weight": request.cfgWeight,
            "seed": request.seed,
            "speed_factor": request.speedFactor,
            "language": request.language,
            "stream": false
        ]
        if request.voiceMode == "clone" {
            payload["reference_audio_filename"] = request.voiceFilename
        } else {
            payload["predefined_voice_id"] = request.voiceFilename
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: urlRequest) { [weak self] data, response, error in
                    self?.stateQueue.sync {
                        self?.activeTask = nil
                    }

                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.resume(throwing: ChatterboxSpeechClientError.invalidResponse("Chatterbox did not return an HTTP response."))
                        return
                    }

                    let bodyData = data ?? Data()
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        let body = String(decoding: bodyData.prefix(4_000), as: UTF8.self)
                        continuation.resume(throwing: ChatterboxSpeechClientError.httpFailure(statusCode: httpResponse.statusCode, body: body))
                        return
                    }

                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
                    guard bodyData.startsWithRIFFWave || contentType?.localizedCaseInsensitiveContains("audio") == true else {
                        let body = String(decoding: bodyData.prefix(4_000), as: UTF8.self)
                        continuation.resume(throwing: ChatterboxSpeechClientError.invalidResponse(body.isEmpty ? "Chatterbox returned a non-audio response." : body))
                        return
                    }

                    continuation.resume(
                        returning: ChatterboxTTSResponse(
                            data: bodyData,
                            contentType: contentType,
                            statusCode: httpResponse.statusCode
                        )
                    )
                }

                stateQueue.sync {
                    activeTask = task
                }
                task.resume()
            }
        } onCancel: { [weak self] in
            self?.cancel()
        }
    }

    public func cancel() {
        stateQueue.sync {
            activeTask?.cancel()
            activeTask = nil
        }
    }
}

public protocol ChatterboxLogFollowing: AnyObject {
    func followLogs(
        since: Date,
        profile: BackendProfile,
        endpoint: URL?,
        onChunk: @escaping (String) -> Void
    ) -> ChatterboxLogFollowHandle?
}

public final class ChatterboxLogFollowHandle {
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.chatterbox-log-handle")
    private var hasStopped = false
    private let stopAction: () -> Void

    public init(stopAction: @escaping () -> Void) {
        self.stopAction = stopAction
    }

    public func stop() {
        stateQueue.sync {
            guard !hasStopped else { return }
            hasStopped = true
            stopAction()
        }
    }

    deinit {
        stop()
    }
}

public final class ChatterboxDockerLogFollower: ChatterboxLogFollowing {
    public init() {}

    public func followLogs(
        since: Date,
        profile: BackendProfile,
        endpoint: URL?,
        onChunk: @escaping (String) -> Void
    ) -> ChatterboxLogFollowHandle? {
        guard let docker = dockerExecutablePath(),
              let containerName = containerName(for: profile, endpoint: endpoint, docker: docker) else {
            return nil
        }

        let sinceText = ISO8601DateFormatter().string(from: since)
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let deliveryQueue = DispatchQueue(label: "local.vibevoice.batch.chatterbox-log-delivery-\(UUID().uuidString)")

        process.executableURL = URL(fileURLWithPath: docker)
        process.arguments = ["logs", "--timestamps", "--since", sinceText, "-f", containerName]
        process.standardOutput = stdout
        process.standardError = stderr

        let handler: (FileHandle) -> Void = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            deliveryQueue.async {
                onChunk(text)
            }
        }
        stdout.fileHandleForReading.readabilityHandler = handler
        stderr.fileHandleForReading.readabilityHandler = handler

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        return ChatterboxLogFollowHandle {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private func dockerExecutablePath() -> String? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/bin/docker"
        ]
        if let candidate = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return candidate
        }
        return commandOutput(executablePath: "/usr/bin/which", arguments: ["docker"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    private func containerName(for profile: BackendProfile, endpoint: URL?, docker: String) -> String? {
        if let containerName = profile.containerName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !containerName.isEmpty {
            return containerName
        }

        guard let output = commandOutput(
            executablePath: docker,
            arguments: ["ps", "--format", "{{.Names}}\t{{.Image}}\t{{.Ports}}"]
        ) else {
            return nil
        }

        let port = endpoint?.port ?? profile.exposedPort
        let rows = output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if let port,
           let match = rows.first(where: { row in
               let lower = row.lowercased()
               return lower.contains("chatterbox") && lower.contains(":\(port)->")
           }) {
            return match.split(separator: "\t").first.map(String.init)
        }

        if let match = rows.first(where: { $0.lowercased().contains("chatterbox") }) {
            return match.split(separator: "\t").first.map(String.init)
        }

        if let port,
           let match = rows.first(where: { $0.contains(":\(port)->") }) {
            return match.split(separator: "\t").first.map(String.init)
        }

        return nil
    }

    private func commandOutput(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

public final class ChatterboxHTTPAdapter: EngineAdapter {
    public let profile: BackendProfile
    private let backendManager: BackendManager
    private let fileStore: SessionFileStore
    private let client: ChatterboxSpeechGenerating
    private let logFollower: ChatterboxLogFollowing
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.chatterbox-adapter")
    private var activeJobID: String?
    private var cancelledJobIDs: Set<String> = []
    private var progressByJobID: [String: GenerationProgressSnapshot] = [:]
    private var progressKeyByJobID: [String: String] = [:]

    public init(
        profile: BackendProfile = BackendProfiles.chatterboxTTS,
        projectRoot: URL = AppDefaults.projectRoot,
        backendManager: BackendManager? = nil,
        fileStore: SessionFileStore? = nil,
        client: ChatterboxSpeechGenerating? = nil,
        logFollower: ChatterboxLogFollowing? = nil
    ) {
        self.profile = profile
        self.backendManager = backendManager ?? BackendManager(projectRoot: projectRoot)
        self.fileStore = fileStore ?? SessionFileStore(projectRoot: projectRoot)
        self.client = client ?? ChatterboxSpeechClient()
        self.logFollower = logFollower ?? ChatterboxDockerLogFollower()
    }

    public func healthCheck() async -> BackendHealthReport {
        await backendManager.healthReportAsync(for: profile)
    }

    public func listVoices() async throws -> [VoiceDescriptor] {
        ChatterboxVoiceCatalog.voiceDescriptors
    }

    public func listModels() async throws -> [ModelDescriptor] {
        profile.requiredModels.map { model in
            ModelDescriptor(id: model.id, displayName: model.displayName, role: profile.role)
        }
    }

    public func generate(
        _ job: GenerationJob,
        events: @escaping (GenerationEvent) -> Void
    ) async throws -> GenerationRecord {
        let startedAt = Date()
        let endpoint = generationEndpoint(for: job)
        let commandDisplay = endpoint.map { "POST \($0.absoluteString)" } ?? "Chatterbox service endpoint not configured"

        let workspace: GenerationWorkspace
        do {
            workspace = try fileStore.createGenerationSession(
                text: job.inputText,
                voice: job.voiceID,
                cfgScale: job.settings.cfgScale,
                ddpmInferenceSteps: job.settings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps,
                now: job.createdAt
            )
        } catch {
            throw BackendError.generationFailed(
                GenerationErrorRecord(
                    title: "Could not create generation session",
                    explanation: "The app could not create a protected history folder for this Chatterbox generation.",
                    recoverySuggestion: "Check that the project folder is writable and try again.",
                    technicalDetails: error.localizedDescription
                )
            )
        }

        stateQueue.sync {
            activeJobID = job.id
            cancelledJobIDs.remove(job.id)
            progressByJobID[job.id] = nil
        }
        defer {
            stateQueue.sync {
                activeJobID = nil
                cancelledJobIDs.remove(job.id)
                progressByJobID[job.id] = nil
                progressKeyByJobID[job.id] = nil
            }
        }

        var metadata = workspace.record.metadata
        metadata.dockerImage = job.settings.extraParameters["docker_image"] ?? profile.dockerImage ?? "Chatterbox service"
        metadata.dockerCommand = commandDisplay
        try? fileStore.writeMetadata(metadata, in: workspace.record.folderURL)

        let session = (try? fileStore.loadRecord(folderURL: workspace.record.folderURL)) ?? workspace.record
        events(.sessionStarted(session))
        events(.status("Running"))

        let logQueue = DispatchQueue(label: "local.vibevoice.batch.chatterbox-log-\(job.id)")
        var logText = initialLog(session: session, job: job, endpoint: endpoint, startedAt: startedAt)

        @discardableResult
        func appendLog(_ text: String) -> String {
            let currentLog = logQueue.sync { () -> String in
                logText += text
                return logText
            }
            try? fileStore.appendLog(text, to: session.folderURL)
            events(.log(text))
            return currentLog
        }

        try? fileStore.replaceLog(logText, in: session.folderURL)

        do {
            if let recovered = try fileStore.recoverExistingGeneratedWAV(reason: "pre_run_chatterbox") {
                appendLog("Recovered existing staging WAV before Chatterbox run: \(recovered.path)\n")
            }
        } catch {
            appendLog("Could not inspect staging WAV before Chatterbox run: \(error.localizedDescription)\n")
        }

        guard let endpoint else {
            appendLog("FAILED: Chatterbox service endpoint is not configured.\n")
            let record = finalize(
                session: session,
                job: job,
                status: .failed,
                startedAt: startedAt,
                outputURL: nil,
                extraLog: "",
                errorMessage: "Chatterbox needs a service URL and /tts endpoint before it can generate audio."
            )
            events(.status(record.status.displayName))
            return record
        }

        let request = makeRequest(endpoint: endpoint, job: job)
        emitProgress(
            jobID: job.id,
            fraction: 0.08,
            message: "sending request to Chatterbox",
            startedAt: startedAt,
            events: events
        )
        appendLog("Sending request to Chatterbox.\n")
        appendLog(requestLog(request))
        let logHandle = logFollower.followLogs(
            since: startedAt.addingTimeInterval(-2),
            profile: profile,
            endpoint: endpoint
        ) { [weak self] chunk in
            guard let self else { return }
            let currentLog = appendLog(chunk)
            self.emitChatterboxProgress(
                jobID: job.id,
                logText: currentLog,
                startedAt: startedAt,
                events: events
            )
        }
        if logHandle == nil {
            appendLog("Chatterbox runtime log stream unavailable; progress will use request milestones.\n")
        } else {
            appendLog("Following Chatterbox runtime logs for live progress.\n")
        }
        defer {
            logHandle?.stop()
        }

        do {
            let response = try await client.generateSpeech(request)

            if isCancelled(jobID: job.id) {
                appendLog("Generation cancelled after Chatterbox returned audio.\n")
                let record = finalize(
                    session: session,
                    job: job,
                    status: .cancelled,
                    startedAt: startedAt,
                    outputURL: nil,
                    extraLog: "",
                    errorMessage: nil
                )
                events(.status(record.status.displayName))
                return record
            }

            emitProgress(
                jobID: job.id,
                fraction: 0.90,
                message: "received audio from Chatterbox",
                startedAt: startedAt,
                events: events
            )
            appendLog("Chatterbox returned \(response.data.count) bytes (\(response.contentType ?? "audio")).\n")
            let outputURL = try fileStore.writeOutputWAV(response.data, to: session.folderURL)
            appendLog("Saved output: \(outputURL.path)\n")

            let record = finalize(
                session: session,
                job: job,
                status: .completed,
                startedAt: startedAt,
                outputURL: outputURL,
                extraLog: "",
                errorMessage: nil
            )
            if let normalized = try? await normalizeOutput(EngineOutput(fileURL: outputURL, format: .wav)) {
                events(.output(normalized))
            }
            events(.status(record.status.displayName))
            return record
        } catch {
            let status: SessionStatus = isCancelled(jobID: job.id) || (error as? URLError)?.code == .cancelled ? .cancelled : .failed
            appendLog("\(status == .cancelled ? "Cancelled" : "FAILED"): \(error.localizedDescription)\n")
            let record = finalize(
                session: session,
                job: job,
                status: status,
                startedAt: startedAt,
                outputURL: nil,
                extraLog: "",
                errorMessage: error.localizedDescription
            )
            events(.status(record.status.displayName))
            return record
        }
    }

    public func cancel(jobID: String) async {
        let shouldCancel = stateQueue.sync { () -> Bool in
            cancelledJobIDs.insert(jobID)
            return activeJobID == jobID
        }
        if shouldCancel {
            client.cancel()
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

    private func generationEndpoint(for job: GenerationJob) -> URL? {
        if let value = job.settings.extraParameters["generate_endpoint"],
           let url = URL(string: value),
           url.scheme != nil,
           url.host != nil {
            return url
        }
        return profile.generateEndpoint
    }

    private func makeRequest(endpoint: URL, job: GenerationJob) -> ChatterboxTTSRequest {
        let extra = job.settings.extraParameters
        return ChatterboxTTSRequest(
            endpoint: endpoint,
            voiceID: job.voiceID,
            inputText: job.inputText,
            outputFormat: extra["output_format"] ?? "wav",
            splitText: extra.boolean("split_text") ?? true,
            chunkSize: extra.integer("chunk_size") ?? 120,
            temperature: extra.double("temperature") ?? 0.8,
            exaggeration: extra.double("exaggeration") ?? 1.3,
            cfgWeight: extra.double("cfg_weight") ?? 0.5,
            seed: extra.integer("seed") ?? 0,
            speedFactor: extra.double("speed_factor") ?? 1.0,
            language: extra["language"] ?? "en"
        )
    }

    private func initialLog(
        session: SessionRecord,
        job: GenerationJob,
        endpoint: URL?,
        startedAt: Date
    ) -> String {
        """
        Session: \(session.id)
        Job: \(job.id)
        Created: \(ISO8601DateFormatter().string(from: startedAt))
        Backend: \(profile.displayName)
        Runtime: Chatterbox HTTP service
        Endpoint: \(endpoint?.absoluteString ?? "not configured")
        Model: \(job.modelID)
        Voice: \(job.voiceID)

        Starting generation...

        """
    }

    private func requestLog(_ request: ChatterboxTTSRequest) -> String {
        """
        Voice mode: \(request.voiceMode)
        Voice file: \(request.voiceFilename)
        Output format: \(request.outputFormat)
        Split text: \(request.splitText)
        Chunk size: \(request.chunkSize)
        Temperature: \(request.temperature)
        Exaggeration: \(request.exaggeration)
        CFG weight: \(request.cfgWeight)
        Seed: \(request.seed)
        Speed factor: \(request.speedFactor)
        Language: \(request.language)

        """
    }

    private func emitProgress(
        jobID: String,
        fraction: Double,
        message: String,
        startedAt: Date,
        events: @escaping (GenerationEvent) -> Void
    ) {
        let snapshot = GenerationProgressSnapshot(
            jobID: jobID,
            fractionComplete: fraction,
            elapsedSeconds: Date().timeIntervalSince(startedAt),
            estimatedRemainingSeconds: nil,
            message: message
        )
        stateQueue.sync {
            progressByJobID[jobID] = snapshot
        }
        events(.progress(snapshot))
    }

    private func emitChatterboxProgress(
        jobID: String,
        logText: String,
        startedAt: Date,
        events: @escaping (GenerationEvent) -> Void
    ) {
        guard let progress = GenerationOutputParser.latestChatterboxProgress(in: logText) else {
            return
        }

        let elapsedSeconds = Date().timeIntervalSince(startedAt)
        let snapshot = GenerationProgressSnapshot(
            jobID: jobID,
            fractionComplete: progress.fraction,
            currentStep: progress.currentStep,
            totalSteps: progress.totalSteps,
            elapsedSeconds: elapsedSeconds,
            estimatedRemainingSeconds: progress.estimatedRemainingSeconds(elapsedSeconds: elapsedSeconds),
            message: progress.displayMessage
        )
        let shouldEmit = stateQueue.sync { () -> Bool in
            guard progressKeyByJobID[jobID] != progress.progressKey else {
                return false
            }
            progressKeyByJobID[jobID] = progress.progressKey
            progressByJobID[jobID] = snapshot
            return true
        }
        guard shouldEmit else { return }
        events(.progress(snapshot))
    }

    private func finalize(
        session: SessionRecord,
        job: GenerationJob,
        status: SessionStatus,
        startedAt: Date,
        outputURL: URL?,
        extraLog: String,
        errorMessage: String?
    ) -> GenerationRecord {
        let completedAt = Date()
        var metadata = session.metadata
        metadata.completedAt = completedAt
        metadata.status = status
        metadata.generationTimeSeconds = completedAt.timeIntervalSince(startedAt)
        if let outputURL {
            metadata.outputFile = outputURL.path
            if let duration = try? WaveAudioInspector.durationSeconds(for: outputURL) {
                metadata.audioDurationSeconds = duration
                if duration > 0 {
                    metadata.rtf = metadata.generationTimeSeconds.map { $0 / duration }
                }
            }
        }

        let finalLog = extraLog + "\nChatterbox generation \(status.displayName.lowercased()).\n"
        try? fileStore.appendLog(finalLog, to: session.folderURL)
        try? fileStore.writeMetadata(metadata, in: session.folderURL)

        let reloaded = (try? fileStore.loadRecord(folderURL: session.folderURL)) ?? SessionRecord(
            folderURL: session.folderURL,
            metadata: metadata,
            inputText: job.inputText,
            logText: finalLog,
            metadataJSON: ""
        )
        return generationRecord(from: reloaded, job: job, errorMessage: errorMessage)
    }

    private func generationRecord(
        from session: SessionRecord,
        job: GenerationJob,
        errorMessage: String?
    ) -> GenerationRecord {
        GenerationRecord(
            id: session.id,
            jobID: job.id,
            inputText: session.inputText,
            createdAt: session.metadata.createdAt,
            completedAt: session.metadata.completedAt,
            status: generationStatus(from: session.metadata.status),
            backendID: profile.id,
            backendDisplayName: profile.displayName,
            engineType: profile.engineType,
            modelID: job.modelID,
            voiceID: session.metadata.voice,
            settings: job.settings,
            exportPath: session.metadata.outputFile,
            durationSeconds: session.metadata.audioDurationSeconds,
            logs: session.logText,
            error: errorRecord(for: session.metadata.status, message: errorMessage)
        )
    }

    private func generationStatus(from status: SessionStatus) -> GenerationRecordStatus {
        switch status {
        case .draft:
            return .queued
        case .running:
            return .running
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        }
    }

    private func errorRecord(for status: SessionStatus, message: String?) -> GenerationErrorRecord? {
        switch status {
        case .failed:
            return GenerationErrorRecord(
                title: "Chatterbox generation failed",
                explanation: message ?? "Chatterbox could not complete this narration.",
                recoverySuggestion: "Check the Chatterbox service, then duplicate the session as new or retry."
            )
        case .cancelled:
            return GenerationErrorRecord(
                title: "Generation cancelled",
                explanation: "The Chatterbox request was stopped before a completed output was produced.",
                recoverySuggestion: "Duplicate the session as new if you want to run it again."
            )
        case .draft, .running, .completed:
            return nil
        }
    }

    private func isCancelled(jobID: String) -> Bool {
        stateQueue.sync {
            cancelledJobIDs.contains(jobID)
        }
    }
}

private extension Data {
    var startsWithRIFFWave: Bool {
        count >= 12 &&
            self[0] == 0x52 &&
            self[1] == 0x49 &&
            self[2] == 0x46 &&
            self[3] == 0x46 &&
            self[8] == 0x57 &&
            self[9] == 0x41 &&
            self[10] == 0x56 &&
            self[11] == 0x45
    }
}

private extension Dictionary where Key == String, Value == String {
    func double(_ key: String) -> Double? {
        guard let value = self[key] else { return nil }
        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func integer(_ key: String) -> Int? {
        guard let value = self[key] else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func boolean(_ key: String) -> Bool? {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }
        if ["true", "yes", "1"].contains(value) {
            return true
        }
        if ["false", "no", "0"].contains(value) {
            return false
        }
        return nil
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
