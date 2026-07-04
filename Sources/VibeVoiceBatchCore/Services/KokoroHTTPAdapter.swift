import Foundation

public struct KokoroSpeechRequest: Equatable, Sendable {
    public var endpoint: URL
    public var modelID: String
    public var voiceID: String
    public var inputText: String
    public var responseFormat: String
    public var speed: Double?
    public var extraPayload: [String: String]

    public init(
        endpoint: URL,
        modelID: String,
        voiceID: String,
        inputText: String,
        responseFormat: String = "wav",
        speed: Double? = nil,
        extraPayload: [String: String] = [:]
    ) {
        self.endpoint = endpoint
        self.modelID = modelID
        self.voiceID = voiceID
        self.inputText = inputText
        self.responseFormat = responseFormat
        self.speed = speed
        self.extraPayload = extraPayload
    }
}

public struct KokoroSpeechResponse: Equatable, Sendable {
    public var data: Data
    public var contentType: String?
    public var statusCode: Int

    public init(data: Data, contentType: String? = nil, statusCode: Int = 200) {
        self.data = data
        self.contentType = contentType
        self.statusCode = statusCode
    }
}

public enum KokoroSpeechClientError: Error, Equatable, LocalizedError {
    case invalidResponse(String)
    case httpFailure(statusCode: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return message
        case .httpFailure(let statusCode, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "Kokoro returned HTTP \(statusCode)."
            }
            return "Kokoro returned HTTP \(statusCode): \(detail)"
        }
    }
}

public protocol KokoroSpeechGenerating: AnyObject {
    func generateSpeech(_ request: KokoroSpeechRequest) async throws -> KokoroSpeechResponse
    func cancel()
}

public final class KokoroSpeechClient: KokoroSpeechGenerating, @unchecked Sendable {
    private let session: URLSession
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.kokoro-client")
    private var activeTask: URLSessionDataTask?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func generateSpeech(_ request: KokoroSpeechRequest) async throws -> KokoroSpeechResponse {
        var urlRequest = URLRequest(url: request.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("audio/wav", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 600
        var payload: [String: Any] = [
            "model": request.modelID,
            "voice": request.voiceID,
            "input": request.inputText,
            "response_format": request.responseFormat
        ]
        if let speed = request.speed {
            payload["speed"] = speed
        }
        for (key, value) in request.extraPayload where payload[key] == nil {
            payload[key] = value
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
                        continuation.resume(throwing: KokoroSpeechClientError.invalidResponse("Kokoro did not return an HTTP response."))
                        return
                    }

                    let bodyData = data ?? Data()
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        let body = String(decoding: bodyData.prefix(4_000), as: UTF8.self)
                        continuation.resume(throwing: KokoroSpeechClientError.httpFailure(statusCode: httpResponse.statusCode, body: body))
                        return
                    }

                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
                    guard bodyData.startsWithRIFFWave || contentType?.localizedCaseInsensitiveContains("audio") == true else {
                        let body = String(decoding: bodyData.prefix(4_000), as: UTF8.self)
                        continuation.resume(throwing: KokoroSpeechClientError.invalidResponse(body.isEmpty ? "Kokoro returned a non-audio response." : body))
                        return
                    }

                    continuation.resume(
                        returning: KokoroSpeechResponse(
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

public protocol KokoroLogFollowing: AnyObject {
    func followLogs(
        since: Date,
        profile: BackendProfile,
        endpoint: URL?,
        onChunk: @escaping (String) -> Void
    ) -> KokoroLogFollowHandle?
}

public final class KokoroLogFollowHandle {
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.kokoro-log-handle")
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

public final class KokoroDockerLogFollower: KokoroLogFollowing {
    public init() {}

    public func followLogs(
        since: Date,
        profile: BackendProfile,
        endpoint: URL?,
        onChunk: @escaping (String) -> Void
    ) -> KokoroLogFollowHandle? {
        guard let docker = dockerExecutablePath(),
              let containerName = containerName(for: profile, endpoint: endpoint, docker: docker) else {
            return nil
        }

        let sinceText = ISO8601DateFormatter().string(from: since)
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let deliveryQueue = DispatchQueue(label: "local.vibevoice.batch.kokoro-log-delivery-\(UUID().uuidString)")

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

        return KokoroLogFollowHandle {
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
            .trimmedOrNil
    }

    private func containerName(for profile: BackendProfile, endpoint: URL?, docker: String) -> String? {
        if let containerName = profile.containerName?.trimmedOrNil {
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
            .filter { $0.trimmedOrNil != nil }

        if let port,
           let match = rows.first(where: { row in
               let lower = row.lowercased()
               return lower.contains("kokoro") && lower.contains(":\(port)->")
           }) {
            return match.split(separator: "\t").first.map(String.init)
        }

        if let match = rows.first(where: { $0.lowercased().contains("kokoro") }) {
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

public final class KokoroHTTPAdapter: EngineAdapter {
    public let profile: BackendProfile
    private let backendManager: BackendManager
    private let fileStore: SessionFileStore
    private let client: KokoroSpeechGenerating
    private let logFollower: KokoroLogFollowing
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.kokoro-adapter")
    private var activeJobID: String?
    private var cancelledJobIDs: Set<String> = []
    private var progressByJobID: [String: GenerationProgressSnapshot] = [:]
    private var progressKeyByJobID: [String: String] = [:]

    public init(
        profile: BackendProfile = BackendProfiles.kokoroTTS,
        projectRoot: URL = AppDefaults.projectRoot,
        backendManager: BackendManager? = nil,
        fileStore: SessionFileStore? = nil,
        client: KokoroSpeechGenerating? = nil,
        logFollower: KokoroLogFollowing? = nil
    ) {
        self.profile = profile
        self.backendManager = backendManager ?? BackendManager(projectRoot: projectRoot)
        self.fileStore = fileStore ?? SessionFileStore(projectRoot: projectRoot)
        self.client = client ?? KokoroSpeechClient()
        self.logFollower = logFollower ?? KokoroDockerLogFollower()
    }

    public func healthCheck() async -> BackendHealthReport {
        await backendManager.healthReportAsync(for: profile)
    }

    public func listVoices() async throws -> [VoiceDescriptor] {
        let catalog = await backendManager.catalogReportAsync(for: profile)
        if !catalog.voices.isEmpty {
            return catalog.voices.map { voice in
                let fallback = KokoroVoiceCatalog.descriptor(for: voice.id, displayName: voice.displayName)
                return VoiceDescriptor(
                    id: voice.id,
                    displayName: voice.displayName,
                    locale: voice.locale ?? fallback.locale,
                    traits: voice.traits.isEmpty ? fallback.traits : voice.traits
                )
            }
        }
        return KokoroVoiceCatalog.voiceDescriptors
    }

    public func listModels() async throws -> [ModelDescriptor] {
        let catalog = await backendManager.catalogReportAsync(for: profile)
        if !catalog.models.isEmpty {
            return catalog.models.map { model in
                ModelDescriptor(id: model.id, displayName: model.displayName, role: profile.role)
            }
        }
        return profile.requiredModels.map { model in
            ModelDescriptor(id: model.id, displayName: model.displayName, role: profile.role)
        }
    }

    public func generate(
        _ job: GenerationJob,
        events: @escaping (GenerationEvent) -> Void
    ) async throws -> GenerationRecord {
        let startedAt = Date()
        let endpoint = generationEndpoint(for: job)
        let commandDisplay = endpoint.map { "POST \($0.absoluteString)" } ?? "Kokoro service endpoint not configured"

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
                    explanation: "The app could not create a protected history folder for this Kokoro generation.",
                    recoverySuggestion: "Check that the project folder is writable and try again.",
                    technicalDetails: error.localizedDescription
                )
            )
        }

        stateQueue.sync {
            activeJobID = job.id
            cancelledJobIDs.remove(job.id)
            progressByJobID[job.id] = nil
            progressKeyByJobID[job.id] = nil
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
        metadata.dockerImage = job.settings.extraParameters["docker_image"] ?? profile.dockerImage ?? "Kokoro service"
        metadata.dockerCommand = commandDisplay
        try? fileStore.writeMetadata(metadata, in: workspace.record.folderURL)

        let session = (try? fileStore.loadRecord(folderURL: workspace.record.folderURL)) ?? workspace.record
        events(.sessionStarted(session))
        events(.status("Running"))

        let logQueue = DispatchQueue(label: "local.vibevoice.batch.kokoro-log-\(job.id)")
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
            if let recovered = try fileStore.recoverExistingGeneratedWAV(reason: "pre_run_kokoro") {
                appendLog("Recovered existing staging WAV before Kokoro run: \(recovered.path)\n")
            }
        } catch {
            appendLog("Could not inspect staging WAV before Kokoro run: \(error.localizedDescription)\n")
        }

        guard let endpoint else {
            appendLog("FAILED: Kokoro service endpoint is not configured.\n")
            let record = finalize(
                session: session,
                job: job,
                status: .failed,
                startedAt: startedAt,
                outputURL: nil,
                extraLog: "",
                errorMessage: "Kokoro needs a service URL and generate endpoint before it can generate audio."
            )
            events(.status(record.status.displayName))
            return record
        }

        let logHandle = logFollower.followLogs(
            since: startedAt.addingTimeInterval(-2),
            profile: profile,
            endpoint: endpoint
        ) { [weak self] chunk in
            guard let self else { return }
            let currentLog = appendLog(chunk)
            self.emitKokoroProgress(
                jobID: job.id,
                logText: currentLog,
                startedAt: startedAt,
                events: events
            )
        }
        if logHandle == nil {
            appendLog("Kokoro runtime log stream unavailable; progress will use request milestones.\n")
        } else {
            appendLog("Following Kokoro runtime logs for live progress.\n")
        }
        defer {
            logHandle?.stop()
        }

        emitProgress(
            jobID: job.id,
            fraction: 0.10,
            message: "sending request to Kokoro",
            startedAt: startedAt,
            events: events
        )
        appendLog("Sending request to Kokoro.\n")
        let request = makeRequest(endpoint: endpoint, job: job)
        appendLog(requestLog(request))

        do {
            let response = try await client.generateSpeech(request)

            if isCancelled(jobID: job.id) {
                appendLog("Generation cancelled after Kokoro returned audio.\n")
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
                fraction: 0.86,
                message: "received audio from Kokoro",
                startedAt: startedAt,
                events: events
            )
            appendLog("Kokoro returned \(response.data.count) bytes (\(response.contentType ?? "audio")).\n")
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

    private func makeRequest(endpoint: URL, job: GenerationJob) -> KokoroSpeechRequest {
        let extra = job.settings.extraParameters
        let reservedKeys = Set([
            "generate_endpoint",
            "health_url",
            "docker_image",
            "backend_display_name",
            "response_format",
            "speed"
        ])
        let extraPayload = extra.filter { key, _ in !reservedKeys.contains(key) }
        return KokoroSpeechRequest(
            endpoint: endpoint,
            modelID: job.modelID,
            voiceID: job.voiceID,
            inputText: job.inputText,
            responseFormat: extra["response_format"] ?? "wav",
            speed: extra.double("speed"),
            extraPayload: extraPayload
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
        Runtime: Kokoro HTTP service
        Endpoint: \(endpoint?.absoluteString ?? "not configured")
        Model: \(job.modelID)
        Voice: \(job.voiceID)

        Starting generation...

        """
    }

    private func requestLog(_ request: KokoroSpeechRequest) -> String {
        var lines = [
            "Model: \(request.modelID)",
            "Voice: \(request.voiceID)",
            "Response format: \(request.responseFormat)"
        ]
        if let speed = request.speed {
            lines.append("Speed: \(speed)")
        }
        if !request.extraPayload.isEmpty {
            lines.append("Extra options: \(request.extraPayload.keys.sorted().joined(separator: ", "))")
        }
        return lines.joined(separator: "\n") + "\n\n"
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

    private func emitKokoroProgress(
        jobID: String,
        logText: String,
        startedAt: Date,
        events: @escaping (GenerationEvent) -> Void
    ) {
        guard let progress = GenerationOutputParser.latestKokoroProgress(in: logText) else {
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
        if shouldEmit {
            events(.progress(snapshot))
        }
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

        let finalLog = extraLog + "\nKokoro generation \(status.displayName.lowercased()).\n"
        try? fileStore.appendLog(finalLog, to: session.folderURL)
        try? fileStore.writeMetadata(metadata, in: session.folderURL)

        let reloaded = (try? fileStore.loadRecord(folderURL: session.folderURL)) ?? SessionRecord(
            folderURL: session.folderURL,
            metadata: metadata,
            inputText: job.inputText,
            logText: finalLog,
            metadataJSON: "",
            hasOutputWAV: outputURL != nil
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
            error: errorRecord(for: session.metadata.status, message: errorMessage)
        )
    }

    private func errorRecord(for status: SessionStatus, message: String?) -> GenerationErrorRecord? {
        switch status {
        case .failed:
            return GenerationErrorRecord(
                title: "Kokoro generation failed",
                explanation: message ?? "Kokoro could not complete this narration.",
                recoverySuggestion: "Check the Kokoro service, then duplicate the session as new or retry."
            )
        case .cancelled:
            return GenerationErrorRecord(
                title: "Generation cancelled",
                explanation: "The Kokoro request was stopped before a completed output was produced.",
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
        self[key].flatMap(Double.init)
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
