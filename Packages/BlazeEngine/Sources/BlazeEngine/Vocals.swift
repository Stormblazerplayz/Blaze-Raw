import Foundation

// MARK: - Voice description

/// Vowel numbers: 0 = "ah", 1 = "eh", 2 = "ee", 3 = "oh", 4 = "oo"
struct VoiceSpec {
    var female: Bool
    var vowelFrom: Int
    var vowelTo: Int
    var vibratoCents: Float = 25
    var breath: Float = 0.05
    var whisper: Bool = false
    var robot: Bool = false
    var unison: Int = 1
    var detuneCents: Float = 8
    var attack: Float = 0.08
    var release: Float = 0.25
    var bendSemis: Float = 0
    var formantShift: Float = 1
}

struct VoiceEvent {
    var note: NoteEvent
    var spec: VoiceSpec
    var pan: Float
}

// MARK: - The voice synthesizer (source + three formant filters)

enum VoiceSynth {
    static let maleFormants: [[Float]] = [
        [730, 1090, 2440], [530, 1840, 2480], [270, 2290, 3010], [570, 840, 2410], [300, 870, 2240]
    ]
    static let femaleFormants: [[Float]] = [
        [850, 1220, 2810], [610, 2330, 2990], [310, 2790, 3310], [590, 920, 2710], [370, 950, 2670]
    ]
    static let bandwidths: [Float] = [65, 95, 130]
    static let sampleRate: Float = 44100

    /// Loudness correction per vowel, so "ee" and "ah" sound equally loud.
    /// Index = kind * 5 + vowel, where kind 0 = male, 1 = female, 2 = whisper.
    static let gains: [Float] = {
        var g: [Float] = []
        for kind in 0..<3 {
            for vowel in 0..<5 {
                g.append(measureGain(female: kind == 1, vowel: vowel, noiseSource: kind == 2))
            }
        }
        return g
    }()

    static func lpCoef(_ cutoff: Float, _ sr: Float) -> Float {
        1 - exp(-2 * Float.pi * cutoff / sr)
    }

    static func measureGain(female: Bool, vowel: Int, noiseSource: Bool) -> Float {
        let sr = sampleRate
        let formants = (female ? femaleFormants : maleFormants)[vowel]
        let coef = lpCoef(1200, sr)
        // Measure at several pitches and average, so the correction works across the whole singing range.
        let pitches: [Float] = female ? [200, 240, 290, 350, 420] : [100, 120, 145, 175, 210]
        var totalPower: Float = 0
        for f in pitches {
            var res = [Resonator](repeating: Resonator(), count: 3)
            for j in 0..<3 {
                res[j].set(freq: formants[j], bandwidth: bandwidths[j] * (noiseSource ? 2.4 : 1), sr: sr)
            }
            var lp: Float = 0
            var noise = Noise(seed: 5)
            let dt = f / sr
            var ph: Float = 0
            var sum: Float = 0
            var count = 0
            let n = Int(sr * 0.35)
            for k in 0..<n {
                var src: Float
                if noiseSource {
                    src = noise.next() * 0.5
                } else {
                    lp += coef * (sawBL(ph, dt) - lp)
                    src = lp
                    advance(&ph, dt)
                }
                for j in 0..<3 { src = res[j].process(src) }
                if k > Int(sr * 0.08) {
                    sum += src * src
                    count += 1
                }
            }
            totalPower += sum / Float(max(count, 1))
            if noiseSource { break }
        }
        let rms = sqrt(totalPower / Float(noiseSource ? 1 : pitches.count))
        return clampf(0.2 / max(rms, 1e-4), 0.02, 60)
    }

    private struct Singer {
        var phase: Float
        var lp: Float = 0
        var res = [Resonator](repeating: Resonator(), count: 3)
        var noise: Noise
        var detuneRatio: Float
        var vibPhase: Float
        var vibRate: Float
        var shift: Float
    }

    static func render(_ events: [VoiceEvent], ctx: RenderContext, mix: Mix) {
        let sr = ctx.sr
        let coef = lpCoef(1200, sr)
        let twoPi = 2 * Float.pi

        for (ei, ev) in events.enumerated() {
            let spec = ev.spec
            let f0 = Float(ctx.tuning.frequency(semis: ev.note.semis))
            if !spec.whisper && (f0 < 55 || f0 > 1500) { continue }
            let start = max(0, ctx.frame(beat: ev.note.beat))
            let durS = Float(ev.note.dur * ctx.spb)
            let total = max(1, Int((durS + spec.release) * sr))
            let voices = max(1, min(spec.unison, 4))
            var singers: [Singer] = []
            for v in 0..<voices {
                let off = Float(v) - Float(voices - 1) / 2
                let seed = UInt32(truncatingIfNeeded: 31 * ei + 977 * v + 13)
                singers.append(Singer(phase: Float((ei * 17 + v * 29) % 100) / 100,
                                      noise: Noise(seed: seed &+ 1),
                                      detuneRatio: Float(pow(2.0, Double(off * spec.detuneCents) / 1200.0)),
                                      vibPhase: Float((ei * 11 + v * 23) % 100) / 100 * twoPi,
                                      vibRate: 4.9 + 0.35 * Float(v) + Float(ei % 5) * 0.05,
                                      shift: spec.formantShift * (1 + 0.025 * off)))
            }
            let m = mix.with(pan: ev.pan)
            let formA = (spec.female ? femaleFormants : maleFormants)[min(max(spec.vowelFrom, 0), 4)]
            let formB = (spec.female ? femaleFormants : maleFormants)[min(max(spec.vowelTo, 0), 4)]
            let kind = spec.whisper ? 2 : (spec.female ? 1 : 0)
            let gainA = gains[kind * 5 + min(max(spec.vowelFrom, 0), 4)]
            let gainB = gains[kind * 5 + min(max(spec.vowelTo, 0), 4)]
            let bwScale: Float = spec.whisper ? 2.4 : (spec.robot ? 0.55 : 1)
            let morphs = spec.vowelFrom != spec.vowelTo && !spec.robot
            let voiceNorm = 1 / sqrt(Float(voices))
            var morph: Float = 0
            var vowelGain = gainA

            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) / sr
                if k & 15 == 0 {
                    morph = morphs ? smoothstep(((t / max(durS, 0.05)) - 0.55) / 0.35) : 0
                    vowelGain = gainA + (gainB - gainA) * morph
                    for v in 0..<voices {
                        for j in 0..<3 {
                            let fr = (formA[j] + (formB[j] - formA[j]) * morph) * singers[v].shift
                            singers[v].res[j].set(freq: fr, bandwidth: bandwidths[j] * bwScale, sr: sr)
                        }
                    }
                }
                let bend = spec.bendSemis != 0 ? pow(2, spec.bendSemis * exp(-t / 0.06) / 12) : 1
                let vibOnset = smoothstep((t - 0.15) / 0.35)
                var sum: Float = 0
                for v in 0..<voices {
                    var src: Float
                    if spec.whisper {
                        src = singers[v].noise.next() * 0.5
                    } else {
                        let vib = 1 + (spec.vibratoCents / 1200 * 0.693) * vibOnset
                            * sin(twoPi * singers[v].vibRate * t + singers[v].vibPhase)
                        let dt = min(f0 * singers[v].detuneRatio * bend * vib / sr, 0.45)
                        let saw = sawBL(singers[v].phase, dt)
                        advance(&singers[v].phase, dt)
                        singers[v].lp += coef * (saw - singers[v].lp)
                        src = singers[v].lp
                        if spec.breath > 0 { src += singers[v].noise.next() * spec.breath * 0.35 }
                    }
                    for j in 0..<3 { src = singers[v].res[j].process(src) }
                    sum += src
                }
                let env = adsrLevel(t, durS, spec.attack, 0.05, 1.0, spec.release)
                let y = sum * voiceNorm * vowelGain * env * ev.note.vel
                ctx.bus.add(i, y, m, ctx.duck(i, m.duck))
            }
        }
    }
}

// MARK: - Writing the vocal lines

extension SongPlan {
    static func vocalLevel(_ s: VocalStyle, _ k: SectionKind) -> Float {
        // order: intro, verse, chorus, breakdown, outro
        let table: [Float]
        switch s {
        case .femaleAah: table = [0, 0.55, 1.0, 1.0, 0.6]
        case .maleOoh: table = [0, 0.6, 0.7, 0.5, 0.6]
        case .choir: table = [0.35, 0.55, 0.9, 1.0, 0.7]
        case .vocalChops: table = [0, 0.55, 1.0, 0, 0]
        case .robot: table = [0, 0.7, 1.0, 0, 0]
        case .whisper: table = [0.8, 0, 0.4, 1.0, 0.9]
        case .duet: table = [0, 0.7, 1.0, 1.0, 0.6]
        }
        return table[k.rawValue]
    }

    static func vocalMix(_ s: VocalStyle) -> Mix {
        switch s {
        case .femaleAah: return Mix(gain: 0.46, pan: -0.1, reverb: 0.35, delay: 0.15)
        case .maleOoh: return Mix(gain: 0.5, pan: 0.1, reverb: 0.3)
        case .choir: return Mix(gain: 0.42, reverb: 0.55, duck: 0.25)
        case .vocalChops: return Mix(gain: 0.42, reverb: 0.3, delay: 0.4)
        case .robot: return Mix(gain: 0.4, reverb: 0.15, delay: 0.1, duck: 0.3)
        case .whisper: return Mix(gain: 0.55, reverb: 0.5)
        case .duet: return Mix(gain: 0.44, reverb: 0.4, delay: 0.1)
        }
    }

    /// Stretches each melody note until the next one starts, so the singing is smooth.
    private func legato(_ evs: [(note: NoteEvent, kind: SectionKind)], minDur: Double, maxDur: Double) -> [(note: NoteEvent, kind: SectionKind)] {
        var out = evs
        for i in 0..<out.count {
            let next = i + 1 < out.count ? out[i + 1].note.beat : Double.infinity
            let room = next - out[i].note.beat + 0.15
            out[i].note.dur = min(max(out[i].note.dur, minDur), min(maxDur, room))
        }
        return out
    }

    func vocalEvents(_ style: VocalStyle) -> [VoiceEvent] {
        var g = rng.fork(UInt64(100 + style.hashValueStable))
        var out: [VoiceEvent] = []

        switch style {
        case .femaleAah:
            let evs = legato(hookEvents(center: 70, onlyStrong: true), minDur: 1.5, maxDur: 4)
            for (ev, kind) in evs {
                let lvl = SongPlan.vocalLevel(.femaleAah, kind)
                if lvl <= 0 { continue }
                var n = ev
                n.vel = vel(lvl, &g)
                let soft = kind == .verse || kind == .outro
                let spec = VoiceSpec(female: true, vowelFrom: soft ? 4 : 0, vowelTo: 3,
                                     vibratoCents: 28, breath: 0.08, unison: kind == .chorus ? 2 : 1,
                                     detuneCents: 7, attack: 0.12, release: 0.35)
                out.append(VoiceEvent(note: n, spec: spec, pan: -0.1))
            }

        case .maleOoh:
            for sec in sections {
                let lvl = SongPlan.vocalLevel(.maleOoh, sec.kind)
                if lvl <= 0 { continue }
                var b = 0
                while b < sec.bars {
                    let bar = sec.startBar + b
                    let chord = self.chord(atBar: bar)
                    let len = min(profile.barsPerChord, sec.bars - b)
                    var tones = [lowRoot(chord, lowest: 45)]
                    if sec.kind == .chorus, chord.tones.count > 2 {
                        var fifth = chord.tones[2]
                        while tonicMidi + fifth < 52 { fifth += 12 }
                        while tonicMidi + fifth >= 64 { fifth -= 12 }
                        tones.append(fifth)
                    }
                    for t in tones {
                        let n = NoteEvent(beat: Double(bar * 4), dur: Double(len * 4) - 0.1, semis: t, vel: vel(lvl, &g))
                        let spec = VoiceSpec(female: false, vowelFrom: 4, vowelTo: 3, vibratoCents: 20,
                                             breath: 0.06, unison: 2, detuneCents: 9, attack: 0.25, release: 0.5)
                        out.append(VoiceEvent(note: n, spec: spec, pan: 0.1))
                    }
                    b += len
                }
            }

        case .choir:
            for sec in sections {
                let lvl = SongPlan.vocalLevel(.choir, sec.kind)
                if lvl <= 0 { continue }
                var b = 0
                var idx = 0
                while b < sec.bars {
                    let bar = sec.startBar + b
                    let chord = self.chord(atBar: bar)
                    let len = min(profile.barsPerChord, sec.bars - b)
                    let tones = voicing(chord, center: 62)
                    for (k, t) in tones.enumerated() {
                        let n = NoteEvent(beat: Double(bar * 4), dur: Double(len * 4) - 0.1, semis: t, vel: vel(lvl, &g))
                        let spec = VoiceSpec(female: k % 2 == 1, vowelFrom: idx % 2 == 0 ? 0 : 3, vowelTo: idx % 2 == 0 ? 3 : 0,
                                             vibratoCents: 18, breath: 0.1, unison: 2, detuneCents: 10, attack: 0.5, release: 0.9)
                        let pan = (Float(k) - Float(tones.count - 1) / 2) * 0.35
                        out.append(VoiceEvent(note: n, spec: spec, pan: pan))
                    }
                    idx += 1
                    b += len
                }
            }

        case .vocalChops:
            let patterns: [[Int]] = [[0, 3, 6, 10, 12], [2, 5, 8, 11, 14], [0, 2, 6, 8, 11, 14]]
            let patA = g.pick(patterns)
            let patB = g.pick(patterns)
            let vowels = [0, 1, 3, 2]
            var hitCount = 0
            for sec in sections {
                let lvl = SongPlan.vocalLevel(.vocalChops, sec.kind)
                if lvl <= 0 { continue }
                for b in 0..<sec.bars {
                    if sec.kind == .verse && b % 2 == 0 { continue }
                    let bar = sec.startBar + b
                    let chord = self.chord(atBar: bar)
                    var tones = voicing(chord, center: 70)
                    while tones.count < 4 { tones.append((tones.last ?? 0) + 12) }
                    let pat = b % 2 == 0 ? patA : patB
                    for step in pat {
                        var t = tones[g.int(0...(tones.count - 1))]
                        if g.chance(0.15) { t += 12 }
                        let len = g.chance(0.35) ? 2 : 1
                        let n = NoteEvent(beat: stepBeat(bar, step), dur: Double(len) * 0.25 * 0.85, semis: t, vel: vel(lvl, &g))
                        let v = vowels[hitCount % vowels.count]
                        let spec = VoiceSpec(female: true, vowelFrom: v, vowelTo: v, vibratoCents: 0, breath: 0.15,
                                             unison: 1, attack: 0.008, release: 0.07, bendSemis: -2,
                                             formantShift: 0.95 + 0.3 * g.float())
                        out.append(VoiceEvent(note: n, spec: spec, pan: hitCount % 2 == 0 ? 0.35 : -0.35))
                        hitCount += 1
                    }
                }
            }

        case .robot:
            let steps = [0, 2, 3, 6, 8, 10, 11, 14]
            let vowels = [0, 1, 2, 3, 4, 3, 2, 1]
            for sec in sections {
                let lvl = SongPlan.vocalLevel(.robot, sec.kind)
                if lvl <= 0 { continue }
                for b in 0..<sec.bars {
                    if sec.kind == .verse && b % 2 == 1 { continue }
                    let bar = sec.startBar + b
                    let chord = self.chord(atBar: bar)
                    let root = lowRoot(chord, lowest: 48)
                    for (k, step) in steps.enumerated() {
                        let n = NoteEvent(beat: stepBeat(bar, step), dur: 0.2, semis: root, vel: vel(lvl, &g))
                        let v = vowels[(k + b) % vowels.count]
                        let spec = VoiceSpec(female: false, vowelFrom: v, vowelTo: v, vibratoCents: 0, breath: 0,
                                             robot: true, unison: 2, detuneCents: 14, attack: 0.005, release: 0.04)
                        out.append(VoiceEvent(note: n, spec: spec, pan: 0))
                    }
                }
            }

        case .whisper:
            let vowels = [0, 3, 1, 4]
            var hitCount = 0
            for sec in sections {
                let lvl = SongPlan.vocalLevel(.whisper, sec.kind)
                if lvl <= 0 { continue }
                for b in 0..<sec.bars {
                    if sec.kind == .chorus && b % 2 == 1 { continue }
                    let bar = sec.startBar + b
                    for step in [2, 6, 10, 14] {
                        let n = NoteEvent(beat: stepBeat(bar, step), dur: 0.35, semis: 0, vel: vel(lvl, &g))
                        let v = vowels[hitCount % vowels.count]
                        let spec = VoiceSpec(female: false, vowelFrom: v, vowelTo: vowels[(hitCount + 1) % vowels.count],
                                             breath: 0, whisper: true, attack: 0.04, release: 0.15)
                        out.append(VoiceEvent(note: n, spec: spec, pan: hitCount % 2 == 0 ? 0.7 : -0.7))
                        hitCount += 1
                    }
                }
            }

        case .duet:
            let high = legato(hookEvents(center: 70, onlyStrong: true), minDur: 1.5, maxDur: 4)
            let low = legato(hookEvents(center: 55, onlyStrong: true), minDur: 1.5, maxDur: 4)
            func window(_ beat: Double) -> Int {
                let bar = Int(beat / 4)
                let sec = sections[sectionIndex(atBar: bar)]
                return ((bar - sec.startBar) / 2) % 2
            }
            for (ev, kind) in high {
                let lvl = SongPlan.vocalLevel(.duet, kind)
                if lvl <= 0 { continue }
                let w = window(ev.beat)
                // female sings the first part, male answers; in the chorus they sing together
                if kind == .verse && w == 1 { continue }
                if kind == .outro { continue }
                var n = ev
                n.vel = vel(lvl, &g) * (kind == .chorus ? 0.85 : 1)
                let spec = VoiceSpec(female: true, vowelFrom: 0, vowelTo: 3, vibratoCents: 26, breath: 0.08,
                                     unison: 1, attack: 0.1, release: 0.3)
                out.append(VoiceEvent(note: n, spec: spec, pan: -0.2))
            }
            for (ev, kind) in low {
                let lvl = SongPlan.vocalLevel(.duet, kind)
                if lvl <= 0 { continue }
                let w = window(ev.beat)
                if kind == .verse && w == 0 { continue }
                if kind == .breakdown { continue }
                var n = ev
                n.vel = vel(lvl, &g) * (kind == .chorus ? 0.8 : 1)
                let spec = VoiceSpec(female: false, vowelFrom: 3, vowelTo: 4, vibratoCents: 22, breath: 0.06,
                                     unison: 1, attack: 0.12, release: 0.3)
                out.append(VoiceEvent(note: n, spec: spec, pan: 0.2))
            }
        }
        return out
    }
}

extension VocalStyle {
    /// A stable small number for each style (Swift's own hashValue changes between runs).
    var hashValueStable: Int {
        switch self {
        case .femaleAah: return 1
        case .maleOoh: return 2
        case .choir: return 3
        case .vocalChops: return 4
        case .robot: return 5
        case .whisper: return 6
        case .duet: return 7
        }
    }
}
