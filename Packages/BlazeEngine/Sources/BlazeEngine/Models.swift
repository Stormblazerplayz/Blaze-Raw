import Foundation

// MARK: - What the user can pick

public enum Mood: String, CaseIterable, Codable, Identifiable, Sendable {
    case dark, happy, chill, energetic, sad, dreamy, epic, raw

    public var id: String { rawValue }

    public var title: String {
        switch self {
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
    public var seed: UInt64

    public init(tempo: Double = 120,
                mood: Mood = .dark,
                instruments: Set<InstrumentKind> = [.drums, .subBass, .pad, .arp],
                vocals: Set<VocalStyle> = [],
                key: Int? = nil,
                lengthSeconds: Double = 90,
                intensity: Double = 0.7,
                grit: Double = 0.5,
                justIntonation: Bool = false,
                seed: UInt64 = 1) {
        self.tempo = tempo
        self.mood = mood
        self.instruments = instruments
        self.vocals = vocals
        self.key = key
        self.lengthSeconds = lengthSeconds
        self.intensity = intensity
        self.grit = grit
        self.justIntonation = justIntonation
        self.seed = seed
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
        }
    }

    public var blurb: String {
        switch self {
        case .aloboi: return "Gritty saw synths, pure-ratio tuning, house/downtempo beat and vocal chops."
        case .lofiChill: return "Slow, warm e-piano, soft guitar and a lazy beat."
        case .darkTechno: return "Driving beat, growling bass and a robot voice."
        case .happyPop: return "Bright chords, strummed guitar and a sing-along duet."
        case .epicCinema: return "Big drums, strings and a choir."
        case .dreamyAmbient: return "Floating pads, bells and whispers. No drums."
        case .rawBass: return "Heavy, distorted and loud."
        }
    }

    public func settings(seed: UInt64) -> SongSettings {
        switch self {
        case .aloboi:
            // Based on the public tags of the track: electronic, house, downtempo, vocal.
            // The artist is known for distorted saw synths and just intonation.
            return SongSettings(tempo: 122, mood: .dark,
                                instruments: [.drums, .subBass, .growlBass, .pad, .arp],
                                vocals: [.vocalChops, .femaleAah],
                                key: nil, lengthSeconds: 90, intensity: 0.75, grit: 0.75,
                                justIntonation: true, seed: seed)
        case .lofiChill:
            return SongSettings(tempo: 78, mood: .chill,
                                instruments: [.drums, .piano, .subBass, .guitar, .pad],
                                vocals: [], key: nil, lengthSeconds: 90, intensity: 0.45, grit: 0.15,
                                justIntonation: false, seed: seed)
        case .darkTechno:
            return SongSettings(tempo: 132, mood: .dark,
                                instruments: [.drums, .subBass, .growlBass, .arp, .pad],
                                vocals: [.robot], key: nil, lengthSeconds: 90, intensity: 0.85, grit: 0.7,
                                justIntonation: false, seed: seed)
        case .happyPop:
            return SongSettings(tempo: 118, mood: .happy,
                                instruments: [.drums, .subBass, .piano, .guitar, .lead, .pad],
                                vocals: [.duet], key: nil, lengthSeconds: 90, intensity: 0.7, grit: 0.15,
                                justIntonation: false, seed: seed)
        case .epicCinema:
            return SongSettings(tempo: 96, mood: .epic,
                                instruments: [.drums, .strings, .piano, .subBass, .bells, .pad],
                                vocals: [.choir], key: nil, lengthSeconds: 120, intensity: 0.8, grit: 0.25,
                                justIntonation: false, seed: seed)
        case .dreamyAmbient:
            return SongSettings(tempo: 84, mood: .dreamy,
                                instruments: [.pad, .bells, .piano, .strings, .pluck, .subBass],
                                vocals: [.femaleAah, .whisper], key: nil, lengthSeconds: 120, intensity: 0.35,
                                grit: 0.05, justIntonation: true, seed: seed)
        case .rawBass:
            return SongSettings(tempo: 140, mood: .raw,
                                instruments: [.drums, .subBass, .growlBass, .lead, .pad],
                                vocals: [.vocalChops], key: nil, lengthSeconds: 90, intensity: 0.9, grit: 0.95,
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

    public var frameCount: Int { left.count }
    public var durationSeconds: Double { Double(left.count) / Double(sampleRate) }
}
