import Foundation

public enum AppDefaults {
    public static let projectRoot = URL(fileURLWithPath: "/Volumes/FastData/vibevoice-docker", isDirectory: true)
    public static let dockerImage = "vibevoice-cpu"
    public static let modelPath = "microsoft/VibeVoice-Realtime-0.5B"
    public static let defaultVoice = "en-carter"
    public static let defaultCFGScale = "1.8"
}

public extension URL {
    var historyDirectory: URL { appendingPathComponent("history", isDirectory: true) }
    var outputsDirectory: URL { appendingPathComponent("outputs", isDirectory: true) }
    var recoveredDirectory: URL { appendingPathComponent("recovered", isDirectory: true) }
    var hfCacheDirectory: URL { appendingPathComponent("hf-cache", isDirectory: true) }
    var stagingInputFile: URL { appendingPathComponent("input.txt", isDirectory: false) }
    var generatedWAVFile: URL { outputsDirectory.appendingPathComponent("input_generated.wav", isDirectory: false) }
}
