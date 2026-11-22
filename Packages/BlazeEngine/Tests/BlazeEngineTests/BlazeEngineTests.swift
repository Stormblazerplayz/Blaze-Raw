import XCTest
@testable import BlazeEngine

final class BlazeEngineTests: XCTestCase {

    // MARK: helpers

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

    private func allFinite(_ s: RenderedSong) -> Bool {
        for i in 0..<s.frameCount where !s.left[i].isFinite || !s.right[i].isFinite { return false }
        return true
    }

    private func render(_ settings: SongSettings, file: StaticString = #filePath, line: UInt = #line) -> RenderedSong {
        guard let song = SongEngine.render(settings) else {
            XCTFail("render returned nil", file: file, line: line)
            fatalError("render failed")
        }
        return song
    }

    private func checkHealthy(_ s: RenderedSong, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(s.durationSeconds, 60, "\(label): shorter than one minute", file: file, line: line)
        XCTAssertTrue(allFinite(s), "\(label): contains NaN/inf", file: file, line: line)
        XCTAssertLessThanOrEqual(peak(s), 1.0, "\(label): clips", file: file, line: line)
        XCTAssertGreaterThan(rms(s), 0.02, "\(label): nearly silent", file: file, line: line)
        XCTAssertEqual(s.left.count, s.right.count, file: file, line: line)
    }

    // MARK: length

    func testEveryTempoAndLengthIsAtLeastOneMinute() {
        for tempo in [60.0, 75, 100, 128, 160, 200] {
            for length in [60.0, 90, 180] {
                var s = SongSettings(tempo: tempo, mood: .dark, instruments: [.drums, .pad, .subBass],
                                     lengthSeconds: length, seed: 5)
                s.key = 4
                let song = render(s)
                checkHealthy(song, "tempo \(tempo) length \(length)")
                XCTAssertGreaterThanOrEqual(song.durationSeconds, length, "tempo \(tempo) length \(length)")
            }
        }
    }

    func testCrazySettingsAreSafelyClamped() {
        let s = SongSettings(tempo: .nan, mood: .happy, instruments: [], vocals: [], key: -5,
                             lengthSeconds: 1, intensity: .infinity, grit: -3, seed: 99)
        let c = s.clamped()
        XCTAssertEqual(c.tempo, 120)
        XCTAssertGreaterThanOrEqual(c.lengthSeconds, 60)
        XCTAssertEqual(c.intensity, 0.7)
        XCTAssertEqual(c.grit, 0)
        XCTAssertEqual(c.key, 7)
        XCTAssertFalse(c.instruments.isEmpty)
        checkHealthy(render(s), "crazy settings")

        let tooBig = SongSettings(tempo: 9999, lengthSeconds: 99999, intensity: 5, grit: 5)
        let c2 = tooBig.clamped()
        XCTAssertEqual(c2.tempo, 200)
        XCTAssertEqual(c2.lengthSeconds, 180)
        XCTAssertEqual(c2.intensity, 1)
    }

    // MARK: all the choices

    func testEveryMoodWorks() {
        for mood in Mood.allCases {
            let s = SongSettings(tempo: mood.suggestedTempo, mood: mood,
                                 instruments: [.drums, .subBass, .pad, .piano, .arp],
                                 vocals: [.choir], lengthSeconds: 60, seed: 11)
            checkHealthy(render(s), "mood \(mood)")
        }
    }

    func testEveryInstrumentAloneMakesSound() {
        for inst in InstrumentKind.allCases {
            let s = SongSettings(tempo: 110, mood: .energetic, instruments: [inst], vocals: [],
                                 lengthSeconds: 60, seed: 21)
            let song = render(s)
            checkHealthy(song, "instrument \(inst)")
        }
    }

    func testEveryVocalStyleChangesTheSong() {
        let base = SongSettings(tempo: 110, mood: .dreamy, instruments: [.pad, .subBass], vocals: [],
                                lengthSeconds: 60, seed: 31)
        let without = render(base)
        for style in VocalStyle.allCases {
            var s = base
            s.vocals = [style]
            let song = render(s)
            checkHealthy(song, "vocal \(style)")
            var diff = 0.0
            let n = min(song.frameCount, without.frameCount)
            for i in 0..<n { diff += Double(abs(song.left[i] - without.left[i])) }
            XCTAssertGreaterThan(diff / Double(n), 0.001, "vocal \(style) did not change the audio")
        }
    }

    func testEveryPresetWorks() {
        for preset in StylePreset.allCases {
            let s = preset.settings(seed: 42)
            let song = render(s)
            checkHealthy(song, "preset \(preset)")
            XCTAssertFalse(song.title.isEmpty)
        }
    }

    func testJustIntonationAndKeys() {
        for key in [0, 5, 11] {
            for just in [false, true] {
                var s = SongSettings(tempo: 100, mood: .raw, instruments: [.drums, .subBass, .growlBass, .lead, .pad],
                                     vocals: [.vocalChops], key: key, lengthSeconds: 60, justIntonation: just, seed: 8)
                s.grit = 1
                checkHealthy(render(s), "key \(key) just \(just)")
            }
        }
    }

    // MARK: determinism

    func testSameSeedGivesSameSong() {
        let s = StylePreset.aloboi.settings(seed: 1234)
        let a = render(s)
        let b = render(s)
        XCTAssertEqual(a.left, b.left)
        XCTAssertEqual(a.right, b.right)
        XCTAssertEqual(a.title, b.title)
        var other = s
        other.seed = 1235
        let c = render(other)
        XCTAssertNotEqual(a.left, c.left)
    }

    func testAddingAnInstrumentKeepsTheMelody() {
        // Forked random streams: the hook is chosen from the seed only.
        let a = Composer.makePlan(SongSettings(instruments: [.pad], seed: 77))
        let b = Composer.makePlan(SongSettings(instruments: [.pad, .drums, .lead, .piano], vocals: [.choir], seed: 77))
        XCTAssertEqual(a.hook.map { $0.offset }, b.hook.map { $0.offset })
        XCTAssertEqual(a.key, b.key)
    }

    // MARK: theory

    func testSectionAllocationAddsUp() {
        for total in 4...60 {
            let w: [Double] = total <= 5 ? [1, 1, 2, 1] : [1, 1.5, 2, 1, 2, 1]
            let counts = Composer.allocate(w, total: total)
            XCTAssertEqual(counts.reduce(0, +), total, "total \(total)")
            XCTAssertTrue(counts.allSatisfy { $0 >= 1 })
        }
    }

    func testPlanCoversEveryBarExactlyOnce() {
        for tempo in [60.0, 97, 133, 200] {
            for length in [60.0, 120, 180] {
                let plan = Composer.makePlan(SongSettings(tempo: tempo, lengthSeconds: length, seed: 3))
                XCTAssertEqual(plan.totalBars % 4, 0)
                var bar = 0
                for sec in plan.sections {
                    XCTAssertEqual(sec.startBar, bar)
                    XCTAssertGreaterThan(sec.bars, 0)
                    bar += sec.bars
                }
                XCTAssertEqual(bar, plan.totalBars)
                let secs = Double(plan.totalBars) * 4 * 60 / tempo
                XCTAssertGreaterThanOrEqual(secs, length)
            }
        }
    }

    func testJustIntonationRatios() {
        let just = TuningSystem(tonicHz: 100, just: true)
        XCTAssertEqual(just.frequency(semis: 0), 100, accuracy: 1e-9)
        XCTAssertEqual(just.frequency(semis: 7), 150, accuracy: 1e-9)       // perfect fifth 3:2
        XCTAssertEqual(just.frequency(semis: 4), 125, accuracy: 1e-9)       // major third 5:4
        XCTAssertEqual(just.frequency(semis: 3), 120, accuracy: 1e-9)       // minor third 6:5
        XCTAssertEqual(just.frequency(semis: 12), 200, accuracy: 1e-9)
        XCTAssertEqual(just.frequency(semis: -5), 75, accuracy: 1e-9)       // fifth below the octave: 3:4
        let equal = TuningSystem(tonicHz: 100, just: false)
        XCTAssertEqual(equal.frequency(semis: 12), 200, accuracy: 1e-9)
        XCTAssertEqual(equal.frequency(semis: 7), 100 * pow(2, 7.0 / 12), accuracy: 1e-9)
    }

    func testScaleDegrees() {
        XCTAssertEqual(Scale.major.semitone(degree: 0), 0)
        XCTAssertEqual(Scale.major.semitone(degree: 4), 7)
        XCTAssertEqual(Scale.major.semitone(degree: 7), 12)
        XCTAssertEqual(Scale.major.semitone(degree: -1), -1)
        XCTAssertEqual(Scale.naturalMinor.semitone(degree: 2), 3)
        XCTAssertEqual(Scale.naturalMinor.semitone(degree: -7), -12)
    }

    // MARK: file output

    func testWavFileIsValid() {
        let song = render(SongSettings(instruments: [.pad], lengthSeconds: 60, seed: 2))
        let data = WAV.data(for: song)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
        XCTAssertEqual(data.count, 44 + song.frameCount * 4)
        let dataSize = data[40..<44].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(Int(UInt32(littleEndian: dataSize)), song.frameCount * 4)
        let rate = data[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(Int(UInt32(littleEndian: rate)), 44100)
    }

    // MARK: progress and cancel

    func testProgressReachesOneAndCancelWorks() {
        var last = 0.0
        var calls = 0
        let s = SongSettings(instruments: [.drums, .pad, .arp], lengthSeconds: 60, seed: 6)
        let song = SongEngine.render(s, progress: { p in
            XCTAssertGreaterThanOrEqual(p, last)
            last = p
            calls += 1
        })
        XCTAssertNotNil(song)
        XCTAssertEqual(last, 1.0)
        XCTAssertGreaterThan(calls, 3)

        let cancelled = SongEngine.render(s, isCancelled: { true })
        XCTAssertNil(cancelled)
    }

    // MARK: the singing voice

    /// Renders one sung note and returns the energy near a few frequencies (Goertzel).
    private func voiceEnergy(female: Bool, vowel: Int, f0Semis: Int, bands: [(Double, Double)]) -> [Double] {
        let sr: Float = 44100
        let frames = Int(sr * 1.5)
        let ctx = RenderContext(sr: sr, bpm: 120, frames: frames, bodyFrames: frames,
                                tuning: TuningSystem(tonicHz: 110, just: false), grit: 0, intensity: 0.5)
        let note = NoteEvent(beat: 0, dur: 2.5, semis: f0Semis, vel: 1)
        let spec = VoiceSpec(female: female, vowelFrom: vowel, vowelTo: vowel, vibratoCents: 0, breath: 0,
                             unison: 1, attack: 0.02, release: 0.1)
        VoiceSynth.render([VoiceEvent(note: note, spec: spec, pan: 0)], ctx: ctx, mix: Mix(gain: 1))
        let start = Int(sr * 0.3), end = Int(sr * 1.2)
        var result: [Double] = []
        for (lo, hi) in bands {
            var e = 0.0
            var f = lo
            while f <= hi {
                let w = 2 * Double.pi * f / Double(sr)
                var re = 0.0, im = 0.0
                for i in start..<end {
                    let x = Double(ctx.bus.l[i])
                    re += x * cos(w * Double(i))
                    im -= x * sin(w * Double(i))
                }
                e += re * re + im * im
                f += 20
            }
            result.append(e)
        }
        return result
    }

    func testVowelsHaveTheRightFormants() {
        // f0 = 110 * 2^(12/12) = 220 Hz
        let bands: [(Double, Double)] = [(250, 450), (700, 1000), (2500, 3100)]
        let ah = voiceEnergy(female: true, vowel: 0, f0Semis: 12, bands: bands)
        let ee = voiceEnergy(female: true, vowel: 2, f0Semis: 12, bands: bands)
        XCTAssertGreaterThan(ah[1], 0)
        XCTAssertGreaterThan(ee[0], 0)
        // "ah" has a strong first formant near 850 Hz; "ee" has a low first formant (310 Hz) and a high second formant (2790 Hz).
        XCTAssertGreaterThan(ah[1] / max(ah[0], 1e-12), 3 * ee[1] / max(ee[0], 1e-12), "ah vs ee first formant")
        XCTAssertGreaterThan(ee[2] / max(ee[1], 1e-12), 5 * ah[2] / max(ah[1], 1e-12), "ee has a strong second formant")
    }

    private func voiceRMSdB(female: Bool, vowel: Int, f0Semis: Int) -> Double {
        let sr: Float = 44100
        let frames = Int(sr * 1.5)
        let ctx = RenderContext(sr: sr, bpm: 120, frames: frames, bodyFrames: frames,
                                tuning: TuningSystem(tonicHz: 110, just: false), grit: 0, intensity: 0.5)
        let note = NoteEvent(beat: 0, dur: 2.5, semis: f0Semis, vel: 1)
        let spec = VoiceSpec(female: female, vowelFrom: vowel, vowelTo: vowel, vibratoCents: 0, breath: 0,
                             unison: 1, attack: 0.02, release: 0.1)
        VoiceSynth.render([VoiceEvent(note: note, spec: spec, pan: 0)], ctx: ctx, mix: Mix(gain: 1))
        var sum = 0.0
        let start = Int(sr * 0.3), end = Int(sr * 1.2)
        for i in start..<end { sum += Double(ctx.bus.l[i] * ctx.bus.l[i]) }
        return 10 * log10(sum / Double(end - start) + 1e-12)
    }

    func testVowelLoudnessIsBalanced() {
        // Every vowel should land in a similar loudness range (thanks to the calibration table),
        // at several different pitches.
        for female in [false, true] {
            for semis in (female ? [10, 14, 17] : [0, 3, 6]) {
                var levels: [Double] = []
                for v in 0..<5 { levels.append(voiceRMSdB(female: female, vowel: v, f0Semis: semis)) }
                XCTAssertLessThan(levels.max()! - levels.min()!, 7, "female=\(female) semis=\(semis) spread \(levels)")
            }
        }
    }

    func testSettingsCanBeSavedAndLoaded() throws {
        let s = StylePreset.epicCinema.settings(seed: 9)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SongSettings.self, from: data)
        XCTAssertEqual(s, back)
    }
}
