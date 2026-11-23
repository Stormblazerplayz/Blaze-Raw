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
    /// "Alobend" retuning: what chord sounds in each bar of the song (empty = no retuning).
    let barChords: [ChordTuning]

    init(tonicHz: Double, just: Bool, barChords: [ChordTuning] = []) {
        self.tonicHz = tonicHz
        self.just = just
        self.barChords = barChords
    }

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

    /// The pitch of a note that starts at `beat`. Without Alobend this is the plain `frequency(semis:)`.
    /// With Alobend the note is tuned against the chord that is playing in its bar: the chord's root sits
    /// where just intonation puts it, and every other note is a pure ratio above that root, so the chord
    /// has no beating at all (a major chord becomes exactly 4:5:6).
    func frequency(semis: Int, beat: Double) -> Double {
        if barChords.isEmpty || !beat.isFinite { return frequency(semis: semis) }
        let bar = min(max(Int(beat / 4), 0), barChords.count - 1)
        let chord = barChords[bar]
        let rel = semis - chord.rootSemis
        let oct = floorDiv(rel, 12)
        let idx = rel - oct * 12
        return frequency(semis: chord.rootSemis) * chord.ratio(idx) * pow(2.0, Double(oct))
    }

    /// MIDI-style note number of a pitch (only used to keep notes in a comfortable range).
    func midi(semis: Int, key: Int) -> Int { 24 + key + semis }
}

/// What the Alobend retuning needs to know about one chord: where its root is, and which pure ratios fit it.
struct ChordTuning {
    /// Semitones above the song's tonic.
    let rootSemis: Int
    /// The chord has a major third (so a minor seventh on it is the "harmonic" seventh, 7:4).
    let majorThird: Bool
    /// The chord has no perfect fifth (a diminished chord), so the tritone is the pure 7:5.
    let flatFive: Bool

    init(rootSemis: Int, majorThird: Bool, flatFive: Bool) {
        self.rootSemis = rootSemis
        self.majorThird = majorThird
        self.flatFive = flatFive
    }

    init(_ chord: Chord) {
        var classes = Set<Int>()
        for t in chord.tones { classes.insert(((t - chord.rootSemis) % 12 + 12) % 12) }
        self.rootSemis = chord.rootSemis
        self.majorThird = classes.contains(4)
        self.flatFive = classes.contains(6) && !classes.contains(7)
    }

    /// The pure ratio of a note `interval` semitones (0...11) above the chord root.
    func ratio(_ interval: Int) -> Double {
        switch interval {
        case 0: return 1
        case 1: return 16.0 / 15.0
        case 2: return 9.0 / 8.0
        case 3: return 6.0 / 5.0
        case 4: return 5.0 / 4.0
        case 5: return 4.0 / 3.0
        case 6: return flatFive ? 7.0 / 5.0 : 45.0 / 32.0
        case 7: return 3.0 / 2.0
        case 8: return 8.0 / 5.0
        case 9: return 5.0 / 3.0
        case 10: return majorThird ? 7.0 / 4.0 : 9.0 / 5.0
        default: return 15.0 / 8.0
        }
    }
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
