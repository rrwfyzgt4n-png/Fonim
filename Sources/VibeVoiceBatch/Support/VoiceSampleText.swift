import VibeVoiceBatchCore

enum VoiceSampleText {
    static func sample(for profile: BackendProfile, voiceID: String) -> String {
        let display = VoiceDisplayFormatter.descriptor(for: voiceID).displayName
        switch profile.engineType {
        case .chatterbox:
            return "Hello, this is \(display). I am reading a short local sample so you can judge pacing, clarity, and expression before using this voice in a longer narration."
        case .kokoro:
            return "Hello, this is \(display). This quick sample is for checking tone, pronunciation, and speed on your local Kokoro backend."
        case .vibeVoiceTTS:
            return "Hello, this is \(display). This is a brief narration sample for evaluating voice character, rhythm, and long-form reading style."
        case .comfyUITTS, .f5TTS, .cosyVoice, .custom:
            return "Hello, this is \(display). This short sample is for evaluating the selected local narration backend."
        }
    }
}
