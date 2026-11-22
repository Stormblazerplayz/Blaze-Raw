import Foundation

// MARK: - Basic building blocks

struct NoteEvent {
    var beat: Double
    var dur: Double
    /// Semitones above the song's tonic (can be negative).
    var semis: Int
    var vel: Float
    var aux: Int = 0
}

enum SectionKind: Int {
    case intro, verse, chorus, breakdown, outro
}

struct Section {
    let kind: SectionKind
    let startBar: Int
    let bars: Int
    let progression: [Chord]
    /// True when the next section is a chorus (so we build up with a fill and riser).
    let preDrop: Bool
    var endBar: Int { startBar + bars }
}

/// One note of the main melody ("hook"), written relative to the current chord so it follows the harmony.
struct HookNote {
    let step: Int       // 16th-note step inside a 2-bar window (0..<32)
    let len: Int        // length in 16th steps
    let offset: Int     // scale-degree offset from the chord root
}

struct SongPlan {
    let settings: SongSettings
    let key: Int
    let profile: MoodProfile
    let tuning: TuningSystem
    let sections: [Section]
    let totalBars: Int
    let hook: [HookNote]
    let hookAlt: [HookNote]
    let hookMean: Double
    let rng: SeededRNG
    let fallbackKinds: Set<Int>

    var bpm: Double { settings.tempo }
    var tonicMidi: Int { 24 + key }

    // MARK: lookups

    func sectionIndex(atBar bar: Int) -> Int {
        for (i, s) in sections.enumerated() where bar >= s.startBar && bar < s.endBar { return i }
        return max(0, sections.count - 1)
    }

    func chord(atBar bar: Int) -> Chord {
        let s = sections[sectionIndex(atBar: bar)]
        let k = ((bar - s.startBar) / profile.barsPerChord) % s.progression.count
        return s.progression[k]
    }

    /// Beat position of a 16th-note step in a bar (with swing on the off-steps).
    func stepBeat(_ bar: Int, _ step: Int) -> Double {
        var b = Double(bar * 4) + Double(step) * 0.25
        if step % 2 == 1 { b += profile.swing * 0.25 }
        return b
    }

    // MARK: how loud each instrument is in each part of the song

    static func baseLevel(_ inst: InstrumentKind, _ kind: SectionKind) -> Float {
        switch inst {
        case .drums:
            switch kind {
            case .intro: return 0.55
            case .verse: return 0.75
            case .chorus: return 1.0
            case .breakdown: return 0.0
            case .outro: return 0.5
            }
        case .subBass:
            switch kind {
            case .intro: return 0
            case .verse: return 0.9
            case .chorus: return 1.0
            case .breakdown: return 0.7
            case .outro: return 0.6
            }
        case .growlBass:
            return kind == .chorus ? 1.0 : 0
        case .pad:
            switch kind {
            case .intro: return 0.85
            case .verse: return 0.7
            case .chorus: return 0.8
            case .breakdown: return 1.0
            case .outro: return 0.8
            }
        case .lead:
            return kind == .chorus ? 1.0 : 0
        case .piano:
            switch kind {
            case .intro: return 1.0
            case .verse: return 0.9
            case .chorus: return 0.7
            case .breakdown: return 1.0
            case .outro: return 0.9
            }
        case .pluck:
            switch kind {
            case .intro: return 0.5
            case .verse: return 0.7
            case .chorus: return 1.0
            case .breakdown: return 0
            case .outro: return 0
            }
        case .guitar:
            switch kind {
            case .intro: return 1.0
            case .verse: return 0.9
            case .chorus: return 1.0
            case .breakdown: return 0
            case .outro: return 0.8
            }
        case .strings:
            switch kind {
            case .intro: return 0.6
            case .verse: return 0.6
            case .chorus: return 1.0
            case .breakdown: return 1.0
            case .outro: return 0.9
            }
        case .bells:
            switch kind {
            case .intro: return 0.9
            case .verse: return 0
            case .chorus: return 0.6
            case .breakdown: return 1.0
            case .outro: return 0.9
            }
        case .arp:
            switch kind {
            case .intro: return 0.5
            case .verse: return 0.7
            case .chorus: return 1.0
            case .breakdown: return 0
            case .outro: return 0
            }
        }
    }

    func level(_ inst: InstrumentKind, _ kind: SectionKind) -> Float {
        guard settings.instruments.contains(inst) else { return 0 }
        let base = SongPlan.baseLevel(inst, kind)
        if base > 0 { return base }
        // If nothing at all would play in this part of the song, let everything play softly.
        if fallbackKinds.contains(kind.rawValue) && inst != .drums { return 0.75 }
        return 0
    }

    func vel(_ level: Float, _ rng: inout SeededRNG) -> Float {
        level * (0.84 + 0.16 * rng.float())
    }

    // MARK: voicings

    /// Chord tones packed closely around a centre note (semitones above the tonic).
    func voicing(_ chord: Chord, center: Int) -> [Int] {
        var out = Set<Int>()
        let base = tonicMidi
        for s in chord.tones {
            var m = base + s
            while m < center - 6 { m += 12 }
            while m >= center + 6 { m -= 12 }
            out.insert(m - base)
        }
        return out.sorted()
    }

    /// The chord's root placed in a low register (semitones above the tonic).
    func lowRoot(_ chord: Chord, lowest: Int) -> Int {
        var m = tonicMidi + chord.rootSemis
        while m < lowest { m += 12 }
        while m >= lowest + 12 { m -= 12 }
        return m - tonicMidi
    }

    func hookSemis(_ n: HookNote, chord: Chord) -> Int {
        profile.scale.semitone(degree: chord.rootDegree + n.offset)
    }

    /// Octave shift (a multiple of 12) that moves the hook's average pitch near `center` (a MIDI note).
    func hookShift(center: Int) -> Int {
        let mean = Double(tonicMidi) + hookMean
        return Int(((Double(center) - mean) / 12.0).rounded()) * 12
    }

    // MARK: - Bass

    func bassRoot(_ chord: Chord) -> Int {
        var r = chord.rootSemis % 12
        if r > 6 { r -= 12 }
        let off = (tonicMidi + 12 > 42) ? 0 : 12
        return r + off
    }

    func bassNotes() -> [NoteEvent] {
        var g = rng.fork(11)
        var notes: [NoteEvent] = []
        let low = settings.intensity < 0.45
        for sec in sections {
            let lvl = level(.subBass, sec.kind)
            if lvl <= 0 { continue }
            for b in 0..<sec.bars {
                let bar = sec.startBar + b
                let base = bassRoot(chord(atBar: bar))
                let pattern: [(Int, Int, Float)]
                if sec.kind == .breakdown {
                    pattern = [(0, 16, 0.9)]
                } else {
                    switch profile.kit {
                    case .fourOnFloor:
                        pattern = low ? [(0, 8, 1), (8, 8, 0.9)] : [(2, 2, 1), (6, 2, 0.9), (10, 2, 1), (14, 2, 0.9)]
                    case .halfTime:
                        pattern = profile.swing > 0.15
                            ? [(0, 6, 1), (6, 4, 0.7), (10, 6, 0.9)]
                            : [(0, 10, 1), (10, 6, 0.8)]
                    case .breakbeat:
                        pattern = [(0, 3, 1), (3, 2, 0.8), (6, 2, 0.9), (10, 3, 1), (14, 2, 0.8)]
                    case .epic:
                        pattern = [(0, 16, 1)]
                    }
                }
                for (step, len, v) in pattern {
                    var semis = base
                    if step != 0 && profile.kit != .epic && g.chance(0.18) { semis += 12 }
                    notes.append(NoteEvent(beat: stepBeat(bar, step),
                                           dur: Double(len) * 0.25 * 0.94,
                                           semis: semis,
                                           vel: lvl * v * (0.92 + 0.08 * g.float())))
                }
            }
        }
        return notes
    }

    func growlNotes() -> [NoteEvent] {
        var g = rng.fork(12)
        var notes: [NoteEvent] = []
        for sec in sections {
            let lvl = level(.growlBass, sec.kind)
            if lvl <= 0 { continue }
            // One wobble speed per section keeps it musical.
            let wobble: Int
            switch profile.kit {
            case .halfTime: wobble = g.pick([0, 1, 2])
            case .fourOnFloor: wobble = g.pick([1, 2, 1])
            case .breakbeat: wobble = g.pick([1, 3, 2])
            case .epic: wobble = 0
            }
            for b in 0..<sec.bars {
                let bar = sec.startBar + b
                let base = bassRoot(chord(atBar: bar)) + 12
                let pattern: [(Int, Int)]
                switch profile.kit {
                case .fourOnFloor: pattern = [(0, 2), (3, 1), (6, 2), (8, 2), (11, 1), (14, 2)]
                case .halfTime: pattern = [(0, 6), (6, 2), (8, 4), (12, 2), (14, 2)]
                case .breakbeat: pattern = [(0, 2), (2, 1), (3, 1), (6, 2), (10, 2), (12, 1), (14, 2)]
                case .epic: pattern = [(0, 16)]
                }
                for (step, len) in pattern {
                    var semis = base
                    let r = g.double()
                    if r > 0.95 { semis += 10 } else if r > 0.85 { semis += 7 } else if r > 0.7 { semis += 12 }
                    notes.append(NoteEvent(beat: stepBeat(bar, step),
                                           dur: Double(len) * 0.25 * 0.92,
                                           semis: semis,
                                           vel: lvl * (0.85 + 0.15 * g.float()),
                                           aux: wobble))
                }
            }
        }
        return notes
    }

    // MARK: - Pads, strings

    func chordHoldNotes(_ inst: InstrumentKind, center: Int, doubleRoot: Bool) -> [NoteEvent] {
        var g = rng.fork(inst == .pad ? 13 : 14)
        var notes: [NoteEvent] = []
        for sec in sections {
            let lvl = level(inst, sec.kind)
            if lvl <= 0 { continue }
            var b = 0
            while b < sec.bars {
                let bar = sec.startBar + b
                let chord = self.chord(atBar: bar)
                let len = min(profile.barsPerChord, sec.bars - b)
                var tones = voicing(chord, center: center)
                if doubleRoot, let lowest = tones.first {
                    // Add the chord root just below the lowest note for a fuller sound.
                    var r = chord.rootSemis
                    while r >= lowest { r -= 12 }
                    while r < lowest - 12 { r += 12 }
                    tones.insert(r, at: 0)
                }
                // Gentle build-up through the intro.
                var v = lvl
                if sec.kind == .intro { v *= 0.6 + 0.4 * Float(b) / Float(max(1, sec.bars - 1)) }
                for t in tones {
                    notes.append(NoteEvent(beat: Double(bar * 4),
                                           dur: Double(len * 4) + 0.05,
                                           semis: t,
                                           vel: v * (0.9 + 0.1 * g.float()),
                                           aux: sec.kind.rawValue))
                }
                b += len
            }
        }
        return notes
    }

    func padNotes() -> [NoteEvent] { chordHoldNotes(.pad, center: 60, doubleRoot: false) }
    func stringNotes() -> [NoteEvent] { chordHoldNotes(.strings, center: 64, doubleRoot: true) }

    // MARK: - Lead melody

    func hookEvents(center: Int, onlyStrong: Bool = false) -> [(note: NoteEvent, kind: SectionKind)] {
        let shift = hookShift(center: center)
        var out: [(note: NoteEvent, kind: SectionKind)] = []
        for sec in sections {
            var b = 0
            while b < sec.bars {
                let useAlt = (b / 2) % 2 == 1
                let motif = useAlt ? hookAlt : hook
                for n in motif {
                    let barOffset = n.step / 16
                    let bar = sec.startBar + b + barOffset
                    if bar >= sec.endBar { continue }
                    let step = n.step % 16
                    let chord = self.chord(atBar: bar)
                    let semis = hookSemis(n, chord: chord) + shift
                    if onlyStrong && step % 4 != 0 { continue }
                    let ev = NoteEvent(beat: stepBeat(bar, step), dur: Double(n.len) * 0.25, semis: semis, vel: 1, aux: n.step)
                    out.append((note: ev, kind: sec.kind))
                }
                b += 2
            }
        }
        return out
    }

    func leadNotes() -> [NoteEvent] {
        var g = rng.fork(15)
        var notes: [NoteEvent] = []
        for (ev, kind) in hookEvents(center: 72) {
            let lvl = level(.lead, kind)
            if lvl <= 0 { continue }
            var e = ev
            e.dur *= 0.92
            e.vel = vel(lvl, &g)
            notes.append(e)
        }
        return notes
    }

    func bellNotes() -> [NoteEvent] {
        var g = rng.fork(16)
        var notes: [NoteEvent] = []
        for (ev, kind) in hookEvents(center: 84) {
            let lvl = level(.bells, kind)
            if lvl <= 0 { continue }
            let step = ev.aux % 16
            let keep: Bool
            if lvl >= 0.9 { keep = step % 2 == 0 || g.chance(0.2) } else { keep = step % 8 == 0 }
            if !keep { continue }
            var e = ev
            e.dur = max(e.dur, 1.5)
            e.vel = vel(lvl, &g) * 0.9
            notes.append(e)
        }
        return notes
    }

    // MARK: - Piano, guitar, pluck, arp

    func pianoNotes() -> [NoteEvent] {
        var g = rng.fork(17)
        var notes: [NoteEvent] = []
        for sec in sections {
            let lvl = level(.piano, sec.kind)
            if lvl <= 0 { continue }
            var style = profile.pianoStyle
            if sec.kind == .intro || sec.kind == .breakdown || sec.kind == .outro { style = 3 }
            for b in 0..<sec.bars {
                let bar = sec.startBar + b
                let chord = self.chord(atBar: bar)
                let tones = voicing(chord, center: 58)
                guard !tones.isEmpty else { continue }
                switch style {
                case 0, 2:
                    let hits: [(Int, Int)] = style == 0 ? [(0, 10), (10, 6)] : [(2, 2), (6, 2), (10, 2), (14, 2)]
                    for (step, len) in hits {
                        for (k, t) in tones.enumerated() {
                            notes.append(NoteEvent(beat: stepBeat(bar, step) + Double(k) * 0.01,
                                                   dur: Double(len) * 0.25,
                                                   semis: t,
                                                   vel: vel(lvl, &g) * 0.85))
                        }
                    }
                case 1:
                    let order = [0, 1, 2, 1, 0, 1, 2, tones.count - 1]
                    for k in 0..<8 {
                        let t = tones[order[k] % tones.count] + (k == 0 ? -12 : 0)
                        notes.append(NoteEvent(beat: stepBeat(bar, k * 2),
                                               dur: 0.75,
                                               semis: t,
                                               vel: vel(lvl, &g) * (k % 4 == 0 ? 1.0 : 0.75)))
                    }
                default:
                    let order = [0, 1, 2, min(3, tones.count - 1)]
                    for k in 0..<4 {
                        let t = tones[order[k] % tones.count] + (k == 0 ? -12 : 0)
                        notes.append(NoteEvent(beat: stepBeat(bar, k * 4),
                                               dur: 1.8,
                                               semis: t,
                                               vel: vel(lvl, &g) * (k == 0 ? 1.0 : 0.7)))
                    }
                }
            }
        }
        return notes
    }

    func guitarNotes() -> [NoteEvent] {
        var g = rng.fork(18)
        var notes: [NoteEvent] = []
        for sec in sections {
            let lvl = level(.guitar, sec.kind)
            if lvl <= 0 { continue }
            let strum = profile.guitarStyle == 1 && sec.kind != .intro && sec.kind != .outro
            for b in 0..<sec.bars {
                let bar = sec.startBar + b
                let chord = self.chord(atBar: bar)
                var strings = [lowRoot(chord, lowest: 40)]
                strings.append(contentsOf: voicing(chord, center: 60))
                if strum {
                    let hits: [(Int, Float)] = [(0, 1.0), (6, 0.7), (8, 0.9), (14, 0.7)]
                    for (step, v) in hits {
                        let down = step != 6 && step != 14
                        let order = down ? Array(strings.indices) : Array(strings.indices.reversed())
                        for (k, idx) in order.enumerated() {
                            notes.append(NoteEvent(beat: stepBeat(bar, step) + Double(k) * 0.035,
                                                   dur: 1.2,
                                                   semis: strings[idx],
                                                   vel: vel(lvl, &g) * v * 0.8))
                        }
                    }
                } else {
                    let order = [0, 2, 3, 2, 1, 2, 3, 2]
                    for k in 0..<8 {
                        let idx = order[k] % strings.count
                        notes.append(NoteEvent(beat: stepBeat(bar, k * 2),
                                               dur: 1.6,
                                               semis: strings[idx],
                                               vel: vel(lvl, &g) * (k == 0 ? 1.0 : 0.75)))
                    }
                }
            }
        }
        return notes
    }

    func pluckNotes() -> [NoteEvent] {
        var g = rng.fork(19)
        var notes: [NoteEvent] = []
        // A short riff that repeats every bar, written as (step, chord tone index, octave).
        let stepSets: [[Int]] = [
            [0, 3, 6, 8, 11, 14], [0, 2, 6, 8, 10, 14], [0, 4, 6, 10, 12, 15], [1, 3, 6, 9, 11, 14]
        ]
        let steps = g.pick(stepSets)
        let riff: [(Int, Int, Int)] = steps.map { ($0, g.int(0...3), g.chance(0.25) ? 1 : 0) }
        for sec in sections {
            let lvl = level(.pluck, sec.kind)
            if lvl <= 0 { continue }
            for b in 0..<sec.bars {
                let bar = sec.startBar + b
                let chord = self.chord(atBar: bar)
                var tones = voicing(chord, center: 66)
                if tones.count < 4, let f = tones.first { tones.append(f + 12) }
                for (step, ti, oct) in riff {
                    notes.append(NoteEvent(beat: stepBeat(bar, step),
                                           dur: 0.4,
                                           semis: tones[ti % tones.count] + 12 * oct,
                                           vel: vel(lvl, &g) * 0.9))
                }
            }
        }
        return notes
    }

    func arpNotes() -> [NoteEvent] {
        var g = rng.fork(20)
        var notes: [NoteEvent] = []
        let patterns: [[Int]] = [
            [0, 1, 2, 3, 2, 1, 0, 1], [0, 2, 1, 3, 2, 3, 1, 2], [0, 0, 2, 1, 3, 2, 1, 3]
        ]
        let pattern = g.pick(patterns)
        let sparse = settings.intensity < 0.4
        for sec in sections {
            let lvl = level(.arp, sec.kind)
            if lvl <= 0 { continue }
            for b in 0..<sec.bars {
                let bar = sec.startBar + b
                let chord = self.chord(atBar: bar)
                var tones = voicing(chord, center: 72)
                while tones.count < 4 { tones.append((tones.last ?? 0) + 12) }
                for step in 0..<16 {
                    if sparse && step % 2 == 1 { continue }
                    let t = tones[pattern[step % pattern.count] % tones.count]
                    notes.append(NoteEvent(beat: stepBeat(bar, step),
                                           dur: 0.32,
                                           semis: t,
                                           vel: lvl * (step % 4 == 0 ? 1.0 : 0.62) * (0.92 + 0.08 * g.float()),
                                           aux: step))
                }
            }
        }
        return notes
    }
}

// MARK: - Making a plan

enum Composer {
    static func allocate(_ weights: [Double], total: Int) -> [Int] {
        let n = weights.count
        var counts = [Int](repeating: 1, count: n)
        let remaining = total - n
        if remaining <= 0 { return counts }
        let wsum = weights.reduce(0, +)
        var fracs: [(Int, Double)] = []
        for i in 0..<n {
            let ideal = Double(remaining) * weights[i] / wsum
            let fl = Int(ideal.rounded(.down))
            counts[i] += fl
            fracs.append((i, ideal - Double(fl)))
        }
        var used = counts.reduce(0, +)
        fracs.sort { $0.1 > $1.1 }
        var k = 0
        while used < total {
            counts[fracs[k % n].0] += 1
            used += 1
            k += 1
        }
        return counts
    }

    static func nearestChordTone(_ off: Int) -> Int {
        var best = 0
        var bestDist = Int.max
        for c in -4...9 {
            let m = ((c % 7) + 7) % 7
            if m == 0 || m == 2 || m == 4 {
                let d = abs(c - off)
                if d < bestDist { bestDist = d; best = c }
            }
        }
        return best
    }

    static func makeHook(style: Int, rng g: inout SeededRNG) -> [HookNote] {
        let options: [[[Int]]] = [
            [[0, 6, 8, 16, 22, 24], [0, 4, 8, 14, 16, 24]],
            [[0, 3, 6, 8, 11, 16, 19, 22, 24, 27], [0, 3, 6, 10, 12, 16, 19, 22, 26, 28]],
            [[0, 4, 8, 12, 16, 20, 24, 28], [0, 4, 8, 12, 16, 18, 20, 24, 28]],
            [[0, 2, 4, 6, 8, 11, 12, 16, 18, 20, 22, 24, 27, 28, 30], [0, 2, 3, 6, 8, 10, 12, 16, 18, 19, 22, 24, 26, 28, 30]]
        ]
        let onsets = g.pick(options[min(max(style, 0), 3)])
        let maxLen = style == 0 ? 8 : 6
        var off = g.pick([0, 2, 4])
        var notes: [HookNote] = []
        for (i, step) in onsets.enumerated() {
            if i > 0 {
                let r = g.double()
                var d: Int
                if r < 0.15 { d = 0 }
                else if r < 0.45 { d = 1 }
                else if r < 0.75 { d = -1 }
                else if r < 0.87 { d = 2 }
                else if r < 0.97 { d = -2 }
                else { d = g.pick([-3, 3]) }
                off += d
            }
            off = min(max(off, -2), 8)
            if step % 8 == 0 || i == onsets.count - 1 { off = nearestChordTone(off) }
            let next = i + 1 < onsets.count ? onsets[i + 1] : 32
            let len = max(1, min(next - step, maxLen))
            notes.append(HookNote(step: step, len: len, offset: off))
        }
        return notes
    }

    static func makePlan(_ input: SongSettings) -> SongPlan {
        let s = input.clamped()
        let rng = SeededRNG(seed: s.seed)
        var keyRNG = rng.fork(1)
        let key = s.key ?? keyRNG.int(0...11)
        let profile = MoodProfile.profile(for: s.mood)
        let tuning = TuningSystem(tonicHz: midiToHz(Double(24 + key)), just: s.justIntonation)

        // How many bars do we need? Always at least one minute.
        let barSeconds = 4.0 * 60.0 / s.tempo
        let needed = Int((s.lengthSeconds / barSeconds).rounded(.up))
        let totalBars = max(16, ((needed + 3) / 4) * 4)
        let phrases = totalBars / 4

        let kinds: [SectionKind]
        let weights: [Double]
        if phrases <= 5 {
            kinds = [.intro, .verse, .chorus, .outro]
            weights = [1, 1, 2, 1]
        } else if phrases <= 13 {
            kinds = [.intro, .verse, .chorus, .breakdown, .chorus, .outro]
            weights = [1, 1.5, 2, 1, 2, 1]
        } else {
            kinds = [.intro, .verse, .chorus, .breakdown, .verse, .chorus, .breakdown, .chorus, .outro]
            weights = [1, 1.5, 1.5, 1, 1.5, 2, 1, 2, 1]
        }
        let counts = allocate(weights, total: phrases)

        var progRNG = rng.fork(2)
        let idxA = progRNG.int(0...(profile.progressions.count - 1))
        let progA = profile.progressions[idxA].map { profile.chord(rootDegree: $0) }
        let progB = profile.progressions[(idxA + 1) % profile.progressions.count].map { profile.chord(rootDegree: $0) }

        var sections: [Section] = []
        var bar = 0
        for (i, kind) in kinds.enumerated() {
            let bars = counts[i] * 4
            let next: SectionKind? = i + 1 < kinds.count ? kinds[i + 1] : nil
            sections.append(Section(kind: kind,
                                    startBar: bar,
                                    bars: bars,
                                    progression: kind == .chorus ? progB : progA,
                                    preDrop: next == .chorus))
            bar += bars
        }

        var hookRNG = rng.fork(3)
        let hook = makeHook(style: profile.hookStyle, rng: &hookRNG)
        // The "answer" version changes the second half of the melody a little.
        var altRNG = rng.fork(4)
        var alt = hook
        for i in 0..<alt.count {
            let n = alt[i]
            if n.step >= 16 && altRNG.chance(0.6) {
                let moved = nearestChordTone(n.offset + altRNG.pick([-2, -1, 1, 2]))
                alt[i] = HookNote(step: n.step, len: n.len, offset: moved)
            }
        }

        // Average pitch of the hook (used to place it in a comfortable range).
        let chorusProg = progB
        var total = 0.0
        for n in hook {
            let chord = chorusProg[((n.step / 16) / profile.barsPerChord) % chorusProg.count]
            total += Double(profile.scale.semitone(degree: chord.rootDegree + n.offset))
        }
        let mean = total / Double(max(1, hook.count))

        // Parts of the song where none of the chosen instruments would normally play.
        var fallback = Set<Int>()
        let kindsAll: [SectionKind] = [.intro, .verse, .chorus, .breakdown, .outro]
        for k in kindsAll {
            var any = !s.vocals.isEmpty
            for inst in s.instruments where SongPlan.baseLevel(inst, k) > 0 { any = true }
            if !any { fallback.insert(k.rawValue) }
        }

        return SongPlan(settings: s, key: key, profile: profile, tuning: tuning, sections: sections,
                        totalBars: totalBars, hook: hook, hookAlt: alt, hookMean: mean, rng: rng,
                        fallbackKinds: fallback)
    }
}
