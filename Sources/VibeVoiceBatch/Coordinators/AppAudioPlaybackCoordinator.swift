import AVFoundation
import Foundation

@MainActor
final class AppAudioPlaybackCoordinator: NSObject, AVAudioPlayerDelegate {
    struct State: Equatable {
        var isPlaying = false
        var sessionID: String?
        var elapsedSeconds: TimeInterval = 0
        var durationSeconds: TimeInterval = 0

        var progressFraction: Double? {
            guard durationSeconds > 0 else { return nil }
            return min(1, max(0, elapsedSeconds / durationSeconds))
        }
    }

    var onStateChange: ((State) -> Void)?
    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var state = State()
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?

    deinit {
        playbackTimer?.invalidate()
    }

    func isPlaying(sessionID: String) -> Bool {
        state.isPlaying && state.sessionID == sessionID
    }

    func play(outputURL: URL, sessionID: String) {
        do {
            if state.isPlaying {
                stop()
            }

            let player = try AVAudioPlayer(contentsOf: outputURL)
            player.delegate = self
            player.prepareToPlay()
            player.play()

            audioPlayer = player
            state = State(
                isPlaying: true,
                sessionID: sessionID,
                elapsedSeconds: player.currentTime,
                durationSeconds: player.duration
            )
            emitState()
            startPlaybackTimer()
            onStatus?("Playing \(sessionID)")
        } catch {
            onError?("Could not play WAV: \(error.localizedDescription)")
        }
    }

    func stop(status: String? = nil) {
        audioPlayer?.stop()
        audioPlayer = nil
        stopPlaybackTimer(reset: true)
        state = State()
        emitState()
        if let status {
            onStatus?(status)
        }
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer(reset: false)
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let audioPlayer = self.audioPlayer else { return }
                self.state.elapsedSeconds = audioPlayer.currentTime
                self.state.durationSeconds = audioPlayer.duration
                self.emitState()
            }
        }
        playbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPlaybackTimer(reset: Bool) {
        playbackTimer?.invalidate()
        playbackTimer = nil
        if reset {
            state.elapsedSeconds = 0
            state.durationSeconds = 0
        }
    }

    private func emitState() {
        onStateChange?(state)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop(status: flag ? "Playback finished" : "Playback stopped")
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.stop(status: "Playback failed")
            if let error {
                self.onError?("Could not play WAV: \(error.localizedDescription)")
            }
        }
    }
}
