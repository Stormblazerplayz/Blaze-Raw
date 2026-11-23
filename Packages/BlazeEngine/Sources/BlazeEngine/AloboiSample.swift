import Foundation

/// The "Aloboi Synth" sound: a gritty, slightly detuned stack of synth tones recorded into a SoundFont
/// (Assets/Aloboi_Synth.sf2). The raw samples live in AloboiSampleData.swift as base64 text (made by
/// scripts/make_aloboi_sample.py), so the engine needs no files at run time and works the same on iOS,
/// macOS and Linux.
///
/// The sample is a steady tone that repeats (a loop of 3712 frames holds exactly 20 cycles of its main
/// pitch). It is played like a sampler plays a note: faster for higher notes, slower for lower notes, and
/// looping at the loop points for as long as the note is held. Everything else about the note (envelope,
/// filter, vibrato, stereo detune) comes from the SynthPatch that uses it.
final class AloboiSample {
    /// One shared copy (decoding the text takes a few milliseconds, and happens only once).
    static let shared = AloboiSample()

    /// Mono samples from frame 0 to the end of the loop, as -1...1.
    let frames: [Float]
    let loopStart: Int
    let loopEnd: Int
    let loopLength: Int
    /// The frequency the sample sounds at when played unchanged.
    let rootHz: Double
    /// The rate the sample was recorded at.
    let rate: Double

    private init() {
        rate = AloboiSampleData.sampleRate
        rootHz = AloboiSampleData.rootHz
        loopStart = AloboiSampleData.loopStart
        loopEnd = AloboiSampleData.loopEnd
        loopLength = AloboiSampleData.loopEnd - AloboiSampleData.loopStart
        var out = [Float]()
        if let bytes = Data(base64Encoded: AloboiSampleData.base64, options: .ignoreUnknownCharacters) {
            let count = bytes.count / 2
            out.reserveCapacity(count)
            bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for i in 0..<count {
                    // Little-endian 16-bit, read byte by byte so alignment never matters.
                    let lo = UInt16(raw[2 * i])
                    let hi = UInt16(raw[2 * i + 1])
                    out.append(Float(Int16(bitPattern: lo | (hi << 8))) * (1.0 / 32768.0))
                }
            }
        }
        // If the text could not be read (it should always be readable) fall back to one silent loop, so
        // the engine still renders and never crashes.
        if out.count < AloboiSampleData.loopEnd {
            out = [Float](repeating: 0, count: AloboiSampleData.loopEnd)
        }
        frames = out
    }

    /// Source frames to step per output frame for a note of `hz` rendered at `sr`.
    /// Notes far from the sample's own pitch are folded by octaves so a very high note does not fold back
    /// (alias) and a very low note does not slow the sample down to a crawl.
    func increment(forHz hz: Float, sr: Float) -> Double {
        var ratio = Double(hz) / rootHz
        if !(ratio > 0) { return 0 }
        while ratio > 4.5 { ratio *= 0.5 }
        while ratio < 0.3 { ratio *= 2 }
        return ratio * rate / Double(sr)
    }

    /// Moves a read position on by `step` source frames, jumping back by one loop length at the loop end.
    @inline(__always) func advance(_ pos: inout Double, _ step: Double) {
        pos += step
        let end = Double(loopEnd)
        if pos >= end { pos -= Double(loopLength) * ((pos - Double(loopStart)) / Double(loopLength)).rounded(.down) }
    }

    /// The sample at a (fractional) position, with 4-point Hermite interpolation. Neighbours past the loop
    /// end wrap round to the loop start, so the loop point is smooth.
    @inline(__always) func read(_ pos: Double) -> Float {
        let base = Int(pos)
        let t = Float(pos - Double(base))
        let a = frames[wrap(base - 1)]
        let b = frames[wrap(base)]
        let c = frames[wrap(base + 1)]
        let d = frames[wrap(base + 2)]
        let c1 = 0.5 * (c - a)
        let c2 = a - 2.5 * b + 2 * c - 0.5 * d
        let c3 = 0.5 * (d - a) + 1.5 * (b - c)
        return ((c3 * t + c2) * t + c1) * t + b
    }

    @inline(__always) private func wrap(_ i: Int) -> Int {
        if i >= loopEnd { return i - loopLength }
        return i < 0 ? 0 : i
    }
}
