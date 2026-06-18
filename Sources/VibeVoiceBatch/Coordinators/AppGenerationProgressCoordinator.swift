import Foundation
import VibeVoiceBatchCore

struct GenerationQueueProgressUpdate: Equatable {
    var progressFraction: Double?
    var currentStep: Int?
    var totalSteps: Int?
    var elapsedSeconds: TimeInterval?
    var estimatedRemainingSeconds: TimeInterval?
    var shouldUpdateEstimatedRemainingSeconds = false
    var statusMessage: String
}

@MainActor
final class AppGenerationProgressCoordinator {
    private(set) var latestLine = "Ready"
    private(set) var estimatedProgressFraction: Double?
    private(set) var estimatedRemainingSeconds: TimeInterval?
    private(set) var phaseName = "idle"
    private(set) var ticker = GenerationTickerState.idle

    private var liveLogBySessionID: [String: String] = [:]
    private var activeSessionID: String?

    func resetToIdle() {
        latestLine = "Ready"
        estimatedProgressFraction = nil
        estimatedRemainingSeconds = nil
        phaseName = "idle"
        ticker = .idle
        activeSessionID = nil
    }

    func prepareForBackendCheck() {
        estimatedProgressFraction = nil
        estimatedRemainingSeconds = nil
        phaseName = "checking backend"
        setLatestLine("Checking backend", elapsedSeconds: 0)
    }

    func startGeneration(voice: String, cfgScale: String, ddpmInferenceSteps: Int) {
        estimatedProgressFraction = nil
        estimatedRemainingSeconds = nil
        phaseName = "starting"
        ticker = .started(
            voice: voice,
            cfgScale: cfgScale,
            ddpmInferenceSteps: ddpmInferenceSteps
        )
        setLatestLine("Starting queued generation", elapsedSeconds: 0)
    }

    func startSession(id: String) {
        activeSessionID = id
        liveLogBySessionID[id] = ""
        setLatestLine("Session created: \(id)", elapsedSeconds: ticker.elapsedSeconds)
    }

    func ingest(snapshot: GenerationProgressSnapshot, fallbackElapsedSeconds: TimeInterval) -> GenerationQueueProgressUpdate {
        if let fraction = snapshot.fractionComplete {
            estimatedProgressFraction = fraction
        }
        if let remaining = snapshot.estimatedRemainingSeconds {
            estimatedRemainingSeconds = remaining
        }
        let elapsed = snapshot.elapsedSeconds ?? fallbackElapsedSeconds
        phaseName = snapshot.message
        setLatestLine(snapshot.message, elapsedSeconds: elapsed)

        return GenerationQueueProgressUpdate(
            progressFraction: snapshot.fractionComplete,
            currentStep: snapshot.currentStep,
            totalSteps: snapshot.totalSteps,
            elapsedSeconds: elapsed,
            estimatedRemainingSeconds: snapshot.estimatedRemainingSeconds,
            shouldUpdateEstimatedRemainingSeconds: true,
            statusMessage: snapshot.message
        )
    }

    func appendLog(_ chunk: String, sessionID: String, elapsedSeconds: TimeInterval) -> Bool {
        liveLogBySessionID[sessionID, default: ""] += chunk
        guard sessionID == activeSessionID else { return false }

        if let latest = latestTerminalLine(from: liveLogBySessionID[sessionID, default: ""]) {
            setLatestLine(latest, elapsedSeconds: elapsedSeconds)
        }
        ticker = ticker.ingesting(
            logText: liveLogBySessionID[sessionID, default: ""],
            elapsed: elapsedSeconds
        )
        return true
    }

    @discardableResult
    func setLatestLine(_ line: String, elapsedSeconds: TimeInterval) -> GenerationQueueProgressUpdate? {
        latestLine = line
        return updateEstimatedProgress(from: line, elapsedSeconds: elapsedSeconds)
    }

    func tick(elapsedSeconds: TimeInterval, previousElapsedSeconds: TimeInterval, isActive: Bool) {
        if let remaining = estimatedRemainingSeconds {
            let delta = max(0, elapsedSeconds - previousElapsedSeconds)
            estimatedRemainingSeconds = max(0, remaining - delta)
        }
        if isActive {
            ticker = ticker.ticking(elapsed: elapsedSeconds)
        }
    }

    func finish(logText: String, elapsedSeconds: TimeInterval, status: GenerationRecordStatus) {
        ticker = ticker
            .ingesting(logText: logText, elapsed: elapsedSeconds)
            .finished(
                message: status.displayName,
                elapsed: elapsedSeconds,
                phase: status.tickerPhase
            )
        estimatedProgressFraction = status == .completed ? 1 : estimatedProgressFraction
        estimatedRemainingSeconds = nil
        phaseName = status.displayName.lowercased()
        setLatestLine(status.displayName, elapsedSeconds: elapsedSeconds)
        activeSessionID = nil
    }

    func fail(elapsedSeconds: TimeInterval) {
        ticker = ticker.finished(message: "Failed", elapsed: elapsedSeconds, phase: .failed)
        estimatedRemainingSeconds = nil
        phaseName = "failed"
        setLatestLine("Failed", elapsedSeconds: elapsedSeconds)
        activeSessionID = nil
    }

    func logText(for record: SessionRecord) -> String {
        liveLogBySessionID[record.id] ?? record.logText
    }

    func liveLog(sessionID: String, fallback: String) -> String {
        liveLogBySessionID[sessionID, default: fallback]
    }

    private func updateEstimatedProgress(
        from line: String,
        elapsedSeconds currentElapsedSeconds: TimeInterval
    ) -> GenerationQueueProgressUpdate? {
        if let estimate = GenerationOutputParser.latestEstimatedProgress(in: line) {
            let displayPhase = estimate.displayPhase
            phaseName = displayPhase
            estimatedProgressFraction = estimate.fraction
            let elapsed = estimate.elapsedSeconds ?? currentElapsedSeconds
            if let reportedElapsed = estimate.elapsedSeconds, reportedElapsed > ticker.elapsedSeconds {
                ticker = ticker.ticking(elapsed: reportedElapsed)
            }
            if let estimated = estimate.estimatedSeconds, estimated > elapsed {
                estimatedRemainingSeconds = estimated - elapsed
            } else {
                estimatedRemainingSeconds = nil
            }

            return GenerationQueueProgressUpdate(
                progressFraction: estimate.fraction,
                elapsedSeconds: elapsed,
                estimatedRemainingSeconds: estimatedRemainingSeconds,
                shouldUpdateEstimatedRemainingSeconds: true,
                statusMessage: displayPhase.capitalized
            )
        }

        if let progress = GenerationOutputParser.latestProgress(in: line) {
            phaseName = "Current Step"
            estimatedProgressFraction = progress.fraction
            let elapsed = progress.reportedElapsedSeconds ?? currentElapsedSeconds
            estimatedRemainingSeconds = progress.estimatedRemainingSeconds(elapsedSeconds: elapsed)

            return GenerationQueueProgressUpdate(
                progressFraction: progress.fraction,
                currentStep: progress.currentStep,
                totalSteps: progress.maxSteps,
                elapsedSeconds: elapsed,
                estimatedRemainingSeconds: estimatedRemainingSeconds,
                shouldUpdateEstimatedRemainingSeconds: true,
                statusMessage: "Current Step"
            )
        }

        phaseName = phaseName(for: line)
        return nil
    }

    private func phaseName(for line: String) -> String {
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
