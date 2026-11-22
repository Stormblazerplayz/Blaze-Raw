import Foundation

// MARK: - Scales

enum Scale: String {
    case major, naturalMinor, dorian, phrygian, lydian, mixolydian, harmonicMinor, melodicMinor

    var intervals: [Int] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: return [0, 2, 3, 5, 7, 8, 10]
        case .dorian: return [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: return [0, 1, 3, 5, 7, 8, 10]
        case .lydian: return [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian: return [0, 2, 4, 5, 7, 9, 10]
        case .harmonicMinor: return [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor: return [0, 2, 3, 5, 7, 9, 11]
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
        case .harmonicMinor: return "Harmonic Minor"
        case .melodicMinor: return "Melodic Minor"
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
    /// How many semitones the whole chord has been moved up (a key change). `rootSemis` and `tones`
    /// already include it; melodies written in scale degrees add it themselves.
    let shift: Int

    /// The same chord moved up by `semis` semitones.
    func transposed(by semis: Int) -> Chord {
        Chord(rootDegree: rootDegree,
              rootSemis: rootSemis + semis,
              tones: tones.map { $0 + semis },
              shift: shift + semis)
    }
}
