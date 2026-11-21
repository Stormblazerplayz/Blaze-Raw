import Foundation

// MARK: - Random numbers

/// Small, fast, seedable random number generator (SplitMix64).
/// The same seed always gives the same song.
public struct SeededRNG {
    public let base: UInt64
    private var state: UInt64

    public init(seed: UInt64) {
        base = seed
        state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Float in [0, 1)
    public mutating func float() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    /// Double in [0, 1)
    public mutating func double() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    public mutating func int(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    public mutating func chance(_ p: Double) -> Bool {
        double() < p
    }

    public mutating func pick<T>(_ items: [T]) -> T {
        items[int(0...(items.count - 1))]
    }

    /// A new, independent generator derived from this one's *original seed*.
    /// Using forks means adding or removing an instrument never changes the notes
    /// that the other instruments play.
    public func fork(_ salt: UInt64) -> SeededRNG {
        SeededRNG(seed: (base ^ (salt &* 0xD6E8_FEB8_6659_FD93)) &+ 0x9E37_79B9_7F4A_7C15)
    }
}

/// Cheap white-noise generator (xorshift32), output in [-1, 1).
struct Noise {
    var s: UInt32
    init(seed: UInt32) { s = seed == 0 ? 0x1234_5678 : seed }
    @inline(__always) mutating func next() -> Float {
        s ^= s << 13
        s ^= s >> 17
        s ^= s << 5
        return Float(Int32(bitPattern: s)) * (1.0 / 2_147_483_648.0)
    }
}

// MARK: - Small math helpers

@inline(__always) func clampf(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
    min(max(x, lo), hi)
}

/// Smooth tanh-like soft clipper (Pade approximation). Output stays within [-1, 1].
@inline(__always) func softClip(_ x: Float) -> Float {
    let c = min(max(x, -3), 3)
    let c2 = c * c
    return c * (27 + c2) / (27 + 9 * c2)
}

@inline(__always) func smoothstep(_ x: Float) -> Float {
    let c = min(max(x, 0), 1)
    return c * c * (3 - 2 * c)
}

@inline(__always) func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}

@inline(__always) func midiToHz(_ midi: Double) -> Double {
    440.0 * pow(2.0, (midi - 69.0) / 12.0)
}

// MARK: - Oscillator helpers (band-limited with PolyBLEP)

@inline(__always) func polyBLEP(_ t: Float, _ dt: Float) -> Float {
    if t < dt {
        let x = t / dt
        return x + x - x * x - 1
    } else if t > 1 - dt {
        let x = (t - 1) / dt
        return x * x + x + x + 1
    }
    return 0
}

@inline(__always) func sawBL(_ phase: Float, _ dt: Float) -> Float {
    2 * phase - 1 - polyBLEP(phase, dt)
}

@inline(__always) func squareBL(_ phase: Float, _ dt: Float, _ pw: Float) -> Float {
    var p2 = phase - pw
    if p2 < 0 { p2 += 1 }
    let v: Float = phase < pw ? 1 : -1
    return v + polyBLEP(phase, dt) - polyBLEP(p2, dt)
}

@inline(__always) func advance(_ phase: inout Float, _ dt: Float) {
    phase += dt
    if phase >= 1 { phase -= 1 }
}

/// ADSR envelope evaluated at time `t` for a note held `dur` seconds, then released over `r` seconds.
@inline(__always) func adsrLevel(_ t: Float, _ dur: Float, _ a: Float, _ d: Float, _ s: Float, _ r: Float) -> Float {
    var lvl: Float
    if t < a {
        lvl = a > 0 ? t / a : 1
    } else if t < a + d {
        lvl = 1 - (1 - s) * ((t - a) / max(d, 0.0001))
    } else {
        lvl = s
    }
    if t > dur {
        let rt = (t - dur) / max(r, 0.0001)
        lvl *= max(0, 1 - rt)
    }
    return lvl
}

// MARK: - Mixing

/// How a sound is placed in the mix.
struct Mix {
    let gain: Float
    let gL: Float
    let gR: Float
    let rev: Float
    let dly: Float
    let duck: Float

    init(gain: Float, pan: Float = 0, reverb: Float = 0, delay: Float = 0, duck: Float = 0) {
        let p = clampf(pan, -1, 1)
        let a = (p + 1) * 0.25 * Float.pi
        self.gain = gain
        self.gL = gain * cos(a) * 1.4142135
        self.gR = gain * sin(a) * 1.4142135
        self.rev = reverb
        self.dly = delay
        self.duck = duck
    }

    /// Same sound, different place in the stereo field.
    func with(pan: Float) -> Mix {
        Mix(gain: gain, pan: pan, reverb: rev, delay: dly, duck: duck)
    }
}

/// All the audio buffers a song is mixed into.
final class Bus {
    let frames: Int
    let l: UnsafeMutablePointer<Float>
    let r: UnsafeMutablePointer<Float>
    let rev: UnsafeMutablePointer<Float>
    let dly: UnsafeMutablePointer<Float>

    init(frames: Int) {
        self.frames = frames
        l = .allocate(capacity: frames)
        r = .allocate(capacity: frames)
        rev = .allocate(capacity: frames)
        dly = .allocate(capacity: frames)
        l.initialize(repeating: 0, count: frames)
        r.initialize(repeating: 0, count: frames)
        rev.initialize(repeating: 0, count: frames)
        dly.initialize(repeating: 0, count: frames)
    }

    deinit {
        l.deallocate()
        r.deallocate()
        rev.deallocate()
        dly.deallocate()
    }

    @inline(__always) func add(_ i: Int, _ x: Float, _ m: Mix, _ duckGain: Float) {
        let v = x * duckGain
        l[i] += v * m.gL
        r[i] += v * m.gR
        rev[i] += v * m.rev
        dly[i] += v * m.dly
    }

    @inline(__always) func addStereo(_ i: Int, _ xl: Float, _ xr: Float, _ m: Mix, _ duckGain: Float) {
        let vl = xl * duckGain
        let vr = xr * duckGain
        l[i] += vl * m.gL
        r[i] += vr * m.gR
        let mono = (vl + vr) * 0.5
        rev[i] += mono * m.rev
        dly[i] += mono * m.dly
    }
}

/// Everything a synth needs while rendering.
final class RenderContext {
    let sr: Float
    let bpm: Double
    let spb: Double          // seconds per beat
    let frames: Int          // total frames, including the reverb tail
    let bodyFrames: Int      // frames of actual music (no tail)
    let bus: Bus
    let tuning: TuningSystem
    let grit: Float
    let intensity: Float
    let duckBlocks: Int
    let duckEnv: UnsafeMutablePointer<Float>
    static let duckShift = 4   // one envelope value per 16 frames

    init(sr: Float, bpm: Double, frames: Int, bodyFrames: Int, tuning: TuningSystem, grit: Float, intensity: Float) {
        self.sr = sr
        self.bpm = bpm
        self.spb = 60.0 / bpm
        self.frames = frames
        self.bodyFrames = bodyFrames
        self.bus = Bus(frames: frames)
        self.tuning = tuning
        self.grit = grit
        self.intensity = intensity
        duckBlocks = (frames >> RenderContext.duckShift) + 2
        duckEnv = .allocate(capacity: duckBlocks)
        duckEnv.initialize(repeating: 0, count: duckBlocks)
    }

    deinit { duckEnv.deallocate() }

    @inline(__always) func frame(beat: Double) -> Int {
        Int((beat * spb * Double(sr)).rounded())
    }

    /// Sidechain gain: 1 = untouched, lower = ducked by the kick drum.
    @inline(__always) func duck(_ i: Int, _ amount: Float) -> Float {
        1 - amount * duckEnv[i >> RenderContext.duckShift]
    }

    /// Builds the "pumping" curve from the kick drum hit times.
    func buildDuck(kickFrames: [Int]) {
        let release = 0.17 * sr
        var k = 0
        let sorted = kickFrames.sorted()
        for b in 0..<duckBlocks {
            let f = b << RenderContext.duckShift
            while k + 1 < sorted.count && sorted[k + 1] <= f { k += 1 }
            if sorted.isEmpty || sorted[k] > f {
                duckEnv[b] = 0
            } else {
                let since = Float(f - sorted[k])
                // quick fall then smooth recovery
                let x = min(since / release, 1)
                duckEnv[b] = (1 - x) * (1 - x)
            }
        }
    }
}
