import Foundation

// MARK: - What the user can pick

public enum Mood: String, CaseIterable, Codable, Identifiable, Sendable {
    // The five newer moods come first so they show up first in the app.
    case relaxed, introspective, melancholic, romantic, uplifting
    case dark, happy, chill, energetic, sad, dreamy, epic, raw

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .introspective: return "Introspective"
        case .melancholic: return "Melancholic"
        case .romantic: return "Romantic"
        case .uplifting: return "Uplifting"
        case .dark: return "Dark"
        case .happy: return "Happy"
        case .chill: return "Chill"
        case .energetic: return "Energetic"
        case .sad: return "Sad"
        case .dreamy: return "Dreamy"
        case .epic: return "Epic"
        case .raw: return "Raw"
        }
    }

    public var emoji: String {
        switch self {
        case .relaxed: return "🍃"
        case .introspective: return "🪞"
        case .melancholic: return "🍂"
        case .romantic: return "💞"
        case .uplifting: return "🌅"
        case .dark: return "🌑"
        case .happy: return "😄"
        case .chill: return "😌"
        case .energetic: return "⚡️"
        case .sad: return "🌧"
        case .dreamy: return "🌈"
        case .epic: return "🏔"
        case .raw: return "🔥"
        }
    }

    /// A good starting tempo for this mood.
    public var suggestedTempo: Double {
        switch self {
        case .relaxed: return 88
        case .introspective: return 84
        case .melancholic: return 76
        case .romantic: return 86
        case .uplifting: return 120
        case .dark: return 120
        case .happy: return 118
        case .chill: return 82
        case .energetic: return 128
        case .sad: return 72
        case .dreamy: return 90
        case .epic: return 96
        case .raw: return 140
        }
    }

    /// -1...1: how far into the faster (+) or slower (-) part of a genre's tempo range this mood sits.
    var tempoLean: Double {
        switch self {
        case .relaxed: return -0.2
        case .introspective: return -0.25
        case .melancholic: return -0.3
        case .romantic: return -0.1
        case .uplifting: return 0.25
        case .dark: return 0
        case .happy: return 0.1
        case .chill: return -0.2
        case .energetic: return 0.3
        case .sad: return -0.3
        case .dreamy: return -0.1
        case .epic: return 0
        case .raw: return 0.2
        }
    }
}

/// The kind of music. Every genre has its own tempo range, drum grooves, bass lines, chords,
/// sounds, effects and song layout. Leave it out (`nil`) for an open, genre-free sound.
public enum Genre: String, CaseIterable, Codable, Identifiable, Sendable {
    case electronic, synthpop, pop, chillwave, downtempo, ambient, dreamPop, indietronica, lofi, nuDisco, edm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .electronic: return "Electronic"
        case .synthpop: return "Synthpop"
        case .pop: return "Pop"
        case .chillwave: return "Chillwave"
        case .downtempo: return "Downtempo"
        case .ambient: return "Ambient"
        case .dreamPop: return "Dream Pop"
        case .indietronica: return "Indietronica"
        case .lofi: return "Lo-fi"
        case .nuDisco: return "Nu-Disco"
        case .edm: return "EDM"
        }
    }

    public var emoji: String {
        switch self {
        case .electronic: return "🎛"
        case .synthpop: return "🕶"
        case .pop: return "🎤"
        case .chillwave: return "🏖"
        case .downtempo: return "🛋"
        case .ambient: return "🌌"
        case .dreamPop: return "☁️"
        case .indietronica: return "🧩"
        case .lofi: return "📼"
        case .nuDisco: return "🪩"
        case .edm: return "🎆"
        }
    }

    public var blurb: String {
        switch self {
        case .electronic: return "Pulsing synths, rolling bass and a driving beat."
        case .synthpop: return "Bright 80s-style synths, a big snare and a catchy hook."
        case .pop: return "Clean, catchy and made to sing along to."
        case .chillwave: return "Hazy, washed-out synths and a slow, faded beat."
        case .downtempo: return "Deep bass, warm keys and a slow, rolling groove."
        case .ambient: return "Slow, floating textures with little or no beat."
        case .dreamPop: return "Shimmering guitars, soft haze and gentle drums."
        case .indietronica: return "Quirky plucks, bells and indie electronic beats."
        case .lofi: return "Dusty drums, jazzy chords and a lazy swung groove."
        case .nuDisco: return "Four-on-the-floor funk, octave bass and shiny strings."
        case .edm: return "Big builds, huge drops and festival-size synths."
        }
    }

    /// The tempo range this genre usually lives in (always inside the engine's 60...200).
    public var tempoRange: ClosedRange<Double> {
        switch self {
        case .electronic: return 112...128
        case .synthpop: return 100...124
        case .pop: return 96...124
        case .chillwave: return 74...100
        case .downtempo: return 80...104
        case .ambient: return 60...84
        case .dreamPop: return 86...116
        case .indietronica: return 98...124
        case .lofi: return 66...92
        case .nuDisco: return 112...126
        case .edm: return 124...150
        }
    }

    /// The middle of the genre's tempo range.
    public var suggestedTempo: Double {
        ((tempoRange.lowerBound + tempoRange.upperBound) / 2).rounded()
    }

    /// A tempo that fits this genre and mood. Different seeds land on different tempos inside the range,
    /// and the same seed always gives the same tempo.
    public func tempo(for mood: Mood, seed: UInt64) -> Double {
        var g = SeededRNG(seed: seed).fork(55)
        let position = min(max(g.double() + mood.tempoLean * 0.5, 0), 1)
        let lo = tempoRange.lowerBound
        let hi = tempoRange.upperBound
        return (lo + (hi - lo) * position).rounded()
    }
}

public enum InstrumentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case drums, subBass, growlBass, pad, lead, piano, pluck, guitar, strings, bells, arp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .drums: return "Drums"
        case .subBass: return "Sub Bass"
        case .growlBass: return "Growl Bass"
        case .pad: return "Synth Pad"
        case .lead: return "Lead Synth"
        case .piano: return "E-Piano"
        case .pluck: return "Pluck"
        case .guitar: return "Guitar"
        case .strings: return "Strings"
        case .bells: return "Bells"
        case .arp: return "Arpeggio"
        }
    }

    public var emoji: String {
        switch self {
        case .drums: return "🥁"
        case .subBass: return "🔊"
        case .growlBass: return "👹"
        case .pad: return "🌫"
        case .lead: return "🎛"
        case .piano: return "🎹"
        case .pluck: return "🪕"
        case .guitar: return "🎸"
        case .strings: return "🎻"
        case .bells: return "🔔"
        case .arp: return "✨"
        }
    }
}

public enum VocalStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case femaleAah, maleOoh, choir, vocalChops, robot, whisper, duet

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .femaleAah: return "Female Aah"
        case .maleOoh: return "Male Ooh"
        case .choir: return "Choir"
        case .vocalChops: return "Vocal Chops"
        case .robot: return "Robot Voice"
        case .whisper: return "Whisper"
        case .duet: return "Duet"
        }
    }

    public var emoji: String {
        switch self {
        case .femaleAah: return "👩‍🎤"
        case .maleOoh: return "🧑‍🎤"
        case .choir: return "🎶"
        case .vocalChops: return "✂️"
        case .robot: return "🤖"
        case .whisper: return "🤫"
        case .duet: return "👫"
        }
    }
}

// MARK: - Song settings

public struct SongSettings: Codable, Equatable, Hashable, Sendable {
    public static let minLength: Double = 60
    public static let maxLength: Double = 180
    public static let minTempo: Double = 60
    public static let maxTempo: Double = 200

    public var tempo: Double
    public var mood: Mood
    /// The kind of music. `nil` means "any genre" (also what songs saved by older versions of the app use).
    public var genre: Genre?
    public var instruments: Set<InstrumentKind>
    public var vocals: Set<VocalStyle>
    /// 0 = C ... 11 = B. `nil` lets the app choose a key for you.
    public var key: Int?
    /// Song length in seconds. Never shorter than one minute.
    public var lengthSeconds: Double
    /// 0...1: how busy and loud the arrangement is.
    public var intensity: Double
    /// 0...1: how crunchy / distorted the synths are.
    public var grit: Double
    /// Tune the notes with pure "just intonation" ratios instead of piano tuning.
    public var justIntonation: Bool
    /// "Alobend" tuning: every chord is bent into pure whole-number ratios above its own root (a pure major
    /// third 5:4, a pure fifth 3:2, a pure seventh 7:4...), like a MIDI retuning tool does for a keyboard.
    /// The chord roots follow just intonation, so this also switches `justIntonation` on.
    public var alobend: Bool
    /// The Aloboi sound: unstable oscillators, Reese basses, rich pads and the "Aloboi Synth" sample.
    public var aloboiSound: Bool
    public var seed: UInt64

    public init(tempo: Double = 120,
                mood: Mood = .dark,
                genre: Genre? = nil,
                instruments: Set<InstrumentKind> = [.drums, .subBass, .pad, .arp],
                vocals: Set<VocalStyle> = [],
                key: Int? = nil,
                lengthSeconds: Double = 90,
                intensity: Double = 0.7,
                grit: Double = 0.5,
                justIntonation: Bool = false,
                alobend: Bool = false,
                aloboiSound: Bool = false,
                seed: UInt64 = 1) {
        self.tempo = tempo
        self.mood = mood
        self.genre = genre
        self.instruments = instruments
        self.vocals = vocals
        self.key = key
        self.lengthSeconds = lengthSeconds
        self.intensity = intensity
        self.grit = grit
        self.justIntonation = justIntonation
        self.alobend = alobend
        self.aloboiSound = aloboiSound
        self.seed = seed
    }

    private enum CodingKeys: String, CodingKey {
        case tempo, mood, genre, instruments, vocals, key, lengthSeconds, intensity, grit
        case justIntonation, alobend, aloboiSound, seed
    }

    /// Reads songs saved by any older version of the app: a setting that is missing gets its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tempo = try c.decodeIfPresent(Double.self, forKey: .tempo) ?? 120
        mood = try c.decodeIfPresent(Mood.self, forKey: .mood) ?? .dark
        genre = try c.decodeIfPresent(Genre.self, forKey: .genre)
        instruments = try c.decodeIfPresent(Set<InstrumentKind>.self, forKey: .instruments) ?? [.drums, .subBass, .pad, .arp]
        vocals = try c.decodeIfPresent(Set<VocalStyle>.self, forKey: .vocals) ?? []
        key = try c.decodeIfPresent(Int.self, forKey: .key)
        lengthSeconds = try c.decodeIfPresent(Double.self, forKey: .lengthSeconds) ?? 90
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.7
        grit = try c.decodeIfPresent(Double.self, forKey: .grit) ?? 0.5
        justIntonation = try c.decodeIfPresent(Bool.self, forKey: .justIntonation) ?? false
        alobend = try c.decodeIfPresent(Bool.self, forKey: .alobend) ?? false
        aloboiSound = try c.decodeIfPresent(Bool.self, forKey: .aloboiSound) ?? false
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed) ?? 1
    }

    /// The same settings, forced into safe ranges (so the engine can never crash on odd input).
    public func clamped() -> SongSettings {
        var s = self
        s.tempo = min(max(tempo.isFinite ? tempo : 120, Self.minTempo), Self.maxTempo)
        s.lengthSeconds = min(max(lengthSeconds.isFinite ? lengthSeconds : 90, Self.minLength), Self.maxLength)
        s.intensity = min(max(intensity.isFinite ? intensity : 0.7, 0), 1)
        s.grit = min(max(grit.isFinite ? grit : 0.5, 0), 1)
        if let k = key { s.key = ((k % 12) + 12) % 12 }
        // There is always at least a soft pad underneath, so a song is never silent.
        if s.instruments.isEmpty { s.instruments = [.pad] }
        return s
    }

    public static let keyNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
}

// MARK: - Style presets ("sounds like...")

public enum StylePreset: String, CaseIterable, Identifiable, Sendable {
    case aloboi, lofiChill, darkTechno, happyPop, epicCinema, dreamyAmbient, rawBass
    case synthpop, nuDisco, chillwave, dreamPop, indietronica, edm, downtempo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .aloboi: return "Aloboi-style"
        case .lofiChill: return "Lo-fi Chill"
        case .darkTechno: return "Dark Techno"
        case .happyPop: return "Happy Pop"
        case .epicCinema: return "Epic Movie"
        case .dreamyAmbient: return "Dreamy Ambient"
        case .rawBass: return "Raw Bass"
        case .synthpop: return "Neon Synthpop"
        case .nuDisco: return "Disco Night"
        case .chillwave: return "Beach Haze"
        case .dreamPop: return "Dream Pop"
        case .indietronica: return "Indie Sparkle"
        case .edm: return "Festival Drop"
        case .downtempo: return "Slow Groove"
        }
    }

    public var emoji: String {
        switch self {
        case .aloboi: return "🔥"
        case .lofiChill: return "☕️"
        case .darkTechno: return "🌑"
        case .happyPop: return "🎉"
        case .epicCinema: return "🎬"
        case .dreamyAmbient: return "🌌"
        case .rawBass: return "💥"
        case .synthpop: return "🕶"
        case .nuDisco: return "🪩"
        case .chillwave: return "🏖"
        case .dreamPop: return "☁️"
        case .indietronica: return "🧩"
        case .edm: return "🎆"
        case .downtempo: return "🛋"
        }
    }

    public var blurb: String {
        switch self {
        case .aloboi: return "Unstable synths, Reese bass, rich pads, the Aloboi Synth sound and chords bent into pure ratios."
        case .lofiChill: return "Slow, warm e-piano, soft guitar and a lazy beat."
        case .darkTechno: return "Driving beat, growling bass and a robot voice."
        case .happyPop: return "Bright chords, strummed guitar and a sing-along duet."
        case .epicCinema: return "Big drums, strings and a choir."
        case .dreamyAmbient: return "Floating pads, bells and whispers. No drums."
        case .rawBass: return "Heavy, distorted and loud."
        case .synthpop: return "Bright synths, a big snare and a catchy hook."
        case .nuDisco: return "Funky bass, chopped guitar and shiny strings."
        case .chillwave: return "Hazy, washed-out synths and a slow fade."
        case .dreamPop: return "Shimmering guitars, soft haze and breathy voices."
        case .indietronica: return "Quirky plucks, bells and indie electronic beats."
        case .edm: return "Big builds, huge drops and festival synths."
        case .downtempo: return "Deep bass, warm keys and a rolling slow groove."
        }
    }

    public func settings(seed: UInt64) -> SongSettings {
        switch self {
        case .aloboi:
            // Based on the public tags of the track: electronic, house, downtempo, vocal. The artist relies
            // on MPE synths (Vital, Serum) for unstable oscillators, Reese basses and rich pads, and on a
            // MIDI retuning tool (Alobend) that bends chords into pure just-intonation ratios.
            return SongSettings(tempo: 122, mood: .dark, genre: .electronic,
                                instruments: [.drums, .subBass, .growlBass, .pad, .arp, .lead],
                                vocals: [.vocalChops, .femaleAah],
                                key: nil, lengthSeconds: 90, intensity: 0.75, grit: 0.75,
                                justIntonation: true, alobend: true, aloboiSound: true, seed: seed)
        case .lofiChill:
            return SongSettings(tempo: 78, mood: .chill, genre: .lofi,
                                instruments: [.drums, .piano, .subBass, .guitar, .pad],
                                vocals: [], key: nil, lengthSeconds: 90, intensity: 0.45, grit: 0.15,
                                justIntonation: false, seed: seed)
        case .darkTechno:
            return SongSettings(tempo: 126, mood: .dark, genre: .electronic,
                                instruments: [.drums, .subBass, .growlBass, .arp, .pad],
                                vocals: [.robot], key: nil, lengthSeconds: 90, intensity: 0.85, grit: 0.7,
                                justIntonation: false, seed: seed)
        case .happyPop:
            return SongSettings(tempo: 118, mood: .happy, genre: .pop,
                                instruments: [.drums, .subBass, .piano, .guitar, .lead, .pad],
                                vocals: [.duet], key: nil, lengthSeconds: 90, intensity: 0.7, grit: 0.15,
                                justIntonation: false, seed: seed)
        case .epicCinema:
            return SongSettings(tempo: 96, mood: .epic, genre: nil,
                                instruments: [.drums, .strings, .piano, .subBass, .bells, .pad],
                                vocals: [.choir], key: nil, lengthSeconds: 120, intensity: 0.8, grit: 0.25,
                                justIntonation: false, seed: seed)
        case .dreamyAmbient:
            return SongSettings(tempo: 72, mood: .dreamy, genre: .ambient,
                                instruments: [.pad, .bells, .piano, .strings, .pluck, .subBass],
                                vocals: [.femaleAah, .whisper], key: nil, lengthSeconds: 120, intensity: 0.35,
                                grit: 0.05, justIntonation: true, seed: seed)
        case .rawBass:
            return SongSettings(tempo: 140, mood: .raw, genre: .edm,
                                instruments: [.drums, .subBass, .growlBass, .lead, .pad],
                                vocals: [.vocalChops], key: nil, lengthSeconds: 90, intensity: 0.9, grit: 0.95,
                                justIntonation: false, seed: seed)
        case .synthpop:
            return SongSettings(tempo: 112, mood: .uplifting, genre: .synthpop,
                                instruments: [.drums, .subBass, .pad, .lead, .arp],
                                vocals: [.duet], key: nil, lengthSeconds: 90, intensity: 0.7, grit: 0.25,
                                justIntonation: false, seed: seed)
        case .nuDisco:
            return SongSettings(tempo: 120, mood: .uplifting, genre: .nuDisco,
                                instruments: [.drums, .subBass, .guitar, .piano, .strings, .pluck],
                                vocals: [.vocalChops], key: nil, lengthSeconds: 90, intensity: 0.75, grit: 0.15,
                                justIntonation: false, seed: seed)
        case .chillwave:
            return SongSettings(tempo: 88, mood: .dreamy, genre: .chillwave,
                                instruments: [.drums, .subBass, .pad, .arp, .guitar],
                                vocals: [.femaleAah], key: nil, lengthSeconds: 90, intensity: 0.4, grit: 0.3,
                                justIntonation: false, seed: seed)
        case .dreamPop:
            return SongSettings(tempo: 100, mood: .romantic, genre: .dreamPop,
                                instruments: [.drums, .guitar, .pad, .subBass, .piano],
                                vocals: [.femaleAah, .whisper], key: nil, lengthSeconds: 90, intensity: 0.5, grit: 0.1,
                                justIntonation: false, seed: seed)
        case .indietronica:
            return SongSettings(tempo: 110, mood: .happy, genre: .indietronica,
                                instruments: [.drums, .subBass, .pluck, .piano, .bells, .guitar],
                                vocals: [.vocalChops], key: nil, lengthSeconds: 90, intensity: 0.65, grit: 0.2,
                                justIntonation: false, seed: seed)
        case .edm:
            return SongSettings(tempo: 128, mood: .energetic, genre: .edm,
                                instruments: [.drums, .subBass, .lead, .pad, .arp, .pluck],
                                vocals: [.vocalChops], key: nil, lengthSeconds: 120, intensity: 0.9, grit: 0.45,
                                justIntonation: false, seed: seed)
        case .downtempo:
            return SongSettings(tempo: 92, mood: .relaxed, genre: .downtempo,
                                instruments: [.drums, .subBass, .piano, .pad, .guitar],
                                vocals: [.whisper], key: nil, lengthSeconds: 90, intensity: 0.45, grit: 0.2,
                                justIntonation: false, seed: seed)
        }
    }
}

// MARK: - Result

public struct RenderedSong {
    public let left: [Float]
    public let right: [Float]
    public let sampleRate: Int
    public let title: String
    public let keyName: String
    public let scaleName: String
    public let bars: Int
    public let settings: SongSettings
    /// The genre's name ("Open" when the song has no genre).
    public let genreTitle: String
    /// A one-line description of every random choice made for this song (scale, chords, beat, sounds...).
    /// Handy for the library, for tests and for understanding why two songs differ.
    public let recipe: String

    public init(left: [Float], right: [Float], sampleRate: Int, title: String, keyName: String,
                scaleName: String, bars: Int, settings: SongSettings,
                genreTitle: String = "", recipe: String = "") {
        self.left = left
        self.right = right
        self.sampleRate = sampleRate
        self.title = title
        self.keyName = keyName
        self.scaleName = scaleName
        self.bars = bars
        self.settings = settings
        self.genreTitle = genreTitle
        self.recipe = recipe
    }

    public var frameCount: Int { left.count }
    public var durationSeconds: Double { Double(left.count) / Double(sampleRate) }
}
