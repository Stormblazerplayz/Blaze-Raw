import Foundation
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
        /// 16 log-spaced frequency bands (50 Hz to 16 kHz): energy in dB relative to the whole song.
        var bands: [Double]
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

    private func bandProfile(_ s: RenderedSong) -> [Double] {
        let size = 4096
        let hop = 16384
        var power = [Double](repeating: 0, count: size / 2)
        var start = 0
        while start + size <= s.frameCount {
            var re = [Double](repeating: 0, count: size)
            var im = [Double](repeating: 0, count: size)
            for k in 0..<size {
                let w = 0.5 - 0.5 * cos(2 * Double.pi * Double(k) / Double(size - 1))
                re[k] = Double((s.left[start + k] + s.right[start + k]) * 0.5) * w
            }
            fft(&re, &im)
            for b in 0..<(size / 2) { power[b] += re[b] * re[b] + im[b] * im[b] }
            start += hop
        }
        let sr = Double(s.sampleRate)
        var bands = [Double](repeating: 0, count: 16)
        let lo = 50.0
        let hi = 16000.0
        for b in 0..<(size / 2) {
            let f = Double(b) * sr / Double(size)
            if f < lo || f >= hi { continue }
            let idx = Int(16 * log(f / lo) / log(hi / lo))
            bands[min(idx, 15)] += power[b]
        }
        let total = bands.reduce(0, +) + 1e-12
        return bands.map { 10 * log10($0 / total + 1e-9) }
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
                        crest: Double(peak) / max(rms, 1e-9),
                        bands: bandProfile(s))
    }

    private func spread(_ values: [Double]) -> Double {
        guard let lo = values.min(), let hi = values.max() else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return (hi - lo) / max(abs(mean), 1e-9)
    }

    /// The average difference in dB between the frequency profiles of every pair of songs.
    private func spectralDifference(_ all: [Features]) -> Double {
        var sum = 0.0
        var pairs = 0
        for i in 0..<all.count {
            for j in (i + 1)..<all.count where j < all.count {
                var d = 0.0
                for b in 0..<16 { d += abs(all[i].bands[b] - all[j].bands[b]) }
                sum += d / 16
                pairs += 1
            }
        }
        return pairs > 0 ? sum / Double(pairs) : 0
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
        print("BASELINE SPECTRAL same settings, 10 seeds: average difference between two songs = \(spectralDifference(all)) dB")
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
        print("BASELINE MOODS spread zcr \(spread(table.map { $0.1.zcr })) low \(spread(table.map { $0.1.lowShare })) onsets \(spread(table.map { $0.1.onsets })) crest \(spread(table.map { $0.1.crest }))")
        print("BASELINE SPECTRAL 8 moods: average difference between two songs = \(spectralDifference(table.map { $0.1 })) dB")
    }

    func testBaselineHowManyDistinctRecipes() {
        // The old engine: how many different (scale, chord loop, kit, hook) combinations in 60 songs?
        var prints = Set<String>()
        var progressions = Set<String>()
        for seed in 1...60 {
            let s = SongSettings(tempo: 110, mood: .happy, instruments: fullBand, lengthSeconds: 90, seed: UInt64(seed))
            let plan = Composer.makePlan(s)
            let progression = plan.sections.map { $0.progression.map { "\($0.rootDegree)" }.joined(separator: ",") }
            progressions.insert("\(plan.profile.scale.rawValue)|\(progression)")
            prints.insert("\(plan.profile.scale.rawValue)|\(progression)|\(plan.hook.map { "\($0.step):\($0.offset)" })")
        }
        print("BASELINE distinct (scale + chord loops) in 60 songs of one mood: \(progressions.count)")
        print("BASELINE distinct (scale + chord loops + melody) in 60 songs of one mood: \(prints.count)")
        var drumKits = Set<String>()
        for mood in Mood.allCases { drumKits.insert("\(MoodProfile.profile(for: mood).kit)") }
        print("BASELINE drum kits in the whole engine: \(drumKits.count)")
    }
}
