import Foundation

public struct VibeVoiceGenerationEstimate: Equatable {
    public let estimatedSeconds: TimeInterval
    public let sampleCount: Int
    public let scope: String

    public init(estimatedSeconds: TimeInterval, sampleCount: Int, scope: String) {
        self.estimatedSeconds = estimatedSeconds
        self.sampleCount = sampleCount
        self.scope = scope
    }
}

public protocol VibeVoiceGenerationEstimating {
    func estimate(for job: GenerationJob, ddpmInferenceSteps: Int) -> VibeVoiceGenerationEstimate?
}

public final class VibeVoiceGenerationEstimator: VibeVoiceGenerationEstimating {
    private let fileStore: SessionFileStore

    public init(fileStore: SessionFileStore) {
        self.fileStore = fileStore
    }

    public func estimate(for job: GenerationJob, ddpmInferenceSteps: Int) -> VibeVoiceGenerationEstimate? {
        let wordCount = max(1, TextMetrics.wordCount(in: job.inputText))
        let samples = loadSamples()
        guard !samples.isEmpty else { return nil }

        let exact = samples.filter { $0.voice == job.voiceID && $0.ddpmInferenceSteps == ddpmInferenceSteps }
        if let estimate = estimate(from: exact, wordCount: wordCount, ddpmInferenceSteps: ddpmInferenceSteps, scope: "voice+steps", minimumSamples: 2) {
            return estimate
        }

        let sameVoice = samples.filter { $0.voice == job.voiceID }
        if let estimate = estimate(from: sameVoice, wordCount: wordCount, ddpmInferenceSteps: ddpmInferenceSteps, scope: "voice", minimumSamples: 3) {
            return estimate
        }

        let sameSteps = samples.filter { $0.ddpmInferenceSteps == ddpmInferenceSteps }
        if let estimate = estimate(from: sameSteps, wordCount: wordCount, ddpmInferenceSteps: ddpmInferenceSteps, scope: "steps", minimumSamples: 3) {
            return estimate
        }

        return estimate(from: samples, wordCount: wordCount, ddpmInferenceSteps: ddpmInferenceSteps, scope: "all-vibevoice", minimumSamples: 5)
    }

    private func loadSamples() -> [Sample] {
        let records = (try? fileStore.loadSessions()) ?? []
        return records.compactMap { record in
            let metadata = record.metadata
            guard metadata.status == .completed,
                  isVibeVoiceSession(metadata),
                  metadata.inputWordCount > 0,
                  let ddpmInferenceSteps = metadata.ddpmInferenceSteps,
                  ddpmInferenceSteps > 0,
                  let runtimeSeconds = runtimeSeconds(for: metadata),
                  runtimeSeconds >= 5 else {
                return nil
            }

            return Sample(
                voice: metadata.voice,
                ddpmInferenceSteps: ddpmInferenceSteps,
                wordCount: metadata.inputWordCount,
                runtimeSeconds: runtimeSeconds,
                createdAt: metadata.createdAt
            )
        }
        .sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    private func isVibeVoiceSession(_ metadata: SessionMetadata) -> Bool {
        if metadata.dockerImage == AppDefaults.dockerImage {
            return true
        }
        return metadata.dockerCommand.contains(AppDefaults.modelPath) ||
            metadata.dockerCommand.contains("realtime_model_inference_from_file.py")
    }

    private func runtimeSeconds(for metadata: SessionMetadata) -> TimeInterval? {
        if let generationTimeSeconds = metadata.generationTimeSeconds, generationTimeSeconds > 0 {
            return generationTimeSeconds
        }
        guard let completedAt = metadata.completedAt else { return nil }
        let elapsed = completedAt.timeIntervalSince(metadata.createdAt)
        return elapsed > 0 ? elapsed : nil
    }

    private func estimate(
        from samples: [Sample],
        wordCount: Int,
        ddpmInferenceSteps: Int,
        scope: String,
        minimumSamples: Int
    ) -> VibeVoiceGenerationEstimate? {
        let recentSamples = Array(samples.prefix(80))
        guard recentSamples.count >= minimumSamples else { return nil }

        let rates = recentSamples.compactMap { sample -> Double? in
            let denominator = Double(sample.wordCount * sample.ddpmInferenceSteps)
            guard denominator > 0 else { return nil }
            return sample.runtimeSeconds / denominator
        }
        guard let medianRate = median(rates), medianRate > 0 else { return nil }

        let seconds = max(12, medianRate * Double(wordCount * ddpmInferenceSteps))
        return VibeVoiceGenerationEstimate(
            estimatedSeconds: seconds,
            sampleCount: recentSamples.count,
            scope: scope
        )
    }

    private func median(_ values: [Double]) -> Double? {
        let sorted = values.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private struct Sample {
        let voice: String
        let ddpmInferenceSteps: Int
        let wordCount: Int
        let runtimeSeconds: TimeInterval
        let createdAt: Date
    }
}
