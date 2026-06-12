import Foundation
import VibeVoiceBatchCore

@main
struct VibeVoiceBatchCoreChecks {
    static func main() throws {
        try checkDraftCreatesPermanentSessionFiles()
        try checkSessionIDsNeverCollide()
        try checkRecoverExistingGeneratedWAVMovesToRecovered()
        try checkMoveGeneratedWAVToSessionUsesOutputWAV()
        try checkReadsPCMDuration()
        try checkParsesLiveProgressAndFinalSummary()
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

        let summaryText = """
        Input file: /app/input.txt
        Output file: /app/outputs/input_generated.wav
        Speaker names: en-mike_man
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
        precondition(summary.prefilledTextTokens == 389)
        precondition(summary.generatedSpeechTokens == 930)
        precondition(summary.totalTokens == 1467)
        precondition(summary.generationTimeSeconds == 329.40)
        precondition(summary.audioDurationSeconds == 123.47)
        precondition(summary.rtf == 2.67)
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
