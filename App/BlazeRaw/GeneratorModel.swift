import BlazeEngine
import Foundation
import SwiftUI

/// A tiny thread-safe "stop" button for the song renderer.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// Holds everything you pick on the Create screen and makes the song.
@MainActor
final class GeneratorModel: ObservableObject {
    @Published var settings: SongSettings
    @Published var selectedPreset: StylePreset?
    @Published private(set) var isGenerating = false
    @Published private(set) var progress: Double = 0
    @Published var errorMessage: String?

    private var cancelFlag = CancelFlag()
    private var taps: [Date] = []

    init() {
        let seed = UInt64.random(in: 1...999_999)
        settings = StylePreset.aloboi.settings(seed: seed)
        selectedPreset = .aloboi
    }

    // MARK: picking things

    /// A binding that also switches the preset label to "Custom" when you change something by hand.
    func bind<T>(_ keyPath: WritableKeyPath<SongSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in
                self.settings[keyPath: keyPath] = newValue
                self.selectedPreset = nil
            }
        )
    }

    func apply(_ preset: StylePreset) {
        settings = preset.settings(seed: settings.seed)
        selectedPreset = preset
    }

    func setMood(_ mood: Mood) {
        settings.mood = mood
        selectedPreset = nil
    }

    func setTempo(_ tempo: Double) {
        settings.tempo = min(max(tempo.rounded(), SongSettings.minTempo), SongSettings.maxTempo)
        selectedPreset = nil
    }

    func toggle(_ instrument: InstrumentKind) {
        if settings.instruments.contains(instrument) {
            // Keep at least one instrument on so the song is never empty.
            if settings.instruments.count > 1 { settings.instruments.remove(instrument) }
        } else {
            settings.instruments.insert(instrument)
        }
        selectedPreset = nil
    }

    func toggle(_ vocal: VocalStyle) {
        if settings.vocals.contains(vocal) {
            settings.vocals.remove(vocal)
        } else {
            settings.vocals.insert(vocal)
        }
        selectedPreset = nil
    }

    func clearVocals() {
        settings.vocals = []
        selectedPreset = nil
    }

    func newVariation() {
        settings.seed = UInt64.random(in: 1...999_999)
    }

    /// Pick everything at random for a surprise.
    func randomizeAll() {
        let mood = Mood.allCases.randomElement() ?? .dark
        var instruments = Set<InstrumentKind>()
        if Double.random(in: 0...1) < 0.8 { instruments.insert(.drums) }
        let others = InstrumentKind.allCases.filter { $0 != .drums }.shuffled()
        for inst in others.prefix(Int.random(in: 2...4)) { instruments.insert(inst) }
        var vocals = Set<VocalStyle>()
        if Bool.random() {
            for v in VocalStyle.allCases.shuffled().prefix(Int.random(in: 1...2)) { vocals.insert(v) }
        }
        settings = SongSettings(
            tempo: (mood.suggestedTempo + Double.random(in: -12...12)).rounded(),
            mood: mood,
            instruments: instruments,
            vocals: vocals,
            key: Bool.random() ? nil : Int.random(in: 0...11),
            lengthSeconds: [60.0, 90, 120].randomElement() ?? 90,
            intensity: (Double.random(in: 0.4...1) * 10).rounded() / 10,
            grit: (Double.random(in: 0...1) * 10).rounded() / 10,
            justIntonation: Bool.random(),
            seed: UInt64.random(in: 1...999_999)
        ).clamped()
        selectedPreset = nil
    }

    /// Load the settings of an older song so you can make a new version of it.
    func load(_ other: SongSettings) {
        settings = other
        selectedPreset = nil
    }

    /// Tap along with a song to find its tempo.
    func tapTempo() {
        let now = Date()
        if let last = taps.last, now.timeIntervalSince(last) > 2.0 { taps = [] }
        taps.append(now)
        if taps.count > 8 { taps.removeFirst(taps.count - 8) }
        guard taps.count >= 3 else { return }
        let intervals = zip(taps.dropFirst(), taps).map { $0.timeIntervalSince($1) }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        guard average > 0 else { return }
        setTempo(60.0 / average)
    }

    var summary: String {
        let minutes = Int(settings.lengthSeconds) / 60
        let seconds = Int(settings.lengthSeconds) % 60
        let length = String(format: "%d:%02d", minutes, seconds)
        return "\(length) · \(Int(settings.tempo)) BPM · \(settings.mood.title) · "
            + "\(settings.instruments.count) instruments · "
            + (settings.vocals.isEmpty ? "no vocals" : "\(settings.vocals.count) vocal\(settings.vocals.count == 1 ? "" : "s")")
    }

    // MARK: making the song

    func generate(library: SongLibrary, player: AudioPlayerModel) {
        guard !isGenerating else { return }
        isGenerating = true
        progress = 0
        errorMessage = nil
        let wanted = settings
        let flag = CancelFlag()
        cancelFlag = flag

        Task.detached(priority: .userInitiated) { [weak self] in
            let rendered = SongEngine.render(wanted, progress: { value in
                Task { @MainActor [weak self] in self?.progress = value }
            }, isCancelled: { flag.isSet })

            guard let rendered else {
                await MainActor.run { self?.isGenerating = false }
                return
            }

            do {
                let fileName = SongStorage.uniqueFileName(for: rendered.title)
                let url = SongStorage.songsDirectory.appendingPathComponent(fileName)
                try WAV.write(rendered, to: url)
                let saved = SavedSong(id: UUID(),
                                      title: rendered.title,
                                      createdAt: Date(),
                                      settings: rendered.settings,
                                      duration: rendered.durationSeconds,
                                      fileName: fileName,
                                      keyName: rendered.keyName,
                                      scaleName: rendered.scaleName)
                await MainActor.run {
                    library.add(saved)
                    self?.isGenerating = false
                    player.play(saved, url: url)
                }
            } catch {
                await MainActor.run {
                    self?.isGenerating = false
                    self?.errorMessage = "Could not save the song: \(error.localizedDescription)"
                }
            }
        }
    }

    func cancel() {
        cancelFlag.set()
    }
}
