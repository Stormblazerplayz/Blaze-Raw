import AVFoundation
import Foundation

/// Plays the songs. Keeps playing when the screen is locked.
@MainActor
final class AudioPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var current: SavedSong?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func play(_ song: SavedSong, url: URL) {
        // Pressing play on the song that is already loaded just resumes it.
        if current?.id == song.id, let p = player {
            p.play()
            isPlaying = true
            startTimer()
            return
        }
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            current = song
            duration = p.duration
            position = 0
            isPlaying = true
            startTimer()
        } catch {
            errorMessage = "Could not play this song: \(error.localizedDescription)"
        }
    }

    func toggle() {
        guard let p = player else { return }
        if p.isPlaying {
            p.pause()
            isPlaying = false
            stopTimer()
        } else {
            p.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(to seconds: Double) {
        guard let p = player else { return }
        let clamped = min(max(seconds, 0), max(p.duration - 0.05, 0))
        p.currentTime = clamped
        position = clamped
    }

    func stop() {
        stopTimer()
        player?.stop()
        player = nil
        current = nil
        isPlaying = false
        position = 0
        duration = 0
    }

    /// Stops playback if the song that is playing gets deleted.
    func stopIfPlaying(_ song: SavedSong) {
        if current?.id == song.id { stop() }
    }

    // MARK: timer

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player else { return }
                self.position = p.currentTime
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = false
            self.position = 0
            self.player?.currentTime = 0
            self.stopTimer()
        }
    }
}
