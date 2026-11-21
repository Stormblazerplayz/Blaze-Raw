import Foundation

// MARK: - Scales

enum Scale: String {
    case major, naturalMinor, dorian, phrygian, lydian, mixolydian

    var intervals: [Int] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: return [0, 2, 3, 5, 7, 8, 10]
        case .dorian: return [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: return [0, 1, 3, 5, 7, 8, 10]
        case .lydian: return [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian: return [0, 2, 4, 5, 7, 9, 10]
        }
    }

    var displayName: String {
        switch self {
        case .major: return "Major"
        case .naturalMinor: return "Minor"
        case .dorian: return "Dorian"
        case .phrygian: return "Phrygian"
        case .lydian: return "Lydian"
        case .mixolydian: return "Mixolydian"
        }
    }

    /// Semitones above the tonic for a scale degree. Degrees may be negative or bigger than 6
    /// (they wrap into other octaves).
    func semitone(degree: Int) -> Int {
        let oct = floorDiv(degree, 7)
        let idx = degree - oct * 7
        return intervals[idx] + 12 * oct
    }
}

// MARK: - Tuning

/// Turns "semitones above the tonic" into Hertz.
/// With `just == true` the notes use pure whole-number ratios (just intonation),
/// which sounds smoother and a little "unreal" compared with piano tuning.
struct TuningSystem {
    let tonicHz: Double
    let just: Bool

    static let justRatios: [Double] = [
        1.0, 16.0 / 15.0, 9.0 / 8.0, 6.0 / 5.0, 5.0 / 4.0, 4.0 / 3.0,
        45.0 / 32.0, 3.0 / 2.0, 8.0 / 5.0, 5.0 / 3.0, 9.0 / 5.0, 15.0 / 8.0
    ]

    func frequency(semis: Int) -> Double {
        let oct = floorDiv(semis, 12)
        let idx = semis - oct * 12
        let ratio = just ? TuningSystem.justRatios[idx] : pow(2.0, Double(idx) / 12.0)
        return tonicHz * ratio * pow(2.0, Double(oct))
    }

    /// MIDI-style note number of a pitch (only used to keep notes in a comfortable range).
    func midi(semis: Int, key: Int) -> Int { 24 + key + semis }
}

// MARK: - Chords

struct Chord {
    let rootDegree: Int
    /// Semitones above the tonic of the chord root (can be negative or > 11).
    let rootSemis: Int
    /// All chord tones, ascending, in semitones above the tonic.
    let tones: [Int]
}

// MARK: - Mood profiles

enum DrumKit {
    case fourOnFloor, halfTime, breakbeat, epic
}

struct MoodProfile {
    let scale: Scale
    /// Chord progressions as scale degrees (0 = first degree). Each lasts `barsPerChord` bars per chord.
    let progressions: [[Int]]
    let barsPerChord: Int
    /// Which stacked thirds make up a chord: [0,2,4] = triad, [0,2,4,6] = seventh chord.
    let chordShape: [Int]
    let kit: DrumKit
    let swing: Double
    let duck: Float
    /// 0...1 how bright the pads/strings are.
    let brightness: Float
    let reverb: Float
    /// Preferred hook rhythm style: 0 = sparse, 1 = syncopated, 2 = straight, 3 = busy
    let hookStyle: Int
    /// 0 = block stabs, 1 = broken chords, 2 = offbeat stabs, 3 = slow arpeggio
    let pianoStyle: Int
    /// 0 = finger-picking, 1 = strum
    let guitarStyle: Int

    static func profile(for mood: Mood) -> MoodProfile {
        switch mood {
        case .dark:
            return MoodProfile(scale: .naturalMinor,
                               progressions: [[0, 5, 2, 6], [0, 3, 5, 4], [0, 6, 5, 6]],
                               barsPerChord: 1, chordShape: [0, 2, 4], kit: .halfTime, swing: 0.0, duck: 0.5,
                               brightness: 0.35, reverb: 0.55, hookStyle: 1, pianoStyle: 1, guitarStyle: 0)
        case .happy:
            return MoodProfile(scale: .major,
                               progressions: [[0, 4, 5, 3], [5, 3, 0, 4], [0, 3, 4, 4]],
                               barsPerChord: 1, chordShape: [0, 2, 4], kit: .fourOnFloor, swing: 0.05, duck: 0.45,
                               brightness: 0.85, reverb: 0.35, hookStyle: 2, pianoStyle: 2, guitarStyle: 1)
        case .chill:
            return MoodProfile(scale: .dorian,
                               progressions: [[0, 3, 2, 3], [0, 2, 3, 0], [1, 3, 0, 0]],
                               barsPerChord: 2, chordShape: [0, 2, 4, 6], kit: .halfTime, swing: 0.18, duck: 0.25,
                               brightness: 0.45, reverb: 0.5, hookStyle: 0, pianoStyle: 0, guitarStyle: 0)
        case .energetic:
            return MoodProfile(scale: .mixolydian,
                               progressions: [[0, 6, 3, 0], [0, 3, 6, 3], [5, 6, 0, 0]],
                               barsPerChord: 1, chordShape: [0, 2, 4], kit: .fourOnFloor, swing: 0.0, duck: 0.6,
                               brightness: 0.9, reverb: 0.3, hookStyle: 3, pianoStyle: 2, guitarStyle: 1)
        case .sad:
            return MoodProfile(scale: .naturalMinor,
                               progressions: [[0, 5, 2, 6], [0, 3, 5, 4], [5, 3, 0, 4]],
                               barsPerChord: 1, chordShape: [0, 2, 4, 6], kit: .halfTime, swing: 0.08, duck: 0.2,
                               brightness: 0.3, reverb: 0.6, hookStyle: 0, pianoStyle: 3, guitarStyle: 0)
        case .dreamy:
            return MoodProfile(scale: .lydian,
                               progressions: [[0, 1, 5, 4], [0, 4, 5, 1], [0, 5, 1, 4]],
                               barsPerChord: 2, chordShape: [0, 2, 4, 6], kit: .halfTime, swing: 0.1, duck: 0.25,
                               brightness: 0.6, reverb: 0.75, hookStyle: 0, pianoStyle: 3, guitarStyle: 0)
        case .epic:
            return MoodProfile(scale: .naturalMinor,
                               progressions: [[0, 5, 3, 4], [0, 3, 5, 4], [0, 5, 2, 6]],
                               barsPerChord: 2, chordShape: [0, 2, 4], kit: .epic, swing: 0.0, duck: 0.3,
                               brightness: 0.6, reverb: 0.7, hookStyle: 2, pianoStyle: 1, guitarStyle: 1)
        case .raw:
            return MoodProfile(scale: .phrygian,
                               progressions: [[0, 1, 0, 6], [0, 1, 6, 5], [0, 5, 6, 1]],
                               barsPerChord: 1, chordShape: [0, 2, 4], kit: .breakbeat, swing: 0.0, duck: 0.65,
                               brightness: 0.4, reverb: 0.4, hookStyle: 1, pianoStyle: 2, guitarStyle: 1)
        }
    }

    func chord(rootDegree: Int) -> Chord {
        let tones = chordShape.map { scale.semitone(degree: rootDegree + $0) }.sorted()
        return Chord(rootDegree: rootDegree, rootSemis: scale.semitone(degree: rootDegree), tones: tones)
    }
}
