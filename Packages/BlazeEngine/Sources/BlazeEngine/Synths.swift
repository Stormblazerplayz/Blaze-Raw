import Foundation

/// The sound makers. Each one turns a list of notes plus a patch (see Patches.swift) into audio and
/// adds it to the mix bus. All of them are deterministic: the same notes and patch give the same audio.
///
/// A few rules every voice follows so notes never click:
///   * a fast attack of at least a few milliseconds (it never starts at full level),
///   * a release of at least 20 to 30 ms after the note ends,
///   * filters are updated once per block of 16 samples, not per sample (fast and still smooth).
enum Synths {
    private static let twoPi = 2 * Float.pi

    // MARK: - Generic unison synth (pads, strings, leads, arps, plucks)

    /// - Parameters:
    ///   - tiers: optional loudness/brightness steps per section kind (index = `NoteEvent.aux`), used by
    ///     pads and strings so that intros are darker and choruses brighter.
    static func poly(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix, patch: SynthPatch, tiers: [Float]? = nil) {
        let sr = ctx.sr
        let invSr = 1 / sr
        let nv = min(max(patch.voices, 1), 5)
        // The Aloboi Synth sample (if the patch uses it) is played by two readers, one panned left and
        // one right, each following the lowest and the highest unison voice's pitch.
        let sampler: AloboiSample? = patch.sample > 0.001 ? AloboiSample.shared : nil
        let stereo = (nv > 1 || sampler != nil) && patch.spread > 0.01
        // Roughly constant loudness whatever the number of voices (voices add up like random signals).
        let norm: Float = 0.6 / Float(nv).squareRoot()
        let oscGain = patch.oscLevel
        let sampleWidth = clampf(patch.spread, 0, 1)
        let angA = (1 - sampleWidth) * 0.25 * Float.pi
        let angB = (1 + sampleWidth) * 0.25 * Float.pi
        let sampleLevel = patch.sample * 0.5 * 1.4142135
        let sAL = cos(angA) * sampleLevel
        let sAR = sin(angA) * sampleLevel
        let sBL = cos(angB) * sampleLevel
        let sBR = sin(angB) * sampleLevel
        let unstable = patch.unstable

        // Per-voice constants: pitch ratio and stereo gains, from -1 (lowest) to +1 (highest) voice.
        var voiceRatio = [Float](repeating: 1, count: nv)
        var gl = [Float](repeating: norm, count: nv)
        var gr = [Float](repeating: norm, count: nv)
        for v in 0..<nv {
            let pos: Float = nv == 1 ? 0 : (2 * Float(v) / Float(nv - 1) - 1)
            voiceRatio[v] = centsRatio(patch.detune * pos)
            let pan = clampf(patch.spread * pos, -1, 1)
            let a = (pan + 1) * 0.25 * Float.pi
            gl[v] = cos(a) * 1.4142135 * norm
            gr[v] = sin(a) * 1.4142135 * norm
        }

        let driveAmount = patch.drive + patch.gritDrive * ctx.grit
        let useDrive = driveAmount > 1.02
        let attackBase = max(patch.attack, 0.003)
        let rel = max(patch.release, 0.02)
        let tremDepth = clampf(patch.tremolo, 0, 1)
        let tremHz: Float = patch.tremoloSync > 0 ? patch.tremoloSync * Float(ctx.bpm) / 60 : patch.tremoloRate
        let driftRatio = patch.drift * 0.000578
        let percussive = patch.percTau > 0.001
        let percDecay: Float = percussive ? exp(-1 / (patch.percTau * sr)) : 1
        let useSub = patch.sub > 0.001
        let useNoise = patch.noise > 0.001
        let envDecay = max(patch.envDecay, 0.005)
        var noise = Noise(seed: 4242)

        for (ni, n) in notes.enumerated() {
            if n.vel <= 0.001 { continue }
            let f = Float(ctx.tuning.frequency(semis: n.semis, beat: n.beat))
            if !(f > 15) || f > sr * 0.22 { continue }
            let start = max(0, ctx.frame(beat: n.beat))
            if start >= ctx.frames { continue }
            let durS = Float(n.dur * ctx.spb)
            let total: Int
            if percussive {
                let ring = max(min(durS + 0.1, patch.percTau * 6), patch.percTau * 3.2)
                total = max(1, Int(ring * sr))
            } else {
                total = max(1, Int((durS + rel) * sr))
            }
            // A long attack never outlasts the note itself.
            let attack = max(0.003, min(attackBase, durS * 0.4))

            var tierScale: Float = 1
            if let tr = tiers, !tr.isEmpty {
                let tier = tr[min(max(n.aux, 0), tr.count - 1)]
                tierScale = 0.35 + 0.65 * tier
            }
            let keyScale: Float = patch.keyTrack > 0.001 ? pow(f / 261.63, patch.keyTrack) : 1
            let baseCut = (patch.cutoff + patch.gritCut * ctx.grit) * keyScale * tierScale
            let envAmt = patch.envAmount * (1 - patch.velToEnv + patch.velToEnv * n.vel)

            var ph = [Float](repeating: 0, count: nv)
            var dts = [Float](repeating: 0, count: nv)
            for v in 0..<nv {
                ph[v] = Float((v * 37 + ni * 53) % 100) / 100
                dts[v] = f * voiceRatio[v] * invSr
            }
            // Sample readers: source frames per output frame for the note, and a read position for each.
            let sampleStep: Double = sampler?.increment(forHz: f, sr: sr) ?? 0
            let toSample: Double = sampleStep / Double(f * invSr)
            var posA: Double = 0
            var posB: Double = 0
            var stepA = sampleStep
            var stepB = sampleStep
            // Unstable oscillators: a slowly wandering random pitch offset for every voice.
            var wander = [Float](repeating: 0, count: nv)
            var wanderNoise = Noise(seed: UInt32(truncatingIfNeeded: ni &* 7919 &+ 9001))
            let osc2On = patch.mix2 > 0.001 && f * patch.ratio2 < sr * 0.4
            let dt2 = f * patch.ratio2 * invSr
            var ph2 = Float((ni * 29) % 100) / 100
            var phSub: Float = 0
            let dtSub = f * 0.5 * invSr

            var fL = SVF(cutoff: max(baseCut, 40), q: patch.q, sr: sr)
            var fR = SVF(cutoff: max(baseCut, 40), q: patch.q, sr: sr)
            let lfoPhase = Float(ni % 7) * 0.9
            var pw = patch.pulseWidth
            var trem: Float = 1
            var penv: Float = 1
            let placement: Mix = patch.panAlt > 0.001 ? mix.with(pan: (ni % 2 == 0 ? 1 : -1) * patch.panAlt) : mix
            let tailStart = total - 300

            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) * invSr

                if k & 15 == 0 {
                    let tAbs = Float(i) * invSr
                    var vib: Float = 1
                    if patch.vibrato > 0 {
                        vib = 1 + patch.vibrato * smoothstep((t - 0.18) / 0.4) * sin(twoPi * patch.vibratoRate * t)
                    }
                    for v in 0..<nv {
                        var m = voiceRatio[v] * vib
                        if driftRatio > 0 {
                            let driftArg = twoPi * (0.19 + 0.07 * Float(v)) * tAbs + Float(v) * 1.7 + lfoPhase
                            m *= 1 + driftRatio * sin(driftArg)
                        }
                        if unstable > 0.001 {
                            // Smoothed white noise (about 2 Hz wide) is about 0.026 big, and one cent is a
                            // pitch ratio change of 0.000578, so this wanders by roughly `unstable` cents.
                            wander[v] += (wanderNoise.next() - wander[v]) * 0.004
                            m *= 1 + 0.022 * unstable * wander[v]
                        }
                        dts[v] = f * m * invSr
                    }
                    if sampler != nil {
                        stepA = toSample * Double(dts[0])
                        stepB = toSample * Double(dts[nv - 1])
                    }
                    if patch.pwmDepth > 0 {
                        pw = clampf(patch.pulseWidth + patch.pwmDepth * sin(twoPi * 0.4 * tAbs + lfoPhase), 0.1, 0.9)
                    }
                    var cut = baseCut
                    if patch.lfoDepth > 0 {
                        cut *= 1 + patch.lfoDepth * sin(twoPi * patch.lfoRate * tAbs + lfoPhase)
                    }
                    if envAmt > 0 {
                        cut += envAmt * exp(-t / envDecay)
                    }
                    fL.set(cutoff: cut, q: patch.q, sr: sr)
                    if stereo { fR.set(cutoff: cut, q: patch.q, sr: sr) }
                    if tremDepth > 0 {
                        trem = 1 - tremDepth * (0.5 + 0.5 * sin(twoPi * tremHz * t))
                    }
                }

                var l: Float = 0
                var r: Float = 0
                for v in 0..<nv {
                    let s = oscSample(patch.wave, ph[v], dts[v], pw) * oscGain
                    advance(&ph[v], dts[v])
                    l += s * gl[v]
                    r += s * gr[v]
                }
                if let sp = sampler {
                    let a = sp.read(posA)
                    let b = sp.read(posB)
                    sp.advance(&posA, stepA)
                    sp.advance(&posB, stepB)
                    l += a * sAL + b * sBL
                    r += a * sAR + b * sBR
                }
                if osc2On {
                    let s2 = oscSample(patch.wave2, ph2, dt2, patch.pulseWidth2) * patch.mix2 * 0.6
                    advance(&ph2, dt2)
                    l += s2
                    r += s2
                }
                if useSub {
                    let sb = sin(twoPi * phSub) * patch.sub * 0.5
                    advance(&phSub, dtSub)
                    l += sb
                    r += sb
                }
                if useNoise {
                    let nz = noise.next() * patch.noise * 0.5
                    l += nz
                    r += nz
                }
                if useDrive {
                    l = softClip(l * driveAmount)
                    if stereo { r = softClip(r * driveAmount) }
                }
                let yl = fL.lowpass(l)
                let yr: Float = stereo ? fR.lowpass(r) : yl

                var env: Float
                if percussive {
                    let atk: Float = t < 0.002 ? t / 0.002 : 1
                    env = penv * atk
                    penv *= percDecay
                    if k >= tailStart { env *= Float(total - k) / 300 }
                } else {
                    env = adsrLevel(t, durS, attack, patch.decay, patch.sustain, rel)
                }
                let amp = env * trem * n.vel
                let duckGain = ctx.duck(i, mix.duck)
                if stereo {
                    ctx.bus.addStereo(i, yl * amp, yr * amp, mix, duckGain)
                } else {
                    ctx.bus.add(i, yl * amp, placement, duckGain)
                }
            }
        }
    }

    // MARK: - Bass (sub bass instrument)

    static func bass(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix, patch: BassPatch) {
        let sr = ctx.sr
        let invSr = 1 / sr
        let drive = patch.drive + patch.gritDrive * ctx.grit
        let rel = max(patch.release, 0.03)
        let filtered = patch.kind == .saw || patch.kind == .square || patch.kind == .funk || patch.kind == .tri
            || patch.kind == .reese
        let detuneRatio = centsRatio(patch.detune)
        let envDecay = max(patch.envDecay, 0.01)
        let fmDecay = max(patch.fmDecay, 0.02)

        for n in notes {
            if n.vel <= 0.001 { continue }
            let f0 = Float(ctx.tuning.frequency(semis: n.semis, beat: n.beat))
            if !(f0 > 15) || f0 > sr * 0.2 { continue }
            let start = max(0, ctx.frame(beat: n.beat))
            if start >= ctx.frames { continue }
            let durS = Float(n.dur * ctx.spb)
            let total = max(1, Int((durS + rel) * sr))
            let attack = max(0.003, min(patch.attack, durS * 0.4))

            var p1: Float = 0
            var p2: Float = 0.37
            var p3: Float = 0.71
            var pSub: Float = 0
            var pMod: Float = 0
            var filt = SVF(cutoff: max(patch.cutoff, 40), q: patch.q, sr: sr)
            var pitch: Float = 1
            var dt1 = f0 * invSr
            var dt2 = dt1 * detuneRatio
            var dt3 = dt1 / detuneRatio
            var fmIdx = patch.fmIndex
            let envAmt = patch.envAmount * (0.4 + 0.6 * n.vel)

            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) * invSr

                if k & 15 == 0 {
                    if patch.glide > 0.001 {
                        pitch = pow2(patch.glideSemis * exp(-t / patch.glide) / 12)
                    }
                    dt1 = f0 * pitch * invSr
                    dt2 = dt1 * detuneRatio
                    dt3 = dt1 / detuneRatio
                    if patch.kind == .reese {
                        // The detune breathes in and out (about every 5 seconds, locked to the song's clock
                        // so every note shares the same movement): this is the Reese "phasing" sound.
                        let tSong = Float(i) * invSr
                        let breathing = centsRatio(patch.detune * (1 + 0.5 * sin(twoPi * 0.19 * tSong)))
                        dt2 = dt1 * breathing
                        dt3 = dt1 / breathing
                    }
                    if filtered {
                        filt.set(cutoff: patch.cutoff + envAmt * exp(-t / envDecay), q: patch.q, sr: sr)
                    }
                    if patch.kind == .fm {
                        fmIdx = patch.fmIndex * exp(-t / fmDecay) + 0.15
                    }
                }

                var s: Float
                switch patch.kind {
                case .sine, .e808:
                    s = sin(twoPi * p1)
                    if patch.harmonics > 0 { s += patch.harmonics * sin(2 * twoPi * p1) }
                    advance(&p1, dt1)
                case .saw:
                    s = (sawBL(p1, dt1) + sawBL(p2, dt2)) * 0.5
                    advance(&p1, dt1)
                    advance(&p2, dt2)
                case .square:
                    s = squareBL(p1, dt1, patch.pulseWidth) * 0.8
                    advance(&p1, dt1)
                case .fm:
                    s = sin(twoPi * p1 + fmIdx * sin(twoPi * pMod))
                    advance(&p1, dt1)
                    advance(&pMod, min(dt1 * patch.fmRatio, 0.95))
                case .funk:
                    s = sawBL(p1, dt1) * 0.6 + squareBL(p2, dt2, 0.5) * 0.4
                    advance(&p1, dt1)
                    advance(&p2, dt2)
                case .tri:
                    s = 4 * abs(p1 - 0.5) - 1
                    advance(&p1, dt1)
                case .reese:
                    s = (sawBL(p1, dt1) + sawBL(p2, dt2) + sawBL(p3, dt3)) * 0.42
                    advance(&p1, dt1)
                    advance(&p2, dt2)
                    advance(&p3, dt3)
                }
                if patch.sub > 0 {
                    s += patch.sub * sin(twoPi * pSub)
                    advance(&pSub, dt1 * 0.5)
                }
                let y: Float
                if filtered {
                    y = filt.lowpass(softClip(s * drive))
                } else {
                    y = softClip(s * drive) * 0.8
                }
                let env = adsrLevel(t, durS, attack, patch.decay, patch.sustain, rel)
                ctx.bus.add(i, y * env * n.vel, mix, ctx.duck(i, mix.duck))
            }
        }
    }

    // MARK: - Growl bass: detuned saws, ring-mod "intermodulation", drive and a wobbling filter

    static func growl(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix, patch: GrowlPatch) {
        let sr = ctx.sr
        let grit = ctx.grit
        let mults: [Double] = [1, 2, 3, 4]
        let q = patch.qBase + patch.qGrit * grit
        let driveIn = patch.driveBase + patch.driveGrit * grit
        let ringAmt = patch.ringAmount * grit
        let range = patch.cutoffRange + patch.cutoffRangeGrit * grit
        let samplesPerBeat = ctx.spb * Double(sr)
        let rel = max(patch.release, 0.03)

        for n in notes {
            if n.vel <= 0.001 { continue }
            let f = Float(ctx.tuning.frequency(semis: n.semis, beat: n.beat))
            if !(f > 15) || f > sr * 0.2 { continue }
            let start = max(0, ctx.frame(beat: n.beat))
            if start >= ctx.frames { continue }
            let durS = Float(n.dur * ctx.spb)
            let total = max(1, Int((durS + rel) * sr))
            let attack = max(0.003, min(patch.attack, durS * 0.4))
            let dt1 = f / sr
            let dt2 = f * patch.detune / sr
            let dtSub = f * 0.5 / sr
            let dtRing = f * patch.ringRatio / sr
            var p1: Float = 0
            var p2: Float = 0.3
            var pSub: Float = 0
            var pRing: Float = 0
            var filt = SVF()
            let mult = mults[min(max(n.aux, 0), 3)] * Double(patch.wobbleScale)

            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) / sr
                if k & 7 == 0 {
                    let beatPos = Double(i) / samplesPerBeat
                    let lfo = 0.5 + 0.5 * Float(sin(2.0 * Double.pi * mult * beatPos))
                    let cutoff = patch.cutoffBase + lfo * lfo * range
                    filt.set(cutoff: cutoff, q: q, sr: sr)
                }
                let s1 = sawBL(p1, dt1)
                let s2 = sawBL(p2, dt2)
                let sq = squareBL(pSub, dtSub, 0.5)
                var s = (s1 + s2) * 0.5 + sq * patch.subMix
                s *= 1 + ringAmt * sin(twoPi * pRing)
                advance(&p1, dt1)
                advance(&p2, dt2)
                advance(&pSub, dtSub)
                advance(&pRing, min(dtRing, 0.95))
                var y = softClip(s * driveIn)
                y = filt.lowpass(y)
                y = softClip(y * 1.6) * 0.75
                let env = adsrLevel(t, durS, attack, 0.12, 0.85, rel)
                ctx.bus.add(i, y * env * n.vel, mix, ctx.duck(i, mix.duck))
            }
        }
    }

    // MARK: - Keys (FM electric piano family)

    static func keys(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix, patch: KeysPatch) {
        let sr = ctx.sr
        let invSr = 1 / sr
        let rel = max(patch.release, 0.03)
        let attack = max(patch.attack, 0.002)
        let useSecond = patch.index2 > 0.001
        let useFilter = patch.cutoff > 0
        let useTremolo = patch.tremolo > 0.001
        let useWobble = patch.wobble > 0.001

        for (ni, n) in notes.enumerated() {
            if n.vel <= 0.001 { continue }
            let f = Float(ctx.tuning.frequency(semis: n.semis, beat: n.beat))
            if !(f > 20) || f > sr * 0.2 { continue }
            let start = max(0, ctx.frame(beat: n.beat))
            if start >= ctx.frames { continue }
            let durS = Float(n.dur * ctx.spb)
            let hold = durS + 0.1
            let total = max(1, Int((hold + rel + 0.02) * sr))
            let tau = max(clampf(patch.tauBase - f / patch.tauSlope, patch.tauMin, patch.tauMax), 0.05)

            let dAmp = exp(-1 / (tau * sr))
            let dI1 = exp(-1 / (max(patch.idx1Decay, 0.005) * sr))
            let dI2 = exp(-1 / (max(patch.idx2Decay, 0.005) * sr))
            var amp: Float = 1
            var i1Env = patch.index1 * n.vel
            var i2Env = patch.index2 * n.vel
            var pc: Float = 0
            var pm1: Float = 0
            var pm2: Float = 0
            var dt = f * invSr
            var dtm1 = min(dt * patch.ratio1, 0.95)
            var dtm2 = min(dt * patch.ratio2, 0.95)
            var trem: Float = 1
            var filt = SVF(cutoff: useFilter ? patch.cutoff : 1000, q: patch.q, sr: sr)
            if useFilter { filt.set(cutoff: patch.cutoff, q: patch.q, sr: sr) }
            let m = mix.with(pan: (Float((ni * 7) % 5) - 2) * patch.panStep)

            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) * invSr
                if k & 15 == 0 {
                    if useWobble {
                        let tAbs = Float(i) * invSr
                        let wob = 1 + patch.wobble * 0.000578 * sin(twoPi * patch.wobbleRate * tAbs + Float(ni % 5))
                        dt = f * wob * invSr
                        dtm1 = min(dt * patch.ratio1, 0.95)
                        dtm2 = min(dt * patch.ratio2, 0.95)
                    }
                    if useTremolo {
                        trem = 1 - patch.tremolo * (0.5 + 0.5 * sin(twoPi * patch.tremoloRate * t))
                    }
                }
                let i1 = i1Env + patch.idx1Floor
                var phase = twoPi * pc + i1 * sin(twoPi * pm1)
                if useSecond {
                    phase += i2Env * sin(twoPi * pm2)
                    advance(&pm2, dtm2)
                }
                var y = sin(phase)
                advance(&pc, dt)
                advance(&pm1, dtm1)
                i1Env *= dI1
                i2Env *= dI2

                var env = amp * min(1, t / attack)
                amp *= dAmp
                if t > hold { env *= max(0, 1 - (t - hold) / rel) }
                if useFilter { y = filt.lowpass(y) }
                ctx.bus.add(i, y * env * trem * n.vel * 0.8, m, ctx.duck(i, m.duck))
            }
        }
    }

    // MARK: - The Aloboi piano (a piano played on a retro sound chip, see ChipPianoPatch)

    static func aloPiano(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix, patch: ChipPianoPatch) {
        let sr = ctx.sr
        let invSr = 1 / sr
        let rel = max(patch.release, 0.03)
        let sampler: AloboiSample? = patch.sample > 0.001 ? AloboiSample.shared : nil
        // The three sources are scaled so that together they peak at about 1 (the bit crusher's full scale).
        let srcSum = max(patch.pulse + patch.tri + patch.sample, 0.1)
        let pulseLevel = patch.pulse / srcSum
        let triLevel = patch.tri / srcSum
        let sampleLevel = patch.sample / srcSum * 1.4
        let triSteps = max(patch.triSteps, 2)
        let levels: Float = patch.bits >= 16 ? 0 : Float(1 << (min(max(patch.bits, 3), 15) - 1))
        let hold = max(1, patch.hold)
        // The two copies of every note: A leans left and is tuned a little down, B leans right and up.
        let width = clampf(patch.width, 0, 1)
        let angA = (1 - width) * 0.25 * Float.pi
        let angB = (1 + width) * 0.25 * Float.pi
        let copyLevel: Float = 0.5 * 1.4142135
        let aL = cos(angA) * copyLevel, aR = sin(angA) * copyLevel
        let bL = cos(angB) * copyLevel, bR = sin(angB) * copyLevel
        let ratioA = centsRatio(-0.5 * patch.detune)
        let ratioB = centsRatio(0.5 * patch.detune)
        let thump = clampf(patch.thump, 0, 0.95)
        let thumpTau = max(patch.thumpTau, 0.01)
        let brightTau = max(patch.brightTau, 0.01)
        let useHammer = patch.hammer > 0.001
        let pwmDepth = clampf(patch.pwmDepth, 0, 0.35)
        let pwmHz = patch.pwmRate

        for (ni, n) in notes.enumerated() {
            if n.vel <= 0.001 { continue }
            let f = Float(ctx.tuning.frequency(semis: n.semis, beat: n.beat))
            if !(f > 20) || f > sr * 0.2 { continue }
            let start = max(0, ctx.frame(beat: n.beat))
            if start >= ctx.frames { continue }
            let durS = Float(n.dur * ctx.spb)
            let total = max(1, Int((durS + rel + 0.02) * sr))
            let tau = max(clampf(patch.tauBase - f / patch.tauSlope, patch.tauMin, patch.tauMax), 0.05)
            let dSlow = exp(-1 / (tau * sr))
            let dFast = exp(-1 / (thumpTau * sr))
            let dBright = exp(-1 / (brightTau * sr))
            let dHammer = exp(-1 / (0.008 * sr))
            let strikeHz = patch.strike * (0.5 + 0.5 * n.vel)
            let keepHz = patch.keep * f

            var slow: Float = 1 - thump
            var fast: Float = thump
            var bright: Float = 1
            var hammerEnv: Float = patch.hammer * n.vel
            // Both copies start together (like two piano strings hit by one hammer) and drift apart slowly,
            // so the note is wide but never cancels out when a phone plays both sides through one speaker.
            var phA = Float((ni * 37) % 100) / 100
            var phB = phA
            var dtA = f * ratioA * invSr
            var dtB = f * ratioB * invSr
            let sampleStep: Double = sampler?.increment(forHz: f, sr: sr) ?? 0
            let toSample: Double = sampleStep / Double(f * invSr)
            var posA: Double = 0
            var posB: Double = 0
            var stepA = sampleStep
            var stepB = sampleStep
            var wanderA: Float = 0
            var wanderB: Float = 0
            var wanderNoise = Noise(seed: UInt32(truncatingIfNeeded: ni &* 6151 &+ 17))
            var hammerNoise = Noise(seed: UInt32(truncatingIfNeeded: ni &* 2903 &+ 5))
            var hammerFilter = SVF(cutoff: patch.hammerHz, q: 1.2, sr: sr)
            var fA = SVF(cutoff: keepHz + strikeHz, q: patch.q, sr: sr)
            var fB = SVF(cutoff: keepHz + strikeHz, q: patch.q, sr: sr)
            // The sample is a stack of detuned tones, so it also hums below the note (its loop repeats 20
            // times slower than the note). A high-pass just under the note keeps the piano clean and clear.
            var hpA = SVF(cutoff: f * 0.6, q: 0.7, sr: sr)
            var hpB = SVF(cutoff: f * 0.6, q: 0.7, sr: sr)
            var pwA = patch.pulseWidth
            var pwB = patch.pulseWidth
            let pwmPhase = Float(ni % 9) * 0.7
            var heldA: Float = 0
            var heldB: Float = 0
            var holdCount = 0

            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) * invSr

                if k & 15 == 0 {
                    // Each copy wanders slowly out of tune by itself (about `wander` cents).
                    if patch.wander > 0.001 {
                        wanderA += (wanderNoise.next() - wanderA) * 0.004
                        wanderB += (wanderNoise.next() - wanderB) * 0.004
                        dtA = f * ratioA * (1 + 0.022 * patch.wander * wanderA) * invSr
                        dtB = f * ratioB * (1 + 0.022 * patch.wander * wanderB) * invSr
                        if sampler != nil {
                            stepA = toSample * Double(dtA)
                            stepB = toSample * Double(dtB)
                        }
                    }
                    if pwmDepth > 0 {
                        let tAbs = Float(i) * invSr
                        let s = sin(twoPi * pwmHz * tAbs + pwmPhase)
                        let s2 = sin(twoPi * pwmHz * tAbs + pwmPhase + 1.2)
                        pwA = clampf(patch.pulseWidth + pwmDepth * s, 0.08, 0.92)
                        pwB = clampf(patch.pulseWidth + pwmDepth * s2, 0.08, 0.92)
                    }
                    let cut = keepHz + strikeHz * bright
                    fA.set(cutoff: cut, q: patch.q, sr: sr)
                    fB.set(cutoff: cut, q: patch.q, sr: sr)
                }

                // The chip tone of each copy: pulse wave + stepped triangle + the Aloboi Synth sample.
                // (A pulse wave that is not square has an average level of 2 x width - 1; it is taken away,
                // otherwise every note would push the speaker out and back with a low thump.)
                let triA = (4 * abs(phA - 0.5) - 1)
                let triB = (4 * abs(phB - 0.5) - 1)
                var xA = pulseLevel * (squareBL(phA, dtA, pwA) - (2 * pwA - 1))
                    + triLevel * ((triA * triSteps).rounded() / triSteps)
                var xB = pulseLevel * (squareBL(phB, dtB, pwB) - (2 * pwB - 1))
                    + triLevel * ((triB * triSteps).rounded() / triSteps)
                advance(&phA, dtA)
                advance(&phB, dtB)
                if let sp = sampler {
                    xA += sampleLevel * hpA.highpass(sp.read(posA))
                    xB += sampleLevel * hpB.highpass(sp.read(posB))
                    sp.advance(&posA, stepA)
                    sp.advance(&posB, stepB)
                }

                // Piano brightness: bright at the hammer, then darker.
                var yA = fA.lowpass(xA)
                var yB = fB.lowpass(xB)

                // A little scratch: hold samples and round them to a few bits, like an old sampler chip.
                if hold > 1 {
                    if holdCount == 0 {
                        heldA = yA
                        heldB = yB
                    }
                    holdCount += 1
                    if holdCount >= hold { holdCount = 0 }
                    yA = heldA
                    yB = heldB
                }
                if levels > 0 {
                    yA = (clampf(yA, -1, 1) * levels).rounded() / levels
                    yB = (clampf(yB, -1, 1) * levels).rounded() / levels
                }

                // Hammer click (the same in both ears).
                var click: Float = 0
                if useHammer && hammerEnv > 0.0005 {
                    click = hammerFilter.bandpass(hammerNoise.next()) * hammerEnv
                    hammerEnv *= dHammer
                }

                // Piano loudness: a quick drop after the hammer, then a long fade; let go at the note's end.
                var env = slow + fast
                slow *= dSlow
                fast *= dFast
                bright *= dBright
                if t < 0.0015 { env *= t / 0.0015 }
                if t > durS { env *= max(0, 1 - (t - durS) / rel) }
                let amp = env * n.vel
                let outL = (yA * aL + yB * bL) * amp + click
                let outR = (yA * aR + yB * bR) * amp + click
                ctx.bus.addStereo(i, outL, outR, mix, ctx.duck(i, mix.duck))
            }
        }
    }

    // MARK: - Guitar (Karplus-Strong string model)

    static func guitar(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix, patch: GuitarPatch) {
        let sr = ctx.sr
        let two = patch.detune > 0.01
        for (ni, n) in notes.enumerated() {
            if n.vel <= 0.001 { continue }
            let f = Float(ctx.tuning.frequency(semis: n.semis, beat: n.beat))
            if f < 40 || f > sr * 0.2 { continue }
            let start = max(0, ctx.frame(beat: n.beat))
            if start >= ctx.frames { continue }
            let durS = Float(n.dur * ctx.spb)
            // Short chops are damped quickly so they never ring into the next hit.
            let rel = durS < 0.22 ? min(patch.release, 0.06) : patch.release
            let total = max(1, Int((durS + rel) * sr))
            let panBase = (Float(ni % 3) - 1) * 0.12
            let seed = UInt32(truncatingIfNeeded: 9000 + ni * 131 + n.semis * 17)
            if two {
                let fB = f * centsRatio(patch.detune)
                pluckString(ctx: ctx, mix: mix.with(pan: panBase - patch.spread), patch: patch, f: f,
                            start: start, durS: durS, rel: rel, total: total, seed: seed, vel: n.vel, level: 0.75)
                pluckString(ctx: ctx, mix: mix.with(pan: panBase + patch.spread), patch: patch, f: fB,
                            start: start, durS: durS, rel: rel, total: total, seed: seed &+ 7, vel: n.vel, level: 0.75)
            } else {
                pluckString(ctx: ctx, mix: mix.with(pan: panBase), patch: patch, f: f,
                            start: start, durS: durS, rel: rel, total: total, seed: seed, vel: n.vel, level: 1)
            }
        }
    }

    private static func pluckString(ctx: RenderContext, mix: Mix, patch: GuitarPatch, f: Float,
                                    start: Int, durS: Float, rel: Float, total: Int,
                                    seed: UInt32, vel: Float, level: Float) {
        let sr = ctx.sr
        let delay = max(2.5, sr / f - 0.5)
        let size = Int(delay) + 4
        let line = UnsafeMutablePointer<Float>.allocate(capacity: size)
        defer { line.deallocate() }
        var noise = Noise(seed: seed)
        var prev: Float = 0
        let c = clampf(patch.pickBright, 0.1, 1)
        for j in 0..<size {
            let x = noise.next()
            prev = c * x + (1 - c) * prev
            line[j] = prev
        }
        let tau60 = max(clampf(patch.tauBase - f / patch.tauSlope, patch.tauMin, patch.tauMax) * patch.tauScale, 0.1)
        let rho = exp(-6.9078 / (tau60 * f))
        var w = 0
        var dPrev: Float = 0
        var body = SVF(cutoff: patch.bodyCutoff, q: 0.7, sr: sr)
        let useDrive = patch.drive > 1.01
        // patch.level is 1.4 for the classic guitar (the loudness the first version used).
        let gainOut = patch.level * level * vel
        for k in 0..<total {
            let i = start + k
            if i >= ctx.frames { break }
            // read the delay line at a fractional position
            var rd = Float(w) - delay
            while rd < 0 { rd += Float(size) }
            var i0 = Int(rd)
            if i0 >= size { i0 -= size }
            let fr = rd - Float(i0)
            let i1 = i0 + 1 >= size ? 0 : i0 + 1
            let a = line[i0]
            let b = line[i1]
            let d = a * (1 - fr) + b * fr
            let x = rho * 0.5 * (d + dPrev)
            dPrev = d
            line[w] = x
            w += 1
            if w == size { w = 0 }
            let t = Float(k) / sr
            var env: Float = 1
            if t > durS { env = max(0, 1 - (t - durS) / rel) }
            var y = body.lowpass(x) * env * gainOut
            if useDrive { y = softClip(y * patch.drive) }
            ctx.bus.add(i, y, mix, ctx.duck(i, mix.duck))
        }
    }

    // MARK: - Bells and mallets

    static func bells(_ notes: [NoteEvent], ctx: RenderContext, mix: Mix, patch: BellPatch) {
        let sr = ctx.sr
        let invSr = 1 / sr
        let useP1 = patch.p1Level > 0.001
        let useP2 = patch.p2Level > 0.001 && patch.p2Ratio > 0
        let useTremolo = patch.tremolo > 0.001
        let total = max(1, Int(patch.length * sr))
        let fadeN = max(1, min(20000, total / 3))
        let dIdx = exp(-1 / (max(patch.idxDecay, 0.01) * sr))
        let dAmp = exp(-1 / (max(patch.ampTau, 0.05) * sr))
        let dP1 = exp(-1 / (max(patch.p1Tau, 0.02) * sr))
        let dP2 = exp(-1 / (max(patch.p2Tau, 0.02) * sr))

        for (ni, n) in notes.enumerated() {
            if n.vel <= 0.001 { continue }
            let f = Float(ctx.tuning.frequency(semis: n.semis, beat: n.beat))
            if !(f > 20) || f > sr * 0.2 { continue }
            let start = max(0, ctx.frame(beat: n.beat))
            if start >= ctx.frames { continue }
            var pc: Float = 0
            var pm: Float = 0
            var pp1: Float = 0
            var pp2: Float = 0
            let dt = f * invSr
            let dtm = min(dt * patch.modRatio, 0.95)
            let dtp1 = min(dt * patch.p1Ratio, 0.95)
            let dtp2 = min(dt * patch.p2Ratio, 0.95)
            var idxEnv = patch.modIndex * n.vel
            var ampEnv: Float = 1
            var p1Env: Float = 1
            var p2Env: Float = 1
            var trem: Float = 1
            let pan = Float((ni * 13) % 7 - 3) * 0.18
            let m = mix.with(pan: pan)

            for k in 0..<total {
                let i = start + k
                if i >= ctx.frames { break }
                let t = Float(k) * invSr
                if useTremolo && k & 15 == 0 {
                    trem = 1 - patch.tremolo * (0.5 + 0.5 * sin(twoPi * patch.tremoloRate * t))
                }
                let idx = idxEnv + patch.idxFloor
                var y = sin(twoPi * pc + idx * sin(twoPi * pm)) * ampEnv
                if useP1 {
                    y += patch.p1Level * sin(twoPi * pp1) * p1Env
                    advance(&pp1, dtp1)
                    p1Env *= dP1
                }
                if useP2 {
                    y += patch.p2Level * sin(twoPi * pp2) * p2Env
                    advance(&pp2, dtp2)
                    p2Env *= dP2
                }
                advance(&pc, dt)
                advance(&pm, dtm)
                idxEnv *= dIdx
                ampEnv *= dAmp

                var env = min(1, t / 0.001)
                let left = total - k
                if left < fadeN { env *= Float(left) / Float(fadeN) }
                ctx.bus.add(i, y * env * trem * n.vel * 0.7, m, ctx.duck(i, m.duck))
            }
        }
    }
}
