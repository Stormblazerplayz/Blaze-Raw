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
    static func reverb(send: UnsafePointer<Float>, frames: Int,
                       outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>,
                       sr: Float, room: Float, damping: Float, wet: Float) {
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

        for i in 0..<frames {
            let x = send[i] * inputGain
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
}
