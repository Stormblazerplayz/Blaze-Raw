import Foundation

enum DrumVoice: Int {
    case kick, snare, clap, hatClosed, hatOpen, shaker, crash, tomHigh, tomMid, tomLow
}

struct DrumHit {
    let beat: Double
    let voice: DrumVoice
    let vel: Float
}

struct Riser {
    let startBeat: Double
    let lengthBeats: Double
}

// MARK: - Drum sounds (synthesized once, then copied wherever they are needed)

enum DrumSynth {
    private static func fadeTail(_ a: inout [Float], frames: Int = 220) {
        let n = a.count
        guard n > frames else { return }
        for i in 0..<frames {
            a[n - 1 - i] *= Float(i) / Float(frames)
        }
    }

    static func kick(sr: Float, heavy: Bool, variant: Int) -> [Float] {
        let len = Int(sr * 0.7)
        var out = [Float](repeating: 0, count: len)
        let fStart: Float = heavy ? 190 : 145
        let fEnd: Float = heavy ? 44 : 50
        let pitchTau: Float = heavy ? 0.045 : 0.035
        let ampTau: Float = heavy ? 0.26 : 0.19
        var phase: Float = 0
        var noise = Noise(seed: UInt32(7 + variant))
        var hp = SVF(cutoff: 2500, q: 0.7, sr: sr)
        for n in 0..<len {
            let t = Float(n) / sr
            let f = fEnd + (fStart - fEnd) * exp(-t / pitchTau)
            phase += f / sr
            if phase >= 1 { phase -= 1 }
            let env = exp(-t / ampTau) * min(1, t / 0.0015)
            var s = sin(2 * Float.pi * phase) * env
            let click = hp.highpass(noise.next()) * exp(-t / 0.003) * 0.35
            s = softClip((s + click) * (heavy ? 1.8 : 1.25))
            out[n] = s * 0.95
        }
        fadeTail(&out)
        return out
    }

    static func snare(sr: Float, variant: Int, soft: Bool) -> [Float] {
        let len = Int(sr * 0.4)
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: UInt32(101 + variant * 17))
        var hp = SVF(cutoff: 1400, q: 0.7, sr: sr)
        var lp = SVF(cutoff: soft ? 6500 : 10000, q: 0.7, sr: sr)
        for n in 0..<len {
            let t = Float(n) / sr
            let tone = sin(2 * Float.pi * 185 * t) * exp(-t / 0.05) * 0.55
                + sin(2 * Float.pi * 330 * t) * exp(-t / 0.03) * 0.2
            let nz = lp.lowpass(hp.highpass(noise.next())) * exp(-t / 0.1) * 0.9
            out[n] = softClip((tone + nz) * 1.5) * 0.8
        }
        fadeTail(&out)
        return out
    }

    static func clap(sr: Float, variant: Int) -> [Float] {
        let len = Int(sr * 0.35)
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: UInt32(211 + variant * 31))
        var bp = SVF(cutoff: 1500, q: 0.9, sr: sr)
        let bursts: [Float] = [0, 0.011, 0.022]
        for n in 0..<len {
            let t = Float(n) / sr
            var env: Float = 0
            for b in bursts where t >= b { env += exp(-(t - b) / 0.003) }
            if t >= 0.033 { env += exp(-(t - 0.033) / 0.07) }
            out[n] = bp.bandpass(noise.next()) * env * 0.9
        }
        fadeTail(&out)
        return out
    }

    static func hat(sr: Float, open: Bool, variant: Int) -> [Float] {
        let len = Int(sr * (open ? 0.6 : 0.12))
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: UInt32(307 + variant * 13 + (open ? 5 : 0)))
        var hp = SVF(cutoff: open ? 6000 : 7000, q: 0.8, sr: sr)
        let tau: Float = open ? 0.14 : 0.03
        for n in 0..<len {
            let t = Float(n) / sr
            out[n] = hp.highpass(noise.next()) * exp(-t / tau) * 0.8
        }
        fadeTail(&out, frames: 120)
        return out
    }

    static func shaker(sr: Float, variant: Int) -> [Float] {
        let len = Int(sr * 0.12)
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: UInt32(401 + variant * 7))
        var bp = SVF(cutoff: 6500, q: 1.2, sr: sr)
        for n in 0..<len {
            let t = Float(n) / sr
            let env = min(1, t / 0.008) * exp(-t / 0.03)
            out[n] = bp.bandpass(noise.next()) * env
        }
        fadeTail(&out, frames: 120)
        return out
    }

    static func crash(sr: Float) -> [Float] {
        let len = Int(sr * 2.4)
        var out = [Float](repeating: 0, count: len)
        var noise = Noise(seed: 977)
        var hp = SVF(cutoff: 4500, q: 0.7, sr: sr)
        for n in 0..<len {
            let t = Float(n) / sr
            out[n] = hp.highpass(noise.next()) * exp(-t / 0.7) * min(1, t / 0.002) * 0.7
        }
        fadeTail(&out, frames: 400)
        return out
    }

    static func tom(sr: Float, freq: Float) -> [Float] {
        let len = Int(sr * 0.5)
        var out = [Float](repeating: 0, count: len)
        var phase: Float = 0
        for n in 0..<len {
            let t = Float(n) / sr
            let f = freq + freq * 0.6 * exp(-t / 0.06)
            phase += f / sr
            if phase >= 1 { phase -= 1 }
            out[n] = softClip(sin(2 * Float.pi * phase) * exp(-t / 0.18) * 1.4) * 0.85 * min(1, t / 0.001)
        }
        fadeTail(&out)
        return out
    }
}

// MARK: - Drum patterns

struct BarPattern {
    var kick = [Float](repeating: 0, count: 16)
    var snare = [Float](repeating: 0, count: 16)
    var clap = [Float](repeating: 0, count: 16)
    var hat = [Float](repeating: 0, count: 16)
    var open = [Float](repeating: 0, count: 16)
    var shaker = [Float](repeating: 0, count: 16)
}

extension SongPlan {
    func isHeavyKick() -> Bool {
        switch settings.mood {
        case .dark, .raw, .epic, .energetic: return true
        default: return false
        }
    }

    private func basePattern(_ g: inout SeededRNG, bar: Int, phraseEnd: Bool) -> BarPattern {
        var p = BarPattern()
        switch profile.kit {
        case .fourOnFloor:
            for s in [0, 4, 8, 12] { p.kick[s] = 1 }
            p.clap[4] = 0.9; p.clap[12] = 0.9
            p.snare[4] = 0.35; p.snare[12] = 0.35
            for s in [2, 6, 10, 14] { p.open[s] = 0.5 }
            for s in stride(from: 1, to: 16, by: 2) { p.hat[s] = 0.28 }
            for s in 0..<16 { p.shaker[s] = s % 4 == 0 ? 0.2 : (s % 2 == 0 ? 0.12 : 0.16) }
        case .halfTime:
            p.kick[0] = 1; p.kick[10] = 0.85
            if g.chance(0.4) { p.kick[7] = 0.6 }
            if g.chance(0.2) { p.kick[3] = 0.5 }
            if g.chance(0.25) { p.kick[13] = 0.5 }
            p.snare[8] = 1; p.clap[8] = 0.5
            if g.chance(0.3) { p.snare[15] = 0.18 }
            let h: [Float] = [0.45, 0, 0.3, 0, 0.4, 0, 0.3, 0, 0.45, 0, 0.3, 0, 0.4, 0, 0.3, 0]
            for s in 0..<16 { p.hat[s] = h[s] }
            for s in [3, 7, 11, 15] { p.hat[s] = 0.12 }
            if phraseEnd { p.open[14] = 0.4 }
            for s in [2, 6, 10, 14] { p.shaker[s] = 0.12 }
        case .breakbeat:
            p.kick[0] = 1; p.kick[6] = 0.8; p.kick[10] = 0.9
            if g.chance(0.3) { p.kick[3] = 0.7 }
            if g.chance(0.3) { p.kick[13] = 0.7 }
            p.snare[4] = 1; p.snare[12] = 1
            p.clap[4] = 0.4; p.clap[12] = 0.4
            if g.chance(0.5) { p.snare[7] = 0.22 }
            if g.chance(0.5) { p.snare[9] = 0.2 }
            if g.chance(0.4) { p.snare[15] = 0.25 }
            let accents: [Float] = [0.5, 0.22, 0.35, 0.22]
            for s in 0..<16 { p.hat[s] = accents[s % 4] }
            if g.chance(0.6) { p.open[6] = 0.4 }
            if g.chance(0.6) { p.open[14] = 0.4 }
        case .epic:
            p.kick[0] = 1; p.kick[8] = 0.9
            if g.chance(0.5) { p.kick[11] = 0.6 }
            p.snare[4] = 1; p.snare[12] = 1
            p.clap[4] = 0.7; p.clap[12] = 0.7
            for s in stride(from: 0, to: 16, by: 2) { p.hat[s] = 0.18 }
        }
        return p
    }

    func drumHits() -> (hits: [DrumHit], risers: [Riser]) {
        guard settings.instruments.contains(.drums) else { return ([], []) }
        var g = rng.fork(30)
        var hits: [DrumHit] = []
        var risers: [Riser] = []
        let intensity = Float(settings.intensity)
        let scale = 0.7 + 0.3 * intensity

        for sec in sections {
            if sec.kind == .chorus {
                hits.append(DrumHit(beat: Double(sec.startBar * 4), voice: .crash, vel: 0.9))
            }
            if sec.preDrop {
                let beats = Double(min(sec.bars, 2) * 4)
                risers.append(Riser(startBeat: Double(sec.endBar * 4) - beats, lengthBeats: beats))
            }
            let lvl = level(.drums, sec.kind)
            if lvl <= 0 { continue }

            for b in 0..<sec.bars {
                if sec.kind == .outro && b >= sec.bars / 2 { continue }
                let bar = sec.startBar + b
                let phraseEnd = b % 4 == 3
                let fadeOut: Float = sec.kind == .outro
                    ? max(0, 1 - Float(b) / Float(max(1, sec.bars / 2)))
                    : 1
                var p = basePattern(&g, bar: bar, phraseEnd: phraseEnd)

                // Simpler beats in the intro and verse.
                if sec.kind == .intro {
                    p.kick = [Float](repeating: 0, count: 16)
                    p.snare = p.kick
                    p.clap = p.kick
                    p.open = p.kick
                }
                if sec.kind == .verse || sec.kind == .outro {
                    p.clap = [Float](repeating: 0, count: 16)
                    if profile.kit != .halfTime { p.open = [Float](repeating: 0, count: 16) }
                }
                if intensity < 0.4 {
                    // Calmer: fewer hats and no shaker.
                    for s in 0..<16 where s % 4 != 0 { p.hat[s] = 0 }
                    p.shaker = [Float](repeating: 0, count: 16)
                }

                // Build-up bar before a drop: snare roll.
                let rollBar = sec.preDrop && b == sec.bars - 1
                if rollBar {
                    for s in 12..<16 { p.kick[s] = 0 }
                    for s in 8..<16 {
                        p.snare[s] = 0.3 + 0.7 * Float(s - 8) / 7
                        p.hat[s] = 0
                    }
                    for s in 8..<16 { p.open[s] = 0 }
                }

                // Small fill at the end of some phrases.
                if phraseEnd && !rollBar && sec.kind != .intro && g.chance(Double(0.3 + 0.5 * intensity)) {
                    if profile.kit == .epic {
                        hits.append(DrumHit(beat: stepBeat(bar, 12), voice: .tomHigh, vel: 0.8))
                        hits.append(DrumHit(beat: stepBeat(bar, 13), voice: .tomMid, vel: 0.85))
                        hits.append(DrumHit(beat: stepBeat(bar, 14), voice: .tomLow, vel: 0.9))
                        hits.append(DrumHit(beat: stepBeat(bar, 15), voice: .tomLow, vel: 1.0))
                        for s in 12..<16 { p.snare[s] = 0; p.hat[s] = 0 }
                    } else {
                        p.snare[14] = max(p.snare[14], 0.5)
                        p.snare[15] = max(p.snare[15], 0.7)
                    }
                }

                func add(_ pat: [Float], _ voice: DrumVoice, humanize: Float) {
                    for s in 0..<16 where pat[s] > 0 {
                        let jitter = humanize == 0 ? 0 : Double((g.float() - 0.5) * 2 * humanize)
                        let v = pat[s] * scale * lvl * fadeOut * (0.92 + 0.08 * g.float())
                        hits.append(DrumHit(beat: stepBeat(bar, s) + jitter, voice: voice, vel: min(v, 1)))
                    }
                }
                add(p.kick, .kick, humanize: 0)
                add(p.snare, .snare, humanize: 0)
                add(p.clap, .clap, humanize: 0.002)
                add(p.hat, .hatClosed, humanize: 0.005)
                add(p.open, .hatOpen, humanize: 0.003)
                add(p.shaker, .shaker, humanize: 0.005)
            }
        }
        return (hits, risers)
    }
}

// MARK: - Rendering drums

enum DrumRenderer {
    /// Renders all drum hits into the bus. Returns the frames at which a kick drum plays
    /// (the other instruments "duck" around these).
    static func render(plan: SongPlan, ctx: RenderContext, hits: [DrumHit], risers: [Riser]) -> [Int] {
        let sr = ctx.sr
        let heavy = plan.isHeavyKick()
        let soft = plan.settings.mood == .chill || plan.settings.mood == .sad || plan.settings.mood == .dreamy

        let kicks = [DrumSynth.kick(sr: sr, heavy: heavy, variant: 0)]
        let snares = [DrumSynth.snare(sr: sr, variant: 0, soft: soft), DrumSynth.snare(sr: sr, variant: 1, soft: soft)]
        let claps = [DrumSynth.clap(sr: sr, variant: 0), DrumSynth.clap(sr: sr, variant: 1)]
        let hatsC = [DrumSynth.hat(sr: sr, open: false, variant: 0), DrumSynth.hat(sr: sr, open: false, variant: 1),
                     DrumSynth.hat(sr: sr, open: false, variant: 2)]
        let hatsO = [DrumSynth.hat(sr: sr, open: true, variant: 0), DrumSynth.hat(sr: sr, open: true, variant: 1)]
        let shakers = [DrumSynth.shaker(sr: sr, variant: 0), DrumSynth.shaker(sr: sr, variant: 1)]
        let crash = DrumSynth.crash(sr: sr)
        let tomH = DrumSynth.tom(sr: sr, freq: 170)
        let tomM = DrumSynth.tom(sr: sr, freq: 125)
        let tomL = DrumSynth.tom(sr: sr, freq: 88)

        var kickFrames: [Int] = []
        var counters = [Int](repeating: 0, count: 10)

        for hit in hits {
            let frame = ctx.frame(beat: hit.beat)
            if frame < 0 || frame >= ctx.frames { continue }
            let idx = counters[hit.voice.rawValue]
            counters[hit.voice.rawValue] += 1
            let sample: [Float]
            let mix: Mix
            switch hit.voice {
            case .kick:
                sample = kicks[0]
                mix = Mix(gain: 0.85 * hit.vel)
                kickFrames.append(frame)
            case .snare:
                sample = snares[idx % snares.count]
                mix = Mix(gain: 0.65 * hit.vel, pan: 0, reverb: 0.14)
            case .clap:
                sample = claps[idx % claps.count]
                mix = Mix(gain: 0.5 * hit.vel, pan: 0.05, reverb: 0.22)
            case .hatClosed:
                sample = hatsC[idx % hatsC.count]
                mix = Mix(gain: 0.32 * hit.vel, pan: idx % 2 == 0 ? 0.25 : 0.12)
            case .hatOpen:
                sample = hatsO[idx % hatsO.count]
                mix = Mix(gain: 0.3 * hit.vel, pan: -0.25, reverb: 0.05)
            case .shaker:
                sample = shakers[idx % shakers.count]
                mix = Mix(gain: 0.22 * hit.vel, pan: idx % 2 == 0 ? 0.4 : -0.1)
            case .crash:
                sample = crash
                mix = Mix(gain: 0.3 * hit.vel, pan: 0.1, reverb: 0.3)
            case .tomHigh:
                sample = tomH
                mix = Mix(gain: 0.5 * hit.vel, pan: -0.3, reverb: 0.2)
            case .tomMid:
                sample = tomM
                mix = Mix(gain: 0.5 * hit.vel, pan: 0, reverb: 0.2)
            case .tomLow:
                sample = tomL
                mix = Mix(gain: 0.55 * hit.vel, pan: 0.3, reverb: 0.2)
            }
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

    /// A rising noise sweep that builds tension before a drop.
    static func renderRiser(ctx: RenderContext, riser: Riser) {
        let start = ctx.frame(beat: riser.startBeat)
        let len = Int(riser.lengthBeats * ctx.spb * Double(ctx.sr))
        guard len > 100 else { return }
        var nL = Noise(seed: 12345)
        var nR = Noise(seed: 54321)
        var fL = SVF()
        var fR = SVF()
        let mix = Mix(gain: 0.3, pan: 0, reverb: 0.2)
        let fadeOut = 480
        for k in 0..<len {
            let i = start + k
            if i < 0 { continue }
            if i >= ctx.frames { break }
            let x = Float(k) / Float(len)
            if k % 16 == 0 {
                let cutoff = 250 * pow(36, x)
                fL.set(cutoff: cutoff, q: 1.2, sr: ctx.sr)
                fR.set(cutoff: cutoff, q: 1.2, sr: ctx.sr)
            }
            var env = x * x
            if k > len - fadeOut { env *= Float(len - k) / Float(fadeOut) }
            ctx.bus.addStereo(i, fL.lowpass(nL.next()) * env, fR.lowpass(nR.next()) * env, mix, 1)
        }
    }
}
