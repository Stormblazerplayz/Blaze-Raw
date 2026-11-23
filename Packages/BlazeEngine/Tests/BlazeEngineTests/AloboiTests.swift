import Foundation
import XCTest
@testable import BlazeEngine

/// Tests for the "Aloboi sound": the Aloboi piano (a piano played on a retro sound chip), the Aloboi Synth
/// sample, unstable oscillators, the Reese bass and the Alobend chord retuning.
final class AloboiTests: XCTestCase {

    // MARK: helpers

    private func rms(_ x: [Float]) -> Double {
        var sum = 0.0
        for v in x { sum += Double(v) * Double(v) }
        return (sum / Double(max(1, x.count))).squareRoot()
    }

    private func rms(_ s: RenderedSong) -> Double {
        var sum = 0.0
        for i in 0..<s.frameCount {
            let l = Double(s.left[i]), r = Double(s.right[i])
            sum += (l * l + r * r) * 0.5
        }
        return (sum / Double(max(1, s.frameCount))).squareRoot()
    }

    private func peak(_ s: RenderedSong) -> Float {
        var p: Float = 0
        for i in 0..<s.frameCount { p = max(p, abs(s.left[i]), abs(s.right[i])) }
        return p
    }

    private func finite(_ x: [Float]) -> Bool { x.allSatisfy { $0.isFinite } }

    private func render(_ settings: SongSettings, file: StaticString = #filePath, line: UInt = #line) -> RenderedSong {
        guard let song = SongEngine.render(settings) else {
            XCTFail("render returned nil", file: file, line: line)
            fatalError("render failed")
        }
        return song
    }

    private func checkHealthy(_ s: RenderedSong, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(s.durationSeconds, 60, "\(label): shorter than one minute", file: file, line: line)
        for i in 0..<s.frameCount where !s.left[i].isFinite || !s.right[i].isFinite {
            XCTFail("\(label): NaN or infinity at frame \(i)", file: file, line: line)
            break
        }
        XCTAssertLessThanOrEqual(peak(s), 1.0, "\(label): clips", file: file, line: line)
        XCTAssertGreaterThan(rms(s), 0.02, "\(label): nearly silent", file: file, line: line)
    }

    /// Plays one note of a patch through the generic synth and returns the left channel.
    private func playNote(_ patch: SynthPatch, semis: Int, beats: Double = 4, seconds: Double = 3) -> [Float] {
        let sr: Float = 44100
        let frames = Int(Double(sr) * seconds)
        let ctx = RenderContext(sr: sr, bpm: 120, frames: frames, bodyFrames: frames,
                                tuning: TuningSystem(tonicHz: midiToHz(24), just: false), grit: 0.5, intensity: 0.7)
        Synths.poly([NoteEvent(beat: 0, dur: beats, semis: semis, vel: 0.9)], ctx: ctx, mix: Mix(gain: 1), patch: patch)
        return (0..<frames).map { ctx.bus.l[$0] }
    }

    /// Plays one note on the Aloboi piano and returns both channels.
    private func playPiano(_ patch: ChipPianoPatch, semis: Int, beats: Double = 3,
                           seconds: Double = 2.5) -> (l: [Float], r: [Float]) {
        let sr: Float = 44100
        let frames = Int(Double(sr) * seconds)
        let ctx = RenderContext(sr: sr, bpm: 120, frames: frames, bodyFrames: frames,
                                tuning: TuningSystem(tonicHz: midiToHz(24), just: false), grit: 0.5, intensity: 0.7)
        Synths.aloPiano([NoteEvent(beat: 0, dur: beats, semis: semis, vel: 0.9)], ctx: ctx, mix: Mix(gain: 1),
                        patch: patch)
        return ((0..<frames).map { ctx.bus.l[$0] }, (0..<frames).map { ctx.bus.r[$0] })
    }

    private func rms(_ x: [Float], from a: Int, to b: Int) -> Double {
        rms(Array(x[max(0, a)..<min(b, x.count)]))
    }

    /// Plays one note of a bass patch and returns the left channel.
    private func playBass(_ patch: BassPatch, semis: Int, beats: Double = 4) -> [Float] {
        let sr: Float = 44100
        let frames = Int(sr * 3)
        let ctx = RenderContext(sr: sr, bpm: 120, frames: frames, bodyFrames: frames,
                                tuning: TuningSystem(tonicHz: midiToHz(24), just: false), grit: 0.5, intensity: 0.7)
        Synths.bass([NoteEvent(beat: 0, dur: beats, semis: semis, vel: 0.9)], ctx: ctx, mix: Mix(gain: 1), patch: patch)
        return (0..<frames).map { ctx.bus.l[$0] }
    }

    /// In-place radix-2 FFT (the size must be a power of two).
    private func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
        }
        var len = 2
        while len <= n {
            let ang = -2 * Double.pi / Double(len)
            let wr = cos(ang)
            let wi = sin(ang)
            var i = 0
            while i < n {
                var cr = 1.0
                var ci = 0.0
                let half = len / 2
                for k in 0..<half {
                    let ur = re[i + k]
                    let ui = im[i + k]
                    let xr = re[i + k + half]
                    let xi = im[i + k + half]
                    let vr = xr * cr - xi * ci
                    let vi = xr * ci + xi * cr
                    re[i + k] = ur + vr
                    im[i + k] = ui + vi
                    re[i + k + half] = ur - vr
                    im[i + k + half] = ui - vi
                    let ncr = cr * wr - ci * wi
                    ci = cr * wi + ci * wr
                    cr = ncr
                }
                i += len
            }
            len <<= 1
        }
    }

    /// The frequency (Hz) of the strongest spectral peak between `low` and `high` Hz, in a 32768-sample window
    /// (44.1 kHz audio, so about 1.3 Hz per bin).
    private func strongestPeak(_ x: [Float], from start: Int, low: Double, high: Double) -> Double {
        let size = 32768
        var re = [Double](repeating: 0, count: size)
        var im = [Double](repeating: 0, count: size)
        for k in 0..<size {
            let w = 0.5 - 0.5 * cos(2 * Double.pi * Double(k) / Double(size - 1))
            re[k] = Double(x[start + k]) * w
        }
        fft(&re, &im)
        var bestBin = 1
        var bestPower = 0.0
        for b in 1..<(size / 2) {
            let hz = Double(b) * 44100.0 / Double(size)
            if hz < low || hz > high { continue }
            let power = re[b] * re[b] + im[b] * im[b]
            if power > bestPower {
                bestPower = power
                bestBin = b
            }
        }
        return Double(bestBin) * 44100.0 / Double(size)
    }

    // MARK: the sample

    func testTheAloboiSynthSampleLoadsCorrectly() {
        let s = AloboiSample.shared
        XCTAssertEqual(s.frames.count, 86881, "the sample is kept up to the end of its loop")
        XCTAssertEqual(s.loopStart, 83169)
        XCTAssertEqual(s.loopEnd, 86881)
        XCTAssertEqual(s.loopLength, 3712)
        XCTAssertEqual(s.rate, 48000)
        // 20 cycles of the main pitch fit into the loop: 20 * 48000 / 3712 Hz.
        XCTAssertEqual(s.rootHz, 258.62, accuracy: 0.01)
        XCTAssertTrue(finite(s.frames))
        XCTAssertLessThanOrEqual(s.frames.map { abs($0) }.max() ?? 2, 1.0)
        // Measured when the sample was added: the RMS of the whole sample is 0.218.
        XCTAssertGreaterThan(rms(s.frames), 0.15)
        XCTAssertLessThan(rms(s.frames), 0.3)
    }

    func testTheSampleLoopsSmoothly() {
        let s = AloboiSample.shared
        // Play across the loop point several times, at a few different speeds.
        for step in [0.31, 0.5, 1.0, 2.7] {
            var pos = Double(s.loopEnd) - 1500
            var prev = s.read(pos)
            var biggestJump: Float = 0
            var inside = true
            for _ in 0..<20000 {
                s.advance(&pos, step)
                if !(pos >= 0 && pos < Double(s.loopEnd)) { inside = false }
                let v = s.read(pos)
                biggestJump = max(biggestJump, abs(v - prev))
                prev = v
            }
            XCTAssertTrue(inside, "step \(step): the read position left the sample")
            // The loop point jumps no more than the sample itself does in other places.
            XCTAssertLessThan(Double(biggestJump), 0.28 * max(step, 1) + 0.05, "step \(step): click at the loop point")
        }
    }

    func testTheSampleSpeedFollowsThePitch() {
        let s = AloboiSample.shared
        let sr: Float = 44100
        let atRoot = s.increment(forHz: Float(s.rootHz), sr: sr)
        XCTAssertEqual(atRoot, 48000.0 / 44100.0, accuracy: 1e-5)
        XCTAssertEqual(s.increment(forHz: Float(s.rootHz) * 2, sr: sr), 2 * atRoot, accuracy: 1e-4)
        XCTAssertEqual(s.increment(forHz: Float(s.rootHz) / 2, sr: sr), atRoot / 2, accuracy: 1e-4)
        // Far too high or too low: folded by octaves, so it never aliases badly and never crawls.
        XCTAssertEqual(s.increment(forHz: Float(s.rootHz) * 8, sr: sr), 4 * atRoot, accuracy: 1e-3)
        XCTAssertEqual(s.increment(forHz: Float(s.rootHz) / 8, sr: sr), 0.5 * atRoot, accuracy: 1e-3)
        for hz in [20, 55, 110, 220, 440, 880, 1760, 3520, 7040] as [Float] {
            let inc = s.increment(forHz: hz, sr: sr)
            XCTAssertGreaterThan(inc, 0.25 * 48000 / 44100, "\(hz) Hz")
            XCTAssertLessThan(inc, 4.6 * 48000 / 44100, "\(hz) Hz")
        }
        XCTAssertEqual(s.increment(forHz: 0, sr: sr), 0)
        XCTAssertEqual(s.increment(forHz: -5, sr: sr), 0)
    }

    func testASamplePatchPlaysAtThePitchOfTheNote() {
        var p = SynthPatch()
        p.name = "test sample"
        p.sample = 1; p.oscLevel = 0; p.cutoff = 15000; p.q = 0.7
        p.attack = 0.01; p.decay = 0.1; p.sustain = 1; p.release = 0.1
        // After about 1.8 s the sample is inside its loop, an exact comb of partials in which the strongest
        // one is the 10th harmonic of the loop rate: half the pitch the sample sounds at (measured when the
        // sample was added). So the strongest low partial of a note must sit at half the note's frequency.
        for semis in [36, 48, 60] {
            let hz = midiToHz(24) * pow(2.0, Double(semis) / 12)
            let x = playNote(p, semis: semis, beats: 8, seconds: 5)
            XCTAssertTrue(finite(x), "semis \(semis)")
            XCTAssertGreaterThan(rms(x), 0.02, "semis \(semis)")
            let peak = strongestPeak(x, from: 100_000, low: 0.25 * hz, high: 2.6 * hz)
            print("ALOBOI sample pitch check: note \(hz) Hz, strongest partial \(peak) Hz (expected \(hz / 2))")
            XCTAssertEqual(peak / (hz / 2), 1, accuracy: 0.03, "semis \(semis): the sample is not at the note's pitch")
        }
    }

    // MARK: unstable oscillators and the new patches

    func testUnstableOscillatorsWanderButStayAudible() {
        var steady = PatchLibrary.pad(1, brightness: 0.5)
        steady.unstable = 0
        var wobbly = steady
        wobbly.unstable = 15
        let a = playNote(steady, semis: 36)
        let b = playNote(wobbly, semis: 36)
        XCTAssertTrue(finite(a))
        XCTAssertTrue(finite(b))
        var different = 0
        for i in 0..<a.count where abs(a[i] - b[i]) > 1e-4 { different += 1 }
        XCTAssertGreaterThan(different, a.count / 4, "unstable oscillators sound the same as stable ones")
        let ratio = rms(b) / max(rms(a), 1e-9)
        XCTAssertGreaterThan(ratio, 0.5, "unstable oscillators got much quieter")
        XCTAssertLessThan(ratio, 2.0, "unstable oscillators got much louder")
        // Deterministic: the same patch gives the same audio again.
        XCTAssertEqual(playNote(wobbly, semis: 36), b)
    }

    func testStablePatchesStayExactlyAsTheyWere() {
        // The new patch fields default to "off": the original sounds must not change at all.
        let classic = SynthPatch()
        XCTAssertEqual(classic.sample, 0)
        XCTAssertEqual(classic.oscLevel, 1)
        XCTAssertEqual(classic.unstable, 0)
        XCTAssertEqual(PatchLibrary.pad(0, brightness: 0.5).sample, 0)
        XCTAssertEqual(PatchLibrary.lead(0, brightness: 0.5).unstable, 0)
    }

    func testTheNewCharactersAllPlay() {
        for (name, patch) in [("pad 8", PatchLibrary.pad(8, brightness: 0.5)),
                              ("pad 9", PatchLibrary.pad(9, brightness: 0.5)),
                              ("pad 10", PatchLibrary.pad(10, brightness: 0.5)),
                              ("lead 8", PatchLibrary.lead(8, brightness: 0.5)),
                              ("lead 9", PatchLibrary.lead(9, brightness: 0.5)),
                              ("arp 8", PatchLibrary.arp(8, brightness: 0.5))] {
            for semis in [24, 36, 48, 60] {
                let x = playNote(patch, semis: semis, beats: 2)
                XCTAssertTrue(finite(x), "\(name) at \(semis)")
                XCTAssertGreaterThan(rms(x), 0.003, "\(name) at \(semis): silent")
                XCTAssertLessThan(x.map { abs($0) }.max() ?? 0, 6, "\(name) at \(semis): far too loud")
            }
        }
        XCTAssertEqual(PatchLibrary.pad(9, brightness: 0.5).name, "Aloboi Synth")
        XCTAssertGreaterThan(PatchLibrary.pad(9, brightness: 0.5).sample, 0)
        XCTAssertGreaterThan(PatchLibrary.pad(8, brightness: 0.5).unstable, 0)
    }

    func testTheReeseBassBreathes() {
        let reese = PatchLibrary.sub(8)
        XCTAssertEqual(reese.kind, .reese)
        XCTAssertEqual(PatchLibrary.sub(9).kind, .reese)
        for semis in [12, 24, 31] {
            let x = playBass(reese, semis: semis)
            XCTAssertTrue(finite(x), "reese at \(semis)")
            XCTAssertGreaterThan(rms(x), 0.01, "reese at \(semis): silent")
            XCTAssertLessThan(x.map { abs($0) }.max() ?? 0, 4, "reese at \(semis): far too loud")
        }
        // The detune moves, so the loudness of the note moves too (the saws drift in and out of phase).
        let x = playBass(reese, semis: 24, beats: 5)
        var slices: [Double] = []
        let size = 4410
        var start = 44100   // from one second in, after the filter envelope has settled
        while start + size < Int(44100 * 2.2) {
            slices.append(rms(Array(x[start..<(start + size)])))
            start += size
        }
        let lo = slices.min() ?? 0
        let hi = slices.max() ?? 0
        print("ALOBOI reese loudness slices \(slices.map { String(format: "%.3f", $0) })")
        XCTAssertGreaterThan(hi, lo * 1.01, "the Reese bass does not move at all")
    }

    func testTheAloboiCharactersAreCommonOnlyWhenTheAloboiSoundIsOn() {
        var samplePadOn = 0, warmBassOn = 0, reeseOn = 0, padOff = 0, subOff = 0
        var pianos = Set<String>()
        let trials = 60
        for seed in 1...trials {
            let on = Composer.makePlan(SongSettings(tempo: 122, mood: .dark, genre: .electronic,
                                                    instruments: [.pad, .lead, .subBass], aloboiSound: true,
                                                    seed: UInt64(seed))).profile.palette
            XCTAssertTrue(on.aloboi)
            pianos.insert(on.aloPiano.name)
            if on.pad.sample > 0 { samplePadOn += 1 }
            if on.sub.kind == .reese { reeseOn += 1 }
            if on.sub.kind == .sine || on.sub.kind == .tri || on.sub.kind == .fm { warmBassOn += 1 }
            XCTAssertTrue(on.summary.contains("lead \(on.aloPiano.name) piano"), on.summary)
            let off = Composer.makePlan(SongSettings(tempo: 118, mood: .happy, genre: .nuDisco,
                                                     instruments: [.pad, .lead, .subBass], aloboiSound: false,
                                                     seed: UInt64(seed))).profile.palette
            XCTAssertFalse(off.aloboi)
            XCTAssertFalse(off.summary.contains("lead \(off.aloPiano.name) piano"), off.summary)
            if off.pad.sample > 0 || off.pad.unstable > 0 { padOff += 1 }
            if off.sub.kind == .reese { subOff += 1 }
        }
        print("ALOBOI picks (of \(trials)): with the Aloboi sound sample pad \(samplePadOn) warm bass \(warmBassOn) reese \(reeseOn), pianos \(pianos.sorted()); without, in nu-disco: pad \(padOff) sub \(subOff)")
        XCTAssertGreaterThanOrEqual(samplePadOn, 28, "the Aloboi Synth pad should be the usual pad")
        XCTAssertEqual(warmBassOn, trials, "with the Aloboi sound the bass is always round and warm")
        XCTAssertEqual(reeseOn, 0, "no Reese bass under the Aloboi piano")
        XCTAssertEqual(pianos.count, PatchLibrary.aloPianoCount, "every Aloboi piano character comes up")
        XCTAssertLessThanOrEqual(padOff, 16, "Aloboi pads should be rare in nu-disco")
        XCTAssertEqual(subOff, 0, "nu-disco never picks a Reese bass")
    }

    // MARK: the Aloboi piano

    func testTheAloboiPianoPlaysInTuneAtEveryPitch() {
        for c in 0..<PatchLibrary.aloPianoCount {
            let p = PatchLibrary.aloPiano(c)
            for semis in [10, 22, 34, 46, 58] {
                let (l, r) = playPiano(p, semis: semis)
                XCTAssertTrue(finite(l) && finite(r), "\(p.name) at \(semis)")
                XCTAssertGreaterThan(rms(l), 0.01, "\(p.name) at \(semis): silent")
                let peakLevel = max(l.map { abs($0) }.max() ?? 0, r.map { abs($0) }.max() ?? 0)
                XCTAssertLessThan(peakLevel, 2, "\(p.name) at \(semis): far too loud")
                let mono = zip(l, r).map { $0 + $1 }
                let hz = midiToHz(Double(24 + semis))
                let found = strongestPeak(mono, from: 2205, low: hz * 0.7, high: hz * 1.4)
                XCTAssertEqual(found / hz, 1, accuracy: 0.015, "\(p.name) at \(semis): \(found) Hz instead of \(hz)")
            }
        }
    }

    func testTheAloboiPianoFadesLikeAPiano() {
        for c in 0..<PatchLibrary.aloPianoCount {
            let p = PatchLibrary.aloPiano(c)
            // Held for 3 beats (1.5 s at 120 BPM), then let go.
            let (l, _) = playPiano(p, semis: 34, beats: 3, seconds: 2.5)
            let early = rms(l, from: 2205, to: 6615)          // 0.05...0.15 s
            let later = rms(l, from: 44100, to: 48510)        // 1.0...1.1 s
            let after = rms(l, from: 88200, to: 110250)        // 2.0...2.5 s, well after the release
            print("ALOBOI piano \(p.name): early \(early) later \(later) after \(after)")
            XCTAssertLessThan(later, early * 0.85, "\(p.name): a struck note should fade while it is held")
            XCTAssertGreaterThan(later, early * 0.1, "\(p.name): faded far too fast for a piano")
            XCTAssertLessThan(after, early * 0.01, "\(p.name): the note should stop after it is let go")
            // Low notes ring longer than high notes, like piano strings.
            let (low, _) = playPiano(p, semis: 22)
            let (high, _) = playPiano(p, semis: 70)
            let lowKeep = rms(low, from: 44100, to: 48510) / max(rms(low, from: 2205, to: 6615), 1e-9)
            let highKeep = rms(high, from: 44100, to: 48510) / max(rms(high, from: 2205, to: 6615), 1e-9)
            XCTAssertGreaterThan(lowKeep, highKeep * 0.95, "\(p.name): low notes should not die faster than high ones")
        }
    }

    func testTheAloboiPianoIsWideButNeverCancelsOnOneSpeaker() {
        for c in 0..<PatchLibrary.aloPianoCount {
            let p = PatchLibrary.aloPiano(c)
            for semis in [10, 34, 58] {
                let (l, r) = playPiano(p, semis: semis)
                var differ = 0
                for i in 0..<l.count where abs(l[i] - r[i]) > 1e-4 { differ += 1 }
                XCTAssertGreaterThan(differ, l.count / 4, "\(p.name) at \(semis): not wide (left = right)")
                // A phone that plays both sides through one speaker hears (L + R) / 2: it must stay strong.
                let mono = zip(l, r).map { ($0 + $1) * 0.5 }
                let sides = 0.5 * (rms(l) + rms(r))
                XCTAssertGreaterThan(rms(mono), sides * 0.5, "\(p.name) at \(semis): cancels out in mono")
            }
            XCTAssertEqual(playPiano(p, semis: 34).l, playPiano(p, semis: 34).l, "\(p.name): not deterministic")
        }
    }

    func testTheAloboiPianoIsALittleScratchyButHasNoRumble() {
        let p = PatchLibrary.aloPiano(1)   // chip upright: the most crunch
        var clean = p
        clean.bits = 16
        clean.hold = 1
        let (crunchy, _) = playPiano(p, semis: 34)
        let (smooth, _) = playPiano(clean, semis: 34)
        func highs(_ x: [Float]) -> Double {
            var hp = SVF(cutoff: 7000, q: 0.7, sr: 44100)
            var hp2 = SVF(cutoff: 7000, q: 0.7, sr: 44100)
            return rms(x[2205..<44100].map { hp2.highpass(hp.highpass($0)) })
        }
        print("ALOBOI piano highs above 7 kHz: crunchy \(highs(crunchy)) clean \(highs(smooth))")
        XCTAssertGreaterThan(highs(crunchy), highs(smooth) * 1.3, "the bit crusher should add a little scratch on top")
        XCTAssertLessThan(highs(crunchy), rms(crunchy) * 0.5, "a little scratch, not a wall of noise")

        // Nothing far below the note (no low thump from the pulse wave, no hum from the sample's loop).
        for c in 0..<PatchLibrary.aloPianoCount {
            let q = PatchLibrary.aloPiano(c)
            let (l, r) = playPiano(q, semis: 34)
            let mono = zip(l, r).map { $0 + $1 }
            let hz = Float(midiToHz(58))
            var lp = SVF(cutoff: hz * 0.4, q: 0.7, sr: 44100)
            var lp2 = SVF(cutoff: hz * 0.4, q: 0.7, sr: 44100)
            let below = rms(mono.map { lp2.lowpass(lp.lowpass($0)) })
            print("ALOBOI piano \(q.name): below the note \(below / rms(mono))")
            XCTAssertLessThan(below, rms(mono) * 0.15, "\(q.name): rumbles below the note")
        }
    }

    func testTheAloboiSoundPlaysThePianoTheMelodyAndTheArpsOnTheAloboiPiano() {
        let base = SongSettings(tempo: 120, mood: .introspective, genre: .electronic,
                                instruments: [.piano, .lead, .arp], lengthSeconds: 60, seed: 5)
        var on = base
        on.aloboiSound = true
        let a = render(on)
        let b = render(base)
        checkHealthy(a, "Aloboi piano, lead and arp")
        XCTAssertNotEqual(a.left, b.left)
        let pianoName = Composer.makePlan(on).profile.palette.aloPiano.name
        XCTAssertTrue(a.recipe.contains("keys \(pianoName) piano"), a.recipe)
        XCTAssertTrue(a.recipe.contains("lead \(pianoName) piano"), a.recipe)
        XCTAssertTrue(a.recipe.contains("arp \(pianoName) piano"), a.recipe)
        // The notes themselves do not change: the same melody, only the sound and the playing style.
        XCTAssertEqual(Composer.makePlan(on).hook.map { $0.offset }, Composer.makePlan(base).hook.map { $0.offset })
    }

    func testTheAloboiSoundPlaysLikeAClassicalPianistWithRichChords() {
        var classical = 0, rich = 0
        let trials = 40
        for seed in 1...trials {
            let p = Composer.makePlan(SongSettings(tempo: 120, mood: .introspective, genre: .electronic,
                                                   instruments: [.piano], aloboiSound: true, seed: UInt64(seed))).profile
            if p.pianoMode != .stabs { classical += 1 }
            if p.colorVerse != .triad { rich += 1 }
            XCTAssertGreaterThanOrEqual(p.humanize, 0.008, "played by hand")
        }
        XCTAssertEqual(classical, trials, "no short synth stabs on the Aloboi piano")
        XCTAssertGreaterThanOrEqual(rich, trials * 3 / 4, "mostly rich chords (sevenths, ninths, sixths)")
    }

    // MARK: Alobend tuning

    func testAlobendBendsChordsIntoPureRatios() {
        let fMajor = ChordTuning(rootSemis: 5, majorThird: true, flatFive: false)
        let aMinor = ChordTuning(rootSemis: 9, majorThird: false, flatFive: false)
        let tuning = TuningSystem(tonicHz: 100, just: true, barChords: [fMajor, aMinor])

        // Bar 0 (beats 0...3): F major. Its root sits where just intonation puts it (4:3 above the tonic).
        let root = tuning.frequency(semis: 5, beat: 0)
        XCTAssertEqual(root, 100.0 * 4 / 3, accuracy: 1e-9)
        XCTAssertEqual(tuning.frequency(semis: 9, beat: 0.5) / root, 5.0 / 4, accuracy: 1e-9)   // major third
        XCTAssertEqual(tuning.frequency(semis: 12, beat: 3.9) / root, 3.0 / 2, accuracy: 1e-9)  // fifth
        XCTAssertEqual(tuning.frequency(semis: 17, beat: 1) / root, 2, accuracy: 1e-9)          // octave
        XCTAssertEqual(tuning.frequency(semis: -7, beat: 1) / root, 0.5, accuracy: 1e-9)        // octave below
        XCTAssertEqual(tuning.frequency(semis: 15, beat: 2) / root, 7.0 / 4, accuracy: 1e-9)    // harmonic seventh on a major chord

        // Bar 1 (beats 4...7): A minor. Pure minor third 6:5, and the minor seventh is 9:5.
        let root2 = tuning.frequency(semis: 9, beat: 4)
        XCTAssertEqual(root2, 100.0 * 5 / 3, accuracy: 1e-9)
        XCTAssertEqual(tuning.frequency(semis: 12, beat: 5) / root2, 6.0 / 5, accuracy: 1e-9)
        XCTAssertEqual(tuning.frequency(semis: 16, beat: 6) / root2, 3.0 / 2, accuracy: 1e-9)
        XCTAssertEqual(tuning.frequency(semis: 19, beat: 7) / root2, 9.0 / 5, accuracy: 1e-9)
        // A note that is played a hair early (the humanising wobble) still belongs to the chord of its own bar.
        XCTAssertEqual(tuning.frequency(semis: 12, beat: 3.99) / root2, 6.0 / 5, accuracy: 1e-9)
        XCTAssertEqual(tuning.frequency(semis: 12, beat: 3.9) / root, 3.0 / 2, accuracy: 1e-9)   // still the F chord

        // The same note is tuned differently in different chords (that is the point of Alobend).
        // (Semitone 15 is 233.33 Hz over the F chord and 234.38 Hz over the A minor chord.)
        XCTAssertGreaterThan(abs(tuning.frequency(semis: 15, beat: 0) - tuning.frequency(semis: 15, beat: 4)), 0.5)
        // After the last bar, the last chord keeps going; a negative beat uses the first chord and a beat
        // that is not a number falls back to plain just intonation.
        XCTAssertEqual(tuning.frequency(semis: 12, beat: 400), tuning.frequency(semis: 12, beat: 5), accuracy: 1e-9)
        XCTAssertEqual(tuning.frequency(semis: 7, beat: -3), tuning.frequency(semis: 7, beat: 0), accuracy: 1e-9)
        XCTAssertEqual(tuning.frequency(semis: 7, beat: .nan), tuning.frequency(semis: 7), accuracy: 1e-12)
        // Without any chords nothing changes.
        let plain = TuningSystem(tonicHz: 100, just: true)
        XCTAssertEqual(plain.frequency(semis: 9, beat: 2), plain.frequency(semis: 9), accuracy: 1e-12)
    }

    func testChordTuningReadsTheChordQuality() {
        let dominant = Chord(rootDegree: 4, rootSemis: 7, tones: [7, 11, 14, 17], shift: 0)
        let t1 = ChordTuning(dominant)
        XCTAssertTrue(t1.majorThird)
        XCTAssertFalse(t1.flatFive)
        XCTAssertEqual(t1.ratio(10), 7.0 / 4, accuracy: 1e-12)
        let minor7 = Chord(rootDegree: 1, rootSemis: 2, tones: [2, 5, 9, 12], shift: 0)
        let t2 = ChordTuning(minor7)
        XCTAssertFalse(t2.majorThird)
        XCTAssertEqual(t2.ratio(10), 9.0 / 5, accuracy: 1e-12)
        let diminished = Chord(rootDegree: 6, rootSemis: 11, tones: [11, 14, 17], shift: 0)
        let t3 = ChordTuning(diminished)
        XCTAssertTrue(t3.flatFive)
        XCTAssertEqual(t3.ratio(6), 7.0 / 5, accuracy: 1e-12)
        XCTAssertEqual(ChordTuning(rootSemis: 0, majorThird: true, flatFive: false).ratio(6), 45.0 / 32, accuracy: 1e-12)
        // A chord moved up by a key change keeps its quality.
        let lifted = ChordTuning(dominant.transposed(by: 2))
        XCTAssertEqual(lifted.rootSemis, 9)
        XCTAssertTrue(lifted.majorThird)
    }

    func testAlobendTunesEveryChordOfARealSongToPureRatios() {
        let pure: [Double] = [1, 16.0 / 15, 9.0 / 8, 6.0 / 5, 5.0 / 4, 4.0 / 3, 7.0 / 5, 45.0 / 32, 3.0 / 2,
                              8.0 / 5, 5.0 / 3, 7.0 / 4, 9.0 / 5, 15.0 / 8]
        for (genre, mood) in [(Genre.electronic, Mood.dark), (.synthpop, .uplifting), (.downtempo, .melancholic),
                              (.edm, .energetic), (.ambient, .introspective)] {
            for seed in 1...4 {
                var s = SongSettings(tempo: genre.tempo(for: mood, seed: UInt64(seed)), mood: mood, genre: genre,
                                     lengthSeconds: 120, seed: UInt64(seed))
                s.alobend = true
                let plan = Composer.makePlan(s)
                XCTAssertTrue(plan.tuning.just, "\(genre): Alobend puts the chord roots in just intonation")
                XCTAssertEqual(plan.tuning.barChords.count, plan.totalBars, "\(genre): one chord per bar")
                for bar in 0..<plan.totalBars {
                    let chord = plan.chord(atBar: bar)
                    // One beat into the bar, and a hair before the bar line (a humanised downbeat note).
                    for beat in [Double(bar * 4) + 1, Double(bar * 4) - 0.01] {
                        let root = plan.tuning.frequency(semis: chord.rootSemis, beat: beat)
                        XCTAssertEqual(root, plan.tuning.frequency(semis: chord.rootSemis), accuracy: 1e-9,
                                       "\(genre) bar \(bar): the root stays on the just-intonation scale")
                        for tone in chord.tones {
                            var ratio = plan.tuning.frequency(semis: tone, beat: beat) / root
                            while ratio >= 2 { ratio /= 2 }
                            while ratio < 1 { ratio *= 2 }
                            XCTAssertTrue(pure.contains { abs($0 - ratio) < 1e-9 },
                                          "\(genre) seed \(seed) bar \(bar) beat \(beat): tone \(tone) has ratio \(ratio), not a pure ratio")
                        }
                    }
                }
            }
        }
        // Switched off: no chord table, and a plain piano tuning unless just intonation is asked for.
        let plain = Composer.makePlan(SongSettings(seed: 3))
        XCTAssertTrue(plain.tuning.barChords.isEmpty)
        XCTAssertFalse(plain.tuning.just)
    }

    func testAlobendChangesTheSoundButNotTheNotes() {
        var plain = SongSettings(tempo: 100, mood: .melancholic, genre: .downtempo,
                                 instruments: [.pad, .piano, .subBass], lengthSeconds: 60, justIntonation: true, seed: 12)
        plain.key = 2
        var bent = plain
        bent.alobend = true
        let a = Composer.makePlan(plain)
        let b = Composer.makePlan(bent)
        XCTAssertEqual(a.hook.map { $0.offset }, b.hook.map { $0.offset }, "the melody must not change")
        XCTAssertEqual(a.key, b.key)
        XCTAssertEqual(a.totalBars, b.totalBars)
        let songA = render(plain)
        let songB = render(bent)
        checkHealthy(songB, "alobend")
        XCTAssertNotEqual(songA.left, songB.left, "Alobend should change the sound")
    }

    // MARK: settings

    func testTheAloboiSettingsSurviveSavingAndOldSongsStillLoad() throws {
        var s = SongSettings(tempo: 120, mood: .dark, genre: .electronic, seed: 5)
        s.alobend = true
        s.aloboiSound = true
        let back = try JSONDecoder().decode(SongSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(s, back)
        XCTAssertTrue(back.alobend)
        XCTAssertTrue(back.aloboiSound)

        // A song saved before these settings existed has neither key.
        let data = try JSONEncoder().encode(s)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("settings did not encode to a JSON object")
            return
        }
        object.removeValue(forKey: "alobend")
        object.removeValue(forKey: "aloboiSound")
        object.removeValue(forKey: "genre")
        let old = try JSONDecoder().decode(SongSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(old.alobend)
        XCTAssertFalse(old.aloboiSound)
        XCTAssertNil(old.genre)
        XCTAssertEqual(old.tempo, 120)
        XCTAssertEqual(old.mood, .dark)

        // The Aloboi-style preset switches everything on and is led by the piano.
        let preset = StylePreset.aloboi.settings(seed: 1)
        XCTAssertTrue(preset.alobend)
        XCTAssertTrue(preset.aloboiSound)
        XCTAssertTrue(preset.justIntonation)
        XCTAssertTrue(preset.instruments.contains(.lead))
        XCTAssertTrue(preset.instruments.contains(.piano))
        XCTAssertFalse(preset.instruments.contains(.growlBass), "never synthetic")
        // House on even seeds, downtempo on odd seeds (Aloboi's tags: electronic, house, downtempo).
        XCTAssertEqual(StylePreset.aloboi.settings(seed: 2).genre, .electronic)
        XCTAssertEqual(StylePreset.aloboi.settings(seed: 3).genre, .downtempo)
        XCTAssertGreaterThan(StylePreset.aloboi.settings(seed: 2).tempo, StylePreset.aloboi.settings(seed: 3).tempo)
        // And no other preset does by accident.
        for other in StylePreset.allCases where other != .aloboi {
            XCTAssertFalse(other.settings(seed: 1).aloboiSound, "\(other)")
            XCTAssertFalse(other.settings(seed: 1).alobend, "\(other)")
        }
    }

    // MARK: whole songs

    func testTheAloboiSoundRendersCleanlyInEveryGenre() {
        let moods = Mood.allCases
        var genres: [Genre?] = Genre.allCases.map { Optional($0) }
        genres.append(nil)
        for (gi, genre) in genres.enumerated() {
            let mood = moods[(gi * 5 + 1) % moods.count]
            let tempo = genre?.tempo(for: mood, seed: 9) ?? mood.suggestedTempo
            let s = SongSettings(tempo: tempo, mood: mood, genre: genre,
                                 instruments: [.drums, .subBass, .growlBass, .pad, .arp, .lead, .strings],
                                 vocals: [.femaleAah, .vocalChops], lengthSeconds: 60, grit: 0.8,
                                 justIntonation: true, alobend: true, aloboiSound: true, seed: UInt64(30 + gi))
            let song = render(s)
            checkHealthy(song, "aloboi \(genre?.rawValue ?? "any") / \(mood)")
            XCTAssertTrue(song.recipe.contains(" piano,"), "the recipe should name the Aloboi piano: \(song.recipe)")
        }
    }

    func testTheAloboiPresetSoundsDifferentFromTheSameSongWithoutTheAloboiSound() {
        let on = StylePreset.aloboi.settings(seed: 21)
        var off = on
        off.aloboiSound = false
        off.alobend = false
        let a = render(on)
        let b = render(off)
        checkHealthy(a, "aloboi preset")
        checkHealthy(b, "aloboi preset, sound off")
        XCTAssertNotEqual(a.left, b.left)
        XCTAssertEqual(a.bars, b.bars, "same layout")
        print("ALOBOI preset rms with the sound \(rms(a)) without \(rms(b)); recipe: \(a.recipe)")
    }
}
