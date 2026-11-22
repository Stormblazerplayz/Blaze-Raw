import XCTest
@testable import BlazeEngine

/// Measures how different the OLD engine's songs are from each other, with the same measuring code the new
/// tests use, so the before and after numbers can be compared. It only prints; it never fails.
final class BaselineVarietyTests: XCTestCase {
    private struct Features {
        var zcr: Double
        var lowShare: Double
        var onsets: Double
        var crest: Double
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
        var peak: Float = 0
        for i in 0..<n {
            let x = (s.left[i] + s.right[i]) * 0.5
            peak = max(peak, abs(s.left[i]), abs(s.right[i]))
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
        let rms = (total / Double(max(n, 1))).squareRoot()
        return Features(zcr: Double(crossings) / Double(max(n, 1)),
                        lowShare: low / max(total, 1e-12),
                        onsets: Double(onsets) / seconds,
                        crest: Double(peak) / max(rms, 1e-9))
    }

    private func spread(_ values: [Double]) -> Double {
        guard let lo = values.min(), let hi = values.max() else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return (hi - lo) / max(abs(mean), 1e-9)
    }

    private let fullBand: Set<InstrumentKind> = [.drums, .subBass, .pad, .piano, .arp, .guitar, .lead, .strings, .bells, .pluck]

    func testBaselineSameSettingsDifferentSeeds() {
        var all: [Features] = []
        for seed in 1...10 {
            let s = SongSettings(tempo: 112, mood: .happy, instruments: fullBand, vocals: [.femaleAah],
                                 lengthSeconds: 60, seed: UInt64(seed))
            guard let song = SongEngine.render(s) else { XCTFail("render failed"); return }
            all.append(features(song))
        }
        let zcr = spread(all.map { $0.zcr })
        let low = spread(all.map { $0.lowShare })
        let onsets = spread(all.map { $0.onsets })
        let crest = spread(all.map { $0.crest })
        print("BASELINE VARIETY same settings, 10 seeds: spread zcr \(zcr) low \(low) onsets \(onsets) crest \(crest)")
        for (i, f) in all.enumerated() {
            print("BASELINE seed \(i + 1): zcr \(f.zcr) low \(f.lowShare) onsets/s \(f.onsets) crest \(f.crest)")
        }
    }

    func testBaselineAcrossMoods() {
        var table: [(String, Features)] = []
        for mood in Mood.allCases {
            let s = SongSettings(tempo: mood.suggestedTempo, mood: mood, instruments: fullBand, vocals: [],
                                 lengthSeconds: 60, seed: 21)
            guard let song = SongEngine.render(s) else { XCTFail("render failed"); return }
            table.append(("\(mood)", features(song)))
        }
        for (name, f) in table {
            print("BASELINE MOOD \(name) zcr \(f.zcr) low \(f.lowShare) onsets/s \(f.onsets) crest \(f.crest)")
        }
        print("BASELINE MOODS spread zcr \(spread(table.map { $0.1.zcr })) low \(spread(table.map { $0.1.lowShare })) onsets \(spread(table.map { $0.1.onsets }))")
    }

    func testBaselineHowManyDistinctRecipes() {
        // The old engine: how many different (scale, chord loop, kit, hook) combinations in 60 songs?
        var prints = Set<String>()
        for seed in 1...60 {
            let s = SongSettings(tempo: 110, mood: .happy, instruments: fullBand, lengthSeconds: 90, seed: UInt64(seed))
            let plan = Composer.makePlan(s)
            let progression = plan.sections.map { $0.progression.map { "\($0.rootDegree)" }.joined(separator: ",") }
            prints.insert("\(plan.profile.scale.rawValue)|\(progression)|\(plan.hook.map { "\($0.step):\($0.offset)" })")
        }
        print("BASELINE distinct recipes in 60 songs of one mood: \(prints.count)")
        var drumKits = Set<String>()
        for mood in Mood.allCases { drumKits.insert("\(MoodProfile.profile(for: mood).kit)") }
        print("BASELINE drum kits in the whole engine: \(drumKits.count)")
    }
}
