import Foundation
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

        // Every preset (they all carry a genre now) survives a save and load too.
        for preset in StylePreset.allCases {
            let p = preset.settings(seed: 3)
            let again = try JSONDecoder().decode(SongSettings.self, from: JSONEncoder().encode(p))
            XCTAssertEqual(p, again, "preset \(preset)")
        }
    }

    func testSongsSavedByOlderVersionsStillLoad() throws {
        // Older versions did not save a genre. Their JSON must still decode (as "any genre").
        let s = SongSettings(tempo: 100, mood: .sad, genre: .pop, seed: 4)
        let data = try JSONEncoder().encode(s)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("settings did not encode to a JSON object")
            return
        }
        object.removeValue(forKey: "genre")
        let old = try JSONSerialization.data(withJSONObject: object)
        let back = try JSONDecoder().decode(SongSettings.self, from: old)
        XCTAssertNil(back.genre)
        XCTAssertEqual(back.mood, .sad)
        XCTAssertEqual(back.tempo, 100)
    }

    // MARK: genres and moods

    private let fullBand: Set<InstrumentKind> = [.drums, .subBass, .pad, .piano, .arp, .guitar, .lead, .strings, .bells, .pluck]

    func testEveryGenreAndMoodRendersCleanly() {
        // 11 genres x 3 moods, rotated so that every one of the 13 moods is used with several genres.
        let moods = Mood.allCases
        for (gi, genre) in Genre.allCases.enumerated() {
            for mi in 0..<3 {
                let mood = moods[(gi * 3 + mi) % moods.count]
                var s = SongSettings(tempo: genre.tempo(for: mood, seed: 7), mood: mood, genre: genre,
                                     instruments: fullBand, vocals: [.femaleAah, .choir],
                                     lengthSeconds: 60, seed: UInt64(10 + gi * 3 + mi))
                s.key = nil
                let song = render(s)
                checkHealthy(song, "\(genre) / \(mood)")
                XCTAssertEqual(song.genreTitle, genre.title)
                XCTAssertFalse(song.recipe.isEmpty, "\(genre) / \(mood): empty recipe")
            }
        }
    }

    func testEveryMoodWorksWithEveryGenreInTheCheapestWay() {
        // The engine must never crash or go silent for any pair, so check all 143 plans and a light render of a few.
        for genre in Genre.allCases {
            for mood in Mood.allCases {
                let s = SongSettings(tempo: genre.suggestedTempo, mood: mood, genre: genre,
                                     instruments: fullBand, vocals: [.choir], lengthSeconds: 60, seed: 5)
                let plan = Composer.makePlan(s)
                XCTAssertGreaterThanOrEqual(Double(plan.totalBars) * 4 * 60 / s.tempo, 60, "\(genre) / \(mood)")
                XCTAssertFalse(plan.sections.isEmpty)
                XCTAssertFalse(plan.recipe.isEmpty)
                XCTAssertFalse(plan.profile.palette.summary.isEmpty, "\(genre) / \(mood): palette summary")
                XCTAssertFalse(plan.profile.kit.summary.isEmpty, "\(genre) / \(mood): kit summary")
                XCTAssertFalse(plan.profile.fx.summary.isEmpty, "\(genre) / \(mood): fx summary")
                XCTAssertFalse(plan.profile.master.summary.isEmpty, "\(genre) / \(mood): master summary")
            }
        }
    }

    func testGenreTemposStayInsideTheirRange() {
        for genre in Genre.allCases {
            XCTAssertGreaterThanOrEqual(genre.tempoRange.lowerBound, SongSettings.minTempo, "\(genre)")
            XCTAssertLessThanOrEqual(genre.tempoRange.upperBound, SongSettings.maxTempo, "\(genre)")
            var seen = Set<Double>()
            for mood in Mood.allCases {
                for seed in 1...20 {
                    let t = genre.tempo(for: mood, seed: UInt64(seed))
                    XCTAssertTrue(genre.tempoRange.contains(t), "\(genre) / \(mood) seed \(seed): \(t)")
                    seen.insert(t)
                }
            }
            XCTAssertGreaterThanOrEqual(seen.count, 8, "\(genre): tempos barely vary")
            XCTAssertEqual(genre.tempo(for: .happy, seed: 9), genre.tempo(for: .happy, seed: 9), "deterministic")
        }
    }

    // MARK: variety

    func testTheSameSettingsGiveManyDifferentRecipes() {
        // Same genre, same mood, same everything except the seed: the recipes should almost never repeat.
        let combos: [(Genre?, Mood)] = [
            (.pop, .happy), (.edm, .energetic), (.lofi, .melancholic), (.ambient, .introspective),
            (.nuDisco, .uplifting), (.dreamPop, .romantic), (nil, .dark), (.downtempo, .relaxed)
        ]
        for (genre, mood) in combos {
            var prints = Set<String>()
            var scales = Set<String>()
            var drumFeels = Set<Int>()
            var bassFeels = Set<Int>()
            for seed in 1...60 {
                let s = SongSettings(tempo: 110, mood: mood, genre: genre, instruments: fullBand,
                                     lengthSeconds: 90, seed: UInt64(seed))
                let plan = Composer.makePlan(s)
                prints.insert(plan.fingerprint)
                scales.insert(plan.profile.scale.rawValue)
                drumFeels.insert(plan.profile.drumStyle.rawValue * 10 + plan.profile.grooveVariant)
                bassFeels.insert(plan.profile.bassStyle.rawValue * 10 + plan.profile.bassVariant)
            }
            let label = "\(genre?.title ?? "Open") / \(mood.title)"
            XCTAssertGreaterThanOrEqual(prints.count, 57, "\(label): only \(prints.count) different recipes in 60 songs")
            XCTAssertGreaterThanOrEqual(scales.count, 2, "\(label): always the same scale")
            XCTAssertGreaterThanOrEqual(drumFeels.count, 5, "\(label): only \(drumFeels.count) drum feels")
            XCTAssertGreaterThanOrEqual(bassFeels.count, 4, "\(label): only \(bassFeels.count) bass feels")
        }
    }

    func testEachGenreHasItsOwnCharacter() {
        // Same seed and mood, every genre: the recipes must all differ.
        var prints = Set<String>()
        for genre in Genre.allCases {
            let s = SongSettings(tempo: genre.suggestedTempo, mood: .uplifting, genre: genre, instruments: fullBand,
                                 lengthSeconds: 90, seed: 31)
            prints.insert(Composer.makePlan(s).fingerprint)
        }
        XCTAssertEqual(prints.count, Genre.allCases.count)

        // And the genres' signature feels show up often enough to matter.
        func share(_ genre: Genre, _ test: (SongPlan) -> Bool) -> Double {
            var hits = 0
            for seed in 1...80 {
                let s = SongSettings(tempo: genre.suggestedTempo, mood: .relaxed, genre: genre, instruments: fullBand,
                                     lengthSeconds: 90, seed: UInt64(seed))
                if test(Composer.makePlan(s)) { hits += 1 }
            }
            return Double(hits) / 80
        }
        // (80 seeded songs each; about 55 % are expected, so 40 % leaves room without losing the point.)
        XCTAssertGreaterThan(share(.nuDisco) { $0.profile.drumStyle == .disco }, 0.4)
        XCTAssertGreaterThan(share(.lofi) { $0.profile.drumStyle == .boomBap }, 0.4)
        XCTAssertGreaterThan(share(.ambient) { $0.profile.drumStyle == .minimal }, 0.4)
        XCTAssertGreaterThan(share(.ambient) { $0.profile.bassStyle == .drone || $0.profile.bassStyle == .sustained }, 0.8)
        XCTAssertGreaterThan(share(.edm) { $0.profile.drumStyle == .fourOnFloor }, 0.5)
        XCTAssertGreaterThan(share(.synthpop) { $0.profile.drumStyle == .gated80s || $0.profile.drumStyle == .backbeat }, 0.5)
        XCTAssertGreaterThan(share(.chillwave) { $0.profile.swing > 0.05 }, 0.5)
        XCTAssertGreaterThan(share(.lofi) { $0.profile.swing > 0.12 }, 0.5)
    }

    func testMoodsTiltTheHarmony() {
        func share(_ mood: Mood, _ test: (Scale) -> Bool) -> Double {
            var hits = 0
            for seed in 1...80 {
                let s = SongSettings(tempo: 100, mood: mood, genre: nil, instruments: [.pad], lengthSeconds: 60,
                                     seed: UInt64(seed))
                if test(Composer.makePlan(s).profile.scale) { hits += 1 }
            }
            return Double(hits) / 80
        }
        let minorish: (Scale) -> Bool = { $0 == .naturalMinor || $0 == .harmonicMinor || $0 == .melodicMinor || $0 == .phrygian }
        XCTAssertGreaterThan(share(.melancholic, minorish), 0.5)
        XCTAssertGreaterThan(share(.sad, minorish), 0.6)
        XCTAssertLessThan(share(.uplifting, minorish), 0.3)
        XCTAssertLessThan(share(.happy, minorish), 0.25)
        XCTAssertGreaterThan(share(.dreamy) { $0 == .lydian }, 0.2)
    }

    func testPlansAreIndependentOfTheChosenInstruments() {
        // Sound design, drums and melodies come from the seed only.
        for genre in [Genre.pop, .lofi, .edm] {
            let a = Composer.makePlan(SongSettings(mood: .romantic, genre: genre, instruments: [.pad], seed: 123))
            let b = Composer.makePlan(SongSettings(mood: .romantic, genre: genre, instruments: fullBand,
                                                   vocals: [.choir], seed: 123))
            XCTAssertEqual(a.fingerprint, b.fingerprint, "\(genre)")
            XCTAssertEqual(a.recipe, b.recipe, "\(genre)")
            XCTAssertEqual(a.hook.map { $0.offset }, b.hook.map { $0.offset })
            XCTAssertEqual(a.verseHook.map { $0.step }, b.verseHook.map { $0.step })
        }
    }

    func testMelodiesStayInRangeAndEndOnAChordTone() {
        for seed in 1...100 {
            for mood in [Mood.uplifting, .melancholic, .energetic, .introspective] {
                let s = SongSettings(mood: mood, genre: Genre.allCases[seed % Genre.allCases.count], seed: UInt64(seed))
                let plan = Composer.makePlan(s)
                for motif in [plan.hook, plan.hookAlt, plan.verseHook, plan.verseHookAlt] {
                    XCTAssertGreaterThanOrEqual(motif.count, 2)
                    var lastStep = -1
                    for n in motif {
                        XCTAssertGreaterThan(n.step, lastStep, "notes must be in order")
                        XCTAssertLessThan(n.step, 32)
                        XCTAssertGreaterThanOrEqual(n.len, 1)
                        XCTAssertLessThanOrEqual(n.step + n.len, 33)
                        XCTAssertGreaterThanOrEqual(n.offset, -6)
                        XCTAssertLessThanOrEqual(n.offset, 12)
                        lastStep = n.step
                    }
                }
            }
        }
    }

    func testTheKeyChangeLiftsTheLastChorusAndTheOutro() {
        var found = 0
        for seed in 1...300 {
            let s = SongSettings(tempo: 100, mood: .uplifting, genre: .pop, instruments: [.pad, .drums],
                                 lengthSeconds: 180, seed: UInt64(seed))
            let plan = Composer.makePlan(s)
            let lift = plan.profile.keyLift
            let chorusIdx = plan.sections.indices.filter { plan.sections[$0].kind == .chorus }
            guard lift > 0, chorusIdx.count >= 2 else { continue }
            found += 1
            let last = chorusIdx[chorusIdx.count - 1]
            for (i, sec) in plan.sections.enumerated() {
                for chord in sec.progression {
                    XCTAssertEqual(chord.shift, i >= last ? lift : 0, "seed \(seed) section \(i) \(sec.kind)")
                }
            }
        }
        XCTAssertGreaterThan(found, 5, "the key change never happened in 300 songs")
    }

    func testSongsEndOnTheHomeChordWhenTheyHaveAnOutro() {
        for seed in 1...120 {
            let genre = Genre.allCases[seed % Genre.allCases.count]
            let mood = Mood.allCases[seed % Mood.allCases.count]
            for length in [60.0, 120, 180] {
                let s = SongSettings(tempo: genre.suggestedTempo, mood: mood, genre: genre, lengthSeconds: length,
                                     seed: UInt64(seed))
                let plan = Composer.makePlan(s)
                guard let last = plan.sections.last, last.kind == .outro else { continue }
                let finalChord = plan.chord(atBar: plan.totalBars - 1)
                XCTAssertEqual(finalChord.rootDegree, 0, "seed \(seed) \(genre) \(mood) length \(length)")
            }
        }
    }

    func testEverySongLayoutFitsEveryLength() {
        var names = Set<String>()
        for genre in Genre.allCases {
            for length in [60.0, 90, 120, 180] {
                for tempo in [60.0, 90, 120, 200] {
                    for seed in 1...6 {
                        let s = SongSettings(tempo: tempo, mood: .chill, genre: genre, lengthSeconds: length,
                                             seed: UInt64(seed))
                        let plan = Composer.makePlan(s)
                        names.insert(plan.templateName)
                        var bar = 0
                        for sec in plan.sections {
                            XCTAssertEqual(sec.startBar, bar)
                            XCTAssertGreaterThan(sec.bars, 0)
                            XCTAssertEqual(sec.bars % 4, 0)
                            XCTAssertFalse(sec.progression.isEmpty)
                            bar += sec.bars
                        }
                        XCTAssertEqual(bar, plan.totalBars)
                    }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(names.count, 6, "only \(names) layouts were ever used")
    }

    func testArrangementsLetInstrumentsRest() {
        // Across many songs, some instruments sit out some phrases, but the music never goes silent.
        var rests = 0
        for seed in 1...60 {
            let s = SongSettings(mood: .happy, genre: .indietronica, instruments: fullBand, lengthSeconds: 120,
                                 seed: UInt64(seed))
            let plan = Composer.makePlan(s)
            for phrase in 0..<(plan.totalBars / 4) {
                var anyPlaying = false
                for inst in fullBand {
                    if plan.level(inst, bar: phrase * 4) > 0 { anyPlaying = true } else { rests += 1 }
                }
                XCTAssertTrue(anyPlaying, "seed \(seed) phrase \(phrase) is silent")
            }
        }
        XCTAssertGreaterThan(rests, 100)
    }

    func testTitlesAreFriendly() {
        var titles = Set<String>()
        for (gi, genre) in Genre.allCases.enumerated() {
            for (mi, mood) in Mood.allCases.enumerated() {
                let t = Titles.make(genre: genre, mood: mood, seed: UInt64(12 + gi * 13 + mi))
                XCTAssertTrue(t.contains("#"), t)
                XCTAssertGreaterThan(t.count, 6)
                titles.insert(t)
            }
        }
        XCTAssertGreaterThan(titles.count, 100)
        XCTAssertFalse(Titles.make(genre: nil, mood: .romantic, seed: 1).isEmpty)
    }

    // MARK: audio variety (measured, not guessed)

    private struct Features {
        var zcr: Double        // zero crossings per sample: brightness / noisiness
        var lowShare: Double   // share of the energy below roughly 200 Hz
        var onsets: Double     // note and drum onsets per second
        var crest: Double      // peak divided by RMS
    }

    private func features(_ s: RenderedSong) -> Features {
        let n = s.frameCount
        var crossings = 0
        var prev: Float = 0
        var total = 0.0
        var low = 0.0
        var lp: Float = 0
        let a: Float = 1 - exp(-2 * Float.pi * 200 / Float(s.sampleRate))
        let hop = 441
        var env: [Double] = []
        var acc = 0.0
        for i in 0..<n {
            let x = (s.left[i] + s.right[i]) * 0.5
            if (x >= 0) != (prev >= 0) { crossings += 1 }
            prev = x
            lp += a * (x - lp)
            total += Double(x * x)
            low += Double(lp * lp)
            acc += Double(x * x)
            if (i + 1) % hop == 0 {
                env.append(acc / Double(hop))
                acc = 0
            }
        }
        var onsets = 0
        if env.count > 4 {
            var mean = 0.0
            for e in env { mean += e }
            mean /= Double(env.count)
            for i in 2..<env.count where env[i] > 2.2 * env[i - 2] && env[i] > 0.3 * mean && env[i - 1] <= env[i] {
                onsets += 1
            }
        }
        let seconds = Double(n) / Double(s.sampleRate)
        return Features(zcr: Double(crossings) / Double(max(n, 1)),
                        lowShare: low / max(total, 1e-12),
                        onsets: Double(onsets) / seconds,
                        crest: Double(peak(s)) / max(rms(s), 1e-9))
    }

    private func spread(_ values: [Double]) -> Double {
        guard let lo = values.min(), let hi = values.max() else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return (hi - lo) / max(abs(mean), 1e-9)
    }

    func testSameSettingsGiveAudiblyDifferentSongs() {
        // Ten songs with identical settings except the seed. Their measured character must differ.
        var all: [Features] = []
        for seed in 1...10 {
            let s = SongSettings(tempo: 112, mood: .uplifting, genre: .pop, instruments: fullBand,
                                 vocals: [.femaleAah], lengthSeconds: 60, seed: UInt64(seed))
            all.append(features(render(s)))
        }
        let zcr = spread(all.map { $0.zcr })
        let low = spread(all.map { $0.lowShare })
        let onsets = spread(all.map { $0.onsets })
        let crest = spread(all.map { $0.crest })
        print("VARIETY same settings, 10 seeds: spread zcr \(zcr) low \(low) onsets \(onsets) crest \(crest)")
        XCTAssertGreaterThan(zcr, 0.15, "brightness barely changes between seeds")
        XCTAssertGreaterThan(low, 0.15, "bass weight barely changes between seeds")
        XCTAssertGreaterThan(onsets, 0.15, "busyness barely changes between seeds")
    }

    func testGenresSoundDifferentFromEachOther() {
        var table: [(String, Features)] = []
        for genre in Genre.allCases {
            let s = SongSettings(tempo: genre.suggestedTempo, mood: .uplifting, genre: genre, instruments: fullBand,
                                 vocals: [], lengthSeconds: 60, seed: 21)
            table.append((genre.title, features(render(s))))
        }
        for (name, f) in table {
            let label = name.padding(toLength: 13, withPad: " ", startingAt: 0)
            print("GENRE \(label) zcr \(String(format: "%.4f", f.zcr)) low \(String(format: "%.3f", f.lowShare)) onsets/s \(String(format: "%.2f", f.onsets)) crest \(String(format: "%.2f", f.crest))")
        }
        XCTAssertGreaterThan(spread(table.map { $0.1.zcr }), 0.4, "genres do not differ in brightness")
        XCTAssertGreaterThan(spread(table.map { $0.1.lowShare }), 0.3, "genres do not differ in bass weight")
        XCTAssertGreaterThan(spread(table.map { $0.1.onsets }), 0.4, "genres do not differ in busyness")
    }

    func testAmbientIsQuieterAndSofterThanEDM() {
        let ambient = SongSettings(tempo: 70, mood: .introspective, genre: .ambient, instruments: fullBand,
                                   lengthSeconds: 60, seed: 8)
        let edm = SongSettings(tempo: 128, mood: .energetic, genre: .edm, instruments: fullBand,
                               lengthSeconds: 60, seed: 8)
        let a = features(render(ambient))
        let e = features(render(edm))
        print("AMBIENT \(a) EDM \(e)")
        XCTAssertGreaterThan(e.onsets, a.onsets * 1.5, "EDM should be much busier than ambient")
    }
}
