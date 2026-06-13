import Foundation

public enum AppDefaults {
    public static let projectRoot = URL(fileURLWithPath: "/Volumes/FastData/vibevoice-docker", isDirectory: true)
    public static let dockerImage = "vibevoice-cpu"
    public static let modelPath = "microsoft/VibeVoice-Realtime-0.5B"
    public static let defaultVoice = "en-carter_man"
    public static let defaultCFGScale = "1.8"
    public static let defaultDDPMInferenceSteps = 5
    public static let availableCFGScales = (26...60).map { cfgScaleLabel(Double($0) / 20.0) }
    public static let availableDDPMInferenceSteps = Array(5...20)
    public static let availableVoices = [
        "de-spk0_man",
        "de-spk1_woman",
        "en-carter_man",
        "en-davis_man",
        "en-emma_woman",
        "en-frank_man",
        "en-grace_woman",
        "en-mike_man",
        "fr-spk0_man",
        "fr-spk1_woman",
        "in-samuel_man",
        "it-spk0_woman",
        "it-spk1_man",
        "jp-spk0_man",
        "jp-spk1_woman",
        "kr-spk0_woman",
        "kr-spk1_man",
        "nl-spk0_man",
        "nl-spk1_woman",
        "pl-spk0_man",
        "pl-spk1_woman",
        "pt-spk0_woman",
        "pt-spk1_man",
        "sp-spk0_woman",
        "sp-spk1_man"
    ]

    private static func cfgScaleLabel(_ value: Double) -> String {
        let raw = String(format: "%.2f", value)
        if raw.hasSuffix("00") {
            return String(raw.dropLast(3))
        }
        if raw.hasSuffix("0") {
            return String(raw.dropLast())
        }
        return raw
    }
}

public extension URL {
    var historyDirectory: URL { appendingPathComponent("history", isDirectory: true) }
    var outputsDirectory: URL { appendingPathComponent("outputs", isDirectory: true) }
    var recoveredDirectory: URL { appendingPathComponent("recovered", isDirectory: true) }
    var workspaceDirectory: URL { appendingPathComponent("workspace", isDirectory: true) }
    var projectsDirectory: URL { workspaceDirectory.appendingPathComponent("projects", isDirectory: true) }
    var scriptsDirectory: URL { workspaceDirectory.appendingPathComponent("scripts", isDirectory: true) }
    var batchesDirectory: URL { workspaceDirectory.appendingPathComponent("batches", isDirectory: true) }
    var hfCacheDirectory: URL { appendingPathComponent("hf-cache", isDirectory: true) }
    var dockerOverridesDirectory: URL { appendingPathComponent("docker_overrides", isDirectory: true) }
    var inferenceScriptOverrideFile: URL { dockerOverridesDirectory.appendingPathComponent("realtime_model_inference_from_file.py", isDirectory: false) }
    var stagingInputFile: URL { appendingPathComponent("input.txt", isDirectory: false) }
    var generatedWAVFile: URL { outputsDirectory.appendingPathComponent("input_generated.wav", isDirectory: false) }
}
