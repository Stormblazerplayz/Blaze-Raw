import Foundation

// MARK: - The "recipe" of a song
//
// Every song gets a StyleProfile: a long list of choices made from (genre, mood, seed).
// Different seeds make different choices, so two songs with the same settings still sound different:
// scale, chord loops, chord colours, drum groove, bass line, melody shape, section layout and the
// sound of every instrument.
//
// Who owns what (so several people can work at once without touching the same code):
//   * composition choices (this file, StyleMaker.swift, Traits.swift, Banks.swift, Composer.swift, Theory.swift)
//   * sound design of the instruments: Palette, FXSpec, MasterSpec (Patches.swift, Synths.swift, Renderer.swift)
//   * drums: DrumKitSpec and the groove library (Drums.swift)

/// The basic drum feel. Each style has several variants inside it (see `StyleProfile.grooveVariant`).
enum DrumStyle: Int, CaseIterable {
    case fourOnFloor   // house / EDM / electronic: kick on every beat, offbeat hats
    case disco         // nu-disco: four on the floor, open hat on the offbeat, busy 16th hats, clap on 2 and 4
    case halfTime      // downtempo / trip-hop: kick on 1, snare on 3, rolling ghost notes
    case boomBap       // lo-fi hip-hop: swung kick and snare, lazy hats
    case backbeat      // pop / indie: kick on 1 and 3 plus pickups, snare and clap on 2 and 4, 8th hats
    case gated80s      // synthpop: huge gated snare, 8th hats, toms in the fills
    case breakbeat     // syncopated broken beats (electronic, indietronica, raw)
    case dreamy        // dream pop / chillwave: soft kick, rim, shaker, tambourine, light snare
    case epic          // big drums and toms
    case minimal       // ambient: a very soft, sparse pulse

    var name: String {
        switch self {
        case .fourOnFloor: return "four-on-floor"
        case .disco: return "disco"
        case .halfTime: return "half-time"
        case .boomBap: return "boom-bap"
        case .backbeat: return "backbeat"
        case .gated80s: return "gated-80s"
        case .breakbeat: return "breakbeat"
        case .dreamy: return "dreamy"
        case .epic: return "epic"
        case .minimal: return "minimal"
        }
    }
}

enum BassStyle: Int, CaseIterable {
    case sustained       // long root notes
    case rootFifth       // root, then the fifth
    case offbeatOctave   // house and disco: offbeat 8ths jumping between root and octave
    case funk16          // syncopated 16th-note funk with octave pops
    case rolling         // steady pulse on the root with octave pops
    case walking         // quarter notes walking through the chord
    case bounce808       // a few long, round notes with space
    case syncopated      // kick-locked pop bass
    case drone           // one very long note per chord

    var name: String {
        switch self {
        case .sustained: return "sustained"
        case .rootFifth: return "root-fifth"
        case .offbeatOctave: return "offbeat-octave"
        case .funk16: return "funk"
        case .rolling: return "rolling"
        case .walking: return "walking"
        case .bounce808: return "808"
        case .syncopated: return "syncopated"
        case .drone: return "drone"
        }
    }
}

/// How rich the chords are (which scale steps are stacked on the root).
enum ChordColor: Int, CaseIterable {
    case triad, seventh, add9, sus2, sus4, ninth, sixth

    /// Scale steps above the chord root that make up the chord.
    var steps: [Int] {
        switch self {
        case .triad: return [0, 2, 4]
        case .seventh: return [0, 2, 4, 6]
        case .add9: return [0, 2, 4, 8]
        case .sus2: return [0, 1, 4]
        case .sus4: return [0, 3, 4]
        case .ninth: return [0, 2, 4, 6, 8]
        case .sixth: return [0, 2, 4, 5]
        }
    }

    var name: String {
        switch self {
        case .triad: return "triads"
        case .seventh: return "7ths"
        case .add9: return "add9"
        case .sus2: return "sus2"
        case .sus4: return "sus4"
        case .ninth: return "9ths"
        case .sixth: return "6ths"
        }
    }
}

enum Contour: Int, CaseIterable {
    case arch, rising, falling, wave, flat, zigzag
}

/// How the second bar of a two-bar melody answers the first.
enum AnswerKind: Int, CaseIterable {
    case repeatPhrase, sequence, mirror, free
}

enum PianoMode: Int, CaseIterable {
    case block      // chord hits on a rhythm
    case broken     // eighth-note broken chords
    case stabs      // short offbeat stabs
    case slow       // slow rolling quarter notes
    case alberti    // low-high-mid-high pattern
    case ballad     // a low root, then the chord floating above
}

enum GuitarMode: Int, CaseIterable {
    case strum      // strummed chords
    case pick       // finger-picked pattern
    case chop       // short funky muted chops
    case ring       // clean, ringing eighth-note arpeggio
}

/// Shape of a two-bar melody (the "hook"). The notes are written relative to the chord.
struct MelodySpec {
    var density: Double = 0.5        // 0...1: sparse to busy
    var syncopation: Double = 0.3    // 0...1: chance that notes arrive a 16th early
    var stepBias: Double = 0.65      // chance of moving by a single scale step
    var leapChance: Double = 0.12    // chance of a big jump
    var contour: Contour = .arch
    var answer: AnswerKind = .sequence
    var maxLen: Int = 6              // longest note in 16ths
    var rangeLow: Int = -1           // lowest scale-degree offset from the chord root
    var rangeHigh: Int = 7           // highest offset
}

/// All the choices made for one song.
struct StyleProfile {
    let genre: Genre?
    let mood: Mood

    // MARK: harmony
    var scale: Scale = .major
    /// How many bars each chord lasts (1, 2 or 4).
    var barsPerChord: Int = 1
    /// Chord loops as scale degrees (0 = first degree): verse/intro, chorus, breakdown, outro.
    var progA: [Int] = [0, 4, 5, 3]
    var progB: [Int] = [0, 5, 3, 4]
    var progC: [Int] = [5, 3, 0, 4]
    var progOutro: [Int] = [3, 0]
    var colorVerse: ChordColor = .triad
    var colorChorus: ChordColor = .triad
    /// Spread the chord notes over a wider range (open voicings).
    var openVoicings: Bool = false
    /// The last chorus goes up this many semitones (0 = no key change).
    var keyLift: Int = 0

    // MARK: rhythm and bass
    var drumStyle: DrumStyle = .backbeat
    /// 0...7: which variant of the drum style to use.
    var grooveVariant: Int = 0
    var bassStyle: BassStyle = .rootFifth
    /// 0...3: which variant of the bass style to use.
    var bassVariant: Int = 0
    /// 0...0.4: how much the off-16ths are delayed.
    var swing: Double = 0
    /// Sidechain "pumping" depth 0...0.8.
    var duck: Float = 0.4
    /// Random timing wobble of played (not programmed) instruments, in beats.
    var humanize: Double = 0.004

    // MARK: feel
    /// 0...1: how bright the sounds are.
    var brightness: Float = 0.5
    /// 0...1: how big the reverb room is.
    var reverb: Float = 0.5
    /// 0...1: how busy the arrangement is overall.
    var density: Float = 0.6

    // MARK: parts
    var melody: MelodySpec = MelodySpec()
    var verseMelody: MelodySpec = MelodySpec()
    var stabRhythm: [Int] = [0, 6, 10]
    var stabRhythmAlt: [Int] = [2, 6, 10, 14]
    var arpRhythm: [Int] = Array(0..<16)
    var arpOrder: [Int] = [0, 1, 2, 3, 2, 1]
    var pluckRhythm: [Int] = [0, 3, 6, 8, 11, 14]
    /// Guitar strum: (16th step, strength).
    var strumPattern: [(Int, Float)] = [(0, 1.0), (6, 0.7), (8, 0.9), (14, 0.7)]
    /// 0 = held chords, 1 = chords re-played every half bar, 2 = short gated pulses.
    var padStyle: Int = 0
    var pianoMode: PianoMode = .block
    var guitarMode: GuitarMode = .strum
    /// The lead synth also plays (softer) in the verses.
    var leadInVerse: Bool = false

    // MARK: sound design (made by the sound and drum code; see Patches.swift and Drums.swift)
    let palette: Palette
    let kit: DrumKitSpec
    let fx: FXSpec
    let master: MasterSpec

    init(genre: Genre?, mood: Mood, palette: Palette, kit: DrumKitSpec, fx: FXSpec, master: MasterSpec) {
        self.genre = genre
        self.mood = mood
        self.palette = palette
        self.kit = kit
        self.fx = fx
        self.master = master
    }

    /// Builds a chord on a scale degree with the given colour.
    func chord(rootDegree: Int, color: ChordColor) -> Chord {
        let tones = color.steps.map { scale.semitone(degree: rootDegree + $0) }.sorted()
        return Chord(rootDegree: rootDegree, rootSemis: scale.semitone(degree: rootDegree), tones: tones, shift: 0)
    }
}

// MARK: - Weighted random choice

extension SeededRNG {
    /// Picks one item; bigger weights are picked more often. Zero or negative weights are never picked
    /// (unless every weight is zero, then the first item wins).
    mutating func pickWeighted<T>(_ items: [(T, Double)]) -> T {
        var total = 0.0
        for item in items { total += max(item.1, 0) }
        if total <= 0 { return items[0].0 }
        var r = double() * total
        for item in items {
            let w = max(item.1, 0)
            if r < w { return item.0 }
            r -= w
        }
        return items[items.count - 1].0
    }

    /// A number in `range`, uniformly.
    mutating func value(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * double()
    }

    /// Same as `value`, for Float ranges (a separate name keeps number literals unambiguous).
    mutating func valueF(_ range: ClosedRange<Float>) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * float()
    }
}

/// Multiplies a genre's weights (`a`) with a mood's weights (`b`) item by item.
/// The genre decides what is possible: an item the genre does not list gets only `aFloor`, so a mood can
/// rarely drag a song out of its genre. A mood is a gentle tilt: an item the mood does not list gets a
/// middling `bFloor`, so a genre's signature sound survives whatever the mood.
func combineWeights<T: Hashable>(_ a: [(T, Double)], _ b: [(T, Double)],
                                 aFloor: Double = 0.04, bFloor: Double = 0.45) -> [(T, Double)] {
    var wa: [T: Double] = [:]
    var wb: [T: Double] = [:]
    var order: [T] = []
    for (item, w) in a {
        if wa[item] == nil && wb[item] == nil { order.append(item) }
        wa[item] = w
    }
    for (item, w) in b {
        if wa[item] == nil && wb[item] == nil { order.append(item) }
        wb[item] = w
    }
    return order.map { item in
        (item, (wa[item] ?? aFloor) * (wb[item] ?? bFloor))
    }
}
