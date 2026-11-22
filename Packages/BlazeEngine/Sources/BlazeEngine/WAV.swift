import Foundation

/// Saves audio as a standard 16-bit stereo WAV file (plays everywhere, easy to share).
public enum WAV {
    public static func data(left: [Float], right: [Float], sampleRate: Int) -> Data {
        let frames = min(left.count, right.count)
        var samples = [Int16](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            let l = min(max(left[i], -1), 1)
            let r = min(max(right[i], -1), 1)
            samples[2 * i] = Int16((l * 32767).rounded())
            samples[2 * i + 1] = Int16((r * 32767).rounded())
        }

        let dataBytes = frames * 4
        var header = Data()
        func put32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        header.append(contentsOf: Array("RIFF".utf8))
        put32(UInt32(36 + dataBytes))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        put32(16)                       // PCM header size
        put16(1)                        // PCM
        put16(2)                        // stereo
        put32(UInt32(sampleRate))
        put32(UInt32(sampleRate * 4))   // byte rate
        put16(4)                        // block align
        put16(16)                       // bits per sample
        header.append(contentsOf: Array("data".utf8))
        put32(UInt32(dataBytes))

        var out = header
        samples.withUnsafeBytes { out.append(contentsOf: $0) }
        return out
    }

    public static func data(for song: RenderedSong) -> Data {
        data(left: song.left, right: song.right, sampleRate: song.sampleRate)
    }

    public static func write(_ song: RenderedSong, to url: URL) throws {
        try data(for: song).write(to: url, options: .atomic)
    }
}
