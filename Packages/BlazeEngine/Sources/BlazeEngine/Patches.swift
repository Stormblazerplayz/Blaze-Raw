import Foundation

// MARK: - Sound design
//
// Every song gets its own Palette (the sound of each instrument), FXSpec (reverb, echo, lo-fi) and
// MasterSpec (loudness and tone). They are chosen from the genre, the mood and the seed, so two songs
// never use exactly the same sounds. The sound code (Synths.swift) turns these specs into audio.
//
// Each instrument has several "characters" (for example a pad can be a supersaw, a glassy pad or a
// dark drone). A character is a parameter set; on top of that every number is nudged a little by the
// seed, so even two songs with the same character differ.

// MARK: - Oscillator shapes

enum Wave: Int {
    case saw, square, pulse, triangle, sine
}

/// One sample of an oscillator at `phase` (0...1). `dt` = phase step per sample (for band-limiting).
@inline(__always) func oscSample(_ wave: Wave, _ phase: Float, _ dt: Float, _ pw: Float) -> Float {
    switch wave {
    case .saw: return sawBL(phase, dt)
    case .square: return squareBL(phase, dt, 0.5)
    case .pulse: return squareBL(phase, dt, pw)
    case .triangle: return 4 * abs(phase - 0.5) - 1
    case .sine: return sin(2 * Float.pi * phase)
    }
}

// MARK: - Patch types

/// A configurable unison synthesizer voice. Pads, strings, leads, arps and plucks all use it.
struct SynthPatch {
    var name: String = "saw"
    var wave: Wave = .saw
    /// Unison voices, 1...5 (voices are spread in pitch by `detune` and across the stereo field by `spread`).
    var voices: Int = 1
    /// Cents between the lowest and the highest unison voice is 2 x detune.
    var detune: Float = 0
    /// Slow independent pitch drift per voice in cents: the "analog chorus" sound.
    var drift: Float = 0
    var pulseWidth: Float = 0.5
    var pwmDepth: Float = 0
    /// A second oscillator (one voice) added on top: `ratio2` times the pitch.
    var wave2: Wave = .square
    var mix2: Float = 0
    var ratio2: Float = 1
    var pulseWidth2: Float = 0.35
    /// Level of a sine one octave below.
    var sub: Float = 0
    /// Breath / air noise level.
    var noise: Float = 0
    /// Filter cutoff in Hz (before the section "tier" of pads and strings).
    var cutoff: Float = 3000
    /// 0...1: how much the cutoff follows the pitch.
    var keyTrack: Float = 0
    /// Extra cutoff Hz per unit of grit.
    var gritCut: Float = 0
    /// Filter envelope: Hz added at the start of each note, falling away over `envDecay` seconds.
    var envAmount: Float = 0
    var envDecay: Float = 0.2
    /// 0...1: how much the envelope amount follows the note velocity.
    var velToEnv: Float = 0
    var q: Float = 0.9
    var lfoRate: Float = 0.12
    var lfoDepth: Float = 0
    var vibrato: Float = 0
    var vibratoRate: Float = 5
    /// Loudness wobble depth 0...1 at `tremoloRate` Hz, or locked to the tempo with `tremoloSync` cycles per beat.
    var tremolo: Float = 0
    var tremoloRate: Float = 5
    var tremoloSync: Float = 0
    var drive: Float = 1
    var gritDrive: Float = 0
    var attack: Float = 0.02
    var decay: Float = 0.3
    var sustain: Float = 0.8
    var release: Float = 0.3
    /// > 0 makes a plucked sound that just decays (time constant in seconds) instead of ADSR.
    var percTau: Float = 0
    /// Stereo width of the unison voices 0...1 (0 = mono).
    var spread: Float = 0
    /// Alternating left/right placement of consecutive notes (arps).
    var panAlt: Float = 0
    /// Extra loudness trim on top of the automatic balancing.
    var gain: Float = 1
    /// Level of the "Aloboi Synth" sample (see AloboiSample.swift) mixed in with the oscillators, 0 = off.
    /// The sample is played twice, detuned by `detune` cents either way and panned by `spread`.
    var sample: Float = 0
    /// Level of the oscillators themselves (1 = normal). A sample patch lowers it so the sample leads.
    var oscLevel: Float = 1
    /// "Unstable oscillator" amount: every unison voice wanders in pitch on its own by about this many
    /// cents (slow random drift, a few times per second), like an analog oscillator that is not stable.
    var unstable: Float = 0
}

enum BassKind: Int {
    case sine, saw, square, fm, e808, funk, tri
    /// Three saws whose detune slowly breathes in and out: the phasing "Reese" bass of drum and bass.
    case reese
}

struct BassPatch {
    var name: String = "sine"
    var kind: BassKind = .sine
    var cutoff: Float = 200
    var envAmount: Float = 0
    var envDecay: Float = 0.15
    var q: Float = 1
    var drive: Float = 1.3
    var gritDrive: Float = 1.2
    /// Second harmonic added to sine basses so they stay audible on phone speakers.
    var harmonics: Float = 0
    var sub: Float = 0
    var detune: Float = 8
    var pulseWidth: Float = 0.5
    /// 808-style pitch drop: starts `glideSemis` above the note and falls over `glide` seconds.
    var glideSemis: Float = 0
    var glide: Float = 0
    var fmRatio: Float = 1
    var fmIndex: Float = 1.5
    var fmDecay: Float = 0.2
    var attack: Float = 0.005
    var decay: Float = 0.08
    var sustain: Float = 0.9
    var release: Float = 0.1
    var gain: Float = 1
}

struct GrowlPatch {
    var name: String = "classic"
    /// Pitch ratio of the second saw.
    var detune: Float = 1.0075
    var ringRatio: Float = 1.5
    var ringAmount: Float = 0.5
    var cutoffBase: Float = 130
    var cutoffRange: Float = 700
    var cutoffRangeGrit: Float = 5500
    var qBase: Float = 1.6
    var qGrit: Float = 3.5
    var driveBase: Float = 1.3
    var driveGrit: Float = 3.2
    var wobbleScale: Float = 1
    var subMix: Float = 0.45
    var attack: Float = 0.004
    var release: Float = 0.06
    var gain: Float = 1
}

/// Electric-piano style keys: two FM modulators on a sine carrier.
struct KeysPatch {
    var name: String = "rhodes"
    var ratio1: Float = 1
    var index1: Float = 1.6
    var idx1Decay: Float = 0.45
    var idx1Floor: Float = 0.25
    var ratio2: Float = 14
    var index2: Float = 0.5
    var idx2Decay: Float = 0.03
    var tauBase: Float = 1.9
    var tauSlope: Float = 1000
    var tauMin: Float = 0.5
    var tauMax: Float = 1.9
    var attack: Float = 0.002
    var release: Float = 0.25
    var tremolo: Float = 0
    var tremoloRate: Float = 5
    /// Tape-style pitch wobble in cents at `wobbleRate` Hz.
    var wobble: Float = 0
    var wobbleRate: Float = 0.6
    /// Low-pass cutoff in Hz (0 = none), for dull "felt" sounds.
    var cutoff: Float = 0
    var q: Float = 0.8
    var panStep: Float = 0.08
    var gain: Float = 1
}

/// A plucked string (Karplus-Strong) with a body filter.
struct GuitarPatch {
    var name: String = "classic"
    /// 0...1: how bright the initial pluck is (low = soft, nylon-like).
    var pickBright: Float = 0.5
    var bodyCutoff: Float = 4800
    var tauBase: Float = 2.4
    var tauSlope: Float = 500
    var tauMin: Float = 0.8
    var tauMax: Float = 2.4
    /// Multiplies the ring-out time (small = palm-muted).
    var tauScale: Float = 1
    var release: Float = 0.3
    /// > 0 adds a second string detuned by this many cents, panned apart (shimmer / chorus).
    var detune: Float = 0
    var spread: Float = 0.3
    var drive: Float = 1
    var level: Float = 1.4
    var gain: Float = 1
}

/// Bells and mallets: an FM bell plus up to two extra inharmonic partials.
struct BellPatch {
    var name: String = "glass bell"
    var modRatio: Float = 3.5
    var modIndex: Float = 2.2
    var idxDecay: Float = 0.8
    var idxFloor: Float = 0.15
    var ampTau: Float = 1.5
    var p1Ratio: Float = 2.756
    var p1Level: Float = 0.25
    var p1Tau: Float = 0.6
    var p2Ratio: Float = 0
    var p2Level: Float = 0
    var p2Tau: Float = 0.3
    /// Length of each bell note in seconds.
    var length: Float = 3.5
    var tremolo: Float = 0
    var tremoloRate: Float = 4
    var gain: Float = 1
}

// MARK: - Palette: the sound of every instrument in one song

struct Palette {
    var pad: SynthPatch
    var strings: SynthPatch
    var lead: SynthPatch
    var arp: SynthPatch
    var pluck: SynthPatch
    var sub: BassPatch
    var growl: GrowlPatch
    var keys: KeysPatch
    var guitar: GuitarPatch
    var bells: BellPatch

    var summary: String {
        "pad \(pad.name), strings \(strings.name), lead \(lead.name), arp \(arp.name), pluck \(pluck.name), "
            + "bass \(sub.name), growl \(growl.name), keys \(keys.name), guitar \(guitar.name), bells \(bells.name)"
    }

    /// The original sounds of the first version of the app, at neutral brightness. They are the
    /// loudness yardstick: every other patch is balanced to be as loud as its classic counterpart.
    static func classic() -> Palette {
        Palette(pad: PatchLibrary.pad(0, brightness: 0.5),
                strings: PatchLibrary.strings(0, brightness: 0.5),
                lead: PatchLibrary.lead(0, brightness: 0.5),
                arp: PatchLibrary.arp(0, brightness: 0.5),
                pluck: PatchLibrary.pluck(0, brightness: 0.5),
                sub: PatchLibrary.sub(0),
                growl: PatchLibrary.growl(0),
                keys: PatchLibrary.keys(0),
                guitar: PatchLibrary.guitar(0),
                bells: PatchLibrary.bells(0))
    }
}

// MARK: - Mood tilt

/// How a mood bends the sounds: soft moods have slower attacks and darker filters, energetic moods
/// have wider detune.
private struct MoodTilt {
    let soft: Float
    let energy: Float

    init(_ mood: Mood) {
        switch mood {
        case .relaxed: soft = 0.7; energy = 0.2
        case .introspective: soft = 0.8; energy = 0.1
        case .melancholic: soft = 0.6; energy = 0.2
        case .romantic: soft = 0.6; energy = 0.4
        case .uplifting: soft = 0.1; energy = 0.8
        case .dark: soft = 0.3; energy = 0.5
        case .happy: soft = 0.1; energy = 0.8
        case .chill: soft = 0.5; energy = 0.3
        case .energetic: soft = 0.0; energy = 1.0
        case .sad: soft = 0.6; energy = 0.2
        case .dreamy: soft = 0.6; energy = 0.4
        case .epic: soft = 0.2; energy = 0.7
        case .raw: soft = 0.0; energy = 0.9
        }
    }

    var cutoffScale: Float { 1 - 0.28 * soft }
    var attackScale: Float { 1 + 1.2 * soft }
    var releaseScale: Float { 1 + 0.6 * soft }
    var detuneScale: Float { 0.8 + 0.5 * energy }
}

// MARK: - Small helpers

/// A Float between `lo` and `hi`.
private func jit(_ g: inout SeededRNG, _ lo: Float, _ hi: Float) -> Float {
    lo + (hi - lo) * g.float()
}

/// Picks an index in 0..<count; bigger weights win more often. Missing weights count as 1.
private func pickIndex(_ weights: [Double], count: Int, _ g: inout SeededRNG) -> Int {
    var total = 0.0
    for i in 0..<count {
        total += max(i < weights.count ? weights[i] : 1.0, 0)
    }
    if total <= 0 { return 0 }
    var r = g.double() * total
    for i in 0..<count {
        let w = max(i < weights.count ? weights[i] : 1.0, 0)
        if r < w { return i }
        r -= w
    }
    return count - 1
}

private func genreWeights(_ table: [Genre: [Double]], _ genre: Genre?) -> [Double] {
    guard let gn = genre, let w = table[gn] else { return [] }
    return w
}

/// Weights for every character of an instrument: the old characters (from the genre's taste table) first,
/// then the Aloboi characters. With the Aloboi sound on, the Aloboi characters win nearly always.
private func characterWeights(_ table: [Genre: [Double]], _ genre: Genre?, oldCount: Int,
                              extra: [Genre: [Double]], extraCount: Int, extraDefault: Double,
                              aloboi: Bool) -> [Double] {
    var old = genreWeights(table, genre)
    while old.count < oldCount { old.append(1.0) }
    if old.count > oldCount { old = Array(old.prefix(oldCount)) }
    var new: [Double] = genre.flatMap { extra[$0] } ?? [Double](repeating: extraDefault, count: extraCount)
    while new.count < extraCount { new.append(extraDefault) }
    if aloboi {
        old = old.map { $0 * 0.15 }
        new = new.map { max($0, 0.5) * 6 }
    }
    return old + new
}

// MARK: - Character libraries

enum PatchLibrary {
    // The first characters of every instrument are the ones the engine always had. The last ones (pads 8-10,
    // leads 8-9, arp 8, sub bass 8-9) are the "Aloboi" sounds: unstable oscillators, the Aloboi Synth sample
    // and Reese basses. They are common when a song uses the Aloboi sound and rare in a few genres otherwise.
    static let oldPadCount = 8
    static let oldLeadCount = 8
    static let oldArpCount = 8
    static let oldSubCount = 8
    static let padCount = 11
    static let stringsCount = 7
    static let leadCount = 10
    static let arpCount = 9
    static let pluckCount = 8
    static let subCount = 10
    static let growlCount = 6
    static let keysCount = 7
    static let guitarCount = 6
    static let bellsCount = 6

    // MARK: pads

    static func pad(_ c: Int, brightness b: Float) -> SynthPatch {
        var p = SynthPatch()
        switch c {
        case 1:
            p.name = "supersaw"
            p.voices = 5; p.detune = 22; p.cutoff = 2200 + 4200 * b; p.q = 0.9
            p.lfoRate = 0.09; p.lfoDepth = 0.12
            p.attack = 0.18; p.decay = 0.6; p.sustain = 0.9; p.release = 1.0
            p.spread = 1.0; p.sub = 0.08
        case 2:
            p.name = "glass"
            p.wave = .triangle; p.voices = 3; p.detune = 6
            p.wave2 = .sine; p.ratio2 = 2; p.mix2 = 0.45
            p.cutoff = 4500 + 3500 * b; p.q = 0.8
            p.lfoRate = 0.07; p.lfoDepth = 0.3
            p.attack = 1.2; p.decay = 0.8; p.sustain = 0.9; p.release = 2.0
            p.spread = 0.9; p.noise = 0.02
        case 3:
            p.name = "warm analog"
            p.voices = 2; p.detune = 7; p.drift = 6; p.sub = 0.3
            p.cutoff = 380 + 1700 * b; p.q = 1.1
            p.lfoRate = 0.08; p.lfoDepth = 0.2
            p.attack = 0.6; p.decay = 0.6; p.sustain = 0.85; p.release = 1.2
            p.spread = 0.6
        case 4:
            p.name = "juno pulse"
            p.wave = .pulse; p.pulseWidth = 0.38; p.pwmDepth = 0.25
            p.voices = 3; p.detune = 9; p.drift = 8; p.sub = 0.2
            p.cutoff = 1400 + 3000 * b; p.q = 1.0
            p.lfoRate = 0.15; p.lfoDepth = 0.12
            p.attack = 0.25; p.decay = 0.4; p.sustain = 0.85; p.release = 0.8
            p.spread = 0.9
        case 5:
            p.name = "drone"
            p.voices = 2; p.detune = 4; p.drift = 5; p.sub = 0.5
            p.cutoff = 260 + 1200 * b; p.q = 1.3
            p.lfoRate = 0.05; p.lfoDepth = 0.45
            p.attack = 2.0; p.decay = 1.0; p.sustain = 0.9; p.release = 2.5
            p.spread = 0.5
        case 6:
            p.name = "gated"
            p.voices = 3; p.detune = 10
            p.cutoff = 1200 + 3200 * b; p.q = 1.0
            p.tremolo = 0.75; p.tremoloSync = 2
            p.attack = 0.02; p.decay = 0.2; p.sustain = 0.9; p.release = 0.25
            p.spread = 0.8
        case 7:
            p.name = "washed"
            p.voices = 3; p.detune = 16; p.drift = 14
            p.cutoff = 700 + 1900 * b; p.q = 0.8
            p.lfoRate = 0.15; p.lfoDepth = 0.35
            p.attack = 0.9; p.decay = 0.6; p.sustain = 0.85; p.release = 1.6
            p.spread = 1.0
        case 8:
            // Five saws that each wander out of tune by themselves, like a wobbly analog oscillator bank.
            p.name = "unstable stack"
            p.voices = 5; p.detune = 18; p.unstable = 9; p.sub = 0.15
            p.cutoff = 700 + 2600 * b; p.q = 1.0
            p.lfoRate = 0.06; p.lfoDepth = 0.4
            p.attack = 0.9; p.decay = 0.8; p.sustain = 0.9; p.release = 1.8
            p.spread = 1.0
        case 9:
            // The Aloboi Synth sample, played twice slightly out of tune, with a little saw underneath.
            p.name = "Aloboi Synth"
            p.sample = 1.0; p.oscLevel = 0.25
            p.voices = 2; p.detune = 9; p.drift = 4; p.unstable = 4; p.sub = 0.12
            p.cutoff = 700 + 2600 * b; p.q = 1.0
            p.lfoRate = 0.07; p.lfoDepth = 0.3
            p.attack = 0.7; p.decay = 0.6; p.sustain = 0.9; p.release = 1.6
            p.spread = 0.9
        case 10:
            // A dark drone: gritty saws that drift apart, with a fifth on top and a thick sub.
            p.name = "intermod drone"
            p.voices = 3; p.detune = 14; p.unstable = 14; p.sub = 0.4
            p.wave2 = .square; p.ratio2 = 1.5; p.mix2 = 0.25
            p.cutoff = 300 + 1500 * b; p.q = 1.5; p.drive = 1.1; p.gritDrive = 1.2
            p.lfoRate = 0.04; p.lfoDepth = 0.5
            p.attack = 1.6; p.decay = 1.0; p.sustain = 0.9; p.release = 2.4
            p.spread = 0.8
        default:
            // The original pad: three detuned saws under a slowly moving low-pass.
            p.name = "classic"
            p.voices = 3; p.detune = 11; p.cutoff = 500 + 3500 * b; p.q = 0.9
            p.lfoRate = 0.12; p.lfoDepth = 0.25
            p.attack = 0.8; p.decay = 0.5; p.sustain = 0.85; p.release = 1.4
            p.spread = 0.8
        }
        return p
    }

    // MARK: strings

    static func strings(_ c: Int, brightness b: Float) -> SynthPatch {
        var p = SynthPatch()
        switch c {
        case 1:
            p.name = "warm ensemble"
            p.voices = 5; p.detune = 10; p.drift = 4; p.cutoff = 1000 + 2200 * b; p.q = 0.8
            p.vibrato = 0.002; p.vibratoRate = 5.0
            p.attack = 0.75; p.decay = 0.5; p.sustain = 0.85; p.release = 1.1; p.spread = 0.8
        case 2:
            p.name = "bright section"
            p.voices = 5; p.detune = 16; p.cutoff = 2800 + 3200 * b; p.q = 0.8
            p.vibrato = 0.004; p.vibratoRate = 5.3
            p.attack = 0.1; p.decay = 0.3; p.sustain = 0.8; p.release = 0.45; p.spread = 0.8
        case 3:
            p.name = "solina"
            p.wave = .pulse; p.pulseWidth = 0.45; p.pwmDepth = 0.12
            p.voices = 5; p.detune = 12; p.drift = 10; p.cutoff = 1800 + 1800 * b; p.q = 0.8
            p.attack = 0.35; p.decay = 0.4; p.sustain = 0.85; p.release = 0.8; p.spread = 1.0
        case 4:
            p.name = "cello"
            p.voices = 2; p.detune = 6; p.cutoff = 650 + 1300 * b; p.q = 1.0
            p.vibrato = 0.006; p.vibratoRate = 5.2
            p.attack = 0.25; p.decay = 0.3; p.sustain = 0.85; p.release = 0.6; p.spread = 0.35
        case 5:
            p.name = "glass strings"
            p.wave = .triangle; p.voices = 5; p.detune = 9
            p.wave2 = .saw; p.mix2 = 0.2; p.ratio2 = 1
            p.cutoff = 2500 + 2500 * b; p.q = 0.8
            p.attack = 0.5; p.decay = 0.4; p.sustain = 0.85; p.release = 1.0; p.spread = 0.9
        case 6:
            p.name = "tremolo strings"
            p.voices = 5; p.detune = 12; p.cutoff = 2000 + 2400 * b; p.q = 0.8
            p.vibrato = 0.002; p.vibratoRate = 5.0
            p.tremolo = 0.55; p.tremoloRate = 6.5
            p.attack = 0.12; p.decay = 0.3; p.sustain = 0.85; p.release = 0.5; p.spread = 0.8
        default:
            // The original strings: five detuned saws with a gentle vibrato.
            p.name = "classic"
            p.voices = 5; p.detune = 14; p.cutoff = 1400 + 3200 * b; p.q = 0.8
            p.vibrato = 0.003; p.vibratoRate = 5.1
            p.attack = 0.5; p.decay = 0.5; p.sustain = 0.85; p.release = 0.9; p.spread = 0.7
        }
        return p
    }

    // MARK: leads

    static func lead(_ c: Int, brightness b: Float) -> SynthPatch {
        var p = SynthPatch()
        let bs = 0.7 + 0.6 * b
        switch c {
        case 1:
            p.name = "supersaw"
            p.voices = 5; p.detune = 18; p.cutoff = 3000 * bs
            p.envAmount = 2500; p.envDecay = 0.25; p.q = 1.0
            p.vibrato = 0.004; p.vibratoRate = 5.4; p.drive = 1.1
            p.attack = 0.01; p.decay = 0.2; p.sustain = 0.85; p.release = 0.25; p.spread = 0.7
        case 2:
            p.name = "pulse"
            p.wave = .pulse; p.pulseWidth = 0.25; p.pwmDepth = 0.15
            p.voices = 2; p.detune = 6; p.cutoff = 2400 * bs
            p.envAmount = 2500; p.envDecay = 0.2; p.q = 1.6
            p.vibrato = 0.006; p.vibratoRate = 5.2
            p.attack = 0.008; p.decay = 0.15; p.sustain = 0.8; p.release = 0.16
        case 3:
            p.name = "chip square"
            p.wave = .square; p.cutoff = 5000 + 3000 * b; p.q = 0.8; p.drive = 1.2
            p.attack = 0.004; p.decay = 0.1; p.sustain = 0.7; p.release = 0.1
        case 4:
            p.name = "soft triangle"
            p.wave = .triangle; p.voices = 2; p.detune = 4
            p.wave2 = .sine; p.ratio2 = 2; p.mix2 = 0.15
            p.cutoff = 3200 * bs; p.lfoDepth = 0.1; p.lfoRate = 0.2
            p.vibrato = 0.01; p.vibratoRate = 5.0
            p.attack = 0.08; p.decay = 0.2; p.sustain = 0.8; p.release = 0.4
        case 5:
            p.name = "brass"
            p.voices = 3; p.detune = 8; p.cutoff = 650 * bs
            p.envAmount = 3500; p.envDecay = 0.12; p.q = 1.2
            p.vibrato = 0.005; p.vibratoRate = 5.3; p.drive = 1.2
            p.attack = 0.03; p.decay = 0.15; p.sustain = 0.8; p.release = 0.2; p.spread = 0.3
        case 6:
            p.name = "plucked lead"
            p.voices = 2; p.detune = 6
            p.wave2 = .square; p.mix2 = 0.25; p.ratio2 = 1
            p.percTau = 0.35; p.cutoff = 1200 * bs
            p.envAmount = 4000; p.envDecay = 0.12; p.velToEnv = 1; p.q = 1.4
        case 7:
            p.name = "whistle"
            p.wave = .sine; p.wave2 = .sine; p.ratio2 = 3; p.mix2 = 0.1
            p.cutoff = 8000; p.vibrato = 0.012; p.vibratoRate = 5.5
            p.attack = 0.05; p.decay = 0.1; p.sustain = 0.85; p.release = 0.3
        case 8:
            // A lead whose oscillators wander out of tune, with grit.
            p.name = "unstable saw"
            p.voices = 3; p.detune = 10; p.unstable = 12
            p.wave2 = .square; p.mix2 = 0.2; p.ratio2 = 1
            p.cutoff = 1400 * bs; p.gritCut = 1500
            p.envAmount = 3200; p.envDecay = 0.22; p.q = 1.5
            p.vibrato = 0.006; p.vibratoRate = 5.2; p.drive = 1.2; p.gritDrive = 1.2
            p.attack = 0.012; p.decay = 0.16; p.sustain = 0.8; p.release = 0.2; p.spread = 0.6
        case 9:
            p.name = "Aloboi Synth"
            p.sample = 1.0; p.oscLevel = 0.2
            p.voices = 2; p.detune = 7; p.unstable = 6
            p.cutoff = 2600 * bs; p.envAmount = 2500; p.envDecay = 0.2; p.q = 1.2
            p.vibrato = 0.006; p.vibratoRate = 5.2; p.drive = 1.1
            p.attack = 0.01; p.decay = 0.2; p.sustain = 0.85; p.release = 0.3; p.spread = 0.7
        default:
            // The original lead: two saws plus a square, a filter that closes after each note, vibrato.
            p.name = "classic"
            p.voices = 2; p.detune = 5
            p.wave2 = .square; p.mix2 = 0.3; p.ratio2 = 1; p.pulseWidth2 = 0.35
            p.cutoff = 900 * bs; p.gritCut = 2500
            p.envAmount = 5600; p.envDecay = 0.18; p.q = 1.4
            p.vibrato = 0.008; p.vibratoRate = 5.4
            p.drive = 1.1; p.gritDrive = 1.5
            p.attack = 0.006; p.decay = 0.12; p.sustain = 0.75; p.release = 0.14
        }
        return p
    }

    // MARK: arps (plucked, percussive)

    static func arp(_ c: Int, brightness b: Float) -> SynthPatch {
        var p = SynthPatch()
        let bs = 0.7 + 0.6 * b
        switch c {
        case 1:
            p.name = "square blip"
            p.wave = .square; p.percTau = 0.09; p.cutoff = 2500 * bs
            p.envAmount = 3500; p.envDecay = 0.06; p.velToEnv = 0.5; p.q = 1.5; p.panAlt = 0.5
        case 2:
            p.name = "pulse pluck"
            p.wave = .pulse; p.pulseWidth = 0.2; p.voices = 2; p.detune = 5
            p.percTau = 0.16; p.cutoff = 1200 * bs
            p.envAmount = 4000; p.envDecay = 0.09; p.velToEnv = 0.6; p.q = 1.8; p.panAlt = 0.5
        case 3:
            p.name = "supersaw pluck"
            p.voices = 3; p.detune = 12; p.spread = 0.6
            p.percTau = 0.22; p.cutoff = 1800 * bs
            p.envAmount = 5000; p.envDecay = 0.14; p.velToEnv = 0.6; p.q = 1.3
        case 4:
            p.name = "soft triangle"
            p.wave = .triangle; p.wave2 = .sine; p.ratio2 = 2; p.mix2 = 0.3
            p.percTau = 0.3; p.cutoff = 5000 * bs; p.q = 0.7; p.panAlt = 0.45
        case 5:
            p.name = "glass FM"
            p.wave = .sine; p.wave2 = .triangle; p.ratio2 = 4; p.mix2 = 0.4
            p.percTau = 0.2; p.cutoff = 6000 + 3000 * b; p.q = 0.7; p.panAlt = 0.5
        case 6:
            p.name = "marimba"
            p.wave = .triangle; p.wave2 = .sine; p.ratio2 = 4; p.mix2 = 0.25
            p.percTau = 0.12; p.cutoff = 4000 * bs
            p.envAmount = 1500; p.envDecay = 0.03; p.q = 0.8; p.panAlt = 0.4
        case 7:
            p.name = "acid"
            p.percTau = 0.14; p.cutoff = 400
            p.envAmount = 3500; p.envDecay = 0.08; p.velToEnv = 0.5; p.q = 4.0
            p.drive = 1.3; p.gritDrive = 1.0; p.panAlt = 0.3
        case 8:
            p.name = "Aloboi Synth"
            p.sample = 1.0; p.oscLevel = 0.3
            p.voices = 2; p.detune = 6; p.unstable = 5
            p.percTau = 0.28; p.cutoff = 1500 * bs
            p.envAmount = 3000; p.envDecay = 0.1; p.velToEnv = 0.8; p.q = 1.3
            p.spread = 0.5; p.panAlt = 0.3
        default:
            // The original arp: two detuned saws through a quick-closing filter.
            p.name = "classic"
            p.voices = 2; p.detune = 3.5
            p.percTau = 0.13; p.cutoff = 900 * bs
            p.envAmount = 7000; p.envDecay = 0.1; p.velToEnv = 0.79; p.q = 2.2
            p.drive = 1; p.gritDrive = 1.5; p.panAlt = 0.5
        }
        return p
    }

    // MARK: plucks (plucked, percussive)

    static func pluck(_ c: Int, brightness b: Float) -> SynthPatch {
        var p = SynthPatch()
        let bs = 0.7 + 0.6 * b
        switch c {
        case 1:
            p.name = "kalimba"
            p.wave = .triangle; p.wave2 = .sine; p.ratio2 = 5.4; p.mix2 = 0.25
            p.percTau = 0.35; p.cutoff = 5000 * bs; p.q = 0.7; p.panAlt = 0.3
        case 2:
            p.name = "funk pluck"
            p.voices = 2; p.detune = 4
            p.percTau = 0.25; p.cutoff = 600 * bs
            p.envAmount = 3500; p.envDecay = 0.1; p.velToEnv = 0.6; p.q = 2.5; p.panAlt = 0.2
        case 3:
            p.name = "pizzicato"
            p.voices = 3; p.detune = 8; p.spread = 0.3
            p.percTau = 0.18; p.cutoff = 1500 * bs
            p.envAmount = 1500; p.envDecay = 0.05; p.q = 1.0
        case 4:
            p.name = "harp"
            p.wave = .triangle; p.wave2 = .sine; p.ratio2 = 2; p.mix2 = 0.4
            p.percTau = 0.6; p.cutoff = 6000 * bs; p.q = 0.7; p.panAlt = 0.4
        case 5:
            p.name = "pulse pluck"
            p.wave = .pulse; p.pulseWidth = 0.3
            p.percTau = 0.2; p.cutoff = 1400 * bs
            p.envAmount = 2800; p.envDecay = 0.08; p.q = 1.6; p.panAlt = 0.35
        case 6:
            p.name = "muted synth"
            p.wave = .square; p.percTau = 0.1; p.cutoff = 700 * bs
            p.envAmount = 1800; p.envDecay = 0.06; p.q = 1.2; p.drive = 1.2; p.panAlt = 0.3
        case 7:
            p.name = "koto"
            p.wave2 = .triangle; p.ratio2 = 2; p.mix2 = 0.3
            p.percTau = 0.5; p.cutoff = 2500 * bs
            p.envAmount = 3000; p.envDecay = 0.04; p.q = 1.4; p.panAlt = 0.4
        default:
            // The original pluck: two detuned saws, closing filter, a little longer than the arp.
            p.name = "classic"
            p.voices = 2; p.detune = 3.5
            p.percTau = 0.22; p.cutoff = 500 * bs
            p.envAmount = 7000; p.envDecay = 0.1; p.velToEnv = 0.79; p.q = 2.2
            p.drive = 1; p.gritDrive = 1.5; p.panAlt = 0.35
        }
        return p
    }

    // MARK: sub basses

    static func sub(_ c: Int) -> BassPatch {
        var p = BassPatch()
        switch c {
        case 1:
            p.name = "saw bass"
            p.kind = .saw; p.cutoff = 180; p.envAmount = 1400; p.envDecay = 0.16; p.q = 1.6
            p.drive = 1.2; p.gritDrive = 1.0; p.sub = 0.4; p.detune = 9
            p.attack = 0.005; p.decay = 0.15; p.sustain = 0.8; p.release = 0.08
        case 2:
            p.name = "square bass"
            p.kind = .square; p.pulseWidth = 0.4; p.cutoff = 300; p.envAmount = 900; p.envDecay = 0.2; p.q = 1.2
            p.drive = 1.2; p.gritDrive = 1.0; p.sub = 0.3
            p.attack = 0.005; p.decay = 0.12; p.sustain = 0.85; p.release = 0.08
        case 3:
            p.name = "FM bass"
            p.kind = .fm; p.fmRatio = 1; p.fmIndex = 2.2; p.fmDecay = 0.15
            p.drive = 1.2; p.gritDrive = 1.0; p.sub = 0.2
            p.attack = 0.004; p.decay = 0.1; p.sustain = 0.85; p.release = 0.08
        case 4:
            p.name = "808"
            p.kind = .e808; p.harmonics = 0.18; p.glideSemis = 7; p.glide = 0.05
            p.drive = 1.8; p.gritDrive = 1.0
            p.attack = 0.003; p.decay = 0.7; p.sustain = 0.55; p.release = 0.18
        case 5:
            p.name = "funk bass"
            p.kind = .funk; p.cutoff = 250; p.envAmount = 2600; p.envDecay = 0.11; p.q = 2.8
            p.sub = 0.25; p.drive = 1.3; p.gritDrive = 1.0; p.detune = 6
            p.attack = 0.003; p.decay = 0.22; p.sustain = 0.45; p.release = 0.07
        case 6:
            p.name = "round bass"
            p.kind = .tri; p.cutoff = 700; p.q = 0.8; p.drive = 1.6; p.gritDrive = 0.8; p.sub = 0.2
            p.attack = 0.008; p.decay = 0.1; p.sustain = 0.9; p.release = 0.12
        case 7:
            p.name = "warm sine"
            p.kind = .sine; p.harmonics = 0.35; p.drive = 1.2; p.gritDrive = 0.6
            p.attack = 0.01; p.decay = 0.12; p.sustain = 0.9; p.release = 0.15
        case 8:
            p.name = "reese"
            p.kind = .reese; p.cutoff = 220; p.envAmount = 900; p.envDecay = 0.25; p.q = 1.4
            p.drive = 1.3; p.gritDrive = 1.0; p.sub = 0.45; p.detune = 14
            p.attack = 0.008; p.decay = 0.2; p.sustain = 0.9; p.release = 0.12
        case 9:
            p.name = "dirty reese"
            p.kind = .reese; p.cutoff = 300; p.envAmount = 1800; p.envDecay = 0.35; p.q = 2.2
            p.drive = 1.8; p.gritDrive = 1.8; p.sub = 0.35; p.detune = 24
            p.attack = 0.006; p.decay = 0.25; p.sustain = 0.85; p.release = 0.12
        default:
            // The original sub: a clean low sine with a little warmth.
            p.name = "sine"
            p.kind = .sine; p.drive = 1.3; p.gritDrive = 1.2
            p.attack = 0.005; p.decay = 0.08; p.sustain = 0.9; p.release = 0.1
        }
        return p
    }

    // MARK: growl basses

    static func growl(_ c: Int) -> GrowlPatch {
        var p = GrowlPatch()
        switch c {
        case 1:
            p.name = "reese"
            p.detune = 1.02; p.ringAmount = 0.15; p.wobbleScale = 0.25
            p.cutoffRange = 400; p.cutoffRangeGrit = 3000; p.qBase = 1.2; p.qGrit = 2.0
            p.subMix = 0.6; p.driveGrit = 2.0
        case 2:
            p.name = "talking"
            p.qBase = 3.0; p.qGrit = 5.0; p.cutoffRange = 900; p.cutoffRangeGrit = 3500
            p.driveGrit = 2.5; p.ringAmount = 0.3
        case 3:
            p.name = "wobble"
            p.wobbleScale = 2; p.qBase = 2.5; p.qGrit = 4.5; p.cutoffRange = 1100; p.cutoffRangeGrit = 6000
            p.driveBase = 1.6; p.driveGrit = 3.6; p.ringAmount = 0.7
        case 4:
            p.name = "smooth"
            p.driveBase = 1.0; p.driveGrit = 1.6; p.ringAmount = 0.1; p.wobbleScale = 0.5
            p.cutoffRangeGrit = 3500; p.qBase = 1.2; p.qGrit = 2.0; p.subMix = 0.55
        case 5:
            p.name = "neuro"
            p.ringRatio = 2.01; p.ringAmount = 1.1; p.wobbleScale = 3
            p.qBase = 2.2; p.qGrit = 3.5; p.driveGrit = 3.5; p.detune = 1.0125
        default:
            p.name = "classic"
        }
        return p
    }

    // MARK: keys

    static func keys(_ c: Int) -> KeysPatch {
        var p = KeysPatch()
        switch c {
        case 1:
            p.name = "DX bell piano"
            p.ratio1 = 1; p.index1 = 2.2; p.idx1Decay = 0.6; p.idx1Floor = 0.2
            p.ratio2 = 4; p.index2 = 0.8; p.idx2Decay = 0.08
            p.tauBase = 2.4; p.tauSlope = 800; p.tauMin = 0.7; p.tauMax = 2.4
        case 2:
            p.name = "felt piano"
            p.index1 = 0.7; p.idx1Decay = 0.22; p.idx1Floor = 0.08
            p.index2 = 0.12; p.idx2Decay = 0.02
            p.tauBase = 1.5; p.tauMin = 0.4; p.tauMax = 1.5
            p.cutoff = 2200; p.q = 0.7; p.attack = 0.008
        case 3:
            p.name = "wobbly EP"
            p.index1 = 1.3; p.tauBase = 1.7; p.tauMax = 1.7
            p.wobble = 14; p.wobbleRate = 0.6; p.cutoff = 3000
        case 4:
            p.name = "tine EP"
            p.ratio1 = 1; p.index1 = 1.0; p.idx1Decay = 0.35; p.idx1Floor = 0.15
            p.ratio2 = 7; p.index2 = 0.35; p.idx2Decay = 0.04
            p.tremolo = 0.35; p.tremoloRate = 4.6; p.tauBase = 1.8; p.tauMax = 1.8
        case 5:
            p.name = "glass keys"
            p.ratio1 = 2; p.index1 = 1.2; p.idx1Decay = 0.5; p.idx1Floor = 0.3
            p.ratio2 = 9; p.index2 = 0.5; p.idx2Decay = 0.05
            p.tauBase = 2.0; p.tauMax = 2.0
        case 6:
            p.name = "soft keys"
            p.index1 = 0.9; p.idx1Decay = 0.3; p.idx1Floor = 0.1
            p.index2 = 0.2; p.tauBase = 1.4; p.tauMax = 1.4
            p.cutoff = 3500; p.attack = 0.012; p.release = 0.3
        default:
            p.name = "rhodes"
        }
        return p
    }

    // MARK: guitars

    static func guitar(_ c: Int) -> GuitarPatch {
        var p = GuitarPatch()
        switch c {
        case 1:
            p.name = "nylon"
            p.pickBright = 0.38; p.bodyCutoff = 2600; p.tauScale = 0.85; p.release = 0.25
        case 2:
            p.name = "clean electric"
            p.pickBright = 0.8; p.bodyCutoff = 5600; p.tauScale = 1.1; p.release = 0.3
        case 3:
            p.name = "jangle"
            p.pickBright = 0.95; p.bodyCutoff = 7500; p.tauScale = 0.7; p.release = 0.25
        case 4:
            p.name = "muted"
            p.pickBright = 0.45; p.bodyCutoff = 3000; p.tauScale = 0.18; p.release = 0.08
        case 5:
            p.name = "shimmer"
            p.pickBright = 0.7; p.bodyCutoff = 6200; p.tauScale = 1.35; p.release = 0.5
            p.detune = 9; p.spread = 0.45
        default:
            p.name = "classic"
        }
        return p
    }

    // MARK: bells

    static func bells(_ c: Int) -> BellPatch {
        var p = BellPatch()
        switch c {
        case 1:
            p.name = "vibes"
            p.modRatio = 4; p.modIndex = 1.0; p.idxDecay = 0.5; p.idxFloor = 0.05; p.ampTau = 1.4
            p.p1Ratio = 10; p.p1Level = 0.15; p.p1Tau = 0.08
            p.length = 3.0; p.tremolo = 0.35; p.tremoloRate = 4.2
        case 2:
            p.name = "music box"
            p.modRatio = 5.4; p.modIndex = 0.8; p.idxDecay = 0.25; p.idxFloor = 0.05; p.ampTau = 0.5
            p.p1Ratio = 2; p.p1Level = 0.3; p.p1Tau = 0.3
            p.p2Ratio = 7.2; p.p2Level = 0.1; p.p2Tau = 0.12
            p.length = 1.6
        case 3:
            p.name = "dark clang"
            p.modRatio = 1.4; p.modIndex = 3.2; p.idxDecay = 1.0; p.idxFloor = 0.3; p.ampTau = 2.2
            p.p1Ratio = 2.4; p.p1Level = 0.2; p.p1Tau = 1.0
            p.length = 4.0
        case 4:
            p.name = "tubular"
            p.modRatio = 2.76; p.modIndex = 1.4; p.idxDecay = 1.2; p.idxFloor = 0.1; p.ampTau = 3.0
            p.p1Ratio = 5.4; p.p1Level = 0.3; p.p1Tau = 1.2
            p.p2Ratio = 8.93; p.p2Level = 0.15; p.p2Tau = 0.8
            p.length = 4.5
        case 5:
            p.name = "kalimba"
            p.modRatio = 3; p.modIndex = 0.6; p.idxDecay = 0.15; p.idxFloor = 0.02; p.ampTau = 0.45
            p.p1Ratio = 5.4; p.p1Level = 0.2; p.p1Tau = 0.1
            p.length = 1.3
        default:
            p.name = "glass bell"
        }
        return p
    }
}

// MARK: - Which characters each genre likes
//
// One number per character (same order as the library above). Bigger = chosen more often.
// Genres missing from a table (and "any genre") use equal weights.

private enum GenreTaste {
    //                               classic supersaw glass warm juno drone gated washed
    static let pad: [Genre: [Double]] = [
        .electronic:   [1.5, 1.5, 0.6, 1.2, 0.6, 0.4, 1.2, 0.3],
        .synthpop:     [0.8, 0.7, 0.3, 0.6, 2.5, 0.1, 0.6, 0.6],
        .pop:          [1.8, 1.0, 0.7, 0.8, 1.0, 0.2, 0.3, 0.4],
        .chillwave:    [0.5, 0.3, 0.8, 0.8, 0.6, 0.3, 0.2, 3.0],
        .downtempo:    [1.0, 0.2, 0.8, 2.0, 0.3, 0.8, 0.2, 1.0],
        .ambient:      [0.3, 0.1, 2.5, 1.0, 0.1, 2.5, 0.1, 1.0],
        .dreamPop:     [0.6, 0.4, 1.5, 0.8, 0.8, 0.3, 0.2, 2.5],
        .indietronica: [1.5, 0.4, 1.0, 0.8, 1.2, 0.2, 0.5, 0.4],
        .lofi:         [0.8, 0.1, 0.4, 2.2, 0.6, 0.3, 0.1, 1.8],
        .nuDisco:      [1.0, 0.8, 0.3, 0.6, 1.8, 0.1, 1.0, 0.2],
        .edm:          [0.8, 3.0, 0.4, 0.4, 0.5, 0.1, 2.0, 0.1]
    ]

    //                               classic warm bright solina cello glass tremolo
    static let strings: [Genre: [Double]] = [
        .electronic:   [1.0, 0.6, 1.0, 1.0, 0.4, 0.8, 0.8],
        .synthpop:     [0.8, 0.5, 1.0, 2.0, 0.2, 0.5, 0.4],
        .pop:          [1.5, 1.5, 1.2, 0.6, 0.8, 0.5, 0.3],
        .chillwave:    [0.6, 1.5, 0.2, 1.5, 0.4, 1.0, 0.1],
        .downtempo:    [0.8, 2.0, 0.4, 0.8, 1.5, 0.6, 0.3],
        .ambient:      [0.5, 1.5, 0.1, 0.8, 1.0, 2.0, 0.2],
        .dreamPop:     [0.6, 1.5, 0.3, 1.5, 0.6, 1.5, 0.2],
        .indietronica: [1.0, 1.2, 0.6, 0.8, 1.0, 0.8, 0.5],
        .lofi:         [0.8, 2.0, 0.2, 1.5, 1.2, 0.4, 0.2],
        .nuDisco:      [1.0, 0.6, 2.5, 1.0, 0.2, 0.3, 0.4],
        .edm:          [1.0, 0.4, 1.5, 0.6, 0.1, 1.0, 1.5]
    ]

    //                               classic supersaw pulse chip soft brass pluck whistle
    static let lead: [Genre: [Double]] = [
        .electronic:   [1.5, 1.2, 1.0, 0.8, 0.3, 0.6, 0.5, 0.2],
        .synthpop:     [1.2, 0.8, 2.2, 0.6, 0.3, 0.5, 0.4, 0.3],
        .pop:          [1.5, 0.8, 0.8, 0.3, 0.7, 0.6, 0.8, 0.6],
        .chillwave:    [0.5, 0.3, 0.6, 0.2, 2.0, 0.2, 0.4, 1.2],
        .downtempo:    [0.6, 0.1, 0.5, 0.1, 2.0, 0.4, 0.8, 1.0],
        .ambient:      [0.2, 0.1, 0.2, 0.0, 2.5, 0.1, 0.3, 2.0],
        .dreamPop:     [0.4, 0.3, 0.4, 0.1, 2.0, 0.2, 0.4, 1.5],
        .indietronica: [0.8, 0.3, 1.2, 1.5, 0.8, 0.4, 2.0, 0.8],
        .lofi:         [0.4, 0.1, 0.8, 0.5, 1.8, 0.3, 1.0, 0.8],
        .nuDisco:      [1.0, 0.6, 1.0, 0.4, 0.4, 2.0, 0.8, 0.3],
        .edm:          [1.0, 3.0, 0.8, 0.8, 0.1, 0.8, 0.6, 0.1]
    ]

    //                               classic blip pulse edm soft glass marimba acid
    static let arp: [Genre: [Double]] = [
        .electronic:   [1.5, 1.2, 1.0, 0.8, 0.3, 0.5, 0.4, 1.2],
        .synthpop:     [1.2, 1.5, 1.2, 0.6, 0.3, 0.4, 0.3, 0.4],
        .pop:          [1.2, 0.6, 1.0, 0.8, 0.8, 0.8, 0.8, 0.1],
        .chillwave:    [0.6, 0.3, 0.5, 0.3, 2.0, 1.2, 0.6, 0.1],
        .downtempo:    [0.8, 0.3, 0.6, 0.2, 1.5, 1.0, 1.2, 0.3],
        .ambient:      [0.3, 0.1, 0.2, 0.1, 2.0, 2.0, 1.0, 0.0],
        .dreamPop:     [0.5, 0.2, 0.4, 0.3, 1.8, 1.5, 0.8, 0.1],
        .indietronica: [0.8, 1.5, 1.2, 0.4, 0.8, 0.8, 2.0, 0.4],
        .lofi:         [0.6, 0.4, 0.6, 0.1, 1.5, 0.6, 1.5, 0.1],
        .nuDisco:      [1.0, 0.8, 1.5, 0.8, 0.3, 0.4, 0.6, 0.5],
        .edm:          [1.0, 0.8, 0.8, 3.0, 0.2, 0.5, 0.2, 1.0]
    ]

    //                               classic kalimba funk pizz harp pulse muted koto
    static let pluck: [Genre: [Double]] = [
        .electronic:   [1.2, 0.6, 0.8, 0.5, 0.4, 1.2, 1.0, 0.6],
        .synthpop:     [1.0, 0.4, 0.8, 0.5, 0.3, 1.5, 0.8, 0.3],
        .pop:          [1.2, 0.8, 0.8, 1.0, 1.0, 0.8, 0.6, 0.6],
        .chillwave:    [0.6, 1.0, 0.4, 0.6, 1.5, 0.6, 0.5, 0.8],
        .downtempo:    [0.8, 1.2, 0.8, 0.8, 1.2, 0.5, 0.8, 1.0],
        .ambient:      [0.3, 1.5, 0.1, 0.5, 2.5, 0.2, 0.2, 1.5],
        .dreamPop:     [0.5, 1.2, 0.3, 0.6, 2.0, 0.4, 0.4, 1.0],
        .indietronica: [0.8, 2.0, 0.8, 1.0, 0.8, 1.0, 1.0, 1.2],
        .lofi:         [0.6, 1.5, 0.6, 0.8, 1.2, 0.4, 1.5, 1.0],
        .nuDisco:      [1.0, 0.4, 2.5, 1.0, 0.3, 0.8, 1.2, 0.4],
        .edm:          [1.0, 0.3, 0.8, 0.5, 0.2, 2.0, 1.0, 0.5]
    ]

    //                               sine saw square fm 808 funk round warm
    static let sub: [Genre: [Double]] = [
        .electronic:   [0.8, 1.5, 1.2, 1.0, 0.6, 0.4, 0.6, 0.5],
        .synthpop:     [0.5, 1.5, 1.5, 0.6, 0.2, 0.8, 0.5, 0.4],
        .pop:          [1.2, 0.8, 0.6, 0.3, 0.3, 0.6, 1.5, 1.2],
        .chillwave:    [1.5, 0.5, 0.4, 0.3, 0.8, 0.1, 1.5, 1.5],
        .downtempo:    [1.0, 0.8, 0.4, 0.4, 2.0, 0.3, 1.0, 1.2],
        .ambient:      [1.5, 0.2, 0.1, 0.2, 0.5, 0.0, 1.5, 2.0],
        .dreamPop:     [1.2, 0.4, 0.3, 0.2, 0.4, 0.2, 1.8, 1.5],
        .indietronica: [0.6, 0.8, 1.5, 1.5, 0.4, 0.6, 1.5, 0.6],
        .lofi:         [1.0, 0.3, 0.3, 0.2, 2.5, 0.3, 1.5, 1.5],
        .nuDisco:      [0.3, 0.8, 0.6, 0.3, 0.1, 3.0, 0.8, 0.3],
        .edm:          [0.8, 2.0, 1.5, 1.5, 0.8, 0.2, 0.3, 0.3]
    ]

    //                               classic reese talking wobble smooth neuro
    static let growl: [Genre: [Double]] = [
        .electronic:   [1.5, 1.5, 1.0, 0.8, 0.8, 1.0],
        .edm:          [1.0, 0.8, 0.8, 2.5, 0.4, 1.5],
        .nuDisco:      [1.0, 0.6, 1.0, 0.3, 1.5, 0.3],
        .lofi:         [1.0, 1.0, 0.6, 0.2, 2.0, 0.2],
        .downtempo:    [1.0, 1.5, 1.0, 0.3, 1.5, 0.3],
        .ambient:      [0.5, 1.5, 0.5, 0.1, 2.0, 0.1]
    ]

    //                               rhodes dx felt wobbly tine glass soft
    static let keys: [Genre: [Double]] = [
        .electronic:   [1.0, 1.0, 0.4, 0.2, 0.8, 1.0, 0.5],
        .synthpop:     [0.8, 1.8, 0.3, 0.1, 0.8, 1.0, 0.3],
        .pop:          [1.0, 0.8, 1.8, 0.1, 0.8, 0.6, 0.8],
        .chillwave:    [1.0, 0.5, 0.4, 0.8, 1.5, 0.8, 1.2],
        .downtempo:    [2.0, 0.6, 0.8, 0.8, 1.0, 0.4, 1.0],
        .ambient:      [0.6, 0.5, 1.0, 0.2, 0.6, 1.5, 2.0],
        .dreamPop:     [1.0, 0.6, 0.6, 0.3, 1.8, 1.0, 1.5],
        .indietronica: [0.8, 1.2, 1.5, 0.4, 1.2, 1.0, 0.6],
        .lofi:         [1.2, 0.2, 1.5, 3.0, 0.8, 0.2, 0.8],
        .nuDisco:      [1.5, 1.0, 0.8, 0.1, 1.5, 0.6, 0.2],
        .edm:          [0.5, 1.5, 1.0, 0.0, 0.6, 1.5, 0.3]
    ]

    //                               classic nylon clean jangle muted shimmer
    static let guitar: [Genre: [Double]] = [
        .electronic:   [1.0, 0.4, 1.0, 0.6, 1.5, 0.5],
        .synthpop:     [0.8, 0.3, 1.5, 1.5, 1.0, 0.8],
        .pop:          [1.2, 1.2, 1.5, 1.0, 0.5, 0.5],
        .chillwave:    [0.6, 0.8, 1.0, 0.6, 0.3, 2.0],
        .downtempo:    [0.8, 1.5, 1.2, 0.4, 0.6, 0.8],
        .ambient:      [0.4, 1.0, 0.8, 0.2, 0.1, 3.0],
        .dreamPop:     [0.4, 0.5, 0.8, 1.5, 0.2, 3.0],
        .indietronica: [0.8, 0.8, 1.2, 2.5, 0.8, 0.8],
        .lofi:         [0.8, 2.0, 0.8, 0.4, 0.6, 0.6],
        .nuDisco:      [0.6, 0.3, 2.0, 0.8, 2.5, 0.3],
        .edm:          [1.0, 0.2, 1.0, 0.5, 1.0, 0.6]
    ]

    //                               glass vibes box dark tubular kalimba
    static let bells: [Genre: [Double]] = [
        .electronic:   [1.5, 0.8, 0.8, 1.5, 0.5, 0.4],
        .synthpop:     [1.5, 0.8, 0.8, 0.6, 0.5, 0.4],
        .pop:          [1.5, 1.0, 1.2, 0.4, 0.6, 0.8],
        .chillwave:    [1.5, 1.0, 0.8, 0.5, 0.8, 0.8],
        .downtempo:    [1.0, 1.8, 0.6, 0.8, 0.8, 1.0],
        .ambient:      [1.5, 1.0, 0.8, 1.0, 2.5, 0.5],
        .dreamPop:     [1.5, 1.0, 1.2, 0.5, 1.0, 0.8],
        .indietronica: [1.0, 1.5, 2.0, 0.5, 0.4, 2.0],
        .lofi:         [0.8, 1.5, 1.5, 0.4, 0.4, 1.5],
        .nuDisco:      [1.0, 2.0, 0.6, 0.4, 0.4, 0.6],
        .edm:          [2.0, 0.5, 0.8, 1.0, 0.5, 0.3]
    ]
}

// How often the Aloboi characters (unstable oscillators, the Aloboi Synth sample, Reese basses) come up in
// each genre when the Aloboi sound is NOT switched on. A genre that is missing uses the default.
private enum AloboiTaste {
    //                               unstable stack, Aloboi Synth, intermod drone
    static let pad: [Genre: [Double]] = [
        .electronic:   [1.2, 0.8, 0.6],
        .edm:          [1.0, 0.3, 0.1],
        .downtempo:    [0.6, 0.8, 0.8],
        .chillwave:    [0.5, 0.4, 0.4],
        .ambient:      [0.3, 0.5, 1.2],
        .dreamPop:     [0.3, 0.3, 0.3],
        .synthpop:     [0.5, 0.2, 0.1],
        .indietronica: [0.4, 0.4, 0.1],
        .nuDisco:      [0.4, 0.2, 0.0],
        .lofi:         [0.1, 0.4, 0.2],
        .pop:          [0.15, 0.1, 0.0]
    ]
    static let padDefault = 0.3

    //                               unstable saw, Aloboi Synth
    static let lead: [Genre: [Double]] = [
        .electronic:   [1.0, 0.8],
        .edm:          [0.8, 0.3],
        .downtempo:    [0.4, 0.5],
        .chillwave:    [0.3, 0.4],
        .ambient:      [0.1, 0.3],
        .dreamPop:     [0.2, 0.3],
        .synthpop:     [0.5, 0.2],
        .indietronica: [0.3, 0.3],
        .nuDisco:      [0.3, 0.1],
        .lofi:         [0.1, 0.3],
        .pop:          [0.1, 0.1]
    ]
    static let leadDefault = 0.3

    //                               Aloboi Synth
    static let arp: [Genre: [Double]] = [
        .electronic:   [0.8],
        .edm:          [0.3],
        .downtempo:    [0.5],
        .chillwave:    [0.4],
        .ambient:      [0.3],
        .dreamPop:     [0.2],
        .synthpop:     [0.2],
        .indietronica: [0.3],
        .nuDisco:      [0.1],
        .lofi:         [0.3],
        .pop:          [0.05]
    ]
    static let arpDefault = 0.25

    //                               reese, dirty reese
    static let sub: [Genre: [Double]] = [
        .electronic:   [1.0, 0.8],
        .edm:          [0.8, 0.8],
        .downtempo:    [0.6, 0.2],
        .chillwave:    [0.2, 0.0],
        .ambient:      [0.1, 0.0],
        .dreamPop:     [0.0, 0.0],
        .synthpop:     [0.2, 0.1],
        .indietronica: [0.2, 0.1],
        .nuDisco:      [0.0, 0.0],
        .lofi:         [0.1, 0.0],
        .pop:          [0.0, 0.0]
    ]
    static let subDefault = 0.25
}

// MARK: - Palette.make

extension Palette {
    /// Picks a character for every instrument from the genre's taste, bends it with the mood and the
    /// brightness, then nudges every number a little with the seed.
    /// Nothing here depends on which instruments the user turned on.
    static func make(genre: Genre?, mood: Mood, brightness: Float, aloboi: Bool = false,
                     rng: SeededRNG) -> Palette {
        let tilt = MoodTilt(mood)
        let b = min(max(brightness, 0), 1)

        var gPad = rng.fork(1)
        let padWeights = characterWeights(GenreTaste.pad, genre, oldCount: PatchLibrary.oldPadCount,
                                          extra: AloboiTaste.pad, extraCount: 3,
                                          extraDefault: AloboiTaste.padDefault, aloboi: aloboi)
        var pad = PatchLibrary.pad(pickIndex(padWeights, count: PatchLibrary.padCount, &gPad), brightness: b)
        varySynth(&pad, tilt, &gPad)

        var gStr = rng.fork(2)
        var strings = PatchLibrary.strings(pickIndex(genreWeights(GenreTaste.strings, genre),
                                                     count: PatchLibrary.stringsCount, &gStr), brightness: b)
        varySynth(&strings, tilt, &gStr)

        var gLead = rng.fork(3)
        let leadWeights = characterWeights(GenreTaste.lead, genre, oldCount: PatchLibrary.oldLeadCount,
                                           extra: AloboiTaste.lead, extraCount: 2,
                                           extraDefault: AloboiTaste.leadDefault, aloboi: aloboi)
        var lead = PatchLibrary.lead(pickIndex(leadWeights, count: PatchLibrary.leadCount, &gLead), brightness: b)
        varySynth(&lead, tilt, &gLead)

        var gArp = rng.fork(4)
        let arpWeights = characterWeights(GenreTaste.arp, genre, oldCount: PatchLibrary.oldArpCount,
                                          extra: AloboiTaste.arp, extraCount: 1,
                                          extraDefault: AloboiTaste.arpDefault, aloboi: aloboi)
        var arp = PatchLibrary.arp(pickIndex(arpWeights, count: PatchLibrary.arpCount, &gArp), brightness: b)
        varySynth(&arp, tilt, &gArp)

        var gPluck = rng.fork(5)
        var pluck = PatchLibrary.pluck(pickIndex(genreWeights(GenreTaste.pluck, genre),
                                                 count: PatchLibrary.pluckCount, &gPluck), brightness: b)
        varySynth(&pluck, tilt, &gPluck)

        var gSub = rng.fork(6)
        let subWeights = characterWeights(GenreTaste.sub, genre, oldCount: PatchLibrary.oldSubCount,
                                          extra: AloboiTaste.sub, extraCount: 2,
                                          extraDefault: AloboiTaste.subDefault, aloboi: aloboi)
        var sub = PatchLibrary.sub(pickIndex(subWeights, count: PatchLibrary.subCount, &gSub))
        sub.cutoff *= jit(&gSub, 0.85, 1.2)
        sub.envAmount *= jit(&gSub, 0.8, 1.25)
        sub.envDecay *= jit(&gSub, 0.85, 1.2)
        sub.drive *= jit(&gSub, 0.92, 1.12)
        sub.release *= tilt.releaseScale

        var gGrowl = rng.fork(7)
        var growl = PatchLibrary.growl(pickIndex(genreWeights(GenreTaste.growl, genre),
                                                 count: PatchLibrary.growlCount, &gGrowl))
        growl.wobbleScale *= jit(&gGrowl, 0.85, 1.2)
        growl.cutoffBase *= jit(&gGrowl, 0.85, 1.2)
        growl.driveBase *= jit(&gGrowl, 0.92, 1.1)

        var gKeys = rng.fork(8)
        var keys = PatchLibrary.keys(pickIndex(genreWeights(GenreTaste.keys, genre), count: PatchLibrary.keysCount, &gKeys))
        keys.index1 *= jit(&gKeys, 0.85, 1.15)
        keys.tauBase *= jit(&gKeys, 0.9, 1.12)
        keys.tauMax = max(keys.tauMax, keys.tauBase)
        keys.release *= tilt.releaseScale
        if keys.cutoff > 0 { keys.cutoff *= tilt.cutoffScale * jit(&gKeys, 0.9, 1.15) }
        if keys.wobble > 0 { keys.wobble *= jit(&gKeys, 0.7, 1.3); keys.wobbleRate *= jit(&gKeys, 0.8, 1.3) }

        var gGuitar = rng.fork(9)
        var guitar = PatchLibrary.guitar(pickIndex(genreWeights(GenreTaste.guitar, genre),
                                                   count: PatchLibrary.guitarCount, &gGuitar))
        guitar.bodyCutoff *= (0.85 + 0.3 * b) * jit(&gGuitar, 0.9, 1.12)
        guitar.tauScale *= jit(&gGuitar, 0.9, 1.15)
        guitar.pickBright = min(max(guitar.pickBright + jit(&gGuitar, -0.06, 0.06), 0.2), 1.0)
        if guitar.detune > 0 { guitar.detune *= jit(&gGuitar, 0.8, 1.3) }

        var gBells = rng.fork(10)
        var bells = PatchLibrary.bells(pickIndex(genreWeights(GenreTaste.bells, genre),
                                                 count: PatchLibrary.bellsCount, &gBells))
        bells.ampTau *= jit(&gBells, 0.85, 1.25)
        bells.modIndex *= jit(&gBells, 0.85, 1.15)
        bells.length = max(0.8, bells.length * jit(&gBells, 0.9, 1.15))

        return Palette(pad: pad, strings: strings, lead: lead, arp: arp, pluck: pluck, sub: sub,
                       growl: growl, keys: keys, guitar: guitar, bells: bells)
    }

    /// Mood and seed variation shared by all synth characters.
    private static func varySynth(_ p: inout SynthPatch, _ tilt: MoodTilt, _ g: inout SeededRNG) {
        p.cutoff *= tilt.cutoffScale * jit(&g, 0.84, 1.2)
        p.detune *= tilt.detuneScale * jit(&g, 0.8, 1.25)
        p.lfoRate *= jit(&g, 0.7, 1.4)
        p.vibratoRate *= jit(&g, 0.92, 1.1)
        if p.percTau > 0 {
            p.percTau *= jit(&g, 0.82, 1.3)
            p.envDecay *= jit(&g, 0.8, 1.3)
        } else {
            p.attack *= tilt.attackScale * jit(&g, 0.85, 1.25)
            p.release *= tilt.releaseScale * jit(&g, 0.9, 1.2)
        }
        if p.wave == .pulse {
            p.pulseWidth = min(max(p.pulseWidth + jit(&g, -0.05, 0.05), 0.12), 0.88)
        }
    }
}

// MARK: - Effects

struct FXSpec {
    /// Reverb room size 0...1 (longer tail when bigger) and how dark the tail is.
    var room: Float = 0.5
    var damping: Float = 0.35
    var wet: Float = 2.2
    /// Seconds between the dry sound and the start of the reverb.
    var preDelay: Float = 0
    /// Multiplies every instrument's reverb send.
    var sendScale: Float = 1
    /// Echo time in beats (0 = no echo): 1 = quarter note, 0.75 = dotted eighth, 0.5 = eighth,
    /// 0.667 = quarter triplet, 1.5 = dotted quarter.
    var echoBeats: Double = 0.75
    var echoFeedback: Float = 0.42
    var echoDamp: Float = 0.35
    var echoGain: Float = 0.8
    /// 0...1: extra analog-style chorus and width on the pad.
    var padChorus: Float = 0
    /// Lo-fi chain: low-pass cutoff (20000 = off), sample-rate reduction (1 = off), bit depth (16 = off),
    /// tape wow depth in milliseconds (0 = off) and vinyl crackle level (0 = off).
    var lofiCutoff: Float = 20000
    var bitHold: Int = 1
    var bits: Int = 16
    var wow: Float = 0
    var crackle: Float = 0

    var usesLoFi: Bool {
        lofiCutoff < 15000 || bitHold > 1 || bits < 16 || wow > 0.001
    }

    var echoName: String {
        if echoBeats <= 0 { return "no echo" }
        if abs(echoBeats - 1.0) < 0.01 { return "1/4 echo" }
        if abs(echoBeats - 0.75) < 0.01 { return "dotted 1/8 echo" }
        if abs(echoBeats - 0.5) < 0.01 { return "1/8 echo" }
        if abs(echoBeats - 1.5) < 0.01 { return "dotted 1/4 echo" }
        if abs(echoBeats - 0.667) < 0.01 { return "triplet echo" }
        return "echo"
    }

    var summary: String {
        var s = "reverb \(Int(room * 100))%, \(echoName)"
        if padChorus > 0.05 { s += ", chorus pad" }
        if usesLoFi { s += ", lo-fi tape" }
        return s
    }
}

private struct FXBase {
    var room: Float = 0.5
    var damping: Float = 0.35
    var wet: Float = 2.2
    var preDelay: Float = 0.01
    var send: Float = 1.0
    var echoBeats: [Double] = [0.75, 1.0, 0.5]
    var echoWeights: [Double] = [1, 1, 1]
    var feedback: Float = 0.4
    var echoDamp: Float = 0.35
    var echoGain: Float = 0.8
    var padChorus: Float = 0
    var lofiCutoff: Float = 20000
    var bitHold: Int = 1
    var bits: Int = 16
    var wow: Float = 0
    var crackle: Float = 0
}

extension FXSpec {
    static func make(genre: Genre?, mood: Mood, reverb: Float, tempo: Double, rng: SeededRNG) -> FXSpec {
        var g = rng.fork(21)
        let tilt = MoodTilt(mood)
        var base = FXBase()

        if let gn = genre {
            switch gn {
            case .electronic:
                base.room = 0.45; base.damping = 0.35; base.wet = 2.0; base.preDelay = 0.012; base.send = 0.9
                base.echoBeats = [0.75, 0.5, 1.0]; base.echoWeights = [3, 2, 1]; base.feedback = 0.4
                base.padChorus = 0.2
            case .synthpop:
                base.room = 0.5; base.damping = 0.3; base.wet = 2.2; base.preDelay = 0.02; base.send = 1.0
                base.echoBeats = [0.75, 1.0]; base.echoWeights = [2, 1]; base.feedback = 0.35
                base.padChorus = 0.7
            case .pop:
                base.room = 0.4; base.damping = 0.4; base.wet = 1.8; base.preDelay = 0.015; base.send = 0.85
                base.echoBeats = [1.0, 0.75, 0.5, 0]; base.echoWeights = [2, 2, 1, 2]; base.feedback = 0.3
                base.echoGain = 0.6; base.padChorus = 0.3
            case .chillwave:
                base.room = 0.75; base.damping = 0.55; base.wet = 2.4; base.preDelay = 0.03; base.send = 1.2
                base.echoBeats = [0.75, 1.0]; base.echoWeights = [2, 1]; base.feedback = 0.5
                base.echoDamp = 0.5; base.echoGain = 0.9; base.padChorus = 0.9
                base.lofiCutoff = 7800; base.wow = 0.7; base.crackle = 0.0
            case .downtempo:
                base.room = 0.6; base.damping = 0.45; base.wet = 2.2; base.preDelay = 0.02; base.send = 1.0
                base.echoBeats = [1.0, 0.75, 0.667]; base.echoWeights = [2, 2, 1]; base.feedback = 0.4
                base.padChorus = 0.3; base.lofiCutoff = 11000; base.crackle = 0.008
            case .ambient:
                base.room = 0.92; base.damping = 0.5; base.wet = 3.0; base.preDelay = 0.04; base.send = 1.6
                base.echoBeats = [1.0, 1.5]; base.echoWeights = [1, 1]; base.feedback = 0.55
                base.echoGain = 0.7; base.padChorus = 0.6
            case .dreamPop:
                base.room = 0.8; base.damping = 0.45; base.wet = 2.6; base.preDelay = 0.025; base.send = 1.3
                base.echoBeats = [0.75, 1.0]; base.echoWeights = [2, 1]; base.feedback = 0.5
                base.padChorus = 0.8
            case .indietronica:
                base.room = 0.45; base.damping = 0.4; base.wet = 1.8; base.preDelay = 0.012; base.send = 0.9
                base.echoBeats = [0.5, 0.75, 0.667]; base.echoWeights = [2, 2, 1]; base.feedback = 0.35
                base.padChorus = 0.3
            case .lofi:
                base.room = 0.5; base.damping = 0.65; base.wet = 1.8; base.preDelay = 0.01; base.send = 0.9
                base.echoBeats = [0.75, 0.5, 0]; base.echoWeights = [2, 2, 1]; base.feedback = 0.35
                base.echoDamp = 0.6; base.padChorus = 0.4
                base.lofiCutoff = 7200; base.bitHold = 2; base.bits = 13; base.wow = 1.1; base.crackle = 0.03
            case .nuDisco:
                base.room = 0.4; base.damping = 0.4; base.wet = 1.7; base.preDelay = 0.01; base.send = 0.8
                base.echoBeats = [0.75, 0.5]; base.echoWeights = [2, 1]; base.feedback = 0.3
                base.echoGain = 0.6; base.padChorus = 0.5
            case .edm:
                base.room = 0.55; base.damping = 0.3; base.wet = 2.0; base.preDelay = 0.015; base.send = 0.9
                base.echoBeats = [0.75, 1.0, 0.5]; base.echoWeights = [3, 1, 1]; base.feedback = 0.4
                base.padChorus = 0.3
            }
        } else {
            base.room = 0.5
            base.padChorus = 0.3
        }

        var fx = FXSpec()
        // The profile's reverb size already reflects genre and mood; blend it with the genre's own taste.
        let room = 0.35 * base.room + 0.65 * reverb + 0.05 * tilt.soft + jit(&g, -0.06, 0.06)
        fx.room = min(max(room, 0.15), 0.97)
        fx.damping = min(max(base.damping + jit(&g, -0.06, 0.06), 0.1), 0.85)
        fx.wet = base.wet * jit(&g, 0.9, 1.1)
        fx.preDelay = max(0, base.preDelay * jit(&g, 0.7, 1.4))
        fx.sendScale = base.send * jit(&g, 0.9, 1.1)

        let ei = pickIndex(base.echoWeights, count: base.echoBeats.count, &g)
        var eb = base.echoBeats[ei]
        if eb > 0 {
            // Keep the echo time musical at very slow and very fast tempos.
            let seconds = eb * 60.0 / max(tempo, 30.0)
            if seconds > 1.6 { eb *= 0.5 } else if seconds < 0.2 { eb *= 2 }
        }
        fx.echoBeats = eb
        fx.echoFeedback = min(max(base.feedback + jit(&g, -0.06, 0.08) + 0.04 * tilt.soft, 0.15), 0.62)
        fx.echoDamp = base.echoDamp
        fx.echoGain = base.echoGain

        fx.padChorus = min(max(base.padChorus + jit(&g, -0.15, 0.15), 0), 1)

        fx.lofiCutoff = base.lofiCutoff < 15000 ? base.lofiCutoff * jit(&g, 0.85, 1.2) : base.lofiCutoff
        fx.bitHold = base.bitHold
        fx.bits = base.bits
        fx.wow = base.wow > 0 ? base.wow * jit(&g, 0.7, 1.3) : 0
        fx.crackle = base.crackle > 0 ? base.crackle * jit(&g, 0.7, 1.3) : 0
        return fx
    }
}

// MARK: - Mastering

struct MasterSpec {
    /// Average loudness the finished song is raised to (RMS, 0...1).
    var targetRMS: Float = 0.2
    /// Rumble filter in Hz.
    var lowCut: Float = 25
    /// Gain of the high shelf ("air") and where it starts.
    var airAmount: Float = 0.4
    var airFreq: Float = 6000
    /// Extra low end around 160 Hz.
    var warmth: Float = 0.1
    /// 0...1 gentle tape-style saturation.
    var saturation: Float = 0.1
    /// Highest level the soft limiter lets through (always below 0.98).
    var ceiling: Float = 0.96
    /// Stereo width: 1 = as mixed, below 1 narrower, above wider.
    var width: Float = 1.1

    var summary: String {
        "master RMS \(Int(targetRMS * 100))%, width \(Int(width * 100))%, warmth \(Int(warmth * 100))%, tape \(Int(saturation * 100))%"
    }
}

extension MasterSpec {
    static func make(genre: Genre?, mood: Mood, rng: SeededRNG) -> MasterSpec {
        var g = rng.fork(31)
        var m = MasterSpec()
        if let gn = genre {
            switch gn {
            case .electronic: m.targetRMS = 0.21; m.airAmount = 0.4; m.warmth = 0.1; m.saturation = 0.15; m.ceiling = 0.97; m.width = 1.15; m.lowCut = 28
            case .synthpop: m.targetRMS = 0.20; m.airAmount = 0.5; m.warmth = 0.1; m.saturation = 0.12; m.ceiling = 0.97; m.width = 1.15; m.lowCut = 28
            case .pop: m.targetRMS = 0.21; m.airAmount = 0.45; m.warmth = 0.05; m.saturation = 0.08; m.ceiling = 0.97; m.width = 1.1; m.lowCut = 30
            case .chillwave: m.targetRMS = 0.17; m.airAmount = 0.2; m.warmth = 0.25; m.saturation = 0.3; m.ceiling = 0.95; m.width = 1.25; m.lowCut = 25
            case .downtempo: m.targetRMS = 0.18; m.airAmount = 0.25; m.warmth = 0.2; m.saturation = 0.2; m.ceiling = 0.96; m.width = 1.1; m.lowCut = 25
            case .ambient: m.targetRMS = 0.14; m.airAmount = 0.3; m.warmth = 0.1; m.saturation = 0.05; m.ceiling = 0.95; m.width = 1.4; m.lowCut = 22
            case .dreamPop: m.targetRMS = 0.17; m.airAmount = 0.35; m.warmth = 0.15; m.saturation = 0.15; m.ceiling = 0.95; m.width = 1.3; m.lowCut = 25
            case .indietronica: m.targetRMS = 0.19; m.airAmount = 0.4; m.warmth = 0.1; m.saturation = 0.1; m.ceiling = 0.96; m.width = 1.15; m.lowCut = 28
            case .lofi: m.targetRMS = 0.16; m.airAmount = 0.0; m.warmth = 0.35; m.saturation = 0.4; m.ceiling = 0.94; m.width = 0.95; m.lowCut = 40
            case .nuDisco: m.targetRMS = 0.21; m.airAmount = 0.45; m.warmth = 0.15; m.saturation = 0.08; m.ceiling = 0.97; m.width = 1.1; m.lowCut = 30
            case .edm: m.targetRMS = 0.24; m.airAmount = 0.5; m.warmth = 0.05; m.saturation = 0.2; m.ceiling = 0.97; m.width = 1.15; m.lowCut = 32
            }
        }
        switch mood {
        case .energetic, .raw, .uplifting, .epic: m.targetRMS += 0.012
        case .relaxed, .introspective, .melancholic, .sad: m.targetRMS -= 0.012
        default: break
        }
        m.targetRMS = min(max(m.targetRMS * jit(&g, 0.95, 1.05), 0.14), 0.24)
        m.airAmount = max(0, m.airAmount * jit(&g, 0.85, 1.15))
        m.airFreq = jit(&g, 5000, 8000)
        m.warmth = max(0, m.warmth * jit(&g, 0.8, 1.2))
        m.saturation = min(max(m.saturation * jit(&g, 0.8, 1.2), 0), 1)
        m.ceiling = min(max(m.ceiling, 0.9), 0.97)
        m.width = min(max(m.width * jit(&g, 0.95, 1.05), 0.6), 1.5)
        return m
    }
}
