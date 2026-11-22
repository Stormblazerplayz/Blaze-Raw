import Foundation

/// The song generator. Give it `SongSettings`, get back stereo audio.
/// Everything runs on the device, offline - no internet and no downloaded AI model needed.
public enum SongEngine {
    public static let sampleRate = 44100

    /// Renders a song.
    /// - Parameters:
    ///   - progress: called with a number from 0 to 1 while rendering (from the rendering thread).
    ///   - isCancelled: return `true` to stop early (the function then returns `nil`).
    public static func render(_ input: SongSettings,
                              progress: ((Double) -> Void)? = nil,
                              isCancelled: (() -> Bool)? = nil) -> RenderedSong? {
        let plan = Composer.makePlan(input)
        let s = plan.settings
        let sr = Float(sampleRate)
        let spb = 60.0 / s.tempo
        let bodyFrames = Int((Double(plan.totalBars * 4) * spb * Double(sr)).rounded())
        let tailFrames = Int(3.5 * Double(sr))
        let ctx = RenderContext(sr: sr, bpm: s.tempo, frames: bodyFrames + tailFrames, bodyFrames: bodyFrames,
                                tuning: plan.tuning, grit: Float(s.grit), intensity: Float(s.intensity))
        let p = plan.profile
        let pal = p.palette
        let fx = p.fx
        let duck = p.duck
        let revAmt = 0.25 + 0.35 * p.reverb
        let grit = Float(s.grit)
        let intensity = Float(s.intensity)

        // Every patch is balanced against the original ("classic") sound of its instrument, so the
        // mix stays even whatever character a song picks.
        let classic = Palette.classic()
        let unit = Mix(gain: 1)
        // Section tiers for pads and strings: intro, verse, chorus, breakdown, outro.
        let padTiers: [Float] = [0.55, 0.75, 1.0, 0.85, 0.6]
        let stringTiers: [Float] = [0.5, 0.7, 1.0, 0.9, 0.6]

        /// The song's reverb amount applied to an instrument's own send.
        func rv(_ x: Float) -> Float { min(x * fx.sendScale, 1) }

        // The list of jobs, in order. Drums come first because other instruments "duck" around the kick.
        var jobs: [(weight: Double, run: () -> Void)] = []

        if s.instruments.contains(.drums) {
            jobs.append((0.08, {
                let (hits, risers) = plan.drumHits()
                let kicks = DrumRenderer.render(plan: plan, ctx: ctx, hits: hits, risers: risers)
                ctx.buildDuck(kickFrames: kicks)
            }))
        }

        for inst in InstrumentKind.allCases where s.instruments.contains(inst) {
            switch inst {
            case .drums:
                break
            case .subBass:
                jobs.append((0.04, {
                    let trim = Calibration.trim(grit: grit, intensity: intensity, semis: 12, aux: 0,
                                                chosen: { c, n in Synths.bass(n, ctx: c, mix: unit, patch: pal.sub) },
                                                reference: { c, n in Synths.bass(n, ctx: c, mix: unit, patch: classic.sub) })
                    Synths.bass(plan.bassNotes(), ctx: ctx,
                                mix: Mix(gain: 0.33 * trim * pal.sub.gain, duck: duck * 0.8), patch: pal.sub)
                }))
            case .growlBass:
                jobs.append((0.08, {
                    let trim = Calibration.trim(grit: grit, intensity: intensity, semis: 24, aux: 1,
                                                chosen: { c, n in Synths.growl(n, ctx: c, mix: unit, patch: pal.growl) },
                                                reference: { c, n in Synths.growl(n, ctx: c, mix: unit, patch: classic.growl) })
                    Synths.growl(plan.growlNotes(), ctx: ctx,
                                 mix: Mix(gain: 0.30 * trim * pal.growl.gain, duck: duck), patch: pal.growl)
                }))
            case .pad:
                // The song's "chorus" setting adds analog-style drift and width to the pad.
                var padVar = pal.pad
                if fx.padChorus > 0.05 {
                    padVar.drift = max(padVar.drift, fx.padChorus * 14)
                    padVar.spread = max(padVar.spread, 0.7 + 0.3 * fx.padChorus)
                    padVar.voices = max(padVar.voices, 3)
                }
                let padPatch = padVar
                jobs.append((0.12, {
                    let trim = Calibration.trim(grit: grit, intensity: intensity, semis: 36, aux: 2,
                                                chosen: { c, n in Synths.poly(n, ctx: c, mix: unit, patch: padPatch, tiers: padTiers) },
                                                reference: { c, n in Synths.poly(n, ctx: c, mix: unit, patch: classic.pad, tiers: padTiers) })
                    Synths.poly(plan.padNotes(), ctx: ctx,
                                mix: Mix(gain: 0.24 * trim * padPatch.gain, reverb: rv(revAmt), duck: duck),
                                patch: padPatch, tiers: padTiers)
                }))
            case .strings:
                jobs.append((0.14, {
                    let trim = Calibration.trim(grit: grit, intensity: intensity, semis: 40, aux: 2,
                                                chosen: { c, n in Synths.poly(n, ctx: c, mix: unit, patch: pal.strings, tiers: stringTiers) },
                                                reference: { c, n in Synths.poly(n, ctx: c, mix: unit, patch: classic.strings, tiers: stringTiers) })
                    Synths.poly(plan.stringNotes(), ctx: ctx,
                                mix: Mix(gain: 0.15 * trim * pal.strings.gain, reverb: rv(revAmt + 0.1), duck: duck * 0.8),
                                patch: pal.strings, tiers: stringTiers)
                }))
            case .lead:
                jobs.append((0.06, {
                    let trim = Calibration.trim(grit: grit, intensity: intensity, semis: 48, aux: 0,
                                                chosen: { c, n in Synths.poly(n, ctx: c, mix: unit, patch: pal.lead) },
                                                reference: { c, n in Synths.poly(n, ctx: c, mix: unit, patch: classic.lead) })
                    Synths.poly(plan.leadNotes(), ctx: ctx,
                                mix: Mix(gain: 0.22 * trim * pal.lead.gain, reverb: rv(0.2), delay: 0.3, duck: duck * 0.5),
                                patch: pal.lead)
                }))
            case .piano:
                jobs.append((0.06, {
                    let trim = Calibration.trim(grit: grit, intensity: intensity, semis: 34, aux: 0,
                                                chosen: { c, n in Synths.keys(n, ctx: c, mix: unit, patch: pal.keys) },
                                                reference: { c, n in Synths.keys(n, ctx: c, mix: unit, patch: classic.keys) })
                    Synths.keys(plan.pianoNotes(), ctx: ctx,
                                mix: Mix(gain: 0.3 * trim * pal.keys.gain, reverb: rv(revAmt * 0.8), duck: duck * 0.4),
                                patch: pal.keys)
                }))
            case .pluck:
                jobs.append((0.05, {
                    let trim = Calibration.trim(grit: grit, intensity: intensity, semis: 42, aux: 0,
                                                chosen: { c, n in Synths.poly(n, ctx: c, mix: unit, patch: pal.pluck) },
                                                reference: { c, n in Synths.poly(n, ctx: c, mix: unit, patch: classic.pluck) })
                    Synths.poly(plan.pluckNotes(), ctx: ctx,
                                mix: Mix(gain: 0.22 * trim * pal.pluck.gain, reverb: rv(0.2), delay: 0.3, duck: duck * 0.4),
                                patch: pal.pluck)
                }))
            case .guitar:
                jobs.append((0.08, {
                    let trim = Calibration.trim(grit: grit, intensity: intensity, semis: 30, aux: 0,
                                                chosen: { c, n in Synths.guitar(n, ctx: c, mix: unit, patch: pal.guitar) },
                                                reference: { c, n in Synths.guitar(n, ctx: c, mix: unit, patch: classic.guitar) })
                    Synths.guitar(plan.guitarNotes(), ctx: ctx,
                                  mix: Mix(gain: 0.3 * trim * pal.guitar.gain, pan: -0.2, reverb: rv(revAmt * 0.7), duck: duck * 0.3),
                                  patch: pal.guitar)
                }))
            case .bells:
                jobs.append((0.03, {
                    let trim = Calibration.trim(grit: grit, intensity: intensity, semis: 60, aux: 0,
                                                chosen: { c, n in Synths.bells(n, ctx: c, mix: unit, patch: pal.bells) },
                                                reference: { c, n in Synths.bells(n, ctx: c, mix: unit, patch: classic.bells) })
                    Synths.bells(plan.bellNotes(), ctx: ctx,
                                 mix: Mix(gain: 0.16 * trim * pal.bells.gain, reverb: rv(0.55), delay: 0.25),
                                 patch: pal.bells)
                }))
            case .arp:
                jobs.append((0.05, {
                    let trim = Calibration.trim(grit: grit, intensity: intensity, semis: 48, aux: 0,
                                                chosen: { c, n in Synths.poly(n, ctx: c, mix: unit, patch: pal.arp) },
                                                reference: { c, n in Synths.poly(n, ctx: c, mix: unit, patch: classic.arp) })
                    Synths.poly(plan.arpNotes(), ctx: ctx,
                                mix: Mix(gain: 0.28 * trim * pal.arp.gain, reverb: rv(0.2), delay: 0.35, duck: duck * 0.6),
                                patch: pal.arp)
                }))
            }
        }

        for style in VocalStyle.allCases where s.vocals.contains(style) {
            jobs.append((0.1, {
                VoiceSynth.render(plan.vocalEvents(style), ctx: ctx,
                                  mix: SongPlan.vocalMix(style).reverbScaled(by: fx.sendScale))
            }))
        }

        let finishWeight = 0.30   // reverb, echo, lo-fi and mastering
        let totalWeight = jobs.reduce(0.0) { $0 + $1.weight } + finishWeight
        var done = 0.0
        progress?(0)
        for job in jobs {
            if isCancelled?() == true { return nil }
            job.run()
            done += job.weight
            progress?(min(done / totalWeight, 0.99))
        }
        if isCancelled?() == true { return nil }

        // Effects: a reverb (with its own pre-delay) and a tempo-synced ping-pong echo.
        Effects.reverb(send: ctx.bus.rev, frames: ctx.frames, outL: ctx.bus.l, outR: ctx.bus.r,
                       sr: sr, room: fx.room, damping: fx.damping, wet: fx.wet,
                       preDelayFrames: Int(fx.preDelay * sr))
        progress?(min((done + finishWeight * 0.5) / totalWeight, 0.99))
        if isCancelled?() == true { return nil }
        if fx.echoBeats > 0 {
            Effects.pingPongDelay(send: ctx.bus.dly, frames: ctx.frames, outL: ctx.bus.l, outR: ctx.bus.r,
                                  delayFrames: Int(fx.echoBeats * spb * Double(sr)),
                                  feedback: fx.echoFeedback, damp: fx.echoDamp, gain: fx.echoGain)
        }

        // Worn-tape character for lo-fi and chillwave songs.
        if fx.usesLoFi {
            LoFi.process(l: ctx.bus.l, r: ctx.bus.r, frames: ctx.frames, sr: sr,
                         cutoff: fx.lofiCutoff, bitHold: fx.bitHold, bits: fx.bits, wowMs: fx.wow)
        }

        master(ctx: ctx, spec: p.master)

        // Vinyl crackle goes on top of the finished mix (and stops before the final fade-out ends).
        if fx.crackle > 0 {
            let fadeFrames = min(Int(2.5 * sr), ctx.frames)
            Effects.addCrackle(l: ctx.bus.l, r: ctx.bus.r, frames: max(0, ctx.frames - fadeFrames),
                               sr: sr, level: fx.crackle)
        }
        progress?(1)

        let n = ctx.frames
        let left = Array(UnsafeBufferPointer(start: ctx.bus.l, count: n))
        let right = Array(UnsafeBufferPointer(start: ctx.bus.r, count: n))
        return RenderedSong(left: left, right: right, sampleRate: sampleRate,
                            title: Titles.make(genre: s.genre, mood: s.mood, seed: s.seed),
                            keyName: SongSettings.keyNames[plan.key],
                            scaleName: p.scale.displayName,
                            bars: plan.totalBars,
                            settings: s,
                            genreTitle: s.genre?.title ?? "Open",
                            recipe: plan.recipe)
    }

    // MARK: - Mastering

    /// High-pass, tone, width, loudness, gentle tape saturation, then a soft limiter.
    private static func master(ctx: RenderContext, spec: MasterSpec) {
        let n = ctx.frames
        let l = ctx.bus.l
        let r = ctx.bus.r
        let sr = ctx.sr

        // Remove inaudible rumble, add a little "air" on top and warmth below, and set the stereo width.
        let hpCoef = 1 - 2 * Float.pi * spec.lowCut / sr
        let shelf = 1 - exp(-2 * Float.pi * spec.airFreq / sr)
        let warmCoef = 1 - exp(-2 * Float.pi * 160 / sr)
        var xl1: Float = 0, yl1: Float = 0, xr1: Float = 0, yr1: Float = 0
        var airL: Float = 0, airR: Float = 0
        var warmL: Float = 0, warmR: Float = 0
        let width = spec.width
        for i in 0..<n {
            let xl = l[i]
            let yl = xl - xl1 + hpCoef * yl1
            xl1 = xl; yl1 = yl
            airL += shelf * (yl - airL)
            warmL += warmCoef * (yl - warmL)
            var outL = yl + spec.airAmount * (yl - airL) + spec.warmth * warmL

            let xr = r[i]
            let yr = xr - xr1 + hpCoef * yr1
            xr1 = xr; yr1 = yr
            airR += shelf * (yr - airR)
            warmR += warmCoef * (yr - warmR)
            var outR = yr + spec.airAmount * (yr - airR) + spec.warmth * warmR

            if width != 1 {
                let mid = (outL + outR) * 0.5
                let side = (outL - outR) * 0.5 * width
                outL = mid + side
                outR = mid - side
            }
            l[i] = outL
            r[i] = outR
        }

        // Fade in at the start and fade out the reverb tail at the end.
        let fadeIn = Int(0.03 * sr)
        for i in 0..<min(fadeIn, n) {
            let g = Float(i) / Float(fadeIn)
            l[i] *= g
            r[i] *= g
        }
        let fadeOut = min(Int(2.5 * sr), n)
        for k in 0..<fadeOut {
            let x = Float(k) / Float(fadeOut)
            let g = 0.5 + 0.5 * cos(Float.pi * x)
            let i = n - fadeOut + k
            l[i] *= g
            r[i] *= g
        }

        // Loudness: aim for the song's target average level (never letting the peaks run away).
        let body = max(1, min(ctx.bodyFrames, n))
        func measure() -> (rms: Float, peak: Float) {
            var sum: Double = 0
            var peak: Float = 0
            for i in 0..<body {
                let a = l[i], b = r[i]
                sum += Double(a * a + b * b) * 0.5
                peak = max(peak, abs(a), abs(b))
            }
            if body < n {
                for i in body..<n { peak = max(peak, abs(l[i]), abs(r[i])) }
            }
            return (Float((sum / Double(body)).squareRoot()), peak)
        }
        let first = measure()
        var gain: Float = first.rms > 1e-6 ? spec.targetRMS / first.rms : 1
        if first.peak > 1e-6 { gain = min(gain, 1.6 / first.peak) }

        // Gentle tape-style saturation (small signals pass unchanged, peaks are rounded off).
        let sat = spec.saturation
        let drive: Float = 1 + 1.1 * sat
        let saturate = sat > 0.001
        for i in 0..<n {
            var a = l[i] * gain
            var b = r[i] * gain
            if saturate {
                a = softClip(a * drive) / drive
                b = softClip(b * drive) / drive
            }
            l[i] = a
            r[i] = b
        }
        var regain: Float = 1
        if saturate {
            let second = measure()
            if second.rms > 1e-6 { regain = min(max(spec.targetRMS / second.rms, 1), 1.6) }
        }

        // Soft limiter: below the knee nothing changes, above it peaks bend smoothly towards the ceiling.
        let knee: Float = 0.17
        let threshold = spec.ceiling - knee
        @inline(__always) func limit(_ x: Float) -> Float {
            let a = abs(x)
            if a <= threshold { return x }
            let o = threshold + knee * tanh((a - threshold) / knee)
            return x < 0 ? -o : o
        }
        for i in 0..<n {
            l[i] = min(max(limit(l[i] * regain), -0.98), 0.98)
            r[i] = min(max(limit(r[i] * regain), -0.98), 0.98)
        }
    }
}

// MARK: - Level matching

/// Measures how loud a patch is on a short test note and compares it with the original ("classic")
/// patch of the same instrument, so every character ends up equally loud in the mix.
private enum Calibration {
    /// The factor to multiply `chosen` by so that it is as loud as `reference` on the same test note.
    static func trim(grit: Float, intensity: Float, semis: Int, aux: Int,
                     chosen: (RenderContext, [NoteEvent]) -> Void,
                     reference: (RenderContext, [NoteEvent]) -> Void) -> Float {
        let notes = [NoteEvent(beat: 0, dur: 2, semis: semis, vel: 0.9, aux: aux)]
        let a = measure(grit: grit, intensity: intensity, notes: notes, render: chosen)
        let b = measure(grit: grit, intensity: intensity, notes: notes, render: reference)
        guard a > 1e-5, b > 1e-5 else { return 1 }
        return min(max(b / a, 0.3), 3.0)
    }

    /// RMS (both channels) of the first second of one test note (2 beats at 120 BPM).
    private static func measure(grit: Float, intensity: Float, notes: [NoteEvent],
                                render: (RenderContext, [NoteEvent]) -> Void) -> Float {
        let sr: Float = 44100
        let frames = Int(sr * 1.6)
        let ctx = RenderContext(sr: sr, bpm: 120, frames: frames, bodyFrames: frames,
                                tuning: TuningSystem(tonicHz: midiToHz(24), just: false),
                                grit: grit, intensity: intensity)
        render(ctx, notes)
        let n = Int(sr)
        var sum: Double = 0
        for i in 0..<n {
            let a = Double(ctx.bus.l[i])
            let b = Double(ctx.bus.r[i])
            sum += (a * a + b * b) * 0.5
        }
        return Float((sum / Double(n)).squareRoot())
    }
}
