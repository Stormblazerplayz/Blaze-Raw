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
    /// True once you set the tempo yourself (slider, Tap tempo or the "Use ... tempo" button).
    /// Until then the tempo follows your genre and mood, and a new variation also gets a new tempo.
    @Published private(set) var tempoIsManual = false

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

    /// The tempo slider. Moving it means "I choose the tempo", so it stops following genre and mood.
    var tempoBinding: Binding<Double> {
        Binding(
            get: { self.settings.tempo },
            set: { newValue in self.setTempo(newValue) }
        )
    }

    func apply(_ preset: StylePreset) {
        settings = preset.settings(seed: settings.seed)
        selectedPreset = preset
        tempoIsManual = false
    }

    /// Picks the kind of music. `nil` means "Any": only the mood decides the style.
    /// A new genre has its own tempo range, so the tempo moves to a fitting one (and stops being "manual").
    func setGenre(_ genre: Genre?) {
        settings.genre = genre
        selectedPreset = nil
        tempoIsManual = false
        settings.tempo = clampTempo(autoTempo())
    }

    func setMood(_ mood: Mood) {
        settings.mood = mood
        selectedPreset = nil
        applyAutoTempoIfNotManual()
    }

    /// Sets the tempo by hand (slider, Tap tempo, "Use ... tempo").
    func setTempo(_ tempo: Double) {
        settings.tempo = clampTempo(tempo)
        tempoIsManual = true
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

    /// Same genre, mood and instruments, a brand-new song. While the tempo is not set by hand it also
    /// gets a new tempo (inside the genre's range) so variations differ in speed too.
    func newVariation() {
        settings.seed = UInt64.random(in: 1...999_999)
        applyAutoTempoIfNotManual()
    }

    /// Pick everything at random for a surprise.
    func randomizeAll() {
        let genre: Genre? = Double.random(in: 0...1) < 0.85 ? Genre.allCases.randomElement() : nil
        let mood = Mood.allCases.randomElement() ?? .dark
        let seed = UInt64.random(in: 1...999_999)
        var tempo = (mood.suggestedTempo + Double.random(in: -12...12)).rounded()
        if let genre = genre {
            tempo = genre.tempo(for: mood, seed: seed)
        }
        // Ambient music usually has no beat.
        let drumChance: Double = genre == .ambient ? 0.15 : 0.8
        var instruments = Set<InstrumentKind>()
        if Double.random(in: 0...1) < drumChance { instruments.insert(.drums) }
        let others = InstrumentKind.allCases.filter { $0 != .drums }.shuffled()
        for inst in others.prefix(Int.random(in: 2...4)) { instruments.insert(inst) }
        var vocals = Set<VocalStyle>()
        if Bool.random() {
            for v in VocalStyle.allCases.shuffled().prefix(Int.random(in: 1...2)) { vocals.insert(v) }
        }
        settings = SongSettings(
            tempo: clampTempo(tempo),
            mood: mood,
            genre: genre,
            instruments: instruments,
            vocals: vocals,
            key: Bool.random() ? nil : Int.random(in: 0...11),
            lengthSeconds: [60.0, 90, 120].randomElement() ?? 90,
            intensity: (Double.random(in: 0.4...1) * 10).rounded() / 10,
            grit: (Double.random(in: 0...1) * 10).rounded() / 10,
            justIntonation: Bool.random(),
            seed: seed
        ).clamped()
        selectedPreset = nil
        tempoIsManual = false
    }

    /// Load the settings of an older song so you can make a new version of it.
    /// The tempo of that song is kept (a remix is "the same, but new"), but the variation number is new:
    /// the same number would give back exactly the same song.
    func load(_ other: SongSettings) {
        settings = other
        settings.seed = UInt64.random(in: 1...999_999)
        selectedPreset = nil
        tempoIsManual = true
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

    // MARK: tempo helpers

    /// What the "Use ... tempo" button uses: the genre's tempo for this mood (or the mood's own tempo).
    var suggestedTempoValue: Double {
        if let genre = settings.genre {
            return clampTempo(genre.tempo(for: settings.mood, seed: settings.seed))
        }
        return clampTempo(settings.mood.suggestedTempo)
    }

    var suggestedTempoName: String {
        settings.genre?.title ?? settings.mood.title
    }

    /// Text of the button, for example "Use Nu-Disco tempo (119)".
    var suggestedTempoTitle: String {
        "Use \(suggestedTempoName) tempo (\(Int(suggestedTempoValue)))"
    }

    func useSuggestedTempo() {
        setTempo(suggestedTempoValue)
    }

    private func clampTempo(_ tempo: Double) -> Double {
        let safe = tempo.isFinite ? tempo : 120
        return min(max(safe.rounded(), SongSettings.minTempo), SongSettings.maxTempo)
    }

    /// The tempo the app picks for you: inside the genre's range, leaning slower or faster with the mood.
    /// Without a genre it is the mood's tempo with a small wobble from the variation number.
    private func autoTempo() -> Double {
        if let genre = settings.genre {
            return genre.tempo(for: settings.mood, seed: settings.seed)
        }
        var g = SeededRNG(seed: settings.seed).fork(56)
        let wobble = (g.double() - 0.5) * 16
        return settings.mood.suggestedTempo + wobble
    }

    private func applyAutoTempoIfNotManual() {
        guard !tempoIsManual else { return }
        settings.tempo = clampTempo(autoTempo())
    }

    var summary: String {
        let minutes = Int(settings.lengthSeconds) / 60
        let seconds = Int(settings.lengthSeconds) % 60
        let length = String(format: "%d:%02d", minutes, seconds)
        var parts: [String] = []
        if let genre = settings.genre { parts.append(genre.title) }
        parts.append(settings.mood.title)
        parts.append("\(Int(settings.tempo)) BPM")
        parts.append(length)
        parts.append("\(settings.instruments.count) instruments")
        parts.append(settings.vocals.isEmpty ? "no vocals" : "\(settings.vocals.count) vocal\(settings.vocals.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
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
