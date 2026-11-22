import Foundation

// MARK: - Voices, hits and risers

/// Every sound the drum machine can play. (The first ten keep their old order.)
enum DrumVoice: Int, CaseIterable {
    case kick, snare, clap, hatClosed, hatOpen, shaker, crash, tomHigh, tomMid, tomLow
    case rim, tambourine, cowbell, congaHigh, congaLow, ride, snap, impact
}

struct DrumHit {
    let beat: Double
    let voice: DrumVoice
    let vel: Float
}

/// The kind of build-up effect played before a chorus.
enum RiserKind: Int, CaseIterable {
    case noiseSweep     // filtered noise rising (a whoosh)
    case pitchSweep     // a rising tone
    case reverseSwell   // a reversed-cymbal style swell
    case downlifter     // a falling sweep that starts on the drop

    var name: String {
        switch self {
        case .noiseSweep: return "noise sweep"
        case .pitchSweep: return "pitch sweep"
        case .reverseSwell: return "reverse swell"
        case .downlifter: return "downlifter"
        }
    }
}

struct Riser {
    let startBeat: Double
    let lengthBeats: Double
    var kind: RiserKind = .noiseSweep
    var gain: Float = 1
}

// MARK: - The sound of a drum kit

/// All the sound-design numbers of one song's drum kit. `make` picks a kit character from the genre,
/// mood and drum style, then nudges every number a little so no two songs share exactly the same drums.
struct DrumKitSpec {
    var character: String = "tight 909"
    /// Overall level of the kit (soft kits are a little quieter).
    var kitGain: Float = 1

    // Kick
    var kickStartHz: Float = 150
    var kickEndHz: Float = 50
    var kickPitchTau: Float = 0.035
    var kickAmpTau: Float = 0.2
    var kickLength: Float = 0.9
    var kickClick: Float = 0.35
    var kickClickHz: Float = 2500
    var kickDrive: Float = 1.25
    /// Extra pure sine underneath (808 style).
    var kickSub: Float = 0
    var kickLevel: Float = 1

    // Snare
    var snareToneHz: Float = 185
    var snareTone2Hz: Float = 330
    var snareToneLevel: Float = 0.55
    var snareToneTau: Float = 0.05
    var snareNoiseTau: Float = 0.1
    var snareNoiseLevel: Float = 0.9
    var snareHP: Float = 1400
    var snareLP: Float = 10000
    var snareDrive: Float = 1.5
    /// 0 = normal tail. Above 0 the noise is cut off after this many seconds (80s gated snare).
    var snareGateTime: Float = 0
    var snareLength: Float = 0.4
    var snareReverb: Float = 0.14
    var snareLevel: Float = 1

    // Clap
    var clapCenterHz: Float = 1500
    var clapQ: Float = 0.9
    var clapGap: Float = 0.011
    var clapBursts: Int = 3
    var clapTailTau: Float = 0.07
    var clapReverb: Float = 0.22

    // Hats and small percussion
    var hatClosedHP: Float = 7000
    var hatClosedTau: Float = 0.03
    var hatOpenHP: Float = 6000
    var hatOpenTau: Float = 0.14
    /// 0...1: how much ringing metallic tone is mixed into the hats.
    var hatMetal: Float = 0
    var shakerBP: Float = 6500
    var shakerTau: Float = 0.03
    var rimHz: Float = 1700
    var rimTau: Float = 0.006
    var tambHP: Float = 6500
    var tambTau: Float = 0.08
    var percLevel: Float = 1

    // Toms and cymbals
    var tomPitch: Float = 1
    var tomTau: Float = 0.18
    var crashHP: Float = 4500
    var crashTau: Float = 0.7

    // Lo-fi treatment of every drum sound (0 / 1 = off)
    var lofiLowpass: Float = 0
    var lofiHold: Int = 1
    var lofiDrive: Float = 0

    /// A short description for the song recipe.
    var summary: String {
        let kickWord: String
        if kickSub >= 0.3 {
            kickWord = "808 sub kick"
        } else if kickAmpTau <= 0.17 {
            kickWord = "tight kick"
        } else if kickAmpTau >= 0.27 {
            kickWord = "long kick"
        } else {
            kickWord = "round kick"
        }
        let snareWord: String
        if snareGateTime > 0 {
            snareWord = "gated snare"
        } else if snareLP < 6000 {
            snareWord = "soft snare"
        } else if snareToneLevel >= 0.65 {
            snareWord = "big snare"
        } else {
            snareWord = "snappy snare"
        }
        let hatWord: String
        if hatMetal >= 0.6 {
            hatWord = "metal hats"
        } else if hatClosedHP >= 8000 {
            hatWord = "bright hats"
        } else if hatClosedHP <= 5800 {
            hatWord = "dark hats"
        } else {
            hatWord = "hats"
        }
        let crunch = lofiLowpass > 0 ? ", lo-fi crunch" : ""
        return "kit: \(character) (\(kickWord), \(snareWord), \(hatWord)\(crunch))"
    }
}

enum KitCharacter: Int, CaseIterable {
    case tight909, deep808, punchyElectro, softThump, dustyLofi, disco, gated80s, ambientSoft, epicBig

    var title: String {
        switch self {
        case .tight909: return "tight 909"
        case .deep808: return "deep 808"
        case .punchyElectro: return "punchy electro"
        case .softThump: return "soft thump"
        case .dustyLofi: return "dusty lo-fi"
        case .disco: return "disco"
        case .gated80s: return "gated 80s"
        case .ambientSoft: return "ambient soft"
        case .epicBig: return "epic big"
        }
    }
}

extension DrumKitSpec {
    static func make(genre: Genre?, mood: Mood, style: DrumStyle, rng: SeededRNG) -> DrumKitSpec {
        var pick = rng.fork(1)
        let kind = chooseCharacter(genre: genre, mood: mood, style: style, g: &pick)
        var s = baseSpec(kind)

        // Nudge every number a little, so two songs with the same kit character still differ.
        var j = rng.fork(2)
        s.kickStartHz *= jit(&j, 0.92, 1.10)
        s.kickEndHz *= jit(&j, 0.92, 1.12)
        s.kickPitchTau *= jit(&j, 0.85, 1.2)
        s.kickAmpTau *= jit(&j, 0.88, 1.18)
        s.snareToneHz *= jit(&j, 0.9, 1.12)
        s.snareTone2Hz *= jit(&j, 0.92, 1.1)
        s.snareNoiseTau *= jit(&j, 0.85, 1.2)
        s.snareLP *= jit(&j, 0.85, 1.1)
        s.hatClosedHP *= jit(&j, 0.88, 1.1)
        s.hatClosedTau *= jit(&j, 0.85, 1.25)
        s.hatOpenTau *= jit(&j, 0.85, 1.25)
        s.clapCenterHz *= jit(&j, 0.9, 1.15)
        s.rimHz *= jit(&j, 0.9, 1.15)
        s.tomPitch *= jit(&j, 0.92, 1.1)
        // The kick must ring out long enough that the end of the sample is silent.
        s.kickLength = min(2.2, max(s.kickLength, s.kickAmpTau * 4.5))
        return s
    }

    private static func jit(_ g: inout SeededRNG, _ lo: Float, _ hi: Float) -> Float {
        lo + (hi - lo) * g.float()
    }

    private static func chooseCharacter(genre: Genre?, mood: Mood, style: DrumStyle, g: inout SeededRNG) -> KitCharacter {
        var w: [(KitCharacter, Double)]
        switch style {
        case .fourOnFloor: w = [(.tight909, 5), (.punchyElectro, 3), (.deep808, 2), (.disco, 1)]
        case .disco: w = [(.disco, 6), (.tight909, 2), (.punchyElectro, 1)]
        case .halfTime: w = [(.deep808, 4), (.dustyLofi, 3), (.softThump, 2), (.punchyElectro, 1.5)]
        case .boomBap: w = [(.dustyLofi, 6), (.deep808, 2.5), (.softThump, 1.5)]
        case .backbeat: w = [(.punchyElectro, 3), (.softThump, 2.5), (.tight909, 2), (.disco, 0.7), (.dustyLofi, 0.7)]
        case .gated80s: w = [(.gated80s, 7), (.punchyElectro, 2)]
        case .breakbeat: w = [(.punchyElectro, 4), (.tight909, 2.5), (.deep808, 2), (.dustyLofi, 1.5)]
        case .dreamy: w = [(.softThump, 5), (.ambientSoft, 2), (.dustyLofi, 1.5)]
        case .epic: w = [(.epicBig, 8), (.punchyElectro, 1)]
        case .minimal: w = [(.ambientSoft, 6), (.softThump, 2)]
        }
        w = w.map { ($0.0, $0.1 * genreFactor(genre, $0.0) * moodFactor(mood, $0.0)) }
        return g.pickWeighted(w)
    }

    private static func genreFactor(_ genre: Genre?, _ c: KitCharacter) -> Double {
        guard let genre = genre else { return 1 }
        switch genre {
        case .lofi:
            switch c {
            case .dustyLofi: return 6
            case .softThump, .deep808: return 1.5
            default: return 0.4
            }
        case .chillwave:
            switch c {
            case .softThump: return 3
            case .dustyLofi: return 1.5
            case .deep808: return 1
            default: return 0.5
            }
        case .downtempo:
            switch c {
            case .deep808: return 2.5
            case .dustyLofi, .softThump: return 1.5
            default: return 0.6
            }
        case .ambient:
            switch c {
            case .ambientSoft: return 5
            case .softThump: return 2
            default: return 0.2
            }
        case .dreamPop:
            switch c {
            case .softThump: return 4
            case .ambientSoft: return 1.5
            case .dustyLofi: return 1
            default: return 0.4
            }
        case .synthpop:
            switch c {
            case .gated80s: return 4
            case .punchyElectro: return 1.5
            case .disco: return 1
            default: return 0.6
            }
        case .pop:
            switch c {
            case .punchyElectro: return 2
            case .softThump, .tight909: return 1.5
            default: return 0.8
            }
        case .nuDisco:
            switch c {
            case .disco: return 5
            case .tight909: return 1.5
            case .punchyElectro: return 1
            default: return 0.3
            }
        case .edm:
            switch c {
            case .tight909, .punchyElectro: return 3
            default: return 0.4
            }
        case .electronic:
            switch c {
            case .tight909, .punchyElectro: return 2
            case .deep808: return 1.5
            default: return 0.6
            }
        case .indietronica:
            switch c {
            case .dustyLofi, .punchyElectro, .softThump: return 1.5
            case .deep808, .tight909: return 1
            default: return 0.6
            }
        }
    }

    private static func moodFactor(_ mood: Mood, _ c: KitCharacter) -> Double {
        switch mood {
        case .dark, .raw, .energetic:
            switch c {
            case .tight909, .punchyElectro, .deep808, .epicBig: return 1.5
            case .softThump, .ambientSoft: return 0.6
            default: return 1
            }
        case .epic:
            return c == .epicBig ? 2 : 1
        case .relaxed, .introspective, .melancholic, .romantic, .chill, .dreamy, .sad:
            switch c {
            case .softThump, .dustyLofi, .ambientSoft: return 1.5
            case .punchyElectro, .tight909: return 0.7
            default: return 1
            }
        case .uplifting, .happy:
            switch c {
            case .tight909, .punchyElectro, .disco: return 1.2
            default: return 1
            }
        }
    }

    private static func baseSpec(_ kind: KitCharacter) -> DrumKitSpec {
        var s = DrumKitSpec()
        s.character = kind.title
        switch kind {
        case .tight909:
            s.kickStartHz = 165; s.kickEndHz = 52; s.kickPitchTau = 0.03; s.kickAmpTau = 0.17
            s.kickClick = 0.45; s.kickDrive = 1.3
            s.snareToneHz = 190; s.snareTone2Hz = 340; s.snareNoiseTau = 0.1; s.snareLP = 11000
            s.hatClosedHP = 7500; s.hatClosedTau = 0.028; s.hatOpenHP = 6500; s.hatOpenTau = 0.16
            s.hatMetal = 0.25
        case .deep808:
            s.kickStartHz = 120; s.kickEndHz = 42; s.kickPitchTau = 0.05; s.kickAmpTau = 0.34
            s.kickLength = 1.3; s.kickClick = 0.12; s.kickDrive = 1.6; s.kickSub = 0.35
            s.snareToneHz = 175; s.snareTone2Hz = 260; s.snareToneTau = 0.07; s.snareNoiseTau = 0.12
            s.snareLP = 8000; s.clapGap = 0.012
            s.hatClosedHP = 7500; s.hatClosedTau = 0.035; s.hatMetal = 0.8
            s.hatOpenHP = 6800; s.hatOpenTau = 0.2
        case .punchyElectro:
            s.kickStartHz = 200; s.kickEndHz = 55; s.kickPitchTau = 0.04; s.kickAmpTau = 0.2
            s.kickClick = 0.5; s.kickDrive = 2.0
            s.snareToneHz = 210; s.snareTone2Hz = 360; s.snareNoiseTau = 0.09; s.snareHP = 1800
            s.snareLP = 12000; s.snareDrive = 1.8
            s.clapBursts = 4; s.clapGap = 0.009; s.clapCenterHz = 1800
            s.hatClosedHP = 8000; s.hatClosedTau = 0.025; s.hatOpenTau = 0.12
        case .softThump:
            s.kickStartHz = 110; s.kickEndHz = 48; s.kickPitchTau = 0.045; s.kickAmpTau = 0.24
            s.kickClick = 0.08; s.kickDrive = 1.0; s.kickSub = 0.1
            s.snareToneHz = 170; s.snareTone2Hz = 280; s.snareToneLevel = 0.4; s.snareToneTau = 0.06
            s.snareNoiseTau = 0.14; s.snareLP = 5500; s.snareHP = 1000; s.snareReverb = 0.25
            s.clapCenterHz = 1200; s.clapBursts = 2; s.clapReverb = 0.35
            s.hatClosedHP = 5500; s.hatClosedTau = 0.05; s.hatOpenHP = 5000; s.hatOpenTau = 0.25
            s.kitGain = 0.9
        case .dustyLofi:
            s.kickStartHz = 105; s.kickEndHz = 52; s.kickPitchTau = 0.04; s.kickAmpTau = 0.2
            s.kickClick = 0.05; s.kickDrive = 1.4
            s.snareToneHz = 180; s.snareTone2Hz = 300; s.snareToneLevel = 0.5; s.snareNoiseTau = 0.12
            s.snareLP = 5000; s.snareReverb = 0.1
            s.hatClosedHP = 6000; s.hatClosedTau = 0.04; s.hatOpenHP = 5500
            s.lofiLowpass = 6500; s.lofiHold = 3; s.lofiDrive = 1.6
            s.kitGain = 0.85
        case .disco:
            s.kickStartHz = 140; s.kickEndHz = 55; s.kickPitchTau = 0.03; s.kickAmpTau = 0.15
            s.kickClick = 0.5; s.kickDrive = 1.3
            s.snareToneHz = 200; s.snareTone2Hz = 350; s.snareNoiseTau = 0.12
            s.clapTailTau = 0.09; s.clapCenterHz = 1600
            s.hatClosedHP = 8500; s.hatClosedTau = 0.03; s.hatOpenHP = 7000; s.hatOpenTau = 0.2
            s.hatMetal = 0.2; s.tambTau = 0.1
        case .gated80s:
            s.kickStartHz = 150; s.kickEndHz = 55; s.kickPitchTau = 0.035; s.kickAmpTau = 0.2
            s.kickClick = 0.3; s.kickDrive = 1.5
            s.snareToneHz = 200; s.snareTone2Hz = 330; s.snareToneLevel = 0.5; s.snareHP = 900
            s.snareLP = 9000; s.snareNoiseLevel = 1.2; s.snareGateTime = 0.17; s.snareDrive = 1.8
            s.snareLength = 0.3; s.snareReverb = 0.3
            s.clapCenterHz = 1300; s.clapReverb = 0.3
            s.tomPitch = 1.1; s.tomTau = 0.22
        case .ambientSoft:
            s.kickStartHz = 90; s.kickEndHz = 45; s.kickPitchTau = 0.06; s.kickAmpTau = 0.3
            s.kickClick = 0; s.kickDrive = 1.0; s.kickSub = 0.15
            s.snareToneLevel = 0.35; s.snareLP = 4500; s.snareNoiseTau = 0.16; s.snareReverb = 0.3
            s.hatClosedHP = 5000; s.hatClosedTau = 0.06; s.hatOpenHP = 4500; s.hatOpenTau = 0.3
            s.kitGain = 0.7
        case .epicBig:
            s.kickStartHz = 180; s.kickEndHz = 40; s.kickPitchTau = 0.05; s.kickAmpTau = 0.3
            s.kickClick = 0.3; s.kickDrive = 2.0; s.kickSub = 0.25
            s.snareToneLevel = 0.7; s.snareNoiseTau = 0.18; s.snareReverb = 0.3
            s.tomPitch = 0.9; s.tomTau = 0.28; s.crashTau = 1.0
        }
        return s
    }
}

// MARK: - Drum sounds (synthesized once per song, then copied wherever they are needed)

enum DrumSynth {
    private static let twoPi: Float = 2 * Float.pi

    static func fadeTail(_ a: inout [Float], frames: Int = 300) {
        let n = a.count
        guard n > frames else { return }
        for i in 0..<frames {
            a[n - 1 - i] *= Float(i) / Float(frames)
        }
    }

    static func normalize(_ a: inout [Float], peak: Float) {
        var m: Float = 0
        for x in a { m = max(m, abs(x)) }
        if m > 1e-6 {
            let gain = peak / m
            for i in 0..<a.count { a[i] *= gain }
        }
    }

    /// Optional dusty treatment: crunch, sample-rate reduction and a dark filter.
    static func lofi(_ a: inout [Float], spec: DrumKitSpec, sr: Float) {
        if spec.lofiDrive > 0 {
            for i in 0..<a.count { a[i] = softClip(a[i] * (1 + spec.lofiDrive)) }
        }
        if spec.lofiHold > 1 {
            var held: Float = 0
            for i in 0..<a.count {
                if i % spec.lofiHold == 0 { held = a[i] }
                a[i] = held
            }
        }
        if spec.lofiLowpass > 0 {
            var lp = SVF(cutoff: spec.lofiLowpass, q: 0.7, sr: sr)
            for i in 0..<a.count { a[i] = lp.lowpass(a[i]) }
        }
    }

    /// Lo-fi treatment, a clean tail, and a fixed peak level (so every kit has the same headroom).
    private static func finish(_ a: inout [Float], sr: Float, spec: DrumKitSpec, peak: Float,
                               tail: Int = 300, applyLofi: Bool = true) {
        if applyLofi { lofi(&a, spec: spec, sr: sr) }
        fadeTail(&a, frames: tail)
        normalize(&a, peak: peak)
    }

    static func kick(sr: Float, spec: DrumKitSpec, variant: Int) -> [Float] {
        let len = max(64, Int(sr * spec.kickLength))
        var out = [Float](repeating: 0, count: len)
        var phase: Float = 0
        var subPhase: Float = 0
        var noise = Noise(seed: UInt32(7 + variant * 29))
        var hp = SVF(cutoff: spec.kickClickHz, q: 0.7, sr: sr)
        let startHz = spec.kickStartHz * (1 + 0.04 * Float(variant))
        for n in 0..<len {
            let t = Float(n) / sr
            let f = spec.kickEndHz + (startHz - spec.kickEndHz) * exp(-t / spec.kickPitchTau)
            phase += f / sr
            if phase >= 1 { phase -= 1 }
            let env = exp(-t / spec.kickAmpTau) * min(1, t / 0.0015)
            var s = sin(twoPi * phase) * env
            if spec.kickSub > 0 {
                subPhase += spec.kickEndHz / sr
                if subPhase >= 1 { subPhase -= 1 }
                let subEnv = exp(-t / (spec.kickAmpTau * 1.4)) * min(1, t / 0.004)
                s += sin(twoPi * subPhase) * subEnv * spec.kickSub
            }
            let click = hp.highpass(noise.next()) * exp(-t / 0.003) * spec.kickClick
            out[n] = softClip((s + click) * spec.kickDrive)
        }
        finish(&out, sr: sr, spec: spec, peak: 0.95, tail: 600)
        return out
    }

    static func snare(sr: Float, spec: DrumKitSpec, variant: Int) -> [Float] {
        // Long enough that the noise tail has died away before the sample ends (no tick at the end).
        let len = max(64, Int(sr * max(spec.snareLength, spec.snareNoiseTau * 4.5)))
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: UInt32(101 + variant * 17))
        var hp = SVF(cutoff: spec.snareHP, q: 0.7, sr: sr)
        var lp = SVF(cutoff: spec.snareLP, q: 0.7, sr: sr)
        for n in 0..<len {
            let t = Float(n) / sr
            let tone1 = sin(twoPi * spec.snareToneHz * t) * exp(-t / spec.snareToneTau)
            let tone2 = sin(twoPi * spec.snareTone2Hz * t) * exp(-t / (spec.snareToneTau * 0.6))
            let tone = (tone1 + tone2 * 0.36) * spec.snareToneLevel
            var nenv: Float
            if spec.snareGateTime > 0 {
                if t < spec.snareGateTime {
                    nenv = 0.75 + 0.25 * exp(-t / 0.04)
                } else {
                    nenv = max(0, 1 - (t - spec.snareGateTime) / 0.012) * 0.75
                }
            } else {
                nenv = exp(-t / spec.snareNoiseTau)
            }
            let nz = lp.lowpass(hp.highpass(noise.next())) * nenv * spec.snareNoiseLevel
            out[n] = softClip((tone + nz) * spec.snareDrive)
        }
        finish(&out, sr: sr, spec: spec, peak: 0.85)
        return out
    }

    static func clap(sr: Float, spec: DrumKitSpec, variant: Int) -> [Float] {
        let len = Int(sr * 0.4)
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: UInt32(211 + variant * 31))
        var bp = SVF(cutoff: spec.clapCenterHz, q: spec.clapQ, sr: sr)
        let bursts = max(1, min(spec.clapBursts, 6))
        let gap = spec.clapGap
        let tailStart = Float(bursts) * gap
        for n in 0..<len {
            let t = Float(n) / sr
            var env: Float = 0
            for b in 0..<bursts {
                let bt = Float(b) * gap
                if t >= bt { env += exp(-(t - bt) / 0.003) }
            }
            if t >= tailStart { env += exp(-(t - tailStart) / spec.clapTailTau) }
            out[n] = bp.bandpass(noise.next()) * env * 0.9
        }
        finish(&out, sr: sr, spec: spec, peak: 0.8)
        return out
    }

    static func hat(sr: Float, spec: DrumKitSpec, open: Bool, variant: Int) -> [Float] {
        let tau = open ? spec.hatOpenTau : spec.hatClosedTau
        // Long enough that the tail has died away before the sample ends (no tick at the end).
        let len = Int(sr * max(open ? 0.8 : 0.16, min(0.9, tau * 4.5)))
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: UInt32(307 + variant * 13 + (open ? 5 : 0)))
        var hp = SVF(cutoff: open ? spec.hatOpenHP : spec.hatClosedHP, q: 0.8, sr: sr)
        var hpMetal = SVF(cutoff: 6000, q: 0.8, sr: sr)
        let ratios: [Float] = [2.0, 3.0, 4.16, 5.43, 6.79, 8.21]
        let baseHz: Float = 330 * (1 + 0.03 * Float(variant))
        var phases = [Float](repeating: 0, count: 6)
        for n in 0..<len {
            let t = Float(n) / sr
            var metal: Float = 0
            if spec.hatMetal > 0 {
                var m: Float = 0
                for k in 0..<6 {
                    phases[k] += baseHz * ratios[k] / sr
                    if phases[k] >= 1 { phases[k] -= 1 }
                    let sq: Float = phases[k] < 0.5 ? 1 : -1
                    m += sq
                }
                metal = hpMetal.highpass(m / 6)
            }
            let nz = hp.highpass(noise.next())
            let mixed = nz * (1 - 0.5 * spec.hatMetal) + metal * spec.hatMetal * 0.9
            out[n] = mixed * exp(-t / tau) * 0.8
        }
        finish(&out, sr: sr, spec: spec, peak: 0.8, tail: 200)
        return out
    }

    static func shaker(sr: Float, spec: DrumKitSpec, variant: Int) -> [Float] {
        let len = Int(sr * 0.14)
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: UInt32(401 + variant * 7))
        var bp = SVF(cutoff: spec.shakerBP, q: 1.2, sr: sr)
        for n in 0..<len {
            let t = Float(n) / sr
            let env = min(1, t / 0.008) * exp(-t / spec.shakerTau)
            out[n] = bp.bandpass(noise.next()) * env
        }
        finish(&out, sr: sr, spec: spec, peak: 0.7, tail: 200)
        return out
    }

    static func rim(sr: Float, spec: DrumKitSpec, variant: Int) -> [Float] {
        let len = Int(sr * 0.14)
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: UInt32(451 + variant * 19))
        var bp = SVF(cutoff: 3500, q: 1.0, sr: sr)
        let hz = spec.rimHz * (1 + 0.06 * Float(variant))
        for n in 0..<len {
            let t = Float(n) / sr
            let body = sin(twoPi * hz * 0.28 * t) * exp(-t / 0.012) * 0.6
            let ping = sin(twoPi * hz * t) * exp(-t / spec.rimTau) * 0.8
            let click = bp.bandpass(noise.next()) * exp(-t / 0.002) * 0.5
            out[n] = softClip((body + ping + click) * 1.4)
        }
        finish(&out, sr: sr, spec: spec, peak: 0.85, tail: 200)
        return out
    }

    static func tambourine(sr: Float, spec: DrumKitSpec, variant: Int) -> [Float] {
        let len = Int(sr * 0.4)
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: UInt32(503 + variant * 11))
        var hp = SVF(cutoff: spec.tambHP, q: 0.9, sr: sr)
        let jingleHz: Float = 5200 * (1 + 0.05 * Float(variant))
        for n in 0..<len {
            let t = Float(n) / sr
            var env = exp(-t / 0.012)
            if t >= 0.016 { env += 0.8 * exp(-(t - 0.016) / spec.tambTau) }
            let j1 = sin(twoPi * jingleHz * t)
            let j2 = sin(twoPi * jingleHz * 1.42 * t)
            let tone = (j1 + 0.7 * j2) * exp(-t / 0.04) * 0.08
            let hiss = hp.highpass(noise.next()) * env * 0.8
            out[n] = hiss + tone
        }
        finish(&out, sr: sr, spec: spec, peak: 0.7, tail: 300)
        return out
    }

    static func cowbell(sr: Float, spec: DrumKitSpec) -> [Float] {
        let len = Int(sr * 0.4)
        var out = [Float](repeating: 0, count: len)
        var p1: Float = 0
        var p2: Float = 0
        var bp = SVF(cutoff: 800, q: 1.5, sr: sr)
        for n in 0..<len {
            let t = Float(n) / sr
            p1 += 540 / sr
            if p1 >= 1 { p1 -= 1 }
            p2 += 800 / sr
            if p2 >= 1 { p2 -= 1 }
            let sq1: Float = p1 < 0.5 ? 1 : -1
            let sq2: Float = p2 < 0.5 ? 1 : -1
            let fast = 0.6 * exp(-t / 0.02)
            let slow = 0.4 * exp(-t / 0.12)
            let env = min(1, t / 0.001) * (fast + slow)
            out[n] = bp.bandpass((sq1 + sq2) * 0.5) * env
        }
        finish(&out, sr: sr, spec: spec, peak: 0.7, tail: 300)
        return out
    }

    static func conga(sr: Float, spec: DrumKitSpec, freq: Float) -> [Float] {
        let len = Int(sr * 0.35)
        var out = [Float](repeating: 0, count: len)
        var phase: Float = 0
        var noise = Noise(seed: UInt32(601 + Int(freq)))
        var bp = SVF(cutoff: 1800, q: 1.2, sr: sr)
        for n in 0..<len {
            let t = Float(n) / sr
            let f = freq * (1 + 0.28 * exp(-t / 0.02))
            phase += f / sr
            if phase >= 1 { phase -= 1 }
            let body = sin(twoPi * phase) * exp(-t / 0.11)
            let slap = bp.bandpass(noise.next()) * exp(-t / 0.008) * 0.4
            out[n] = softClip((body + slap) * 1.2)
        }
        finish(&out, sr: sr, spec: spec, peak: 0.8, tail: 300)
        return out
    }

    static func ride(sr: Float, spec: DrumKitSpec) -> [Float] {
        let len = Int(sr * 1.2)
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: 701)
        var hp = SVF(cutoff: 7500, q: 0.8, sr: sr)
        var hpMetal = SVF(cutoff: 6000, q: 0.8, sr: sr)
        let ratios: [Float] = [2.0, 3.0, 4.16, 5.43, 6.79, 8.21]
        var phases = [Float](repeating: 0, count: 6)
        for n in 0..<len {
            let t = Float(n) / sr
            var m: Float = 0
            for k in 0..<6 {
                phases[k] += 360 * ratios[k] / sr
                if phases[k] >= 1 { phases[k] -= 1 }
                let sq: Float = phases[k] < 0.5 ? 1 : -1
                m += sq
            }
            let metal = hpMetal.highpass(m / 6)
            let nz = hp.highpass(noise.next())
            let bell = sin(twoPi * 3100 * t) * exp(-t / 0.15) * 0.15
            let env = exp(-t / 0.45)
            out[n] = (nz * 0.35 + metal * 0.7) * env + bell
        }
        finish(&out, sr: sr, spec: spec, peak: 0.7, tail: 600)
        return out
    }

    static func snap(sr: Float, spec: DrumKitSpec, variant: Int) -> [Float] {
        let len = Int(sr * 0.16)
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: UInt32(801 + variant * 23))
        var bp = SVF(cutoff: 1900 + 150 * Float(variant), q: 2.0, sr: sr)
        for n in 0..<len {
            let t = Float(n) / sr
            var env = exp(-t / 0.012)
            if t >= 0.02 { env += 0.5 * exp(-(t - 0.02) / 0.02) }
            let tone = sin(twoPi * 1400 * t) * exp(-t / 0.006) * 0.5
            out[n] = bp.bandpass(noise.next()) * env + tone
        }
        finish(&out, sr: sr, spec: spec, peak: 0.8, tail: 200)
        return out
    }

    static func crash(sr: Float, spec: DrumKitSpec) -> [Float] {
        let seconds = min(3.2, spec.crashTau * 3.6 + 0.3)
        let len = Int(sr * seconds)
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: 977)
        var hp = SVF(cutoff: spec.crashHP, q: 0.7, sr: sr)
        for n in 0..<len {
            let t = Float(n) / sr
            out[n] = hp.highpass(noise.next()) * exp(-t / spec.crashTau) * min(1, t / 0.002) * 0.7
        }
        finish(&out, sr: sr, spec: spec, peak: 0.8, tail: 800)
        return out
    }

    static func tom(sr: Float, spec: DrumKitSpec, freq: Float) -> [Float] {
        let len = Int(sr * (spec.tomTau * 3.2 + 0.1))
        var out = [Float](repeating: 0, count: len)
        var phase: Float = 0
        let base = freq * spec.tomPitch
        for n in 0..<len {
            let t = Float(n) / sr
            let f = base + base * 0.6 * exp(-t / 0.06)
            phase += f / sr
            if phase >= 1 { phase -= 1 }
            let body = softClip(sin(twoPi * phase) * exp(-t / spec.tomTau) * 1.4)
            out[n] = body * 0.85 * min(1, t / 0.001)
        }
        finish(&out, sr: sr, spec: spec, peak: 0.9, tail: 400)
        return out
    }

    /// A deep boom for the first beat of a drop.
    static func impact(sr: Float, spec: DrumKitSpec) -> [Float] {
        let len = Int(sr * 2.4)
        var out = [Float](repeating: 0, count: len)
        var phase: Float = 0
        var noise = Noise(seed: 1301)
        var lp = SVF(cutoff: 500, q: 0.7, sr: sr)
        for n in 0..<len {
            let t = Float(n) / sr
            let f = 35 + 45 * exp(-t / 0.25)
            phase += f / sr
            if phase >= 1 { phase -= 1 }
            let boom = sin(twoPi * phase) * exp(-t / 0.9)
            let air = lp.lowpass(noise.next()) * exp(-t / 0.5) * 0.4
            out[n] = softClip((boom + air) * 1.5)
        }
        finish(&out, sr: sr, spec: spec, peak: 0.95, tail: 2000, applyLofi: false)
        return out
    }
}

// MARK: - The groove library

/// One bar of drums as 16 steps per voice (0 = silent, otherwise the strength 0...1).
fileprivate struct DrumGroove {
    var kick: [Float] = GrooveLibrary.zero
    var snare: [Float] = GrooveLibrary.zero
    var clap: [Float] = GrooveLibrary.zero
    var hat: [Float] = GrooveLibrary.zero
    var open: [Float] = GrooveLibrary.zero
    var shaker: [Float] = GrooveLibrary.zero
    var rim: [Float] = GrooveLibrary.zero
    var tamb: [Float] = GrooveLibrary.zero
    var perc: [Float] = GrooveLibrary.zero
    var percVoice: DrumVoice = .congaHigh
    /// Steps where very soft snare ghost notes may appear.
    var ghosts: [Int] = []
    var ghostChance: Double = 0
    /// Steps where an extra soft kick may appear.
    var pickups: [Int] = []
    var pickupChance: Double = 0
}

fileprivate enum GrooveLibrary {
    static let zero: [Float] = [Float](repeating: 0, count: 16)
    static let evens: [Int] = [0, 2, 4, 6, 8, 10, 12, 14]
    static let odds: [Int] = [1, 3, 5, 7, 9, 11, 13, 15]
    static let offbeats: [Int] = [2, 6, 10, 14]
    static let backbeats: [Int] = [4, 12]
    static let quarters: [Int] = [0, 4, 8, 12]

    // MARK: pattern helpers

    /// A pattern with `vel` on each listed step.
    static func steps(_ list: [Int], _ vel: Float) -> [Float] {
        var a = zero
        for s in list where s >= 0 && s < 16 { a[s] = vel }
        return a
    }

    /// A pattern from (step, strength) pairs.
    static func stepsV(_ list: [(Int, Float)]) -> [Float] {
        var a = zero
        for item in list where item.0 >= 0 && item.0 < 16 { a[item.0] = item.1 }
        return a
    }

    /// Repeats a short accent cycle over all 16 steps.
    static func cycle(_ accents: [Float]) -> [Float] {
        var a = zero
        if accents.isEmpty { return a }
        for s in 0..<16 { a[s] = accents[s % accents.count] }
        return a
    }

    static func maxMerge(_ a: [Float], _ b: [Float]) -> [Float] {
        var out = a
        for i in 0..<min(a.count, b.count) { out[i] = max(a[i], b[i]) }
        return out
    }

    static func isEmpty(_ a: [Float]) -> Bool {
        for x in a where x > 0 { return false }
        return true
    }

    // MARK: style facts

    static func lazyOffset(_ style: DrumStyle) -> Double {
        switch style {
        case .boomBap: return 0.012
        case .dreamy: return 0.008
        case .halfTime: return 0.006
        default: return 0
        }
    }

    static func crashVelocity(_ style: DrumStyle) -> Float {
        switch style {
        case .fourOnFloor, .disco, .backbeat, .gated80s, .breakbeat, .epic: return 0.9
        case .halfTime: return 0.6
        case .dreamy, .boomBap, .minimal: return 0
        }
    }

    static func fillFactor(_ style: DrumStyle) -> Double {
        switch style {
        case .minimal: return 0
        case .dreamy: return 0.35
        case .boomBap: return 0.7
        case .halfTime: return 0.8
        default: return 1
        }
    }

    static func allowsOpenVariation(_ style: DrumStyle) -> Bool {
        switch style {
        case .backbeat, .boomBap, .halfTime, .gated80s, .breakbeat: return true
        default: return false
        }
    }

    static func riserKind(_ style: DrumStyle, _ g: inout SeededRNG) -> RiserKind {
        let w: [(RiserKind, Double)]
        switch style {
        case .fourOnFloor, .disco, .breakbeat, .epic:
            w = [(.noiseSweep, 4), (.pitchSweep, 2.5), (.reverseSwell, 2), (.downlifter, 1.5)]
        case .halfTime, .boomBap, .backbeat, .gated80s:
            w = [(.reverseSwell, 4), (.noiseSweep, 3), (.pitchSweep, 2), (.downlifter, 1)]
        case .dreamy, .minimal:
            w = [(.reverseSwell, 7), (.downlifter, 3)]
        }
        return g.pickWeighted(w)
    }

    // MARK: section shaping

    static func shapeIntro(_ p: inout DrumGroove, mode: Int, style: DrumStyle) {
        let floorStyle = style == .fourOnFloor || style == .disco || style == .epic
        switch mode {
        case 0:
            // hats and shaker only
            p.kick = zero; p.snare = zero; p.clap = zero; p.open = zero
        case 1:
            if floorStyle {
                // just the kick
                for s in 0..<16 { p.kick[s] *= 0.8 }
                p.snare = zero; p.clap = zero; p.open = zero; p.hat = zero
            } else {
                p.kick = zero; p.snare = zero; p.clap = zero; p.open = zero
            }
        default:
            // small percussion only
            p.kick = zero; p.snare = zero; p.clap = zero; p.open = zero; p.hat = zero
        }
        let nothing = isEmpty(p.kick) && isEmpty(p.snare) && isEmpty(p.hat) && isEmpty(p.shaker)
            && isEmpty(p.rim) && isEmpty(p.tamb) && isEmpty(p.perc)
        if nothing { p.hat = steps(quarters, 0.25) }
    }

    static func shapeBreakdown(_ p: inout DrumGroove) {
        p.kick = zero; p.snare = zero; p.clap = zero; p.open = zero; p.hat = zero
        if isEmpty(p.shaker) && isEmpty(p.rim) && isEmpty(p.tamb) && isEmpty(p.perc) {
            p.shaker = steps(offbeats, 0.14)
        }
    }

    /// The chorus gets a little extra weight.
    static func thicken(_ p: inout DrumGroove, style: DrumStyle, density: Float) {
        switch style {
        case .fourOnFloor, .disco:
            if isEmpty(p.open) { p.open = steps(offbeats, 0.5) }
            if density > 0.75 { p.shaker = maxMerge(p.shaker, cycle([0.2, 0.12, 0.16, 0.12])) }
        case .backbeat, .gated80s:
            p.clap = maxMerge(p.clap, steps(backbeats, 0.55))
            if density > 0.7 { p.hat = maxMerge(p.hat, steps(odds, 0.2)) }
        case .breakbeat:
            if density > 0.7 { p.open = maxMerge(p.open, steps([6, 14], 0.35)) }
        case .epic:
            p.clap = maxMerge(p.clap, steps(backbeats, 0.7))
        default:
            break
        }
    }

    // MARK: the grooves

    static func groove(_ style: DrumStyle, _ variant: Int) -> DrumGroove {
        let v = ((variant % 8) + 8) % 8
        switch style {
        case .fourOnFloor: return fourOnFloor(v)
        case .disco: return disco(v)
        case .halfTime: return halfTime(v)
        case .boomBap: return boomBap(v)
        case .backbeat: return backbeat(v)
        case .gated80s: return gated80s(v)
        case .breakbeat: return breakbeat(v)
        case .dreamy: return dreamy(v % 6)
        case .epic: return epic(v % 6)
        case .minimal: return minimal(v % 6)
        }
    }

    /// House, techno, electro and trance: a kick on every beat.
    static func fourOnFloor(_ v: Int) -> DrumGroove {
        var d = DrumGroove()
        d.kick = steps(quarters, 1)
        switch v {
        case 0: // classic house
            d.clap = steps(backbeats, 0.9)
            d.snare = steps(backbeats, 0.3)
            d.open = steps(offbeats, 0.5)
            d.hat = steps(odds, 0.26)
            d.shaker = cycle([0.2, 0.12, 0.16, 0.12])
            d.pickups = [14]; d.pickupChance = 0.2
        case 1: // techno: hard 16th hats, rim and conga
            d.clap = steps([12], 0.5)
            d.rim = steps([3, 7, 11, 15], 0.35)
            d.hat = cycle([0.34, 0.14, 0.26, 0.14])
            d.open = steps(offbeats, 0.38)
            d.perc = steps([5, 10, 13], 0.4)
            d.percVoice = .congaHigh
        case 2: // electro house with kick pickups
            d.clap = steps(backbeats, 0.95)
            d.hat = steps(evens, 0.3)
            d.open = steps(offbeats, 0.55)
            d.shaker = steps(Array(0..<16), 0.12)
            d.pickups = [11, 14, 15]; d.pickupChance = 0.35
        case 3: // big room: heavy clap and snare layer
            d.clap = steps(backbeats, 1.0)
            d.snare = steps(backbeats, 0.6)
            d.open = steps(offbeats, 0.6)
            d.hat = steps(quarters, 0.3)
        case 4: // tech house: rim, cowbell and shuffled hats
            d.rim = steps([3, 6, 11, 14], 0.4)
            d.clap = steps(backbeats, 0.6)
            d.hat = stepsV([(1, 0.25), (3, 0.18), (5, 0.25), (7, 0.18), (9, 0.25), (11, 0.18), (13, 0.25), (15, 0.3)])
            d.open = steps([2, 10], 0.45)
            d.perc = steps([3, 7, 11], 0.35)
            d.percVoice = .cowbell
        case 5: // french house: light and bouncy
            d.clap = steps(backbeats, 0.85)
            d.open = steps(offbeats, 0.4)
            d.hat = steps([3, 7, 11, 15], 0.3)
            d.shaker = cycle([0.18, 0.1, 0.14, 0.1])
            d.pickups = [15]; d.pickupChance = 0.15
        case 6: // minimal house: soft kick, rim, tiny hats, congas
            d.kick = steps(quarters, 0.9)
            d.rim = steps(backbeats, 0.5)
            d.hat = steps(offbeats, 0.3)
            d.shaker = steps([1, 5, 9, 13], 0.14)
            d.perc = steps([3, 10, 13], 0.35)
            d.percVoice = .congaLow
        default: // trance: strong offbeat hats and a steady clap
            d.clap = steps(backbeats, 0.8)
            d.open = steps(offbeats, 0.7)
            d.hat = steps(odds, 0.22)
        }
        return d
    }

    /// Nu-disco: the floor kick with offbeat open hats, busy 16th hats and handclaps.
    static func disco(_ v: Int) -> DrumGroove {
        var d = DrumGroove()
        d.kick = steps(quarters, 1)
        d.clap = steps(backbeats, 0.9)
        d.open = steps(offbeats, 0.65)
        d.hat = cycle([0.4, 0.2, 0.3, 0.2])
        switch v {
        case 0: // classic disco
            d.snare = steps(backbeats, 0.5)
            d.tamb = steps(offbeats, 0.3)
        case 1: // funk disco with ghost notes
            d.hat = cycle([0.42, 0.18, 0.3, 0.18])
            d.ghosts = [7, 9, 15]; d.ghostChance = 0.35
            d.perc = steps([3, 11], 0.35)
            d.percVoice = .congaHigh
        case 2: // nu-disco house
            d.hat = steps([3, 7, 11, 15], 0.3)
            d.open = steps(offbeats, 0.55)
            d.shaker = cycle([0.2, 0.12, 0.16, 0.12])
            d.perc = steps([6, 14], 0.3)
            d.percVoice = .cowbell
        case 3: // philly: hard snare, eighth hats
            d.snare = steps(backbeats, 1.0)
            d.clap = steps(backbeats, 0.5)
            d.hat = steps(evens, 0.4)
            d.open = steps([14], 0.5)
            d.tamb = cycle([0.28, 0.14, 0.2, 0.14])
        case 4: // boogie: kick pickups and congas
            d.pickups = [10, 15]; d.pickupChance = 0.4
            d.perc = steps([3, 6, 11, 14], 0.4)
            d.percVoice = .congaHigh
        case 5: // french touch
            d.hat = steps(evens, 0.32)
            d.open = steps(offbeats, 0.6)
            d.tamb = steps(backbeats, 0.35)
        case 6: // italo: snare and clap together, rim ticks
            d.snare = steps(backbeats, 0.8)
            d.clap = steps(backbeats, 0.6)
            d.rim = steps([7, 15], 0.4)
            d.hat = cycle([0.36, 0.16, 0.26, 0.16])
            d.open = steps([2, 10], 0.5)
        default: // sparse disco
            d.clap = steps(backbeats, 0.8)
            d.open = steps(offbeats, 0.5)
            d.hat = steps(quarters, 0.25)
            d.shaker = cycle([0.2, 0.12, 0.16, 0.12])
        }
        return d
    }

    /// Trip-hop and downtempo: kick on 1, snare on 3, space and ghost notes.
    static func halfTime(_ v: Int) -> DrumGroove {
        var d = DrumGroove()
        d.snare = steps([8], 1.0)
        switch v {
        case 0: // trip-hop
            d.kick = stepsV([(0, 1), (10, 0.85)])
            d.clap = steps([8], 0.5)
            d.hat = stepsV([(0, 0.45), (2, 0.3), (4, 0.4), (6, 0.3), (8, 0.45), (10, 0.3), (12, 0.4), (14, 0.3),
                            (3, 0.12), (7, 0.12), (11, 0.12), (15, 0.12)])
            d.shaker = steps(offbeats, 0.12)
            d.pickups = [3, 7, 13]; d.pickupChance = 0.45
            d.ghosts = [15]; d.ghostChance = 0.3
        case 1: // downtempo roll
            d.kick = stepsV([(0, 1), (7, 0.7), (10, 0.85)])
            d.hat = cycle([0.36, 0.14, 0.26, 0.14])
            d.open = steps([14], 0.3)
            d.ghosts = [3, 15]; d.ghostChance = 0.3
        case 2: // dub: rim and snare layer, offbeat hats
            d.kick = stepsV([(0, 1), (6, 0.6), (10, 0.8)])
            d.rim = steps([8], 0.9)
            d.snare = steps([8], 0.6)
            d.hat = steps(offbeats, 0.25)
            d.perc = steps(backbeats, 0.3)
            d.percVoice = .congaLow
        case 3: // heavy
            d.kick = stepsV([(0, 1), (3, 0.6), (10, 0.9)])
            d.clap = steps([8], 0.6)
            d.open = steps([14], 0.45)
            d.hat = steps(evens, 0.3)
        case 4: // broken
            d.kick = stepsV([(0, 1), (5, 0.7), (10, 0.85), (13, 0.6)])
            d.ghosts = [3, 11, 14]; d.ghostChance = 0.4
            d.hat = stepsV([(0, 0.4), (3, 0.25), (6, 0.35), (9, 0.25), (12, 0.4), (15, 0.25)])
        case 5: // minimal
            d.kick = stepsV([(0, 0.9), (10, 0.7)])
            d.snare = zero
            d.rim = steps([8], 0.7)
            d.shaker = steps(evens, 0.12)
            d.hat = steps(backbeats, 0.15)
        case 6: // rolling
            d.kick = stepsV([(0, 1), (6, 0.7), (10, 0.85), (14, 0.5)])
            d.hat = cycle([0.4, 0.16, 0.28, 0.16])
            d.shaker = steps(odds, 0.12)
        default: // jazzy: brushed snare and a ride
            d.kick = stepsV([(0, 0.9), (9, 0.5)])
            d.snare = steps([8], 0.7)
            d.rim = steps([8], 0.4)
            d.hat = steps(evens, 0.28)
            d.perc = steps([0, 4, 6, 8, 12, 14], 0.35)
            d.percVoice = .ride
        }
        return d
    }

    /// Lo-fi hip-hop: lazy, swung kicks and snares on 2 and 4.
    static func boomBap(_ v: Int) -> DrumGroove {
        var d = DrumGroove()
        d.snare = steps(backbeats, 1.0)
        switch v {
        case 0: // classic
            d.kick = stepsV([(0, 1), (7, 0.8), (10, 0.9)])
            d.hat = cycle([0.35, 0.12, 0.28, 0.12])
        case 1:
            d.kick = stepsV([(0, 1), (3, 0.6), (10, 0.9)])
            d.hat = cycle([0.3, 0.1, 0.22, 0.1])
            d.ghosts = [15]; d.ghostChance = 0.3
        case 2:
            d.kick = stepsV([(0, 1), (6, 0.7), (10, 0.9), (13, 0.55)])
            d.open = steps([14], 0.35)
            d.hat = steps(evens, 0.3)
        case 3: // lo-fi hop
            d.kick = stepsV([(0, 0.95), (8, 0.7), (11, 0.8)])
            d.snare = steps(backbeats, 0.9)
            d.rim = steps([15], 0.35)
            d.hat = steps(offbeats, 0.28)
        case 4: // dusty with finger snaps
            d.kick = steps([0, 10], 1.0)
            d.snare = steps(backbeats, 0.9)
            d.perc = steps(backbeats, 0.5)
            d.percVoice = .snap
            d.hat = stepsV([(0, 0.3), (2, 0.2), (4, 0.3), (6, 0.22), (8, 0.3), (10, 0.2), (12, 0.3), (14, 0.25)])
        case 5: // sparse
            d.kick = stepsV([(0, 1), (7, 0.8)])
            d.snare = steps([12], 1.0)
            d.rim = steps([4], 0.5)
            d.hat = steps([2, 10], 0.25)
        case 6: // busy
            d.kick = stepsV([(0, 1), (3, 0.6), (6, 0.7), (10, 0.9)])
            d.ghosts = [7, 9]; d.ghostChance = 0.4
            d.hat = cycle([0.32, 0.12, 0.24, 0.12])
        default: // shuffle
            d.kick = stepsV([(0, 1), (7, 0.8), (10, 0.85)])
            d.hat = steps(evens, 0.3)
            d.shaker = steps(odds, 0.18)
        }
        return d
    }

    /// Pop and indie: kick on 1 and 3 with pickups, snare and clap on 2 and 4.
    static func backbeat(_ v: Int) -> DrumGroove {
        var d = DrumGroove()
        d.snare = steps(backbeats, 0.9)
        switch v {
        case 0: // pop
            d.kick = stepsV([(0, 1), (8, 0.9)])
            d.clap = steps(backbeats, 0.45)
            d.hat = steps(evens, 0.34)
            d.pickups = [10]; d.pickupChance = 0.5
        case 1: // indie
            d.kick = stepsV([(0, 1), (6, 0.7), (8, 0.9)])
            d.snare = steps(backbeats, 1.0)
            d.hat = steps(evens, 0.28)
            d.tamb = steps(backbeats, 0.3)
        case 2: // dance-pop
            d.kick = stepsV([(0, 1), (7, 0.7), (8, 0.9), (15, 0.45)])
            d.clap = steps(backbeats, 0.55)
            d.hat = steps(offbeats, 0.34)
            d.shaker = cycle([0.14, 0.1, 0.16, 0.1])
        case 3: // rock-ish 16th hats
            d.kick = stepsV([(0, 1), (8, 0.9), (10, 0.8)])
            d.hat = cycle([0.38, 0.14, 0.26, 0.14])
        case 4: // kick pickups and open hats
            d.kick = stepsV([(0, 1), (5, 0.6), (8, 0.9), (13, 0.6)])
            d.open = steps([6, 14], 0.35)
            d.hat = steps(evens, 0.3)
            d.ghosts = [9, 15]; d.ghostChance = 0.3
        case 5: // clap-led
            d.kick = stepsV([(0, 1), (8, 0.9)])
            d.clap = steps(backbeats, 1.0)
            d.snare = steps(backbeats, 0.4)
            d.shaker = cycle([0.2, 0.12, 0.16, 0.12])
            d.hat = steps(offbeats, 0.3)
        case 6: // indie shuffle
            d.kick = stepsV([(0, 1), (6, 0.7), (8, 0.9), (11, 0.6)])
            d.ghosts = [9]; d.ghostChance = 0.35
            d.hat = steps(evens, 0.3)
            d.rim = steps([14], 0.3)
        default: // sparse pop
            d.kick = stepsV([(0, 1), (10, 0.8)])
            d.hat = steps(quarters, 0.3)
            d.tamb = steps(offbeats, 0.2)
        }
        return d
    }

    /// 80s synthpop: huge gated snare, eighth hats.
    static func gated80s(_ v: Int) -> DrumGroove {
        var d = DrumGroove()
        d.snare = steps(backbeats, 1.0)
        switch v {
        case 0: // classic
            d.kick = stepsV([(0, 1), (6, 0.6), (8, 0.9), (10, 0.7)])
            d.clap = steps(backbeats, 0.7)
            d.hat = steps(evens, 0.34)
        case 1: // drum-machine groove with cowbell
            d.kick = stepsV([(0, 1), (3, 0.6), (8, 0.9), (11, 0.6)])
            d.hat = cycle([0.3, 0.14, 0.22, 0.14])
            d.perc = steps([2, 10], 0.3)
            d.percVoice = .cowbell
        case 2: // dance pulse
            d.kick = steps(quarters, 0.85)
            d.clap = steps(backbeats, 0.6)
            d.hat = steps(offbeats, 0.34)
        case 3: // ballad
            d.kick = stepsV([(0, 1), (8, 0.8)])
            d.snare = stepsV([(4, 0.5), (12, 1.0)])
            d.hat = steps(quarters, 0.28)
            d.tamb = steps(backbeats, 0.3)
        case 4: // electro-pop
            d.kick = stepsV([(0, 1), (6, 0.7), (8, 0.9), (14, 0.6)])
            d.clap = steps(backbeats, 0.6)
            d.open = steps([6, 14], 0.35)
            d.hat = steps(evens, 0.3)
        case 5: // driving
            d.kick = stepsV([(0, 1), (2, 0.6), (8, 0.9), (10, 0.7)])
            d.hat = cycle([0.34, 0.14, 0.24, 0.14])
        case 6: // sparse
            d.kick = stepsV([(0, 1), (8, 0.85)])
            d.hat = steps(offbeats, 0.3)
            d.perc = steps([7, 15], 0.3)
            d.percVoice = .cowbell
        default: // syncopated
            d.kick = stepsV([(0, 1), (3, 0.6), (6, 0.7), (8, 0.9), (11, 0.6)])
            d.hat = steps(evens, 0.3)
            d.ghosts = [15]; d.ghostChance = 0.3
        }
        return d
    }

    /// Broken beats: syncopated kicks, busy snares.
    static func breakbeat(_ v: Int) -> DrumGroove {
        var d = DrumGroove()
        d.snare = steps(backbeats, 1.0)
        switch v {
        case 0: // classic break
            d.kick = stepsV([(0, 1), (6, 0.8), (10, 0.9)])
            d.clap = steps(backbeats, 0.4)
            d.hat = cycle([0.5, 0.22, 0.35, 0.22])
            d.open = steps([6, 14], 0.4)
            d.ghosts = [7, 9, 15]; d.ghostChance = 0.4
            d.pickups = [3, 13]; d.pickupChance = 0.3
        case 1: // amen-style
            d.kick = stepsV([(0, 1), (2, 0.8), (10, 0.9), (11, 0.6)])
            d.snare = stepsV([(4, 1), (7, 0.4), (9, 0.4), (12, 1), (15, 0.35)])
            d.hat = steps(evens, 0.35)
        case 2: // broken beat
            d.kick = stepsV([(0, 1), (3, 0.7), (10, 0.9)])
            d.snare = stepsV([(4, 1), (13, 0.8)])
            d.hat = cycle([0.4, 0.18, 0.3, 0.18])
            d.open = steps([6], 0.35)
            d.perc = steps([7, 15], 0.35)
            d.percVoice = .congaHigh
        case 3: // techno break
            d.kick = stepsV([(0, 1), (6, 0.8), (8, 0.9), (14, 0.65)])
            d.clap = steps([12], 0.5)
            d.hat = cycle([0.34, 0.14, 0.26, 0.14])
        case 4: // funky drummer
            d.kick = stepsV([(0, 1), (7, 0.8), (10, 0.9)])
            d.ghosts = [1, 6, 9, 14]; d.ghostChance = 0.35
            d.hat = cycle([0.36, 0.16, 0.26, 0.16])
        case 5: // electro
            d.kick = stepsV([(0, 1), (3, 0.8), (10, 0.9)])
            d.snare = steps(backbeats, 0.8)
            d.clap = steps(backbeats, 0.7)
            d.open = steps([6], 0.4)
            d.perc = steps([2, 10], 0.3)
            d.percVoice = .cowbell
        case 6: // jungle
            d.kick = stepsV([(0, 1), (3, 0.7), (10, 0.9), (11, 0.55)])
            d.snare = stepsV([(4, 1), (7, 0.5), (12, 1), (14, 0.5)])
            d.hat = steps(evens, 0.3)
            d.shaker = steps(odds, 0.12)
        default: // idm
            d.kick = stepsV([(0, 1), (5, 0.7), (10, 0.85), (13, 0.6)])
            d.snare = stepsV([(4, 0.9), (11, 0.7)])
            d.rim = steps([7, 14], 0.4)
            d.hat = steps([1, 3, 6, 9, 12, 14], 0.3)
        }
        return d
    }

    /// Dream pop and chillwave: soft kick, rim, shaker and tambourine.
    static func dreamy(_ v: Int) -> DrumGroove {
        var d = DrumGroove()
        switch v {
        case 0:
            d.kick = stepsV([(0, 0.85), (8, 0.7)])
            d.rim = steps(backbeats, 0.5)
            d.shaker = steps(evens, 0.12)
            d.tamb = steps(backbeats, 0.3)
        case 1:
            d.kick = stepsV([(0, 0.85), (10, 0.65)])
            d.snare = steps(backbeats, 0.5)
            d.clap = steps(backbeats, 0.25)
            d.hat = steps(evens, 0.18)
        case 2:
            d.kick = stepsV([(0, 0.85), (6, 0.5), (8, 0.7)])
            d.rim = steps([12], 0.5)
            d.shaker = cycle([0.14, 0.08, 0.12, 0.08])
            d.open = steps([14], 0.3)
        case 3:
            d.kick = stepsV([(0, 0.8), (8, 0.65)])
            d.snare = steps([12], 0.6)
            d.tamb = steps(offbeats, 0.25)
            d.shaker = steps(evens, 0.1)
        case 4:
            d.kick = stepsV([(0, 0.85), (7, 0.5), (10, 0.65)])
            d.rim = steps([4], 0.45)
            d.ghosts = [14]; d.ghostChance = 0.3
            d.hat = steps(offbeats, 0.18)
        default:
            d.kick = steps([0], 0.8)
            d.shaker = steps(quarters, 0.12)
            d.rim = steps([8], 0.4)
            d.tamb = steps([12], 0.2)
        }
        return d
    }

    /// Big drums and toms.
    static func epic(_ v: Int) -> DrumGroove {
        var d = DrumGroove()
        d.snare = steps(backbeats, 1.0)
        switch v {
        case 0:
            d.kick = stepsV([(0, 1), (8, 0.9)])
            d.clap = steps(backbeats, 0.7)
            d.hat = steps(evens, 0.18)
            d.pickups = [11]; d.pickupChance = 0.5
        case 1:
            d.kick = stepsV([(0, 1), (3, 0.6), (8, 0.9), (11, 0.6)])
            d.clap = steps(backbeats, 0.6)
            d.hat = steps(evens, 0.18)
        case 2:
            d.kick = stepsV([(0, 1), (2, 0.6), (8, 0.9), (10, 0.7)])
            d.clap = steps([12], 0.7)
            d.open = steps([14], 0.4)
        case 3: // marching snare
            d.kick = stepsV([(0, 1), (8, 0.9)])
            d.snare = stepsV([(2, 0.35), (4, 1), (6, 0.35), (10, 0.35), (12, 1), (14, 0.5)])
            d.hat = steps(evens, 0.15)
        case 4: // floor toms
            d.kick = stepsV([(0, 1), (8, 0.9)])
            d.snare = steps([12], 1.0)
            d.perc = stepsV([(4, 0.8), (6, 0.6)])
            d.percVoice = .tomLow
            d.hat = steps(evens, 0.15)
        default: // cinematic pulse
            d.kick = stepsV([(0, 1), (6, 0.8), (8, 0.9), (14, 0.7)])
            d.clap = steps([12], 0.6)
            d.shaker = cycle([0.2, 0.12, 0.16, 0.12])
        }
        return d
    }

    /// Ambient: a very soft, sparse pulse.
    static func minimal(_ v: Int) -> DrumGroove {
        var d = DrumGroove()
        switch v {
        case 0:
            d.kick = steps([0], 0.5)
            d.shaker = steps([10], 0.1)
        case 1:
            d.kick = steps([0, 10], 0.4)
            d.hat = steps(backbeats, 0.1)
        case 2:
            d.kick = steps([8], 0.45)
            d.shaker = steps(offbeats, 0.08)
        case 3:
            d.rim = steps([4], 0.2)
            d.kick = steps([0], 0.5)
        case 4:
            d.kick = steps([0, 6], 0.4)
            d.tamb = steps([12], 0.12)
        default:
            d.shaker = steps(evens, 0.07)
            d.kick = steps([0], 0.35)
        }
        return d
    }
}

// MARK: - Writing the drum part

extension SongPlan {
    func drumHits() -> (hits: [DrumHit], risers: [Riser]) {
        guard settings.instruments.contains(.drums) else { return ([], []) }
        var g = rng.fork(300)
        var hits: [DrumHit] = []
        var risers: [Riser] = []
        let style = profile.drumStyle
        let intensity = Float(settings.intensity)
        let density = profile.density
        let scale: Float = 0.7 + 0.3 * intensity
        let calm = intensity < 0.4 || density < 0.4
        let h = profile.humanize

        // The verse groove, and sometimes a different variant of the same style in the chorus.
        let grooveVerse = GrooveLibrary.groove(style, profile.grooveVariant)
        var grooveChorus = grooveVerse
        if g.chance(0.3) {
            grooveChorus = GrooveLibrary.groove(style, profile.grooveVariant + 1 + g.int(0...5))
        }
        // Song-level choices.
        let introMode = g.int(0...2)
        let buildMode = g.int(0...2)
        let riserKind = GrooveLibrary.riserKind(style, &g)
        let riserGain: Float = (style == .minimal || style == .dreamy) ? 0.6 : 1
        let lazyDelay = GrooveLibrary.lazyOffset(style)
        let crashVel = GrooveLibrary.crashVelocity(style)
        let genre = profile.genre
        let bigGenre = genre == .edm || genre == .electronic
        let impactOK = style == .epic || (bigGenre && (style == .fourOnFloor || style == .breakbeat))

        for sec in sections {
            let startLevel = level(.drums, bar: sec.startBar)
            if sec.kind == .chorus && startLevel > 0 {
                if crashVel > 0 {
                    hits.append(DrumHit(beat: Double(sec.startBar * 4), voice: .crash, vel: crashVel * min(1, startLevel)))
                }
                if impactOK && g.chance(0.6) {
                    hits.append(DrumHit(beat: Double(sec.startBar * 4), voice: .impact, vel: 0.9))
                }
            }
            if sec.preDrop && style != .minimal {
                if riserKind == .downlifter {
                    // The downlifter falls away from the first beat of the chorus.
                    risers.append(Riser(startBeat: Double(sec.endBar * 4), lengthBeats: 4, kind: .downlifter, gain: riserGain))
                } else {
                    let beats = Double(min(sec.bars, 2) * 4)
                    risers.append(Riser(startBeat: Double(sec.endBar * 4) - beats, lengthBeats: beats,
                                        kind: riserKind, gain: riserGain))
                }
            }

            for b in 0..<sec.bars {
                let bar = sec.startBar + b
                let lvl = level(.drums, bar: bar)
                if lvl <= 0 { continue }
                if sec.kind == .outro && b >= sec.bars / 2 { continue }
                // Ambient drums only come and go.
                if style == .minimal && b % 2 == 1 && g.chance(0.6) { continue }

                let barInPhrase = b % 4
                let phraseEnd = barInPhrase == 3
                let fade: Float = sec.kind == .outro
                    ? max(0, 1 - Float(b) / Float(max(1, sec.bars / 2)))
                    : 1

                // Writing helpers for this bar.
                func addHit(_ step: Int, _ voice: DrumVoice, _ vel: Float, _ offset: Double = 0) {
                    let v = min(vel * scale * lvl * fade, 1)
                    hits.append(DrumHit(beat: stepBeat(bar, step) + offset, voice: voice, vel: v))
                }
                func emit(_ pat: [Float], _ voice: DrumVoice, jitter: Double, lazyBy: Double) {
                    for s in 0..<16 where pat[s] > 0 {
                        let j: Double = jitter == 0 ? 0 : (Double(g.float()) - 0.5) * 2 * jitter
                        let v = pat[s] * scale * lvl * fade * (0.92 + 0.08 * g.float())
                        hits.append(DrumHit(beat: stepBeat(bar, s) + j + lazyBy, voice: voice, vel: min(v, 1)))
                    }
                }

                // 1. Start from the groove and shape it for this part of the song.
                var p: DrumGroove = sec.kind == .chorus ? grooveChorus : grooveVerse
                switch sec.kind {
                case .intro:
                    GrooveLibrary.shapeIntro(&p, mode: introMode, style: style)
                case .verse:
                    p.clap = GrooveLibrary.zero
                    if style != .halfTime && style != .fourOnFloor && style != .disco {
                        p.open = GrooveLibrary.zero
                    }
                case .breakdown:
                    GrooveLibrary.shapeBreakdown(&p)
                case .chorus:
                    GrooveLibrary.thicken(&p, style: style, density: density)
                case .outro:
                    p.clap = GrooveLibrary.zero
                    if style != .halfTime && style != .disco { p.open = GrooveLibrary.zero }
                }
                if calm {
                    // Calmer: fewer hats and no shaker.
                    // (Thin out by count, not by position: some grooves keep their hats only on off-beats.)
                    var hatsSeen = 0
                    for s in 0..<16 where p.hat[s] > 0 {
                        if hatsSeen % 2 == 1 { p.hat[s] = 0 }
                        hatsSeen += 1
                    }
                    p.shaker = GrooveLibrary.zero
                    if density < 0.25 {
                        p.open = GrooveLibrary.zero
                        p.ghosts = []
                    }
                }

                // 2. Small changes from bar to bar, so no bar repeats forever.
                if sec.kind != .intro && !p.pickups.isEmpty && g.chance(p.pickupChance * Double(0.5 + density)) {
                    let s = p.pickups[g.int(0...(p.pickups.count - 1))]
                    if p.kick[s] == 0 { p.kick[s] = 0.55 + 0.15 * g.float() }
                }
                if sec.kind != .intro && !p.ghosts.isEmpty && !calm {
                    for s in p.ghosts {
                        if g.chance(p.ghostChance) && p.snare[s] == 0 {
                            p.snare[s] = 0.16 + 0.1 * g.float()
                        }
                    }
                }
                if barInPhrase == 1 && sec.kind != .intro && GrooveLibrary.allowsOpenVariation(style) && g.chance(0.3) {
                    let s = g.chance(0.5) ? 6 : 14
                    if p.open[s] == 0 { p.open[s] = 0.38 }
                }
                if phraseEnd && sec.kind != .intro && (style == .fourOnFloor || style == .disco) && g.chance(0.2) {
                    p.kick[12] = 0
                }

                // 3. The build-up bar before a chorus.
                let rollBar = sec.preDrop && b == sec.bars - 1
                if rollBar {
                    switch style {
                    case .dreamy, .minimal, .boomBap:
                        for s in 8..<16 { p.shaker[s] = max(p.shaker[s], 0.1 + 0.05 * Float(s - 8)) }
                        p.rim[14] = max(p.rim[14], 0.5)
                        p.rim[15] = max(p.rim[15], 0.6)
                    case .epic:
                        for s in 8..<16 { p.snare[s] = 0; p.hat[s] = 0; p.open[s] = 0; p.clap[s] = 0 }
                        for s in 12..<16 { p.kick[s] = 0 }
                        let roll: [(Int, DrumVoice, Float)] = [
                            (8, .tomLow, 0.7), (10, .tomLow, 0.8), (12, .tomMid, 0.85),
                            (13, .tomMid, 0.9), (14, .tomHigh, 0.95), (15, .tomHigh, 1.0)
                        ]
                        for (s, voice, v) in roll { addHit(s, voice, v) }
                    default:
                        switch buildMode {
                        case 0:
                            // snare roll
                            for s in 12..<16 { p.kick[s] = 0 }
                            for s in 8..<16 {
                                p.snare[s] = 0.3 + 0.7 * Float(s - 8) / 7
                                p.hat[s] = 0
                                p.open[s] = 0
                            }
                        case 1:
                            // the kick drops out and claps roll
                            for s in 1..<16 { p.kick[s] = 0 }
                            for s in 8..<16 { p.hat[s] = 0; p.open[s] = 0 }
                            for s in [8, 10, 12, 13, 14, 15] { p.clap[s] = 0.35 + 0.1 * Float(s - 8) }
                        default:
                            // a gap right before the drop
                            for s in 12..<16 {
                                p.kick[s] = 0; p.snare[s] = 0; p.clap[s] = 0
                                p.hat[s] = 0; p.open[s] = 0; p.shaker[s] = 0
                            }
                            p.snare[10] = max(p.snare[10], 0.7)
                            p.snare[11] = max(p.snare[11], 0.8)
                        }
                    }
                }

                // 4. A small fill at the end of some phrases.
                if phraseEnd && !rollBar && sec.kind != .intro && sec.kind != .breakdown {
                    let fillChance = Double(0.3 + 0.5 * intensity) * GrooveLibrary.fillFactor(style)
                    if g.chance(fillChance) {
                        switch style {
                        case .epic, .gated80s:
                            let seqs: [[(Int, DrumVoice, Float)]] = [
                                [(12, .tomHigh, 0.8), (13, .tomMid, 0.85), (14, .tomLow, 0.9), (15, .tomLow, 1.0)],
                                [(12, .snare, 0.7), (13, .tomHigh, 0.8), (14, .tomMid, 0.9), (15, .tomLow, 1.0)],
                                [(8, .tomMid, 0.7), (10, .tomMid, 0.8), (12, .tomHigh, 0.85),
                                 (13, .tomHigh, 0.9), (14, .tomMid, 0.95), (15, .tomLow, 1.0)]
                            ]
                            let seq = seqs[g.int(0...2)]
                            var first = 16
                            for (s, _, _) in seq { first = min(first, s) }
                            for s in first..<16 { p.snare[s] = 0; p.hat[s] = 0; p.open[s] = 0; p.clap[s] = 0 }
                            for (s, voice, v) in seq { addHit(s, voice, v) }
                        case .backbeat, .boomBap, .halfTime:
                            switch g.int(0...3) {
                            case 0:
                                p.snare[14] = max(p.snare[14], 0.5)
                                p.snare[15] = max(p.snare[15], 0.7)
                            case 1:
                                for s in 12..<16 {
                                    p.snare[s] = max(p.snare[s], 0.35 + 0.15 * Float(s - 12))
                                    p.hat[s] = 0
                                }
                            case 2:
                                // a flam: a quiet grace note just before the backbeat
                                let flamStep = style == .halfTime ? 8 : 12
                                addHit(flamStep, .snare, 0.35, -0.05)
                            default:
                                p.kick[10] = max(p.kick[10], 0.7)
                                p.snare[13] = max(p.snare[13], 0.45)
                                p.snare[15] = max(p.snare[15], 0.7)
                            }
                        case .fourOnFloor, .disco:
                            switch g.int(0...2) {
                            case 0:
                                for s in 12..<16 { p.hat[s] = max(p.hat[s], 0.2 + 0.12 * Float(s - 12)) }
                                p.open[14] = max(p.open[14], 0.5)
                            case 1:
                                for s in 12..<16 { p.snare[s] = max(p.snare[s], 0.3 + 0.2 * Float(s - 12)) }
                            default:
                                p.clap[14] = max(p.clap[14], 0.6)
                                p.clap[15] = max(p.clap[15], 0.8)
                            }
                        case .breakbeat:
                            p.snare[11] = max(p.snare[11], 0.5)
                            p.snare[13] = max(p.snare[13], 0.6)
                            p.snare[14] = max(p.snare[14], 0.7)
                            p.snare[15] = max(p.snare[15], 0.85)
                            p.kick[12] = max(p.kick[12], 0.7)
                        case .dreamy:
                            for s in 12..<16 { p.shaker[s] = max(p.shaker[s], 0.1 + 0.05 * Float(s - 12)) }
                            p.tamb[14] = max(p.tamb[14], 0.3)
                        case .minimal:
                            break
                        }
                    }
                }

                // 5. Write the notes. Kicks stay on the grid; small percussion wobbles a little;
                //    lazy styles drag the snare a few milliseconds behind the beat.
                let snareJitter: Double = lazyDelay > 0 ? h * 0.5 : 0
                emit(p.kick, .kick, jitter: 0, lazyBy: 0)
                emit(p.snare, .snare, jitter: snareJitter, lazyBy: lazyDelay)
                emit(p.clap, .clap, jitter: h * 0.5, lazyBy: lazyDelay * 0.5)
                emit(p.rim, .rim, jitter: h * 0.5, lazyBy: lazyDelay)
                emit(p.hat, .hatClosed, jitter: h, lazyBy: 0)
                emit(p.open, .hatOpen, jitter: h * 0.6, lazyBy: 0)
                emit(p.shaker, .shaker, jitter: h, lazyBy: 0)
                emit(p.tamb, .tambourine, jitter: h, lazyBy: 0)
                emit(p.perc, p.percVoice, jitter: h, lazyBy: 0)
            }
        }
        return (hits, risers)
    }
}

// MARK: - Rendering drums

/// The drum sounds of one song, rendered once and shared by every hit.
private struct KitSamples {
    /// Indexed by `DrumVoice.rawValue`; each entry holds a few variants of that sound.
    var table: [[[Float]]]

    init(sr: Float, spec: DrumKitSpec, used: [Bool]) {
        var t: [[[Float]]] = []
        for voice in DrumVoice.allCases {
            if used[voice.rawValue] {
                t.append(KitSamples.variants(voice, sr: sr, spec: spec))
            } else {
                t.append([])
            }
        }
        table = t
    }

    static func variants(_ voice: DrumVoice, sr: Float, spec: DrumKitSpec) -> [[Float]] {
        switch voice {
        case .kick:
            return [DrumSynth.kick(sr: sr, spec: spec, variant: 0), DrumSynth.kick(sr: sr, spec: spec, variant: 1)]
        case .snare:
            return (0..<3).map { DrumSynth.snare(sr: sr, spec: spec, variant: $0) }
        case .clap:
            return (0..<2).map { DrumSynth.clap(sr: sr, spec: spec, variant: $0) }
        case .hatClosed:
            return (0..<3).map { DrumSynth.hat(sr: sr, spec: spec, open: false, variant: $0) }
        case .hatOpen:
            return (0..<2).map { DrumSynth.hat(sr: sr, spec: spec, open: true, variant: $0) }
        case .shaker:
            return (0..<2).map { DrumSynth.shaker(sr: sr, spec: spec, variant: $0) }
        case .crash:
            return [DrumSynth.crash(sr: sr, spec: spec)]
        case .tomHigh:
            return [DrumSynth.tom(sr: sr, spec: spec, freq: 170)]
        case .tomMid:
            return [DrumSynth.tom(sr: sr, spec: spec, freq: 125)]
        case .tomLow:
            return [DrumSynth.tom(sr: sr, spec: spec, freq: 88)]
        case .rim:
            return (0..<2).map { DrumSynth.rim(sr: sr, spec: spec, variant: $0) }
        case .tambourine:
            return (0..<2).map { DrumSynth.tambourine(sr: sr, spec: spec, variant: $0) }
        case .cowbell:
            return [DrumSynth.cowbell(sr: sr, spec: spec)]
        case .congaHigh:
            return [DrumSynth.conga(sr: sr, spec: spec, freq: 330)]
        case .congaLow:
            return [DrumSynth.conga(sr: sr, spec: spec, freq: 220)]
        case .ride:
            return [DrumSynth.ride(sr: sr, spec: spec)]
        case .snap:
            return (0..<2).map { DrumSynth.snap(sr: sr, spec: spec, variant: $0) }
        case .impact:
            return [DrumSynth.impact(sr: sr, spec: spec)]
        }
    }
}

enum DrumRenderer {
    /// Renders all drum hits into the bus. Returns the frames at which a kick drum plays
    /// (the other instruments "duck" around these).
    static func render(plan: SongPlan, ctx: RenderContext, hits: [DrumHit], risers: [Riser]) -> [Int] {
        let sr = ctx.sr
        let spec = plan.profile.kit

        var used = [Bool](repeating: false, count: DrumVoice.allCases.count)
        for hit in hits { used[hit.voice.rawValue] = true }
        let kit = KitSamples(sr: sr, spec: spec, used: used)

        var kickFrames: [Int] = []
        var counters = [Int](repeating: 0, count: DrumVoice.allCases.count)

        for hit in hits {
            let frame = ctx.frame(beat: hit.beat)
            if frame < 0 || frame >= ctx.frames { continue }
            let voiceIndex = hit.voice.rawValue
            let variants = kit.table[voiceIndex]
            if variants.isEmpty { continue }
            let idx = counters[voiceIndex]
            counters[voiceIndex] += 1
            let sample = variants[idx % variants.count]
            let vel = min(max(hit.vel, 0), 1)
            let mix = mixFor(hit.voice, vel: vel, idx: idx, spec: spec)
            if hit.voice == .kick { kickFrames.append(frame) }
            let n = min(sample.count, ctx.frames - frame)
            sample.withUnsafeBufferPointer { sp in
                for k in 0..<n {
                    ctx.bus.add(frame + k, sp[k], mix, 1)
                }
            }
        }

        for riser in risers {
            renderRiser(ctx: ctx, riser: riser)
        }
        return kickFrames
    }

    /// Level, stereo position and reverb send of each drum sound.
    private static func mixFor(_ voice: DrumVoice, vel: Float, idx: Int, spec: DrumKitSpec) -> Mix {
        let kg = spec.kitGain
        let pl = spec.percLevel
        switch voice {
        case .kick:
            return Mix(gain: 0.85 * vel * spec.kickLevel * kg)
        case .snare:
            return Mix(gain: 0.65 * vel * spec.snareLevel * kg, pan: 0, reverb: spec.snareReverb)
        case .clap:
            return Mix(gain: 0.5 * vel * spec.snareLevel * kg, pan: 0.05, reverb: spec.clapReverb)
        case .hatClosed:
            return Mix(gain: 0.32 * vel * pl * kg, pan: idx % 2 == 0 ? 0.25 : 0.12)
        case .hatOpen:
            return Mix(gain: 0.3 * vel * pl * kg, pan: -0.25, reverb: 0.05)
        case .shaker:
            return Mix(gain: 0.22 * vel * pl * kg, pan: idx % 2 == 0 ? 0.4 : -0.1)
        case .crash:
            return Mix(gain: 0.3 * vel * kg, pan: 0.1, reverb: 0.3)
        case .tomHigh:
            return Mix(gain: 0.5 * vel * kg, pan: -0.3, reverb: 0.2)
        case .tomMid:
            return Mix(gain: 0.5 * vel * kg, pan: 0, reverb: 0.2)
        case .tomLow:
            return Mix(gain: 0.55 * vel * kg, pan: 0.3, reverb: 0.2)
        case .rim:
            return Mix(gain: 0.4 * vel * pl * kg, pan: 0.1, reverb: 0.12)
        case .tambourine:
            return Mix(gain: 0.24 * vel * pl * kg, pan: idx % 2 == 0 ? 0.3 : -0.2, reverb: 0.1)
        case .cowbell:
            return Mix(gain: 0.25 * vel * pl * kg, pan: -0.15, reverb: 0.08)
        case .congaHigh:
            return Mix(gain: 0.4 * vel * pl * kg, pan: 0.3, reverb: 0.1)
        case .congaLow:
            return Mix(gain: 0.42 * vel * pl * kg, pan: -0.3, reverb: 0.1)
        case .ride:
            return Mix(gain: 0.22 * vel * pl * kg, pan: 0.2, reverb: 0.1)
        case .snap:
            return Mix(gain: 0.45 * vel * pl * kg, pan: 0.05, reverb: 0.2)
        case .impact:
            return Mix(gain: 0.5 * vel * kg, pan: 0, reverb: 0.3)
        }
    }

    /// A build-up or fall-away effect around a chorus.
    static func renderRiser(ctx: RenderContext, riser: Riser) {
        let start = ctx.frame(beat: riser.startBeat)
        let len = Int(riser.lengthBeats * ctx.spb * Double(ctx.sr))
        guard len > 100 else { return }
        let seedBase = UInt32(truncatingIfNeeded: abs(start) % 90000 + 1000)
        var nL = Noise(seed: seedBase &+ 12345)
        var nR = Noise(seed: seedBase &+ 54321)
        var fL = SVF()
        var fR = SVF()
        let mix = Mix(gain: 0.3 * riser.gain, pan: 0, reverb: 0.2)
        let fadeOut = 480
        let twoPi = 2 * Float.pi
        var phase: Float = 0
        for k in 0..<len {
            let i = start + k
            if i < 0 { continue }
            if i >= ctx.frames { break }
            let x = Float(k) / Float(len)
            var endGain: Float = 1
            if k > len - fadeOut { endGain = Float(len - k) / Float(fadeOut) }
            switch riser.kind {
            case .noiseSweep:
                if k % 16 == 0 {
                    let cutoff = 250 * pow(36, x)
                    fL.set(cutoff: cutoff, q: 1.2, sr: ctx.sr)
                    fR.set(cutoff: cutoff, q: 1.2, sr: ctx.sr)
                }
                let env = x * x * endGain
                ctx.bus.addStereo(i, fL.lowpass(nL.next()) * env, fR.lowpass(nR.next()) * env, mix, 1)
            case .pitchSweep:
                let f = 180 * pow(14, x)
                phase += f / ctx.sr
                if phase >= 1 { phase -= 1 }
                let tone = sin(twoPi * phase) * 0.6 + sin(2 * twoPi * phase) * 0.25
                let env = pow(x, 1.6) * endGain
                let hiss = nL.next() * 0.06
                ctx.bus.add(i, (tone + hiss) * env, mix, 1)
            case .reverseSwell:
                if k % 16 == 0 {
                    let centre = 700 * pow(9, x)
                    fL.set(cutoff: centre, q: 1.6, sr: ctx.sr)
                    fR.set(cutoff: centre, q: 1.6, sr: ctx.sr)
                }
                let env = pow(x, 2.4) * endGain * 1.6
                ctx.bus.addStereo(i, fL.bandpass(nL.next()) * env, fR.bandpass(nR.next()) * env, mix, 1)
            case .downlifter:
                if k % 16 == 0 {
                    let cutoff = 9000 * pow(0.033, x)
                    fL.set(cutoff: cutoff, q: 1.0, sr: ctx.sr)
                    fR.set(cutoff: cutoff, q: 1.0, sr: ctx.sr)
                }
                let inv = 1 - x
                let env = pow(inv, 1.4) * min(1, Float(k) / 400) * endGain
                let f = 70 + 430 * inv * inv
                phase += f / ctx.sr
                if phase >= 1 { phase -= 1 }
                let sine = sin(twoPi * phase) * 0.35
                ctx.bus.addStereo(i, (fL.lowpass(nL.next()) + sine) * env, (fR.lowpass(nR.next()) + sine) * env, mix, 1)
            }
        }
    }
}
