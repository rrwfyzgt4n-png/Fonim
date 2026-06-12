import Foundation

public enum AppDefaults {
    public static let projectRoot = URL(fileURLWithPath: "/Volumes/FastData/vibevoice-docker", isDirectory: true)
    public static let dockerImage = "vibevoice-cpu"
    public static let modelPath = "microsoft/VibeVoice-Realtime-0.5B"
    public static let defaultVoice = "en-carter_man"
    public static let defaultCFGScale = "1.8"
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
}

public extension URL {
    var historyDirectory: URL { appendingPathComponent("history", isDirectory: true) }
    var outputsDirectory: URL { appendingPathComponent("outputs", isDirectory: true) }
    var recoveredDirectory: URL { appendingPathComponent("recovered", isDirectory: true) }
    var hfCacheDirectory: URL { appendingPathComponent("hf-cache", isDirectory: true) }
    var stagingInputFile: URL { appendingPathComponent("input.txt", isDirectory: false) }
    var generatedWAVFile: URL { outputsDirectory.appendingPathComponent("input_generated.wav", isDirectory: false) }
}
