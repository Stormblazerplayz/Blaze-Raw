import Foundation

enum Synths {
    private static let twoPi = 2 * Float.pi

    @inline(__always)
    private static func span(_ n: NoteEvent, _ ctx: RenderContext, release: Float) -> (start: Int, durS: Float, total: Int) {
        let start = max(0, ctx.frame(beat: n.beat))
        let durS = Float(n.dur * ctx.spb)
        let total = max(1, Int((durS + release) * ctx.sr))
        return (start, durS, total)
    }

    // MARK: - Sub bass: a clean low sine with a little warmth

    static func subBass(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix) {
        let sr = ctx.sr
        let drive = 1.3 + ctx.grit * 1.2
        for n in notes {
            let f = Float(ctx.tuning.frequency(semis: n.semis))
            let (start, durS, total) = span(n, ctx, release: 0.1)
            var ph: Float = 0
            let dph = f / sr
            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) / sr
                let env = adsrLevel(t, durS, 0.005, 0.08, 0.9, 0.1)
                let y = softClip(sin(twoPi * ph) * drive) * 0.8
                advance(&ph, dph)
                ctx.bus.add(i, y * env * n.vel, mix, ctx.duck(i, mix.duck))
            }
        }
    }

    // MARK: - Growl bass: two detuned saws, ring-mod "intermodulation", drive and a wobbling filter

    static func growl(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix) {
        let sr = ctx.sr
        let grit = ctx.grit
        let mults: [Double] = [1, 2, 3, 4]
        let q = 1.6 + 3.5 * grit
        let driveIn = 1.3 + 3.2 * grit
        let samplesPerBeat = ctx.spb * Double(sr)
        for n in notes {
            let f = Float(ctx.tuning.frequency(semis: n.semis))
            let (start, durS, total) = span(n, ctx, release: 0.06)
            let dt1 = f / sr
            let dt2 = f * 1.0075 / sr
            let dtSub = f * 0.5 / sr
            let dtRing = f * 1.5 / sr
            var p1: Float = 0
            var p2: Float = 0.3
            var pSub: Float = 0
            var pRing: Float = 0
            var filt = SVF()
            let mult = mults[min(max(n.aux, 0), 3)]
            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) / sr
                if k & 7 == 0 {
                    let beatPos = Double(i) / samplesPerBeat
                    let lfo = 0.5 + 0.5 * Float(sin(2.0 * Double.pi * mult * beatPos))
                    let cutoff = 130 + lfo * lfo * (700 + 5500 * grit)
                    filt.set(cutoff: cutoff, q: q, sr: sr)
                }
                let s1 = sawBL(p1, dt1)
                let s2 = sawBL(p2, dt2)
                let sq = squareBL(pSub, dtSub, 0.5)
                var s = (s1 + s2) * 0.5 + sq * 0.45
                s *= 1 + 0.5 * grit * sin(twoPi * pRing)
                advance(&p1, dt1)
                advance(&p2, dt2)
                advance(&pSub, dtSub)
                advance(&pRing, dtRing)
                var y = softClip(s * driveIn)
                y = filt.lowpass(y)
                y = softClip(y * 1.6) * 0.75
                let env = adsrLevel(t, durS, 0.004, 0.12, 0.85, 0.06)
                ctx.bus.add(i, y * env * n.vel, mix, ctx.duck(i, mix.duck))
            }
        }
    }

    // MARK: - Pad: three detuned saws per note, slowly moving filter

    static func pad(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix, brightness: Float) {
        let sr = ctx.sr
        let cents: [Float] = [-11, 0, 11]
        let ratios = cents.map { Float(pow(2.0, Double($0) / 1200.0)) }
        let pans: [Float] = [-0.8, 0, 0.8]
        let gl = pans.map { cos(($0 + 1) * 0.25 * Float.pi) * 1.4142135 / 3 }
        let gr = pans.map { sin(($0 + 1) * 0.25 * Float.pi) * 1.4142135 / 3 }
        let tiers: [Float] = [0.55, 0.75, 1.0, 0.85, 0.6]   // intro, verse, chorus, breakdown, outro
        for (ni, n) in notes.enumerated() {
            let f = Float(ctx.tuning.frequency(semis: n.semis))
            let (start, durS, total) = span(n, ctx, release: 1.4)
            let a = min(0.8, durS * 0.4)
            let tier = tiers[min(max(n.aux, 0), 4)]
            let base = 500 + 3500 * brightness * tier
            var phases: [Float] = (0..<3).map { Float(($0 * 37 + ni * 53) % 100) / 100 }
            let dts = ratios.map { f * $0 / sr }
            var fL = SVF(cutoff: base, q: 0.9, sr: sr)
            var fR = SVF(cutoff: base, q: 0.9, sr: sr)
            let lfoPhase = Float(ni % 7) * 0.9
            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) / sr
                if k & 31 == 0 {
                    let tAbs = Float(i) / sr
                    let c = base * (1 + 0.25 * sin(twoPi * 0.12 * tAbs + lfoPhase))
                    fL.set(cutoff: c, q: 0.9, sr: sr)
                    fR.set(cutoff: c, q: 0.9, sr: sr)
                }
                var l: Float = 0
                var r: Float = 0
                for v in 0..<3 {
                    let s = sawBL(phases[v], dts[v])
                    advance(&phases[v], dts[v])
                    l += s * gl[v]
                    r += s * gr[v]
                }
                let env = adsrLevel(t, durS, a, 0.5, 0.85, 1.4)
                ctx.bus.addStereo(i, fL.lowpass(l) * env * n.vel, fR.lowpass(r) * env * n.vel, mix, ctx.duck(i, mix.duck))
            }
        }
    }

    // MARK: - Strings: five slightly detuned saws with gentle vibrato

    static func strings(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix, brightness: Float) {
        let sr = ctx.sr
        let cents: [Float] = [-14, -6, 0, 6, 14]
        let ratios = cents.map { Float(pow(2.0, Double($0) / 1200.0)) }
        let pans: [Float] = [-0.7, -0.3, 0, 0.3, 0.7]
        let gl = pans.map { cos(($0 + 1) * 0.25 * Float.pi) * 1.4142135 / 4 }
        let gr = pans.map { sin(($0 + 1) * 0.25 * Float.pi) * 1.4142135 / 4 }
        let tiers: [Float] = [0.5, 0.7, 1.0, 0.9, 0.6]
        for (ni, n) in notes.enumerated() {
            let f = Float(ctx.tuning.frequency(semis: n.semis))
            let (start, durS, total) = span(n, ctx, release: 0.9)
            let a = min(0.5, durS * 0.35)
            let tier = tiers[min(max(n.aux, 0), 4)]
            let cutoff = 1400 + 3200 * brightness * tier
            var phases: [Float] = (0..<5).map { Float(($0 * 29 + ni * 41) % 100) / 100 }
            let baseDt = ratios.map { f * $0 / sr }
            var fL = SVF(cutoff: cutoff, q: 0.8, sr: sr)
            var fR = SVF(cutoff: cutoff, q: 0.8, sr: sr)
            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) / sr
                let vibDepth = 0.003 * smoothstep((t - 0.3) / 0.5)
                var l: Float = 0
                var r: Float = 0
                for v in 0..<5 {
                    let vib = 1 + vibDepth * sin(twoPi * (5.1 + 0.2 * Float(v)) * t + Float(v))
                    let dt = baseDt[v] * vib
                    let s = sawBL(phases[v], dt)
                    advance(&phases[v], dt)
                    l += s * gl[v]
                    r += s * gr[v]
                }
                let env = adsrLevel(t, durS, a, 0.5, 0.85, 0.9)
                ctx.bus.addStereo(i, fL.lowpass(l) * env * n.vel, fR.lowpass(r) * env * n.vel, mix, ctx.duck(i, mix.duck))
            }
        }
    }

    // MARK: - Lead synth

    static func lead(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix) {
        let sr = ctx.sr
        let grit = ctx.grit
        let drive = 1.1 + 1.5 * grit
        for n in notes {
            let f = Float(ctx.tuning.frequency(semis: n.semis))
            let (start, durS, total) = span(n, ctx, release: 0.14)
            var pA: Float = 0
            var pB: Float = 0.25
            var pC: Float = 0.5
            var filt = SVF()
            let fc0 = 900 + 2500 * grit
            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) / sr
                let vib = 1 + 0.008 * sin(twoPi * 5.4 * t) * smoothstep((t - 0.2) / 0.3)
                let dtA = f * vib / sr
                let dtB = f * 1.0058 * vib / sr
                if k & 7 == 0 {
                    let cutoff = fc0 + (6500 - fc0) * exp(-t / 0.18)
                    filt.set(cutoff: cutoff, q: 1.4, sr: sr)
                }
                let s = (sawBL(pA, dtA) + sawBL(pB, dtB)) * 0.5 + squareBL(pC, dtA, 0.35) * 0.3
                advance(&pA, dtA)
                advance(&pB, dtB)
                advance(&pC, dtA)
                let y = filt.lowpass(softClip(s * drive)) * 0.9
                let env = adsrLevel(t, durS, 0.006, 0.12, 0.75, 0.14)
                ctx.bus.add(i, y * env * n.vel, mix, ctx.duck(i, mix.duck))
            }
        }
    }

    // MARK: - Electric piano (2-operator FM)

    static func piano(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix) {
        let sr = ctx.sr
        for (ni, n) in notes.enumerated() {
            let f = Float(ctx.tuning.frequency(semis: n.semis))
            let (start, durS, total0) = span(n, ctx, release: 0.25)
            let total = max(total0, Int(1.2 * sr))
            let tau = clampf(1.9 - f / 1000, 0.5, 1.9)
            var pc: Float = 0
            var pm: Float = 0
            var pm2: Float = 0
            let dt = f / sr
            let dt2 = 14 * f / sr
            let pan = (Float((ni * 7) % 5) - 2) * 0.08
            let m = mix.with(pan: pan)
            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) / sr
                let i1 = 1.6 * n.vel * exp(-t / 0.45) + 0.25
                let i2 = 0.5 * n.vel * exp(-t / 0.03)
                let phase = twoPi * pc + i1 * sin(twoPi * pm) + i2 * sin(twoPi * pm2)
                let y = sin(phase)
                advance(&pc, dt)
                advance(&pm, dt)
                advance(&pm2, dt2)
                var env = exp(-t / tau) * min(1, t / 0.002)
                if t > durS + 0.1 { env *= max(0, 1 - (t - durS - 0.1) / 0.25) }
                ctx.bus.add(i, y * env * n.vel * 0.8, m, ctx.duck(i, m.duck))
            }
        }
    }

    // MARK: - Plucked synth (used for the "Pluck" and "Arpeggio" instruments)

    static func pluckSynth(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix, decay: Float, cutoffBase: Float, panSpread: Float) {
        let sr = ctx.sr
        let grit = ctx.grit
        for (ni, n) in notes.enumerated() {
            let f = Float(ctx.tuning.frequency(semis: n.semis))
            let start = max(0, ctx.frame(beat: n.beat))
            let durS = Float(n.dur * ctx.spb)
            let ring = max(durS + 0.1, decay * 3.2)
            let total = max(1, Int(ring * sr))
            let dtA = f / sr
            let dtB = f * 1.004 / sr
            var pA: Float = 0
            var pB: Float = 0.4
            var filt = SVF()
            let pan = (ni % 2 == 0 ? 1 : -1) * panSpread
            let m = mix.with(pan: pan)
            let drive = 1 + grit * 1.5
            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) / sr
                if k & 3 == 0 {
                    let cutoff = cutoffBase + (1500 + 5500 * n.vel) * exp(-t / 0.1)
                    filt.set(cutoff: cutoff, q: 2.2, sr: sr)
                }
                let s = sawBL(pA, dtA) * 0.6 + sawBL(pB, dtB) * 0.4
                advance(&pA, dtA)
                advance(&pB, dtB)
                let y = filt.lowpass(softClip(s * drive))
                var env = exp(-t / decay) * min(1, t / 0.002)
                let left = total - k
                if left < 300 { env *= Float(left) / 300 }
                ctx.bus.add(i, y * env * n.vel, m, ctx.duck(i, m.duck))
            }
        }
    }

    // MARK: - Guitar (Karplus-Strong string model)

    static func guitar(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix) {
        let sr = ctx.sr
        for (ni, n) in notes.enumerated() {
            let f = Float(ctx.tuning.frequency(semis: n.semis))
            if f < 40 || f > sr * 0.2 { continue }
            let (start, durS, total) = span(n, ctx, release: 0.3)
            let delay = max(2.5, sr / f - 0.5)
            let size = Int(delay) + 4
            let line = UnsafeMutablePointer<Float>.allocate(capacity: size)
            defer { line.deallocate() }
            var noise = Noise(seed: UInt32(truncatingIfNeeded: 9000 + ni * 131 + n.semis * 17))
            var prev: Float = 0
            for j in 0..<size {
                let x = noise.next()
                prev = 0.5 * x + 0.5 * prev
                line[j] = prev
            }
            let tau60 = clampf(2.4 - f / 500, 0.8, 2.4)
            let rho = exp(-6.9078 / (tau60 * f))
            var w = 0
            var dPrev: Float = 0
            var body = SVF(cutoff: 4800, q: 0.7, sr: sr)
            let pan = (Float(ni % 3) - 1) * 0.12
            let m = mix.with(pan: pan)
            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                // read the delay line at a fractional position
                var rd = Float(w) - delay
                while rd < 0 { rd += Float(size) }
                let i0 = Int(rd)
                let fr = rd - Float(i0)
                let a = line[i0 % size]
                let b = line[(i0 + 1) % size]
                let d = a * (1 - fr) + b * fr
                let x = rho * 0.5 * (d + dPrev)
                dPrev = d
                line[w] = x
                w += 1
                if w == size { w = 0 }
                let t = Float(k) / sr
                var env: Float = 1
                if t > durS { env = max(0, 1 - (t - durS) / 0.3) }
                let y = body.lowpass(x) * env * n.vel * 1.4
                ctx.bus.add(i, y, m, ctx.duck(i, m.duck))
            }
        }
    }

    // MARK: - Bells (FM)

    static func bells(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix) {
        let sr = ctx.sr
        for (ni, n) in notes.enumerated() {
            let f = Float(ctx.tuning.frequency(semis: n.semis))
            if f > sr * 0.2 { continue }
            let start = max(0, ctx.frame(beat: n.beat))
            let total = Int(3.5 * sr)
            var pc: Float = 0
            var pm: Float = 0
            var pp: Float = 0
            let dt = f / sr
            let dtm = 3.5 * f / sr
            let dtp = 2.756 * f / sr
            let pan = Float((ni * 13) % 7 - 3) * 0.18
            let m = mix.with(pan: pan)
            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) / sr
                let idx = 2.2 * n.vel * exp(-t / 0.8) + 0.15
                let y = sin(twoPi * pc + idx * sin(twoPi * pm)) * exp(-t / 1.5)
                    + 0.25 * sin(twoPi * pp) * exp(-t / 0.6)
                advance(&pc, dt)
                advance(&pm, dtm)
                advance(&pp, dtp)
                var env = min(1, t / 0.001)
                let left = total - k
                if left < 20000 { env *= Float(left) / 20000 }
                ctx.bus.add(i, y * env * n.vel * 0.7, m, ctx.duck(i, m.duck))
            }
        }
    }
}
