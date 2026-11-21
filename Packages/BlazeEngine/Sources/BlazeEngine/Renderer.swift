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
        let duck = p.duck
        let revAmt = 0.25 + 0.35 * p.reverb

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
                    Synths.subBass(plan.bassNotes(), ctx: ctx, mix: Mix(gain: 0.33, duck: duck * 0.8))
                }))
            case .growlBass:
                jobs.append((0.08, {
                    Synths.growl(plan.growlNotes(), ctx: ctx, mix: Mix(gain: 0.30, duck: duck))
                }))
            case .pad:
                jobs.append((0.12, {
                    Synths.pad(plan.padNotes(), ctx: ctx, mix: Mix(gain: 0.24, reverb: revAmt, duck: duck),
                               brightness: p.brightness)
                }))
            case .strings:
                jobs.append((0.14, {
                    Synths.strings(plan.stringNotes(), ctx: ctx,
                                   mix: Mix(gain: 0.15, reverb: revAmt + 0.1, duck: duck * 0.8),
                                   brightness: p.brightness)
                }))
            case .lead:
                jobs.append((0.06, {
                    Synths.lead(plan.leadNotes(), ctx: ctx,
                                mix: Mix(gain: 0.22, reverb: 0.2, delay: 0.3, duck: duck * 0.5))
                }))
            case .piano:
                jobs.append((0.06, {
                    Synths.piano(plan.pianoNotes(), ctx: ctx,
                                 mix: Mix(gain: 0.3, reverb: revAmt * 0.8, duck: duck * 0.4))
                }))
            case .pluck:
                jobs.append((0.05, {
                    Synths.pluckSynth(plan.pluckNotes(), ctx: ctx,
                                      mix: Mix(gain: 0.22, reverb: 0.2, delay: 0.3, duck: duck * 0.4),
                                      decay: 0.22, cutoffBase: 500, panSpread: 0.35)
                }))
            case .guitar:
                jobs.append((0.08, {
                    Synths.guitar(plan.guitarNotes(), ctx: ctx,
                                  mix: Mix(gain: 0.3, pan: -0.2, reverb: revAmt * 0.7, duck: duck * 0.3))
                }))
            case .bells:
                jobs.append((0.03, {
                    Synths.bells(plan.bellNotes(), ctx: ctx, mix: Mix(gain: 0.16, reverb: 0.55, delay: 0.25))
                }))
            case .arp:
                jobs.append((0.05, {
                    Synths.pluckSynth(plan.arpNotes(), ctx: ctx,
                                      mix: Mix(gain: 0.28, reverb: 0.2, delay: 0.35, duck: duck * 0.6),
                                      decay: 0.13, cutoffBase: 900, panSpread: 0.5)
                }))
            }
        }

        for style in VocalStyle.allCases where s.vocals.contains(style) {
            jobs.append((0.1, {
                VoiceSynth.render(plan.vocalEvents(style), ctx: ctx, mix: SongPlan.vocalMix(style))
            }))
        }

        let finishWeight = 0.30   // reverb, echo and mastering
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

        // Effects: reverb and a dotted-eighth ping-pong echo.
        Effects.reverb(send: ctx.bus.rev, frames: ctx.frames, outL: ctx.bus.l, outR: ctx.bus.r,
                       sr: sr, room: p.reverb, damping: 0.35, wet: 2.2)
        progress?(min((done + finishWeight * 0.5) / totalWeight, 0.99))
        if isCancelled?() == true { return nil }
        Effects.pingPongDelay(send: ctx.bus.dly, frames: ctx.frames, outL: ctx.bus.l, outR: ctx.bus.r,
                              delayFrames: Int(0.75 * spb * Double(sr)), feedback: 0.42, damp: 0.35, gain: 0.8)

        master(ctx: ctx)
        progress?(1)

        let n = ctx.frames
        let left = Array(UnsafeBufferPointer(start: ctx.bus.l, count: n))
        let right = Array(UnsafeBufferPointer(start: ctx.bus.r, count: n))
        return RenderedSong(left: left, right: right, sampleRate: sampleRate,
                            title: makeTitle(mood: s.mood, seed: s.seed),
                            keyName: SongSettings.keyNames[plan.key],
                            scaleName: p.scale.displayName,
                            bars: plan.totalBars,
                            settings: s)
    }

    // MARK: - Mastering

    private static func master(ctx: RenderContext) {
        let n = ctx.frames
        let l = ctx.bus.l
        let r = ctx.bus.r
        let sr = ctx.sr

        // Remove inaudible rumble (high-pass at about 25 Hz).
        let hpCoef = 1 - 2 * Float.pi * 25 / sr
        // A gentle "air" shelf adds about 3 dB of sparkle above roughly 6 kHz.
        let shelf = 1 - exp(-2 * Float.pi * 6000 / sr)
        var xl1: Float = 0, yl1: Float = 0, xr1: Float = 0, yr1: Float = 0
        var sl: Float = 0, sr1: Float = 0
        for i in 0..<n {
            let xl = l[i]
            let yl = xl - xl1 + hpCoef * yl1
            xl1 = xl; yl1 = yl
            sl += shelf * (yl - sl)
            l[i] = yl + 0.4 * (yl - sl)
            let xr = r[i]
            let yr = xr - xr1 + hpCoef * yr1
            xr1 = xr; yr1 = yr
            sr1 += shelf * (yr - sr1)
            r[i] = yr + 0.4 * (yr - sr1)
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

        // Loudness: aim for a healthy average level, then softly limit the peaks.
        var sum: Double = 0
        var peak: Float = 0
        let body = max(1, min(ctx.bodyFrames, n))
        for i in 0..<body {
            let a = l[i], b = r[i]
            sum += Double(a * a + b * b) * 0.5
            peak = max(peak, abs(a), abs(b))
        }
        for i in body..<n { peak = max(peak, abs(l[i]), abs(r[i])) }
        let rms = Float((sum / Double(body)).squareRoot())
        let targetRMS: Float = 0.2
        var gain = rms > 1e-6 ? targetRMS / rms : 1
        if peak > 1e-6 { gain = min(gain, 1.6 / peak) }

        @inline(__always) func limit(_ x: Float) -> Float {
            let a = abs(x)
            if a <= 0.8 { return x }
            let o = 0.8 + 0.17 * tanh((a - 0.8) / 0.17)
            return x < 0 ? -o : o
        }
        for i in 0..<n {
            l[i] = min(max(limit(l[i] * gain), -0.98), 0.98)
            r[i] = min(max(limit(r[i] * gain), -0.98), 0.98)
        }
    }

    // MARK: - Titles

    static func makeTitle(mood: Mood, seed: UInt64) -> String {
        var g = SeededRNG(seed: seed).fork(777)
        let adjectives: [String]
        let nouns: [String]
        switch mood {
        case .dark:
            adjectives = ["Midnight", "Obsidian", "Static", "Hollow", "Shadow", "Neon"]
            nouns = ["Signal", "Echo", "Voltage", "Circuit", "Pulse", "Drift"]
        case .happy:
            adjectives = ["Sunny", "Golden", "Bright", "Bouncy", "Sparkling", "Lucky"]
            nouns = ["Morning", "Parade", "Skyline", "Summer", "Smile", "Groove"]
        case .chill:
            adjectives = ["Lazy", "Velvet", "Cozy", "Mellow", "Soft", "Slow"]
            nouns = ["Sunday", "Rain", "Window", "Coffee", "Tape", "Lounge"]
        case .energetic:
            adjectives = ["Turbo", "Electric", "Rapid", "Wild", "Blazing", "Hyper"]
            nouns = ["Rush", "Lightning", "Engine", "Sprint", "Spark", "Run"]
        case .sad:
            adjectives = ["Quiet", "Faded", "Blue", "Lonely", "Distant", "Grey"]
            nouns = ["Rain", "Letter", "Memory", "Goodbye", "Evening", "Tears"]
        case .dreamy:
            adjectives = ["Floating", "Pastel", "Cloudy", "Lucid", "Silver", "Gentle"]
            nouns = ["Dream", "Horizon", "Aurora", "Lagoon", "Orbit", "Haze"]
        case .epic:
            adjectives = ["Rising", "Mighty", "Eternal", "Final", "Golden", "Thunder"]
            nouns = ["Empire", "Voyage", "Legend", "Summit", "Dawn", "Crown"]
        case .raw:
            adjectives = ["Raw", "Crushed", "Savage", "Molten", "Feral", "Rusty"]
            nouns = ["Power", "Fury", "Engine", "Rage", "Metal", "Fire"]
        }
        let number = g.int(100...999)
        return "\(g.pick(adjectives)) \(g.pick(nouns)) #\(number)"
    }
}
