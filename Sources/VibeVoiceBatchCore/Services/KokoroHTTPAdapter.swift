import Foundation

public struct KokoroSpeechRequest: Equatable, Sendable {
    public var endpoint: URL
    public var modelID: String
    public var voiceID: String
    public var inputText: String
    public var responseFormat: String

    public init(
        endpoint: URL,
        modelID: String,
        voiceID: String,
        inputText: String,
        responseFormat: String = "wav"
    ) {
        self.endpoint = endpoint
        self.modelID = modelID
        self.voiceID = voiceID
        self.inputText = inputText
        self.responseFormat = responseFormat
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
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": request.modelID,
            "voice": request.voiceID,
            "input": request.inputText,
            "response_format": request.responseFormat
        ])

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

public final class KokoroHTTPAdapter: EngineAdapter {
    public let profile: BackendProfile
    private let backendManager: BackendManager
    private let fileStore: SessionFileStore
    private let client: KokoroSpeechGenerating
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.kokoro-adapter")
    private var activeJobID: String?
    private var cancelledJobIDs: Set<String> = []
    private var progressByJobID: [String: GenerationProgressSnapshot] = [:]

    public init(
        profile: BackendProfile = BackendProfiles.kokoroTTS,
        projectRoot: URL = AppDefaults.projectRoot,
        backendManager: BackendManager? = nil,
        fileStore: SessionFileStore? = nil,
        client: KokoroSpeechGenerating? = nil
    ) {
        self.profile = profile
        self.backendManager = backendManager ?? BackendManager(projectRoot: projectRoot)
        self.fileStore = fileStore ?? SessionFileStore(projectRoot: projectRoot)
        self.client = client ?? KokoroSpeechClient()
    }

    public func healthCheck() async -> BackendHealthReport {
        await backendManager.healthReportAsync(for: profile)
    }

    public func listVoices() async throws -> [VoiceDescriptor] {
        profile.requiredModels.isEmpty ? [] : [
            VoiceDescriptor(id: "af_heart", displayName: "af_heart")
        ]
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
        }
        defer {
            stateQueue.sync {
                activeJobID = nil
                cancelledJobIDs.remove(job.id)
                progressByJobID[job.id] = nil
            }
        }

        var metadata = workspace.record.metadata
        metadata.dockerImage = job.settings.extraParameters["docker_image"] ?? profile.dockerImage ?? "Kokoro service"
        metadata.dockerCommand = commandDisplay
        try? fileStore.writeMetadata(metadata, in: workspace.record.folderURL)

        let session = (try? fileStore.loadRecord(folderURL: workspace.record.folderURL)) ?? workspace.record
        events(.sessionStarted(session))
        events(.status("Running"))

        var logText = initialLog(session: session, job: job, endpoint: endpoint, startedAt: startedAt)

        func appendLog(_ text: String) {
            logText += text
            try? fileStore.appendLog(text, to: session.folderURL)
            events(.log(text))
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

        emitProgress(
            jobID: job.id,
            fraction: 0.10,
            message: "sending request to Kokoro",
            startedAt: startedAt,
            events: events
        )
        appendLog("Sending request to Kokoro.\n")

        do {
            let response = try await client.generateSpeech(
                KokoroSpeechRequest(
                    endpoint: endpoint,
                    modelID: job.modelID,
                    voiceID: job.voiceID,
                    inputText: job.inputText,
                    responseFormat: "wav"
                )
            )

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

    var displayName: String {
        switch self {
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }
}
