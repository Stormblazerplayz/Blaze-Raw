import Foundation

// MARK: - State-variable filter (stable even when the cutoff moves)

struct SVF {
    var ic1: Float = 0
    var ic2: Float = 0
    var a1: Float = 0
    var a2: Float = 0
    var a3: Float = 0
    var k: Float = 1

    init() {}

    init(cutoff: Float, q: Float, sr: Float) {
        set(cutoff: cutoff, q: q, sr: sr)
    }

    mutating func set(cutoff: Float, q: Float, sr: Float) {
        let fc = min(max(cutoff, 20), sr * 0.45)
        let g = tan(Float.pi * fc / sr)
        k = 1 / max(q, 0.1)
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }

    @inline(__always) mutating func lowpass(_ x: Float) -> Float {
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return v2
    }

    @inline(__always) mutating func bandpass(_ x: Float) -> Float {
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return v1 * k
    }

    @inline(__always) mutating func highpass(_ x: Float) -> Float {
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return x - k * v1 - v2
    }
}

// MARK: - Formant resonator (used for the singing voices)

struct Resonator {
    var y1: Float = 0
    var y2: Float = 0
    var a: Float = 1
    var b: Float = 0
    var c: Float = 0

    mutating func set(freq: Float, bandwidth: Float, sr: Float) {
        let f = min(max(freq, 50), sr * 0.45)
        let cc = -exp(-2 * Float.pi * bandwidth / sr)
        let bb = 2 * exp(-Float.pi * bandwidth / sr) * cos(2 * Float.pi * f / sr)
        a = 1 - bb - cc
        b = bb
        c = cc
    }

    @inline(__always) mutating func process(_ x: Float) -> Float {
        let y = a * x + b * y1 + c * y2
        y2 = y1
        y1 = y
        return y
    }
}

// MARK: - Reverb (Freeverb style)

private final class CombFilter {
    let size: Int
    let buf: UnsafeMutablePointer<Float>
    var idx = 0
    var store: Float = 0

    init(size: Int) {
        self.size = size
        buf = .allocate(capacity: size)
        buf.initialize(repeating: 0, count: size)
    }

    deinit { buf.deallocate() }

    @inline(__always) func process(_ x: Float, feedback: Float, damp: Float) -> Float {
        let out = buf[idx]
        store = out * (1 - damp) + store * damp
        buf[idx] = x + store * feedback
        idx += 1
        if idx == size { idx = 0 }
        return out
    }
}

private final class AllpassFilter {
    let size: Int
    let buf: UnsafeMutablePointer<Float>
    var idx = 0

    init(size: Int) {
        self.size = size
        buf = .allocate(capacity: size)
        buf.initialize(repeating: 0, count: size)
    }

    deinit { buf.deallocate() }

    @inline(__always) func process(_ x: Float) -> Float {
        let b = buf[idx]
        let out = -x + b
        buf[idx] = x + b * 0.5
        idx += 1
        if idx == size { idx = 0 }
        return out
    }
}

enum Effects {
    /// Adds a stereo reverb of `send` into `outL` / `outR`.
    /// `preDelayFrames` delays the start of the reverb after the dry sound (0 = none).
    static func reverb(send: UnsafePointer<Float>, frames: Int,
                       outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>,
                       sr: Float, room: Float, damping: Float, wet: Float, preDelayFrames: Int = 0) {
        let scale = Double(sr) / 44100.0
        let combTunings = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
        let allpassTunings = [556, 441, 341, 225]
        let spread = 23

        let combsL = combTunings.map { CombFilter(size: max(8, Int(Double($0) * scale))) }
        let combsR = combTunings.map { CombFilter(size: max(8, Int(Double($0 + spread) * scale))) }
        let apL = allpassTunings.map { AllpassFilter(size: max(8, Int(Double($0) * scale))) }
        let apR = allpassTunings.map { AllpassFilter(size: max(8, Int(Double($0 + spread) * scale))) }

        let feedback = clampf(0.7 + room * 0.28, 0.5, 0.98)
        let damp = clampf(damping, 0, 0.95)
        let inputGain: Float = 0.015
        let pre = max(0, preDelayFrames)

        for i in 0..<frames {
            let src = i - pre
            let x = (src >= 0 ? send[src] : 0) * inputGain
            var sumL: Float = 0
            var sumR: Float = 0
            for c in 0..<8 {
                sumL += combsL[c].process(x, feedback: feedback, damp: damp)
                sumR += combsR[c].process(x, feedback: feedback, damp: damp)
            }
            for a in 0..<4 {
                sumL = apL[a].process(sumL)
                sumR = apR[a].process(sumR)
            }
            outL[i] += sumL * wet
            outR[i] += sumR * wet
        }
    }

    /// Adds a ping-pong echo of `send` into `outL` / `outR`.
    static func pingPongDelay(send: UnsafePointer<Float>, frames: Int,
                              outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>,
                              delayFrames: Int, feedback: Float, damp: Float, gain: Float) {
        let size = max(delayFrames, 16)
        let bufL = UnsafeMutablePointer<Float>.allocate(capacity: size)
        let bufR = UnsafeMutablePointer<Float>.allocate(capacity: size)
        bufL.initialize(repeating: 0, count: size)
        bufR.initialize(repeating: 0, count: size)
        defer {
            bufL.deallocate()
            bufR.deallocate()
        }
        var idx = 0
        var lpL: Float = 0
        var lpR: Float = 0
        for i in 0..<frames {
            let inp = send[i]
            let yL = bufL[idx]
            let yR = bufR[idx]
            lpL = yL * (1 - damp) + lpL * damp
            lpR = yR * (1 - damp) + lpR * damp
            bufL[idx] = inp + lpR * feedback
            bufR[idx] = lpL * feedback
            outL[i] += yL * gain
            outR[i] += yR * gain
            idx += 1
            if idx == size { idx = 0 }
        }
    }

    /// Adds vinyl crackle (soft random ticks, about nine a second) and a faint hiss on top of the
    /// finished mix. Deterministic (fixed noise seeds). Output stays within +-0.98.
    static func addCrackle(l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>,
                           frames: Int, sr: Float, level: Float) {
        guard level > 0 else { return }
        var tick = Noise(seed: 424_242)
        var hissNoise = Noise(seed: 97_531)
        var env: Float = 0
        let threshold: Float = 1 - 9 / sr
        for i in 0..<frames {
            let u = abs(tick.next())
            let h = hissNoise.next()
            if u > threshold { env = level * (0.35 + 0.65 * abs(h)) }
            var v = h * level * 0.05
            if env > 0.00001 {
                v += h * env
                env *= 0.93
            } else {
                env = 0
            }
            l[i] = min(max(l[i] + v, -0.98), 0.98)
            r[i] = min(max(r[i] + v * 0.85, -0.98), 0.98)
        }
    }
}

// MARK: - Lo-fi tape chain

enum LoFi {
    /// Runs the stereo mix through a worn-tape chain, in place: slow pitch wobble (tape wow and
    /// flutter), sample-rate and bit reduction, then a low-pass filter.
    /// - Parameters:
    ///   - cutoff: low-pass in Hz (at or above 0.4 x the sample rate it is skipped).
    ///   - bitHold: hold every n-th sample (1 = off); 2 = half the sample rate.
    ///   - bits: bit depth (16 or more = off).
    ///   - wowMs: depth of the pitch wobble in milliseconds of delay (0 = off).
    static func process(l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>, frames: Int, sr: Float,
                        cutoff: Float, bitHold: Int, bits: Int, wowMs: Float) {
        let hold = max(1, bitHold)
        let levels: Float = bits >= 16 ? 0 : Float(1 << (min(max(bits, 4), 15) - 1))
        let useLP = cutoff < sr * 0.4
        var lpL = SVF(cutoff: min(cutoff, sr * 0.45), q: 0.75, sr: sr)
        var lpR = SVF(cutoff: min(cutoff, sr * 0.45), q: 0.75, sr: sr)

        let useWow = wowMs > 0.001
        let base = 0.006 * sr
        let depth = min(wowMs, 4) * 0.001 * sr
        let size = Int(base + depth) + 16
        let bufL = UnsafeMutablePointer<Float>.allocate(capacity: size)
        let bufR = UnsafeMutablePointer<Float>.allocate(capacity: size)
        bufL.initialize(repeating: 0, count: size)
        bufR.initialize(repeating: 0, count: size)
        defer {
            bufL.deallocate()
            bufR.deallocate()
        }
        var w = 0
        var heldL: Float = 0
        var heldR: Float = 0
        var holdCount = 0
        let twoPi = 2 * Float.pi
        let invSr = 1 / sr

        for i in 0..<frames {
            var xl = l[i]
            var xr = r[i]
            if useWow {
                bufL[w] = xl
                bufR[w] = xr
                let t = Float(i) * invSr
                // A slow "wow" plus only a whisper of fast "flutter": the fast part was far too strong
                // (about 27 cents of warble), real tape flutter is well under half a percent.
                let wobble = 0.7 * sin(twoPi * 0.55 * t) + 0.03 * sin(twoPi * 6.3 * t + 1.3)
                var rd = Float(w) - (base + depth * wobble)
                if rd < 0 { rd += Float(size) }
                let i0 = min(Int(rd), size - 1)
                let fr = rd - Float(i0)
                let i1 = i0 + 1 >= size ? 0 : i0 + 1
                xl = bufL[i0] * (1 - fr) + bufL[i1] * fr
                xr = bufR[i0] * (1 - fr) + bufR[i1] * fr
                w += 1
                if w == size { w = 0 }
            }
            if hold > 1 {
                if holdCount == 0 {
                    heldL = xl
                    heldR = xr
                }
                holdCount += 1
                if holdCount >= hold { holdCount = 0 }
                xl = heldL
                xr = heldR
            }
            if levels > 0 {
                xl = (xl * levels).rounded() / levels
                xr = (xr * levels).rounded() / levels
            }
            if useLP {
                xl = lpL.lowpass(xl)
                xr = lpR.lowpass(xr)
            }
            l[i] = xl
            r[i] = xr
        }
    }
}
