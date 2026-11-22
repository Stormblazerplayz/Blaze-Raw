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
    /// The chords of this section (already moved up if the song changes key here).
    let progression: [Chord]
    /// True when the next section is a chorus (so we build up with a fill and riser).
    let preDrop: Bool
    var endBar: Int { startBar + bars }
}

/// One note of a melody ("hook"), written relative to the current chord so it follows the harmony.
struct HookNote {
    let step: Int       // 16th-note step inside a 2-bar window (0..<32)
    let len: Int        // length in 16th steps
    let offset: Int     // scale-degree offset from the chord root
}

enum BassTone {
    case root, fifth, octave, third
}

struct BassStep {
    let step: Int
    let len: Int
    let tone: BassTone
    let vel: Float
}

private func bs(_ step: Int, _ len: Int, _ tone: BassTone, _ vel: Float) -> BassStep {
    BassStep(step: step, len: len, tone: tone, vel: vel)
}

struct SongPlan {
    let settings: SongSettings
    let key: Int
    let profile: StyleProfile
    let tuning: TuningSystem
    let sections: [Section]
    let totalBars: Int
    /// The chorus melody, its "answer" version, and the quieter verse melody and its answer.
    let hook: [HookNote]
    let hookAlt: [HookNote]
    let verseHook: [HookNote]
    let verseHookAlt: [HookNote]
    let hookMean: Double
    let verseMean: Double
    let rng: SeededRNG
    let fallbackKinds: Set<Int>
    /// gate[instrument index][phrase]: false means that instrument sits out that 4-bar phrase.
    let gate: [[Bool]]
    /// forced[phrase]: nothing that was chosen would play there, so every chosen instrument plays.
    let forced: [Bool]
    let templateName: String

    var bpm: Double { settings.tempo }
    var tonicMidi: Int { 24 + key }

    // MARK: lookups

    func sectionIndex(atBar bar: Int) -> Int {
        for (i, s) in sections.enumerated() where bar >= s.startBar && bar < s.endBar { return i }
        return max(0, sections.count - 1)
    }

    func chord(atBar bar: Int) -> Chord {
        let s = sections[sectionIndex(atBar: bar)]
        let k = (max(0, bar - s.startBar) / profile.barsPerChord) % s.progression.count
        return s.progression[k]
    }

    /// Beat position of a 16th-note step in a bar (with swing on the off-steps).
    func stepBeat(_ bar: Int, _ step: Int) -> Double {
        var b = Double(bar * 4) + Double(step) * 0.25
        if step % 2 == 1 { b += profile.swing * 0.25 }
        return b
    }

    /// A tiny random timing wobble for played (not programmed) instruments, in beats.
    func wobble(_ g: inout SeededRNG) -> Double {
        if profile.humanize <= 0 { return 0 }
        return (g.double() - 0.5) * 2 * profile.humanize
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

    /// The table level for this style (some styles let the lead synth play softly in the verses).
    static func styleLevel(_ inst: InstrumentKind, _ kind: SectionKind, leadInVerse: Bool) -> Float {
        if inst == .lead && kind == .verse && leadInVerse { return 0.55 }
        return baseLevel(inst, kind)
    }

    /// How loud an instrument is in a kind of section (0 when the user did not pick it).
    func level(_ inst: InstrumentKind, _ kind: SectionKind) -> Float {
        guard settings.instruments.contains(inst) else { return 0 }
        let base = SongPlan.styleLevel(inst, kind, leadInVerse: profile.leadInVerse)
        if base > 0 { return base }
        // If nothing at all would play in this part of the song, let everything play softly.
        if fallbackKinds.contains(kind.rawValue) && inst != .drums { return 0.75 }
        return 0
    }

    /// How loud an instrument is in one particular bar: the section level, or 0 when the arrangement
    /// has this instrument sit out the 4-bar phrase the bar belongs to.
    func level(_ inst: InstrumentKind, bar: Int) -> Float {
        let lvl = level(inst, sections[sectionIndex(atBar: bar)].kind)
        if lvl <= 0 { return 0 }
        guard let idx = InstrumentKind.allCases.firstIndex(of: inst) else { return lvl }
        let phrase = max(0, bar / 4)
        if phrase < forced.count && forced[phrase] { return lvl }
        if idx < gate.count && phrase < gate[idx].count && !gate[idx][phrase] { return 0 }
        return lvl
    }

    func vel(_ level: Float, _ rng: inout SeededRNG) -> Float {
        level * (0.84 + 0.16 * rng.float())
    }

    // MARK: voicings

    /// Chord tones packed closely around a centre note (semitones above the tonic).
    /// With `open` the second-lowest note jumps up an octave for a wider, airier sound.
    func voicing(_ chord: Chord, center: Int, open: Bool = false) -> [Int] {
        var out = Set<Int>()
        let base = tonicMidi
        for s in chord.tones {
            var m = base + s
            while m < center - 6 { m += 12 }
            while m >= center + 6 { m -= 12 }
            out.insert(m - base)
        }
        var sorted = out.sorted()
        if open && sorted.count >= 3 {
            let second = sorted.remove(at: 1)
            sorted.append(second + 12)
            sorted.sort()
        }
        return sorted
    }

    /// The chord's root placed in a low register (semitones above the tonic).
    func lowRoot(_ chord: Chord, lowest: Int) -> Int {
        var m = tonicMidi + chord.rootSemis
        while m < lowest { m += 12 }
        while m >= lowest + 12 { m -= 12 }
        return m - tonicMidi
    }

    func hookSemis(_ n: HookNote, chord: Chord) -> Int {
        profile.scale.semitone(degree: chord.rootDegree + n.offset) + chord.shift
    }

    /// Octave shift (a multiple of 12) that moves a melody's average pitch near `center` (a MIDI note).
    func hookShift(center: Int, mean: Double) -> Int {
        let m = Double(tonicMidi) + mean
        return Int(((Double(center) - m) / 12.0).rounded()) * 12
    }

    // MARK: - Bass

    func bassRoot(_ chord: Chord) -> Int {
        var r = chord.rootSemis % 12
        if r < 0 { r += 12 }
        if r > 6 { r -= 12 }
        let off = (tonicMidi + 12 > 42) ? 0 : 12
        return r + off
    }

    /// The semitone distance from a chord root to its third or fifth, read from the chord's own scale.
    func bassInterval(_ chord: Chord, tone: BassTone) -> Int {
        let root = profile.scale.semitone(degree: chord.rootDegree)
        switch tone {
        case .root: return 0
        case .octave: return 12
        case .third: return profile.scale.semitone(degree: chord.rootDegree + 2) - root
        case .fifth: return profile.scale.semitone(degree: chord.rootDegree + 4) - root
        }
    }

    static func bassPattern(_ style: BassStyle, variant: Int) -> [BassStep] {
        let v = ((variant % 4) + 4) % 4
        switch style {
        case .sustained:
            switch v {
            case 0: return [bs(0, 16, .root, 1)]
            case 1: return [bs(0, 8, .root, 1), bs(8, 8, .root, 0.85)]
            case 2: return [bs(0, 12, .root, 1), bs(12, 4, .fifth, 0.8)]
            default: return [bs(0, 10, .root, 1), bs(10, 6, .root, 0.9)]
            }
        case .rootFifth:
            switch v {
            case 0: return [bs(0, 8, .root, 1), bs(8, 8, .fifth, 0.9)]
            case 1: return [bs(0, 6, .root, 1), bs(6, 2, .root, 0.6), bs(8, 8, .fifth, 0.9)]
            case 2: return [bs(0, 4, .root, 1), bs(4, 4, .fifth, 0.8), bs(8, 4, .root, 0.95), bs(12, 4, .fifth, 0.8)]
            default: return [bs(0, 8, .root, 1), bs(8, 4, .fifth, 0.85), bs(12, 4, .octave, 0.8)]
            }
        case .offbeatOctave:
            switch v {
            case 0: return [bs(2, 2, .root, 1), bs(6, 2, .octave, 0.9), bs(10, 2, .root, 1), bs(14, 2, .octave, 0.9)]
            case 1: return [bs(2, 2, .root, 1), bs(6, 2, .root, 0.9), bs(10, 2, .root, 1), bs(14, 2, .octave, 0.9)]
            case 2: return [bs(0, 2, .root, 0.8), bs(2, 2, .octave, 1), bs(6, 2, .root, 0.9),
                            bs(8, 2, .root, 0.8), bs(10, 2, .octave, 1), bs(14, 2, .root, 0.9)]
            default: return [bs(2, 1, .root, 1), bs(3, 1, .octave, 0.7), bs(6, 1, .root, 0.9),
                             bs(10, 1, .root, 1), bs(11, 1, .octave, 0.7), bs(14, 1, .root, 0.9)]
            }
        case .funk16:
            switch v {
            case 0: return [bs(0, 3, .root, 1), bs(3, 1, .root, 0.6), bs(6, 2, .octave, 0.9), bs(8, 2, .root, 0.9),
                            bs(10, 1, .octave, 0.7), bs(11, 1, .fifth, 0.7), bs(14, 2, .root, 0.9)]
            case 1: return [bs(0, 2, .root, 1), bs(3, 1, .octave, 0.7), bs(4, 2, .root, 0.8), bs(7, 1, .fifth, 0.7),
                            bs(10, 2, .root, 0.95), bs(12, 1, .octave, 0.7), bs(14, 2, .fifth, 0.8)]
            case 2: return [bs(0, 4, .root, 1), bs(6, 2, .octave, 0.9), bs(8, 3, .root, 0.9), bs(11, 1, .root, 0.6),
                            bs(12, 2, .fifth, 0.8), bs(14, 1, .octave, 0.8), bs(15, 1, .root, 0.6)]
            default: return [bs(0, 1, .root, 1), bs(2, 2, .octave, 0.9), bs(4, 2, .root, 0.9), bs(7, 1, .root, 0.7),
                             bs(8, 2, .fifth, 0.9), bs(10, 2, .octave, 0.9), bs(12, 2, .root, 0.9), bs(15, 1, .fifth, 0.7)]
            }
        case .rolling:
            switch v {
            case 0: return [bs(0, 2, .root, 1), bs(2, 2, .root, 0.8), bs(4, 2, .root, 0.9), bs(6, 2, .octave, 0.8),
                            bs(8, 2, .root, 0.95), bs(10, 2, .root, 0.8), bs(12, 2, .root, 0.9), bs(14, 2, .octave, 0.8)]
            case 1:
                var out: [BassStep] = []
                for s in 0..<16 {
                    out.append(bs(s, 1, s % 8 == 6 ? .octave : .root, s % 4 == 0 ? 1.0 : 0.7))
                }
                return out
            case 2: return [bs(0, 3, .root, 1), bs(3, 1, .root, 0.7), bs(4, 3, .root, 0.9), bs(7, 1, .octave, 0.7),
                            bs(8, 3, .root, 1), bs(11, 1, .root, 0.7), bs(12, 3, .root, 0.9), bs(15, 1, .octave, 0.7)]
            default: return [bs(0, 2, .root, 1), bs(3, 2, .root, 0.8), bs(6, 2, .root, 0.9), bs(8, 2, .root, 1),
                             bs(11, 2, .octave, 0.8), bs(14, 2, .root, 0.9)]
            }
        case .walking:
            switch v {
            case 0: return [bs(0, 4, .root, 1), bs(4, 4, .third, 0.85), bs(8, 4, .fifth, 0.9), bs(12, 4, .third, 0.85)]
            case 1: return [bs(0, 4, .root, 1), bs(4, 4, .fifth, 0.85), bs(8, 4, .octave, 0.9), bs(12, 4, .fifth, 0.85)]
            case 2: return [bs(0, 4, .root, 1), bs(4, 4, .third, 0.85), bs(8, 4, .fifth, 0.9), bs(12, 4, .octave, 0.85)]
            default: return [bs(0, 3, .root, 1), bs(4, 4, .third, 0.85), bs(8, 3, .fifth, 0.9), bs(12, 4, .third, 0.85)]
            }
        case .bounce808:
            switch v {
            case 0: return [bs(0, 6, .root, 1), bs(10, 5, .root, 0.9)]
            case 1: return [bs(0, 4, .root, 1), bs(6, 3, .root, 0.8), bs(12, 4, .octave, 0.9)]
            case 2: return [bs(0, 8, .root, 1), bs(10, 2, .root, 0.7), bs(13, 3, .root, 0.8)]
            default: return [bs(0, 3, .root, 1), bs(4, 4, .fifth, 0.8), bs(10, 6, .root, 0.9)]
            }
        case .syncopated:
            switch v {
            case 0: return [bs(0, 3, .root, 1), bs(3, 1, .root, 0.7), bs(6, 2, .root, 0.9), bs(8, 3, .root, 1),
                            bs(11, 1, .root, 0.7), bs(14, 2, .fifth, 0.9)]
            case 1: return [bs(0, 2, .root, 1), bs(3, 2, .root, 0.8), bs(6, 2, .octave, 0.85), bs(10, 2, .root, 0.95),
                            bs(14, 2, .fifth, 0.85)]
            case 2: return [bs(0, 4, .root, 1), bs(4, 2, .root, 0.8), bs(8, 4, .root, 0.95), bs(12, 2, .fifth, 0.85),
                            bs(14, 2, .octave, 0.8)]
            default: return [bs(0, 2, .root, 1), bs(2, 2, .root, 0.7), bs(6, 2, .root, 0.9), bs(8, 2, .root, 1),
                             bs(10, 2, .fifth, 0.8), bs(14, 2, .root, 0.85)]
            }
        case .drone:
            return [bs(0, 16, .root, 1)]
        }
    }

    func bassNotes() -> [NoteEvent] {
        var g = rng.fork(11)
        var notes: [NoteEvent] = []
        let low = settings.intensity < 0.45
        let style = profile.bassStyle
        let popsAllowed = style == .rolling || style == .syncopated || style == .rootFifth
        let approachAllowed = style == .walking || style == .funk16 || style == .syncopated || style == .rootFifth
        for sec in sections {
            let variant = sec.kind == .chorus ? (profile.bassVariant + 1) % 4 : profile.bassVariant
            var pattern = SongPlan.bassPattern(style, variant: variant)
            if low && pattern.count > 2 {
                // Calmer songs: keep every other note and let it ring into the gap.
                var kept: [BassStep] = []
                for (i, p) in pattern.enumerated() where i % 2 == 0 { kept.append(p) }
                var stretched: [BassStep] = []
                for (i, p) in kept.enumerated() {
                    let nextStep = i + 1 < kept.count ? kept[i + 1].step : 16
                    stretched.append(bs(p.step, max(1, nextStep - p.step), p.tone, p.vel))
                }
                pattern = stretched
            }
            var b = 0
            while b < sec.bars {
                let bar = sec.startBar + b
                let lvl = level(.subBass, bar: bar)
                let chord = self.chord(atBar: bar)
                if style == .drone {
                    let len = min(profile.barsPerChord, sec.bars - b)
                    if lvl > 0 && (b % profile.barsPerChord == 0) {
                        notes.append(NoteEvent(beat: Double(bar * 4), dur: Double(len * 4) * 0.97,
                                               semis: bassRoot(chord), vel: lvl * (0.92 + 0.08 * g.float())))
                    }
                    b += 1
                    continue
                }
                b += 1
                if lvl <= 0 { continue }
                let base = bassRoot(chord)
                let barPattern: [BassStep] = sec.kind == .breakdown ? [bs(0, 16, .root, 0.9)] : pattern
                let nextBase = bassRoot(self.chord(atBar: min(bar + 1, totalBars - 1)))
                for (i, p) in barPattern.enumerated() {
                    var semis = base + bassInterval(chord, tone: p.tone)
                    // Octave pops on some off-beat notes keep the line moving.
                    if popsAllowed && p.step != 0 && p.tone == .root && g.chance(0.12) { semis += 12 }
                    var len = p.len
                    // Every fourth bar, the last note sometimes slides toward the next chord's root.
                    let isLast = i == barPattern.count - 1
                    let lastBarOfPhrase = (bar - sec.startBar) % 4 == 3
                    let canApproach = isLast && approachAllowed && sec.kind != .breakdown && lastBarOfPhrase
                    if canApproach && nextBase != base && g.chance(0.35) {
                        semis = nextBase + (g.chance(0.5) ? -1 : 1)
                        len = min(len, 2)
                    }
                    notes.append(NoteEvent(beat: stepBeat(bar, p.step),
                                           dur: Double(len) * 0.25 * 0.94,
                                           semis: semis,
                                           vel: lvl * p.vel * (0.92 + 0.08 * g.float())))
                }
            }
        }
        return notes
    }

    /// Which family of growl patterns fits the drum feel: 0 straight, 1 half-time, 2 broken, 3 epic.
    var growlFamily: Int {
        switch profile.drumStyle {
        case .fourOnFloor, .disco, .backbeat, .gated80s: return 0
        case .halfTime, .boomBap, .dreamy, .minimal: return 1
        case .breakbeat: return 2
        case .epic: return 3
        }
    }

    func growlNotes() -> [NoteEvent] {
        var g = rng.fork(12)
        var notes: [NoteEvent] = []
        let family = growlFamily
        for sec in sections {
            // One wobble speed per section keeps it musical.
            let wobbleSpeed: Int
            switch family {
            case 1: wobbleSpeed = g.pick([0, 1, 2])
            case 0: wobbleSpeed = g.pick([1, 2, 1])
            case 2: wobbleSpeed = g.pick([1, 3, 2])
            default: wobbleSpeed = 0
            }
            for b in 0..<sec.bars {
                let bar = sec.startBar + b
                let lvl = level(.growlBass, bar: bar)
                if lvl <= 0 { continue }
                let base = bassRoot(chord(atBar: bar)) + 12
                let pattern: [(Int, Int)]
                switch family {
                case 0: pattern = [(0, 2), (3, 1), (6, 2), (8, 2), (11, 1), (14, 2)]
                case 1: pattern = [(0, 6), (6, 2), (8, 4), (12, 2), (14, 2)]
                case 2: pattern = [(0, 2), (2, 1), (3, 1), (6, 2), (10, 2), (12, 1), (14, 2)]
                default: pattern = [(0, 16)]
                }
                for (step, len) in pattern {
                    var semis = base
                    let r = g.double()
                    if r > 0.95 { semis += 10 } else if r > 0.85 { semis += 7 } else if r > 0.7 { semis += 12 }
                    notes.append(NoteEvent(beat: stepBeat(bar, step),
                                           dur: Double(len) * 0.25 * 0.92,
                                           semis: semis,
                                           vel: lvl * (0.85 + 0.15 * g.float()),
                                           aux: wobbleSpeed))
                }
            }
        }
        return notes
    }

    // MARK: - Pads, strings

    func chordHoldNotes(_ inst: InstrumentKind, center: Int, doubleRoot: Bool) -> [NoteEvent] {
        var g = rng.fork(inst == .pad ? 13 : 14)
        var notes: [NoteEvent] = []
        let padStyle = inst == .pad ? profile.padStyle : 0
        for sec in sections {
            var b = 0
            while b < sec.bars {
                let bar = sec.startBar + b
                let chord = self.chord(atBar: bar)
                let len = min(profile.barsPerChord, sec.bars - b)
                let lvl = level(inst, bar: bar)
                if lvl <= 0 {
                    b += len
                    continue
                }
                var tones = voicing(chord, center: center, open: profile.openVoicings)
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
                switch padStyle {
                case 1:
                    // Chords re-played every half bar: a gentle pulse.
                    let hits = len * 2
                    for h in 0..<hits {
                        let accent: Float = h % 2 == 0 ? 1.0 : 0.8
                        for t in tones {
                            notes.append(NoteEvent(beat: max(0, Double(bar * 4) + Double(h) * 2 + wobble(&g)),
                                                   dur: 2.05,
                                                   semis: t,
                                                   vel: v * accent * (0.9 + 0.1 * g.float()),
                                                   aux: sec.kind.rawValue))
                        }
                    }
                case 2:
                    // Short chord pulses on every beat (only the top three notes, to keep it light).
                    let top = Array(tones.suffix(3))
                    let hits = len * 4
                    for h in 0..<hits {
                        let accent: Float = h % 4 == 0 ? 1.0 : (h % 2 == 0 ? 0.85 : 0.7)
                        for t in top {
                            notes.append(NoteEvent(beat: max(0, Double(bar * 4) + Double(h) + wobble(&g)),
                                                   dur: 0.85,
                                                   semis: t,
                                                   vel: v * accent * (0.9 + 0.1 * g.float()),
                                                   aux: sec.kind.rawValue))
                        }
                    }
                default:
                    for t in tones {
                        notes.append(NoteEvent(beat: Double(bar * 4) + max(0, wobble(&g)),
                                               dur: Double(len * 4) + 0.05,
                                               semis: t,
                                               vel: v * (0.9 + 0.1 * g.float()),
                                               aux: sec.kind.rawValue))
                    }
                }
                b += len
            }
        }
        return notes
    }

    func padNotes() -> [NoteEvent] { chordHoldNotes(.pad, center: 60, doubleRoot: false) }
    func stringNotes() -> [NoteEvent] { chordHoldNotes(.strings, center: 64, doubleRoot: true) }

    // MARK: - Lead melody

    /// The melody a section plays in one 2-bar window, and whether it is the (lower, sparser) verse melody.
    func melody(for kind: SectionKind, alt: Bool) -> (notes: [HookNote], verse: Bool) {
        switch kind {
        case .chorus:
            return (alt ? hookAlt : hook, false)
        case .breakdown:
            return alt ? (verseHookAlt, true) : (hookAlt, false)
        case .intro, .verse, .outro:
            return (alt ? verseHookAlt : verseHook, true)
        }
    }

    func hookEvents(center: Int, onlyStrong: Bool = false) -> [(note: NoteEvent, kind: SectionKind)] {
        var out: [(note: NoteEvent, kind: SectionKind)] = []
        for sec in sections {
            var b = 0
            while b < sec.bars {
                let useAlt = (b / 2) % 2 == 1
                let (motif, isVerse) = melody(for: sec.kind, alt: useAlt)
                let shift = hookShift(center: center, mean: isVerse ? verseMean : hookMean)
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
        for (ev, _) in hookEvents(center: 72) {
            let lvl = level(.lead, bar: Int(ev.beat / 4))
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
        for (ev, _) in hookEvents(center: 84) {
            let lvl = level(.bells, bar: Int(ev.beat / 4))
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

    /// Hit length (in beats) for each onset of a rhythm, running until the next onset (or the bar's end).
    private func holdLengths(_ steps: [Int], cap: Double) -> [Double] {
        var out: [Double] = []
        for (i, s) in steps.enumerated() {
            let next = i + 1 < steps.count ? steps[i + 1] : 16
            out.append(min(Double(max(1, next - s)) * 0.25 * 0.95, cap))
        }
        return out
    }

    func pianoNotes() -> [NoteEvent] {
        var g = rng.fork(17)
        var notes: [NoteEvent] = []
        for sec in sections {
            var mode = profile.pianoMode
            if sec.kind == .intro || sec.kind == .breakdown || sec.kind == .outro {
                mode = profile.pianoMode == .ballad ? .ballad : .slow
            }
            let rhythm = sec.kind == .chorus ? profile.stabRhythm : profile.stabRhythmAlt
            for b in 0..<sec.bars {
                let bar = sec.startBar + b
                let lvl = level(.piano, bar: bar)
                if lvl <= 0 { continue }
                let chord = self.chord(atBar: bar)
                let tones = voicing(chord, center: 58, open: profile.openVoicings)
                guard !tones.isEmpty else { continue }
                switch mode {
                case .block, .stabs:
                    let lens = holdLengths(rhythm, cap: mode == .stabs ? 0.3 : 2.5)
                    for (i, step) in rhythm.enumerated() {
                        let accent: Float = step % 4 == 0 ? 1.0 : 0.85
                        for (k, t) in tones.enumerated() {
                            notes.append(NoteEvent(beat: max(0, stepBeat(bar, step) + Double(k) * 0.01 + wobble(&g)),
                                                   dur: lens[i],
                                                   semis: t,
                                                   vel: vel(lvl, &g) * 0.85 * accent))
                        }
                    }
                case .broken:
                    let order = [0, 1, 2, 1, 0, 1, 2, tones.count - 1]
                    for k in 0..<8 {
                        let t = tones[order[k] % tones.count] + (k == 0 ? -12 : 0)
                        notes.append(NoteEvent(beat: max(0, stepBeat(bar, k * 2) + wobble(&g)),
                                               dur: 0.75,
                                               semis: t,
                                               vel: vel(lvl, &g) * (k % 4 == 0 ? 1.0 : 0.75)))
                    }
                case .alberti:
                    let low = tones[0]
                    let mid = tones[min(1, tones.count - 1)]
                    let high = tones[min(2, tones.count - 1)]
                    let order = [low, high, mid, high, low, high, mid, high]
                    for k in 0..<8 {
                        notes.append(NoteEvent(beat: max(0, stepBeat(bar, k * 2) + wobble(&g)),
                                               dur: 0.5,
                                               semis: order[k],
                                               vel: vel(lvl, &g) * (k % 4 == 0 ? 1.0 : 0.65)))
                    }
                case .ballad:
                    let root = lowRoot(chord, lowest: 40)
                    notes.append(NoteEvent(beat: Double(bar * 4) + max(0, wobble(&g)), dur: 3.6, semis: root,
                                           vel: vel(lvl, &g)))
                    for t in tones {
                        notes.append(NoteEvent(beat: Double(bar * 4) + 1 + max(0, wobble(&g)), dur: 2.7, semis: t,
                                               vel: vel(lvl, &g) * 0.7))
                    }
                case .slow:
                    let order = [0, 1, 2, min(3, tones.count - 1)]
                    for k in 0..<4 {
                        let t = tones[order[k] % tones.count] + (k == 0 ? -12 : 0)
                        notes.append(NoteEvent(beat: max(0, stepBeat(bar, k * 4) + wobble(&g)),
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
        let pickOrder = Banks.pickOrders[(profile.bassVariant + profile.grooveVariant) % Banks.pickOrders.count]
        for sec in sections {
            var mode = profile.guitarMode
            // Strummed and funky parts rest in the intro and outro; a gentle picked pattern takes over.
            if (mode == .strum || mode == .chop) && (sec.kind == .intro || sec.kind == .outro) { mode = .pick }
            let chopRhythm = sec.kind == .chorus ? profile.stabRhythm : profile.stabRhythmAlt
            for b in 0..<sec.bars {
                let bar = sec.startBar + b
                let lvl = level(.guitar, bar: bar)
                if lvl <= 0 { continue }
                let chord = self.chord(atBar: bar)
                var strings = [lowRoot(chord, lowest: 40)]
                strings.append(contentsOf: voicing(chord, center: 60, open: profile.openVoicings))
                switch mode {
                case .strum:
                    let pattern = profile.strumPattern
                    for (i, hit) in pattern.enumerated() {
                        let (step, strength) = hit
                        let down = step % 4 == 0
                        let order = down ? Array(strings.indices) : Array(strings.indices.reversed())
                        let nextStep = i + 1 < pattern.count ? pattern[i + 1].0 : 16
                        let ring = min(Double(max(1, nextStep - step)) * 0.25 + 0.7, 2.0)
                        for (k, idx) in order.enumerated() {
                            notes.append(NoteEvent(beat: max(0, stepBeat(bar, step) + Double(k) * 0.035 + wobble(&g)),
                                                   dur: ring,
                                                   semis: strings[idx],
                                                   vel: vel(lvl, &g) * strength * 0.8))
                        }
                    }
                case .chop:
                    for step in chopRhythm {
                        let accent: Float = step % 4 == 0 ? 1.0 : 0.8
                        for (k, s) in strings.dropFirst().enumerated() {
                            notes.append(NoteEvent(beat: max(0, stepBeat(bar, step) + Double(k) * 0.012 + wobble(&g)),
                                                   dur: 0.16,
                                                   semis: s,
                                                   vel: vel(lvl, &g) * accent * 0.85))
                        }
                    }
                case .ring:
                    let order = [0, 1, 2, 3, 2, 1, 2, 3]
                    for k in 0..<8 {
                        let idx = order[k] % strings.count
                        notes.append(NoteEvent(beat: max(0, stepBeat(bar, k * 2) + wobble(&g)),
                                               dur: 2.2,
                                               semis: strings[idx],
                                               vel: vel(lvl, &g) * (k % 4 == 0 ? 1.0 : 0.7)))
                    }
                case .pick:
                    for k in 0..<8 {
                        let idx = pickOrder[k] % strings.count
                        notes.append(NoteEvent(beat: max(0, stepBeat(bar, k * 2) + wobble(&g)),
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
        let riff: [(Int, Int, Int)] = profile.pluckRhythm.map { ($0, g.int(0...3), g.chance(0.25) ? 1 : 0) }
        for sec in sections {
            for b in 0..<sec.bars {
                let bar = sec.startBar + b
                let lvl = level(.pluck, bar: bar)
                if lvl <= 0 { continue }
                let chord = self.chord(atBar: bar)
                var tones = voicing(chord, center: 66)
                if tones.count < 4, let f = tones.first { tones.append(f + 12) }
                let lastBarOfPhrase = (bar - sec.startBar) % 4 == 3
                for (i, item) in riff.enumerated() {
                    let (step, ti, oct) = item
                    // On the last bar of a phrase, the riff drops its final note and the chorus doubles it up.
                    if lastBarOfPhrase && i == riff.count - 1 && riff.count > 3 { continue }
                    let lift = (sec.kind == .chorus && i % 3 == 2) ? 12 : 0
                    notes.append(NoteEvent(beat: max(0, stepBeat(bar, step) + wobble(&g)),
                                           dur: 0.4,
                                           semis: tones[ti % tones.count] + 12 * oct + lift,
                                           vel: vel(lvl, &g) * 0.9))
                }
            }
        }
        return notes
    }

    func arpNotes() -> [NoteEvent] {
        var g = rng.fork(20)
        var notes: [NoteEvent] = []
        let order = profile.arpOrder
        let sparse = settings.intensity < 0.4
        var onsets = profile.arpRhythm
        if sparse && onsets.count > 4 {
            var kept: [Int] = []
            for (i, s) in onsets.enumerated() where i % 2 == 0 { kept.append(s) }
            onsets = kept
        }
        for sec in sections {
            for b in 0..<sec.bars {
                let bar = sec.startBar + b
                let lvl = level(.arp, bar: bar)
                if lvl <= 0 { continue }
                let chord = self.chord(atBar: bar)
                var tones = voicing(chord, center: 72)
                while tones.count < 4 { tones.append((tones.last ?? 0) + 12) }
                for (k, step) in onsets.enumerated() {
                    let t = tones[order[k % order.count] % tones.count]
                    let nextStep = k + 1 < onsets.count ? onsets[k + 1] : 16
                    let dur = min(max(Double(nextStep - step) * 0.25 * 0.9, 0.2), 1.5)
                    notes.append(NoteEvent(beat: stepBeat(bar, step),
                                           dur: dur,
                                           semis: t,
                                           vel: lvl * (step % 4 == 0 ? 1.0 : 0.62) * (0.92 + 0.08 * g.float()),
                                           aux: step))
                }
            }
        }
        return notes
    }

    // MARK: - The recipe (a readable description of every choice)

    var recipe: String {
        let genreName = settings.genre?.title ?? "Open"
        let loopA = profile.progA.map { String($0 + 1) }.joined(separator: "-")
        let loopB = profile.progB.map { String($0 + 1) }.joined(separator: "-")
        var parts: [String] = []
        parts.append("\(genreName) / \(settings.mood.title)")
        parts.append("\(SongSettings.keyNames[key]) \(profile.scale.displayName) at \(Int(settings.tempo)) BPM")
        parts.append("chords \(loopA) then \(loopB), \(profile.barsPerChord) bar each, \(profile.colorVerse.name)/\(profile.colorChorus.name)")
        // (The key change only happens in songs with at least two choruses, so look at what was really planned.)
        if sections.contains(where: { ($0.progression.first?.shift ?? 0) > 0 }) {
            parts.append("key change +\(profile.keyLift)")
        }
        parts.append("layout \(templateName)")
        parts.append("drums \(profile.drumStyle.name) #\(profile.grooveVariant), swing \(Int((profile.swing * 100).rounded()))%")
        parts.append("bass \(profile.bassStyle.name) #\(profile.bassVariant)")
        parts.append("melody \(String(describing: profile.melody.contour))/\(String(describing: profile.melody.answer))")
        parts.append(profile.palette.summary)
        parts.append(profile.kit.summary)
        parts.append(profile.fx.summary)
        parts.append(profile.master.summary)
        return parts.joined(separator: " | ")
    }

    /// The discrete choices of this song as one string. Two songs with different fingerprints differ in
    /// harmony, rhythm, melody or sound design (used by the tests that check variety).
    var fingerprint: String {
        var parts: [String] = []
        parts.append(profile.scale.rawValue)
        parts.append(profile.progA.map(String.init).joined(separator: ","))
        parts.append(profile.progB.map(String.init).joined(separator: ","))
        parts.append("\(profile.barsPerChord)\(profile.colorVerse.rawValue)\(profile.colorChorus.rawValue)")
        parts.append("\(profile.drumStyle.rawValue).\(profile.grooveVariant)")
        parts.append("\(profile.bassStyle.rawValue).\(profile.bassVariant)")
        parts.append(hook.map { "\($0.step):\($0.offset)" }.joined(separator: ","))
        parts.append(templateName)
        parts.append(profile.palette.summary)
        parts.append(profile.kit.summary)
        parts.append(profile.fx.summary)
        return parts.joined(separator: "|")
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

    // MARK: melodies

    private static func contourValue(_ c: Contour, _ x: Double, _ i: Int) -> Double {
        switch c {
        case .arch: return 2 * sin(Double.pi * x) - 1
        case .rising: return 2 * x - 1
        case .falling: return 1 - 2 * x
        case .wave: return sin(2 * Double.pi * x)
        case .flat: return 0
        case .zigzag: return i % 2 == 0 ? 0.6 : -0.6
        }
    }

    private static func pickCell(_ spec: MelodySpec, _ g: inout SeededRNG) -> [Int] {
        let d = spec.density + (g.double() - 0.5) * 0.25
        if d < 0.33 { return g.pick(Banks.sparseCells) }
        if d < 0.62 { return g.pick(Banks.midCells) }
        return g.pick(Banks.busyCells)
    }

    /// Moves some on-the-beat notes a 16th earlier, which makes a melody feel syncopated.
    private static func syncopate(_ cell: [Int], amount: Double, _ g: inout SeededRNG) -> [Int] {
        var out: [Int] = []
        for s in cell {
            var step = s
            if step > 0 && step % 4 == 0 && g.chance(amount * 0.5) && !cell.contains(step - 1) { step -= 1 }
            out.append(step)
        }
        return out.sorted()
    }

    /// Writes a two-bar melody from a MelodySpec: a rhythm for bar one, a walk through the scale that
    /// follows the chosen contour, and an answer in bar two (a repeat, a sequence, a mirror or something new).
    static func makeMotif(spec: MelodySpec, rng g: inout SeededRNG) -> [HookNote] {
        let cell1 = syncopate(pickCell(spec, &g), amount: spec.syncopation, &g)
        var cell2 = cell1
        if spec.answer == .free { cell2 = syncopate(pickCell(spec, &g), amount: spec.syncopation, &g) }
        // A small rhythmic change keeps the answer from being a clone.
        if cell2.count > 3 && g.chance(0.4) {
            cell2.remove(at: g.int(1...(cell2.count - 2)))
        } else if g.chance(0.3) {
            let extra = g.pick([2, 3, 6, 7, 10, 11, 14, 15])
            if !cell2.contains(extra) { cell2.append(extra); cell2.sort() }
        }

        // Pitches of bar one.
        let mid = Double(spec.rangeLow + spec.rangeHigh) / 2
        let amp = Double(spec.rangeHigh - spec.rangeLow) / 2 * 0.85
        var off = nearestChordTone(g.pick([0, 2, 4]))
        var first: [Int] = []
        for (i, step) in cell1.enumerated() {
            if i > 0 {
                let x = Double(i) / Double(max(1, cell1.count - 1))
                let target = mid + amp * contourValue(spec.contour, x, i)
                let toward = target >= Double(off) ? 1 : -1
                var d = 0
                if g.chance(0.1) {
                    d = 0
                } else if g.chance(spec.leapChance) {
                    d = (g.chance(0.7) ? toward : -toward) * g.int(2...4)
                } else if g.chance(spec.stepBias) {
                    d = g.chance(0.7) ? toward : -toward
                } else {
                    d = g.pick([-2, -1, 1, 2])
                }
                off += d
            }
            off = min(max(off, spec.rangeLow), spec.rangeHigh)
            if step % 8 == 0 || i == cell1.count - 1 { off = min(max(nearestChordTone(off), spec.rangeLow - 1), spec.rangeHigh + 1) }
            first.append(off)
        }

        // Pitches of bar two: an answer to bar one.
        var second: [Int] = []
        let shift = g.pick([-2, -1, 1, 2])
        for (j, step) in cell2.enumerated() {
            let base = first[j % first.count]
            var o: Int
            switch spec.answer {
            case .repeatPhrase:
                o = base
            case .sequence:
                o = base + shift
            case .mirror:
                o = 2 * first[0] - base
            case .free:
                o = base + g.pick([-2, -1, 0, 1, 2])
            }
            o = min(max(o, spec.rangeLow), spec.rangeHigh)
            if step % 8 == 0 { o = nearestChordTone(o) }
            if j == cell2.count - 1 {
                // The last note settles on a chord tone (a different one from bar one's ending when repeating).
                if spec.answer == .repeatPhrase && g.chance(0.6) { o = nearestChordTone(o + g.pick([-2, 2, -1, 1])) }
                else { o = nearestChordTone(o) }
            }
            second.append(min(max(o, spec.rangeLow - 1), spec.rangeHigh + 1))
        }

        var onsets: [Int] = cell1
        var offsets: [Int] = first
        for (j, s) in cell2.enumerated() {
            onsets.append(s + 16)
            offsets.append(second[j])
        }
        var notes: [HookNote] = []
        for (i, step) in onsets.enumerated() {
            let next = i + 1 < onsets.count ? onsets[i + 1] : 32
            let len = max(1, min(next - step, spec.maxLen))
            notes.append(HookNote(step: step, len: len, offset: offsets[i]))
        }
        return notes
    }

    /// The "answer" version of a melody: the second half changes a little.
    private static func makeAlt(_ motif: [HookNote], rng g: inout SeededRNG) -> [HookNote] {
        var alt = motif
        for i in 0..<alt.count {
            let n = alt[i]
            if n.step >= 16 && g.chance(0.6) {
                let moved = nearestChordTone(n.offset + g.pick([-2, -1, 1, 2]))
                alt[i] = HookNote(step: n.step, len: n.len, offset: moved)
            }
        }
        return alt
    }

    private static func meanPitch(_ motif: [HookNote], progression: [Chord], profile: StyleProfile) -> Double {
        var total = 0.0
        for n in motif {
            let chord = progression[((n.step / 16) / profile.barsPerChord) % progression.count]
            total += Double(profile.scale.semitone(degree: chord.rootDegree + n.offset))
        }
        return total / Double(max(1, motif.count))
    }

    // MARK: song layout

    static func pickTemplate(preferred: [(String, Double)], phrases: Int, rng g: inout SeededRNG) -> SectionTemplate {
        let applicable = Banks.templates.filter {
            phrases >= $0.minPhrases && phrases <= $0.maxPhrases && $0.kinds.count <= phrases
        }
        var weighted: [(Int, Double)] = []
        for (i, t) in applicable.enumerated() {
            for p in preferred where p.0 == t.base {
                weighted.append((i, p.1))
                break
            }
        }
        if weighted.isEmpty {
            for i in 0..<applicable.count { weighted.append((i, 1)) }
        }
        let idx = g.pickWeighted(weighted)
        return applicable[idx]
    }

    /// Which 4-bar phrases each instrument sits out. Draws the same random numbers whatever instruments
    /// were chosen, so adding an instrument never changes when the others play.
    static func makeGate(sections: [Section], totalBars: Int, density: Float, rng: SeededRNG) -> [[Bool]] {
        let phrases = max(1, totalBars / 4)
        let all = InstrumentKind.allCases
        var out = [[Bool]](repeating: [Bool](repeating: true, count: phrases), count: all.count)
        var g = rng.fork(8)
        let colour: [InstrumentKind] = [.arp, .pluck, .bells, .guitar, .lead, .piano]
        for sec in sections {
            let first = sec.startBar / 4
            let n = sec.bars / 4
            let kindFactor: Double
            switch sec.kind {
            case .verse: kindFactor = 1.0
            case .chorus: kindFactor = 0.25
            case .breakdown: kindFactor = 0.5
            case .intro: kindFactor = 0.6
            case .outro: kindFactor = 0.6
            }
            // One colour instrument waits a phrase before joining in: a classic arrangement move.
            var lateEntry: InstrumentKind? = nil
            if n >= 2 && (sec.kind == .verse || sec.kind == .intro) { lateEntry = g.pick(colour) }
            for (idx, inst) in all.enumerated() {
                let volatility: Double
                switch inst {
                case .drums: volatility = 0.04
                case .subBass: volatility = 0.08
                case .growlBass: volatility = 0.12
                case .pad: volatility = 0.10
                case .lead: volatility = 0.15
                case .strings: volatility = 0.22
                case .piano: volatility = 0.28
                case .guitar: volatility = 0.28
                case .bells: volatility = 0.28
                case .pluck: volatility = 0.32
                case .arp: volatility = 0.32
                }
                let dropChance = volatility * kindFactor * Double(1.4 - density)
                for p in 0..<n {
                    let phrase = first + p
                    if phrase >= phrases { continue }
                    var on = !g.chance(dropChance)
                    if let late = lateEntry, late == inst, p == 0 { on = false }
                    out[idx][phrase] = on
                }
            }
        }
        return out
    }

    static func makePlan(_ input: SongSettings) -> SongPlan {
        let s = input.clamped()
        let rng = SeededRNG(seed: s.seed)
        var keyRNG = rng.fork(1)
        let key = s.key ?? keyRNG.int(0...11)
        let profile = StyleMaker.make(settings: s, rng: rng)
        let tuning = TuningSystem(tonicHz: midiToHz(Double(24 + key)), just: s.justIntonation)

        // How many bars do we need? Always at least one minute.
        let barSeconds = 4.0 * 60.0 / s.tempo
        let needed = Int((s.lengthSeconds / barSeconds).rounded(.up))
        let totalBars = max(16, ((needed + 3) / 4) * 4)
        let phrases = totalBars / 4

        // The layout of the song: which sections, in which order, and how long each is.
        var layoutRNG = rng.fork(5)
        let template = pickTemplate(preferred: GenreTraits.traits(for: s.genre).templates,
                                    phrases: phrases, rng: &layoutRNG)
        let kinds = template.kinds
        let counts = allocate(template.weights, total: phrases)

        // The key change (if any) starts at the last chorus and stays for the rest of the song.
        var chorusIndexes: [Int] = []
        for (i, k) in kinds.enumerated() where k == .chorus { chorusIndexes.append(i) }
        var liftFrom = Int.max
        if profile.keyLift > 0 && chorusIndexes.count >= 2 && phrases >= 8 {
            liftFrom = chorusIndexes[chorusIndexes.count - 1]
        }

        var sections: [Section] = []
        var bar = 0
        for (i, kind) in kinds.enumerated() {
            let bars = counts[i] * 4
            let next: SectionKind? = i + 1 < kinds.count ? kinds[i + 1] : nil
            var degrees: [Int]
            var color = profile.colorVerse
            switch kind {
            case .intro, .verse:
                degrees = profile.progA
            case .chorus:
                degrees = profile.progB
                color = profile.colorChorus
            case .breakdown:
                degrees = profile.progC
            case .outro:
                // Always ends on the home chord, whatever the chord length: count back from the end.
                let n = max(1, bars / profile.barsPerChord)
                let useSubdominant = profile.progOutro.first == 3
                degrees = []
                for k in 0..<n {
                    let fromEnd = n - 1 - k
                    degrees.append((useSubdominant && fromEnd % 2 == 1) ? 3 : 0)
                }
            }
            if degrees.isEmpty { degrees = [0] }
            var progression = degrees.map { profile.chord(rootDegree: $0, color: color) }
            if i >= liftFrom { progression = progression.map { $0.transposed(by: profile.keyLift) } }
            sections.append(Section(kind: kind,
                                    startBar: bar,
                                    bars: bars,
                                    progression: progression,
                                    preDrop: next == .chorus))
            bar += bars
        }

        // Melodies: a chorus hook, its answer, a quieter verse melody and its answer.
        var hookRNG = rng.fork(3)
        let hook = makeMotif(spec: profile.melody, rng: &hookRNG)
        var altRNG = rng.fork(4)
        let hookAlt = makeAlt(hook, rng: &altRNG)
        var verseRNG = rng.fork(6)
        let verseHook = makeMotif(spec: profile.verseMelody, rng: &verseRNG)
        var verseAltRNG = rng.fork(7)
        let verseHookAlt = makeAlt(verseHook, rng: &verseAltRNG)

        // Average pitch of each melody (used to place it in a comfortable range).
        let chorusProg = profile.progB.map { profile.chord(rootDegree: $0, color: profile.colorChorus) }
        let verseProg = profile.progA.map { profile.chord(rootDegree: $0, color: profile.colorVerse) }
        let mean = meanPitch(hook, progression: chorusProg, profile: profile)
        let verseMean = meanPitch(verseHook, progression: verseProg, profile: profile)

        // Parts of the song where none of the chosen instruments would normally play.
        var fallback = Set<Int>()
        let kindsAll: [SectionKind] = [.intro, .verse, .chorus, .breakdown, .outro]
        for k in kindsAll {
            // A chosen vocal only counts if it actually sings in this kind of section.
            var anyPlays = s.vocals.contains { SongPlan.vocalLevel($0, k) > 0 }
            for inst in s.instruments where SongPlan.styleLevel(inst, k, leadInVerse: profile.leadInVerse) > 0 { anyPlays = true }
            if !anyPlays { fallback.insert(k.rawValue) }
        }

        // Which instruments sit out which phrases, and the phrases where that would leave nothing playing.
        let gate = makeGate(sections: sections, totalBars: totalBars, density: profile.density, rng: rng)
        var forced = [Bool](repeating: false, count: max(1, totalBars / 4))
        let all = InstrumentKind.allCases
        for phrase in 0..<forced.count {
            let kind = sections[phraseSection(sections, phrase)].kind
            var anyoneIsPlaying = s.vocals.contains { SongPlan.vocalLevel($0, kind) > 0 }
            for (idx, inst) in all.enumerated() where s.instruments.contains(inst) {
                var lvl = SongPlan.styleLevel(inst, kind, leadInVerse: profile.leadInVerse)
                if lvl <= 0 && fallback.contains(kind.rawValue) && inst != .drums { lvl = 0.75 }
                if lvl > 0 && gate[idx][phrase] { anyoneIsPlaying = true }
            }
            forced[phrase] = !anyoneIsPlaying
        }

        return SongPlan(settings: s, key: key, profile: profile, tuning: tuning, sections: sections,
                        totalBars: totalBars, hook: hook, hookAlt: hookAlt, verseHook: verseHook,
                        verseHookAlt: verseHookAlt, hookMean: mean, verseMean: verseMean, rng: rng,
                        fallbackKinds: fallback, gate: gate, forced: forced, templateName: template.base)
    }

    /// The index of the section a 4-bar phrase belongs to.
    private static func phraseSection(_ sections: [Section], _ phrase: Int) -> Int {
        let bar = phrase * 4
        for (i, s) in sections.enumerated() where bar >= s.startBar && bar < s.endBar { return i }
        return max(0, sections.count - 1)
    }
}
