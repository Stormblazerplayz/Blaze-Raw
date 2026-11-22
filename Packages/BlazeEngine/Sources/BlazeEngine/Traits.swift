import Foundation

// MARK: - What each genre likes
//
// A genre is a bag of preferences: which scales, how rich the chords, which drum feels and bass
// lines, how swung, how pumping, which rhythms the keys and guitars play, how busy the melody is,
// and which song layouts fit. The style maker multiplies these weights with the mood's weights and
// then rolls the dice with the song's seed.

struct GenreTraits {
    var scales: [(Scale, Double)]
    /// Chance that the chord loop is a calm two- or three-chord vamp.
    var vamp: Double
    var bars: [(Int, Double)]
    var colors: [(ChordColor, Double)]
    var drums: [(DrumStyle, Double)]
    var bass: [(BassStyle, Double)]
    var swing: ClosedRange<Double>
    var duck: ClosedRange<Float>
    var humanize: Double
    /// Chance of a key change before the last chorus.
    var keyLift: Double
    /// Chance that the lead synth plays (softly) in the verses too.
    var leadVerse: Double
    var openVoicing: Double
    var padStyles: [(Int, Double)]
    var piano: [(PianoMode, Double)]
    var guitar: [(GuitarMode, Double)]
    var stabs: [[Int]]
    var arps: [[Int]]
    var pluckBusy: Bool
    var strums: [Int]
    var melodyDensity: ClosedRange<Double>
    var melodySync: ClosedRange<Double>
    var melodyLen: ClosedRange<Int>
    var templates: [(String, Double)]
    /// Added to the mood's brightness / reverb.
    var brightness: Float
    var reverb: Float
    /// How busy the arrangement is (0...1).
    var density: Float

    static func traits(for genre: Genre?) -> GenreTraits {
        guard let genre = genre else { return open }
        switch genre {
        case .electronic: return electronic
        case .synthpop: return synthpop
        case .pop: return pop
        case .chillwave: return chillwave
        case .downtempo: return downtempo
        case .ambient: return ambient
        case .dreamPop: return dreamPop
        case .indietronica: return indietronica
        case .lofi: return lofi
        case .nuDisco: return nuDisco
        case .edm: return edm
        }
    }

    // MARK: the genres

    static let open = GenreTraits(
        scales: [(.major, 2), (.naturalMinor, 2), (.dorian, 1.5), (.mixolydian, 1.2), (.lydian, 1), (.phrygian, 0.6),
                 (.harmonicMinor, 0.5), (.melodicMinor, 0.4)],
        vamp: 0.12,
        bars: [(1, 2), (2, 2), (4, 0.3)],
        colors: [(.triad, 3), (.seventh, 2), (.add9, 1), (.sus2, 0.7), (.sus4, 0.6), (.ninth, 0.5), (.sixth, 0.4)],
        drums: [(.fourOnFloor, 2), (.backbeat, 2), (.halfTime, 2), (.breakbeat, 1.5), (.epic, 0.8), (.boomBap, 0.8),
                (.dreamy, 0.8), (.disco, 0.5), (.gated80s, 0.5), (.minimal, 0.3)],
        bass: [(.rootFifth, 2), (.rolling, 2), (.syncopated, 1.5), (.sustained, 1.5), (.offbeatOctave, 1.2),
               (.bounce808, 1), (.walking, 1), (.funk16, 0.8), (.drone, 0.3)],
        swing: 0...0.15, duck: 0.2...0.55, humanize: 0.005, keyLift: 0.1, leadVerse: 0.2, openVoicing: 0.25,
        padStyles: [(0, 4), (1, 1.5), (2, 0.8)],
        piano: [(.block, 1), (.broken, 1), (.stabs, 1), (.slow, 1), (.alberti, 1), (.ballad, 1)],
        guitar: [(.strum, 1), (.pick, 1), (.chop, 1), (.ring, 1)],
        stabs: [[0, 6, 10], [2, 6, 10, 14], [0, 3, 6, 10, 12], [0, 4, 8, 12], [0, 7, 10]],
        arps: [Banks.all16, Banks.eighths, Banks.dotted, Banks.dottedBusy, Banks.quarters],
        pluckBusy: true,
        strums: [0, 1, 2, 3, 4, 5, 6],
        melodyDensity: 0.25...0.8, melodySync: 0.1...0.5, melodyLen: 4...10,
        templates: [("classic", 2), ("twoVerses", 1), ("teaser", 1), ("drops", 1), ("loop", 1), ("float", 1),
                    ("twoChoruses", 1), ("noIntro", 0.6)],
        brightness: 0, reverb: 0, density: 0.65)

    static let electronic = GenreTraits(
        scales: [(.naturalMinor, 3), (.dorian, 3), (.phrygian, 1.2), (.harmonicMinor, 1), (.mixolydian, 1.2),
                 (.major, 0.8), (.lydian, 0.5), (.melodicMinor, 0.8)],
        vamp: 0.2,
        bars: [(1, 2), (2, 2)],
        colors: [(.triad, 3), (.seventh, 1), (.sus2, 1), (.sus4, 0.8), (.add9, 0.8)],
        drums: [(.fourOnFloor, 3), (.breakbeat, 2.5), (.halfTime, 1), (.disco, 0.6), (.backbeat, 0.4)],
        bass: [(.rolling, 3), (.offbeatOctave, 1.5), (.sustained, 1), (.rootFifth, 1), (.syncopated, 1)],
        swing: 0...0.06, duck: 0.35...0.6, humanize: 0.002, keyLift: 0.05, leadVerse: 0.3, openVoicing: 0.2,
        padStyles: [(0, 3), (1, 1.5), (2, 2)],
        piano: [(.stabs, 2), (.broken, 1.5), (.block, 1), (.slow, 0.5)],
        guitar: [(.chop, 1.5), (.pick, 1), (.ring, 1), (.strum, 1)],
        stabs: [[2, 6, 10, 14], [0, 3, 6, 10], [3, 7, 11, 15], [0, 6, 10, 12], [2, 5, 8, 11, 14]],
        arps: [Banks.all16, Banks.eighths, Banks.dotted, Banks.dottedBusy],
        pluckBusy: true,
        strums: [1, 3, 6],
        melodyDensity: 0.45...0.8, melodySync: 0.3...0.6, melodyLen: 4...6,
        templates: [("classic", 2), ("teaser", 1.5), ("drops", 2), ("twoVerses", 1), ("twoChoruses", 1)],
        brightness: 0, reverb: -0.05, density: 0.75)

    static let synthpop = GenreTraits(
        scales: [(.major, 3), (.naturalMinor, 2.5), (.mixolydian, 1.2), (.dorian, 1), (.lydian, 0.7), (.harmonicMinor, 0.5)],
        vamp: 0.05,
        bars: [(1, 2), (2, 3)],
        colors: [(.triad, 3), (.add9, 1.2), (.seventh, 1), (.sus2, 0.8), (.sixth, 0.4)],
        drums: [(.gated80s, 3), (.backbeat, 2.5), (.fourOnFloor, 1.2), (.disco, 0.8)],
        bass: [(.offbeatOctave, 2.5), (.syncopated, 2.5), (.rolling, 1.5), (.rootFifth, 1)],
        swing: 0...0.04, duck: 0.2...0.4, humanize: 0.003, keyLift: 0.25, leadVerse: 0.6, openVoicing: 0.2,
        padStyles: [(0, 3), (1, 2), (2, 1)],
        piano: [(.block, 2), (.stabs, 2), (.broken, 1)],
        guitar: [(.strum, 2), (.chop, 1.5), (.ring, 1)],
        stabs: [[0, 4, 8, 12], [2, 6, 10, 14], [0, 6, 8, 14], [0, 3, 6, 10, 12]],
        arps: [Banks.eighths, Banks.dotted, Banks.all16, Banks.quarters],
        pluckBusy: true,
        strums: [1, 3, 0],
        melodyDensity: 0.45...0.7, melodySync: 0.1...0.35, melodyLen: 6...8,
        templates: [("classic", 3), ("twoVerses", 2), ("twoChoruses", 1.5), ("teaser", 1)],
        brightness: 0.12, reverb: 0, density: 0.75)

    static let pop = GenreTraits(
        scales: [(.major, 4), (.naturalMinor, 2.5), (.mixolydian, 1), (.dorian, 0.8), (.lydian, 0.6)],
        vamp: 0.03,
        bars: [(1, 3), (2, 2)],
        colors: [(.triad, 4), (.add9, 1.2), (.sus4, 0.8), (.seventh, 0.6), (.sus2, 0.6)],
        drums: [(.backbeat, 4), (.fourOnFloor, 1), (.gated80s, 0.6), (.halfTime, 0.6)],
        bass: [(.syncopated, 3), (.rootFifth, 2), (.sustained, 1.2), (.rolling, 0.8)],
        swing: 0...0.08, duck: 0.15...0.35, humanize: 0.006, keyLift: 0.3, leadVerse: 0.5, openVoicing: 0.3,
        padStyles: [(0, 4), (1, 1.5)],
        piano: [(.block, 2.5), (.broken, 1.5), (.ballad, 1.5), (.alberti, 1)],
        guitar: [(.strum, 3), (.pick, 1.5), (.ring, 1)],
        stabs: [[0, 6, 10], [0, 4, 8, 12], [0, 3, 6, 10, 12], [0, 6, 8, 14], [0, 8]],
        arps: [Banks.eighths, Banks.quarters, Banks.dotted, [0, 2, 4, 8, 10, 12]],
        pluckBusy: false,
        strums: [0, 1, 3, 5],
        melodyDensity: 0.4...0.65, melodySync: 0.15...0.4, melodyLen: 6...8,
        templates: [("classic", 3), ("twoVerses", 2.5), ("twoChoruses", 1.5), ("teaser", 1), ("noIntro", 0.8)],
        brightness: 0.1, reverb: -0.1, density: 0.7)

    static let chillwave = GenreTraits(
        scales: [(.major, 2), (.lydian, 2), (.dorian, 2), (.mixolydian, 1.2), (.naturalMinor, 1.5)],
        vamp: 0.15,
        bars: [(2, 3), (1, 1), (4, 1)],
        colors: [(.seventh, 2.5), (.add9, 2), (.triad, 1), (.ninth, 1.2), (.sus2, 1)],
        drums: [(.dreamy, 3), (.halfTime, 2), (.boomBap, 1.2), (.backbeat, 1), (.fourOnFloor, 0.4)],
        bass: [(.sustained, 2.5), (.rootFifth, 2), (.bounce808, 1.5), (.syncopated, 0.8)],
        swing: 0.06...0.18, duck: 0.2...0.4, humanize: 0.008, keyLift: 0.03, leadVerse: 0.3, openVoicing: 0.5,
        padStyles: [(0, 4), (1, 1)],
        piano: [(.slow, 2), (.broken, 1.5), (.ballad, 1.5), (.block, 1)],
        guitar: [(.ring, 3), (.pick, 1.5), (.strum, 1)],
        stabs: [[0, 10], [0, 6, 10], [0, 8], [0, 7, 12], [2, 10]],
        arps: [Banks.eighths, Banks.quarters, [0, 6, 8, 14], Banks.hemiola],
        pluckBusy: false,
        strums: [4, 0, 5],
        melodyDensity: 0.2...0.45, melodySync: 0.1...0.3, melodyLen: 8...12,
        templates: [("classic", 1.5), ("loop", 2), ("float", 1.5), ("twoChoruses", 1)],
        brightness: -0.1, reverb: 0.15, density: 0.5)

    static let downtempo = GenreTraits(
        scales: [(.dorian, 3), (.naturalMinor, 3), (.melodicMinor, 1), (.phrygian, 0.6), (.mixolydian, 1), (.major, 1)],
        vamp: 0.1,
        bars: [(2, 3), (1, 1.5), (4, 1)],
        colors: [(.seventh, 3), (.ninth, 2), (.add9, 1), (.triad, 0.6), (.sus2, 0.6)],
        drums: [(.halfTime, 4), (.boomBap, 2), (.breakbeat, 1.5), (.dreamy, 0.8)],
        bass: [(.bounce808, 3), (.walking, 1.5), (.sustained, 2), (.rootFifth, 1.5)],
        swing: 0.08...0.22, duck: 0.1...0.3, humanize: 0.012, keyLift: 0.03, leadVerse: 0.2, openVoicing: 0.4,
        padStyles: [(0, 4), (1, 1.5)],
        piano: [(.broken, 2), (.block, 1.5), (.ballad, 1.5), (.slow, 1.2)],
        guitar: [(.pick, 2), (.ring, 1.5), (.chop, 1), (.strum, 1)],
        stabs: [[0, 10], [0, 3, 10], [0, 6, 10, 14], [2, 10], [0, 7, 10]],
        arps: [Banks.quarters, [0, 3, 6, 10, 12], [2, 6, 10, 14], Banks.eighths],
        pluckBusy: false,
        strums: [4, 5, 0],
        melodyDensity: 0.2...0.5, melodySync: 0.2...0.5, melodyLen: 6...10,
        templates: [("loop", 2.5), ("classic", 2), ("float", 1), ("twoChoruses", 0.8)],
        brightness: -0.08, reverb: 0.05, density: 0.55)

    static let ambient = GenreTraits(
        scales: [(.lydian, 3), (.major, 2), (.dorian, 2.5), (.naturalMinor, 1.5), (.mixolydian, 1), (.phrygian, 0.5)],
        vamp: 0.4,
        bars: [(4, 3), (2, 2), (1, 0.3)],
        colors: [(.sus2, 2.5), (.add9, 2), (.seventh, 1.5), (.sus4, 1), (.triad, 1), (.ninth, 1)],
        drums: [(.minimal, 5), (.dreamy, 1), (.halfTime, 0.5)],
        bass: [(.drone, 5), (.sustained, 2)],
        swing: 0...0.05, duck: 0...0.1, humanize: 0.01, keyLift: 0, leadVerse: 0.05, openVoicing: 0.7,
        padStyles: [(0, 6), (1, 0.6)],
        piano: [(.slow, 3), (.ballad, 2)],
        guitar: [(.ring, 3), (.pick, 1)],
        stabs: [[0], [0, 8], [0, 12]],
        arps: [[0, 8], Banks.quarters, [0, 6, 12], [0, 8, 12]],
        pluckBusy: false,
        strums: [4],
        melodyDensity: 0.08...0.25, melodySync: 0...0.1, melodyLen: 12...16,
        templates: [("float", 4), ("loop", 1.5), ("classic", 0.5)],
        brightness: -0.05, reverb: 0.3, density: 0.4)

    static let dreamPop = GenreTraits(
        scales: [(.major, 2.5), (.lydian, 2), (.mixolydian, 1.5), (.dorian, 1.5), (.naturalMinor, 1.2)],
        vamp: 0.08,
        bars: [(2, 3), (1, 1.5), (4, 0.7)],
        colors: [(.add9, 2.5), (.seventh, 2), (.triad, 1.5), (.sus2, 1.5), (.sixth, 0.8)],
        drums: [(.dreamy, 3.5), (.backbeat, 2), (.halfTime, 1), (.gated80s, 0.4)],
        bass: [(.rootFifth, 2), (.sustained, 2), (.syncopated, 1.5), (.walking, 1)],
        swing: 0.02...0.12, duck: 0.1...0.25, humanize: 0.01, keyLift: 0.05, leadVerse: 0.2, openVoicing: 0.6,
        padStyles: [(0, 4), (1, 1)],
        piano: [(.ballad, 2), (.broken, 2), (.slow, 1.5), (.alberti, 1)],
        guitar: [(.ring, 3.5), (.strum, 1.5), (.pick, 1)],
        stabs: [[0, 8], [0, 6, 10], [0, 4, 8, 12], [0, 10], [0, 3, 8]],
        arps: [Banks.eighths, Banks.quarters, Banks.dotted, [0, 2, 4, 6, 8, 12]],
        pluckBusy: false,
        strums: [0, 4, 5],
        melodyDensity: 0.25...0.5, melodySync: 0.05...0.25, melodyLen: 8...12,
        templates: [("classic", 2), ("float", 1.5), ("twoVerses", 1.5), ("loop", 1)],
        brightness: 0, reverb: 0.2, density: 0.55)

    static let indietronica = GenreTraits(
        scales: [(.major, 2.5), (.mixolydian, 2), (.dorian, 2), (.lydian, 1), (.naturalMinor, 1.5)],
        vamp: 0.05,
        bars: [(1, 2), (2, 2)],
        colors: [(.triad, 2), (.add9, 2), (.seventh, 1.5), (.sus2, 1.5), (.sixth, 1)],
        drums: [(.breakbeat, 3), (.backbeat, 2.5), (.boomBap, 1.2), (.halfTime, 1.2), (.fourOnFloor, 0.8)],
        bass: [(.syncopated, 2.5), (.rolling, 1.2), (.walking, 1.2), (.rootFifth, 1.5), (.funk16, 0.8)],
        swing: 0...0.16, duck: 0.2...0.4, humanize: 0.006, keyLift: 0.1, leadVerse: 0.5, openVoicing: 0.25,
        padStyles: [(0, 3), (1, 2), (2, 1.5)],
        piano: [(.stabs, 2), (.alberti, 2), (.broken, 1.5), (.block, 1.5)],
        guitar: [(.pick, 2), (.strum, 2), (.ring, 1.5), (.chop, 1)],
        stabs: [[0, 3, 6, 10, 12], [2, 6, 10, 14], [0, 6, 8, 14], [1, 5, 9, 13], [0, 3, 8, 11, 14]],
        arps: [Banks.dotted, Banks.dottedBusy, Banks.hemiola, Banks.all16, Banks.eighths],
        pluckBusy: true,
        strums: [0, 2, 5, 6],
        melodyDensity: 0.45...0.8, melodySync: 0.3...0.6, melodyLen: 3...6,
        templates: [("classic", 2), ("teaser", 2), ("twoVerses", 1.5), ("drops", 1), ("noIntro", 1)],
        brightness: 0.05, reverb: -0.05, density: 0.7)

    static let lofi = GenreTraits(
        scales: [(.dorian, 3), (.naturalMinor, 2.5), (.major, 2), (.mixolydian, 1.5), (.melodicMinor, 0.8), (.lydian, 0.7)],
        vamp: 0.1,
        bars: [(2, 3), (1, 2), (4, 0.4)],
        colors: [(.seventh, 3.5), (.ninth, 2.5), (.add9, 1), (.sixth, 0.8), (.triad, 0.5)],
        drums: [(.boomBap, 5), (.halfTime, 1.5), (.dreamy, 0.8)],
        bass: [(.bounce808, 2.5), (.walking, 2), (.rootFifth, 2), (.sustained, 1)],
        swing: 0.14...0.3, duck: 0.1...0.25, humanize: 0.02, keyLift: 0.02, leadVerse: 0.1, openVoicing: 0.3,
        padStyles: [(0, 5), (1, 1)],
        piano: [(.block, 2), (.broken, 2), (.ballad, 1.5), (.alberti, 1)],
        guitar: [(.pick, 3), (.ring, 1.5), (.strum, 1)],
        stabs: [[0, 6, 10], [0, 10], [0, 3, 10, 12], [2, 7, 10], [0, 7, 10, 14]],
        arps: [Banks.quarters, [0, 3, 6, 10, 12], Banks.eighths],
        pluckBusy: false,
        strums: [4, 5, 0],
        melodyDensity: 0.2...0.5, melodySync: 0.2...0.5, melodyLen: 6...10,
        templates: [("loop", 3.5), ("classic", 1), ("float", 1)],
        brightness: -0.15, reverb: -0.05, density: 0.5)

    static let nuDisco = GenreTraits(
        scales: [(.mixolydian, 3), (.dorian, 3), (.major, 2.5), (.naturalMinor, 1.5), (.lydian, 0.8)],
        vamp: 0.05,
        bars: [(1, 3), (2, 2)],
        colors: [(.seventh, 3), (.ninth, 2.5), (.sixth, 1), (.add9, 1), (.triad, 1)],
        drums: [(.disco, 5), (.fourOnFloor, 2), (.backbeat, 0.5)],
        bass: [(.funk16, 4), (.offbeatOctave, 3), (.walking, 0.8)],
        swing: 0.02...0.12, duck: 0.35...0.55, humanize: 0.005, keyLift: 0.1, leadVerse: 0.2, openVoicing: 0.25,
        padStyles: [(0, 3), (1, 2), (2, 1)],
        piano: [(.stabs, 3), (.block, 1.5), (.broken, 0.8)],
        guitar: [(.chop, 5), (.strum, 0.8)],
        stabs: [[3, 7, 11, 15], [2, 6, 10, 14], [0, 3, 6, 10, 12], [0, 2, 6, 8, 10, 14], [1, 3, 7, 9, 11, 15]],
        arps: [Banks.all16, Banks.dottedBusy, Banks.eighths, Banks.dotted],
        pluckBusy: true,
        strums: [2, 6, 3],
        melodyDensity: 0.4...0.7, melodySync: 0.3...0.6, melodyLen: 4...6,
        templates: [("classic", 2.5), ("twoChoruses", 2), ("teaser", 1.5), ("drops", 1)],
        brightness: 0.1, reverb: -0.1, density: 0.75)

    static let edm = GenreTraits(
        scales: [(.naturalMinor, 3), (.major, 3), (.harmonicMinor, 1), (.mixolydian, 1), (.dorian, 1), (.phrygian, 0.6), (.lydian, 0.5)],
        vamp: 0.08,
        bars: [(1, 2), (2, 2.5), (4, 0.3)],
        colors: [(.triad, 4), (.sus4, 1), (.add9, 0.7), (.seventh, 0.5), (.sus2, 0.7)],
        drums: [(.fourOnFloor, 5), (.breakbeat, 0.6), (.disco, 0.5), (.epic, 0.5)],
        bass: [(.offbeatOctave, 3), (.rolling, 3), (.sustained, 1.5), (.syncopated, 0.5)],
        swing: 0...0.03, duck: 0.55...0.8, humanize: 0, keyLift: 0.3, leadVerse: 0.2, openVoicing: 0.2,
        padStyles: [(0, 3), (2, 3), (1, 1)],
        piano: [(.block, 2), (.stabs, 2), (.slow, 1)],
        guitar: [(.strum, 1.5), (.chop, 1), (.ring, 1)],
        stabs: [[0, 6, 10], [0, 4, 8, 12], [2, 6, 10, 14], [0, 3, 8, 11], [0, 8]],
        arps: [Banks.all16, Banks.eighths, Banks.dotted, [0, 1, 3, 4, 6, 8, 9, 11, 12, 14]],
        pluckBusy: true,
        strums: [1, 3, 0],
        melodyDensity: 0.35...0.7, melodySync: 0.1...0.4, melodyLen: 4...8,
        templates: [("drops", 4), ("classic", 1.5), ("teaser", 1)],
        brightness: 0.1, reverb: -0.1, density: 0.85)
}

// MARK: - How each mood tilts the choices

struct MoodTraits {
    var scales: [(Scale, Double)]
    var bars: [(Int, Double)]
    var colors: [(ChordColor, Double)]
    var drums: [(DrumStyle, Double)]
    var bass: [(BassStyle, Double)]
    var contours: [(Contour, Double)]
    var answers: [(AnswerKind, Double)]
    var brightness: Float
    var reverb: Float
    /// Multiplies the genre's melody density.
    var melodyScale: Double
    /// Added to the genre's arrangement density.
    var density: Float
    /// Chance added to the genre's chance of a key change.
    var keyLift: Double
    /// Chance of a calm two- or three-chord vamp, added to the genre's.
    var vamp: Double
    /// How much stepwise motion (0.4 jumpy ... 0.85 smooth).
    var stepBias: Double

    static func traits(for mood: Mood) -> MoodTraits {
        switch mood {
        case .relaxed: return relaxed
        case .introspective: return introspective
        case .melancholic: return melancholic
        case .romantic: return romantic
        case .uplifting: return uplifting
        case .dark: return dark
        case .happy: return happy
        case .chill: return chill
        case .energetic: return energetic
        case .sad: return sad
        case .dreamy: return dreamy
        case .epic: return epic
        case .raw: return raw
        }
    }

    static let relaxed = MoodTraits(
        scales: [(.major, 2.5), (.lydian, 2), (.mixolydian, 2), (.dorian, 2), (.naturalMinor, 0.6)],
        bars: [(2, 1.5), (4, 1), (1, 0.7)],
        colors: [(.seventh, 2), (.add9, 1.5), (.ninth, 1), (.sus2, 1), (.triad, 0.8)],
        drums: [(.halfTime, 2), (.dreamy, 2), (.boomBap, 1.5), (.backbeat, 1), (.minimal, 1)],
        bass: [(.sustained, 1.5), (.bounce808, 1.5), (.rootFifth, 1.5), (.walking, 1)],
        contours: [(.arch, 3), (.wave, 2), (.falling, 1), (.flat, 1)],
        answers: [(.sequence, 2), (.repeatPhrase, 2), (.free, 1), (.mirror, 0.5)],
        brightness: 0.45, reverb: 0.55, melodyScale: 0.7, density: -0.1, keyLift: 0, vamp: 0.1, stepBias: 0.8)

    static let introspective = MoodTraits(
        scales: [(.dorian, 3), (.naturalMinor, 2.5), (.lydian, 1), (.melodicMinor, 1), (.major, 0.6), (.mixolydian, 0.8)],
        bars: [(2, 1.5), (4, 1.5), (1, 0.5)],
        colors: [(.sus2, 2), (.add9, 2), (.seventh, 1.5), (.sus4, 1), (.triad, 0.7)],
        drums: [(.dreamy, 2), (.halfTime, 2), (.minimal, 1.5), (.boomBap, 1)],
        bass: [(.sustained, 2), (.drone, 1.5), (.bounce808, 1.2), (.rootFifth, 1)],
        contours: [(.falling, 2), (.wave, 2), (.flat, 2), (.arch, 1)],
        answers: [(.free, 2), (.sequence, 1.5), (.mirror, 1.5), (.repeatPhrase, 1)],
        brightness: 0.32, reverb: 0.65, melodyScale: 0.6, density: -0.15, keyLift: 0, vamp: 0.2, stepBias: 0.7)

    static let melancholic = MoodTraits(
        scales: [(.naturalMinor, 3), (.harmonicMinor, 1.5), (.dorian, 2), (.melodicMinor, 1), (.phrygian, 0.6), (.major, 0.25)],
        bars: [(2, 1.5), (1, 1), (4, 0.8)],
        colors: [(.seventh, 2), (.add9, 1.5), (.triad, 1.2), (.ninth, 1), (.sus2, 0.8)],
        drums: [(.halfTime, 2), (.dreamy, 1.8), (.boomBap, 1.2), (.minimal, 1), (.backbeat, 0.8)],
        bass: [(.sustained, 1.5), (.rootFifth, 1.5), (.bounce808, 1.5), (.walking, 1)],
        contours: [(.falling, 3), (.arch, 2), (.wave, 1), (.flat, 1)],
        answers: [(.sequence, 2.5), (.mirror, 1.5), (.repeatPhrase, 1), (.free, 1)],
        brightness: 0.3, reverb: 0.6, melodyScale: 0.65, density: -0.1, keyLift: 0, vamp: 0.08, stepBias: 0.78)

    static let romantic = MoodTraits(
        scales: [(.major, 2.5), (.lydian, 2), (.mixolydian, 1.2), (.dorian, 1), (.naturalMinor, 1.2), (.melodicMinor, 0.8),
                 (.harmonicMinor, 0.5)],
        bars: [(2, 1.5), (1, 1), (4, 0.6)],
        colors: [(.seventh, 2.5), (.ninth, 2), (.add9, 1.5), (.sixth, 1.2), (.triad, 0.6)],
        drums: [(.backbeat, 2), (.halfTime, 1.5), (.dreamy, 1.5), (.boomBap, 1)],
        bass: [(.rootFifth, 2), (.walking, 1.5), (.sustained, 1.5), (.syncopated, 1)],
        contours: [(.arch, 3), (.rising, 1.5), (.wave, 1.5), (.falling, 1)],
        answers: [(.sequence, 2.5), (.repeatPhrase, 1.5), (.mirror, 1), (.free, 1)],
        brightness: 0.5, reverb: 0.6, melodyScale: 0.75, density: -0.05, keyLift: 0.1, vamp: 0.04, stepBias: 0.82)

    static let uplifting = MoodTraits(
        scales: [(.major, 3), (.lydian, 2.5), (.mixolydian, 2.2), (.dorian, 0.8), (.naturalMinor, 0.3)],
        bars: [(1, 1.5), (2, 1.2), (4, 0.3)],
        colors: [(.triad, 2.5), (.add9, 1.5), (.sus4, 1), (.seventh, 0.8), (.sus2, 0.8)],
        drums: [(.fourOnFloor, 2), (.backbeat, 2), (.disco, 1.5), (.gated80s, 1)],
        bass: [(.syncopated, 2), (.offbeatOctave, 2), (.rolling, 1.5), (.funk16, 1.2)],
        contours: [(.rising, 3), (.arch, 2), (.wave, 1.5), (.zigzag, 0.8)],
        answers: [(.sequence, 3), (.repeatPhrase, 1.5), (.free, 1), (.mirror, 0.5)],
        brightness: 0.8, reverb: 0.4, melodyScale: 1.1, density: 0.1, keyLift: 0.15, vamp: 0.02, stepBias: 0.62)

    static let dark = MoodTraits(
        scales: [(.naturalMinor, 3), (.phrygian, 2), (.harmonicMinor, 2), (.dorian, 0.8), (.melodicMinor, 0.8), (.major, 0.1)],
        bars: [(1, 1.2), (2, 1.2), (4, 0.5)],
        colors: [(.triad, 2), (.seventh, 1.5), (.sus2, 1), (.sus4, 0.8), (.add9, 0.6)],
        drums: [(.halfTime, 2), (.breakbeat, 2), (.fourOnFloor, 1.5), (.epic, 1)],
        bass: [(.rolling, 2), (.sustained, 1.5), (.syncopated, 1)],
        contours: [(.falling, 2), (.zigzag, 1.5), (.flat, 1.5), (.arch, 1)],
        answers: [(.mirror, 2), (.repeatPhrase, 2), (.sequence, 1.5), (.free, 1)],
        brightness: 0.33, reverb: 0.55, melodyScale: 0.9, density: 0.05, keyLift: 0, vamp: 0.1, stepBias: 0.6)

    static let happy = MoodTraits(
        scales: [(.major, 4), (.mixolydian, 1.5), (.lydian, 1.5), (.dorian, 0.3), (.naturalMinor, 0.1)],
        bars: [(1, 1.5), (2, 1)],
        colors: [(.triad, 3), (.add9, 1.2), (.sixth, 1), (.seventh, 0.7)],
        drums: [(.backbeat, 2), (.fourOnFloor, 2), (.disco, 1.5), (.gated80s, 1)],
        bass: [(.syncopated, 2), (.rootFifth, 1.5), (.offbeatOctave, 1.5)],
        contours: [(.arch, 2.5), (.rising, 2), (.zigzag, 1.5), (.wave, 1.5)],
        answers: [(.sequence, 2.5), (.repeatPhrase, 2), (.free, 1), (.mirror, 0.5)],
        brightness: 0.85, reverb: 0.35, melodyScale: 1.05, density: 0.08, keyLift: 0.1, vamp: 0.02, stepBias: 0.6)

    static let chill = MoodTraits(
        scales: [(.dorian, 3), (.mixolydian, 1.5), (.major, 1.5), (.naturalMinor, 1.5), (.lydian, 1.2)],
        bars: [(2, 1.5), (1, 1)],
        colors: [(.seventh, 3), (.ninth, 1.5), (.add9, 1), (.triad, 0.6)],
        drums: [(.halfTime, 2), (.boomBap, 2), (.dreamy, 1.5), (.backbeat, 0.8)],
        bass: [(.bounce808, 2), (.rootFifth, 1.5), (.walking, 1.5)],
        contours: [(.wave, 2.5), (.arch, 2), (.falling, 1), (.flat, 1.5)],
        answers: [(.sequence, 2), (.repeatPhrase, 2), (.free, 1.5), (.mirror, 0.5)],
        brightness: 0.45, reverb: 0.5, melodyScale: 0.7, density: -0.1, keyLift: 0, vamp: 0.1, stepBias: 0.78)

    static let energetic = MoodTraits(
        scales: [(.mixolydian, 2.5), (.major, 2.5), (.dorian, 1.5), (.naturalMinor, 1.5), (.lydian, 1)],
        bars: [(1, 1.5), (2, 1)],
        colors: [(.triad, 3), (.sus4, 1), (.add9, 0.8), (.seventh, 0.7)],
        drums: [(.fourOnFloor, 3), (.breakbeat, 1.5), (.disco, 1.2), (.backbeat, 1)],
        bass: [(.rolling, 2.5), (.offbeatOctave, 2), (.funk16, 1)],
        contours: [(.zigzag, 2), (.rising, 2), (.arch, 1.5), (.wave, 1.5)],
        answers: [(.repeatPhrase, 2.5), (.sequence, 2), (.free, 1), (.mirror, 0.7)],
        brightness: 0.9, reverb: 0.3, melodyScale: 1.2, density: 0.15, keyLift: 0.1, vamp: 0.02, stepBias: 0.55)

    static let sad = MoodTraits(
        scales: [(.naturalMinor, 4), (.dorian, 1), (.harmonicMinor, 1), (.melodicMinor, 0.5), (.major, 0.1)],
        bars: [(1, 1), (2, 1.2), (4, 0.5)],
        colors: [(.seventh, 2), (.triad, 1.5), (.add9, 1), (.ninth, 0.8)],
        drums: [(.halfTime, 2), (.dreamy, 1.5), (.boomBap, 1.2), (.minimal, 0.8)],
        bass: [(.sustained, 2), (.bounce808, 1.5), (.rootFifth, 1)],
        contours: [(.falling, 3), (.arch, 1.5), (.flat, 1.5), (.wave, 1)],
        answers: [(.sequence, 2.5), (.mirror, 1.5), (.free, 1), (.repeatPhrase, 1)],
        brightness: 0.3, reverb: 0.6, melodyScale: 0.6, density: -0.12, keyLift: 0, vamp: 0.08, stepBias: 0.8)

    static let dreamy = MoodTraits(
        scales: [(.lydian, 4), (.major, 1.5), (.mixolydian, 1), (.dorian, 1.2), (.naturalMinor, 0.5)],
        bars: [(2, 1.5), (4, 1), (1, 0.6)],
        colors: [(.seventh, 2), (.add9, 2), (.sus2, 1.5), (.ninth, 1.2), (.triad, 0.6)],
        drums: [(.dreamy, 3), (.halfTime, 1.5), (.minimal, 1), (.backbeat, 0.8)],
        bass: [(.sustained, 2), (.rootFifth, 1.5), (.drone, 1)],
        contours: [(.wave, 2.5), (.arch, 2), (.rising, 1), (.flat, 1)],
        answers: [(.sequence, 2), (.free, 1.5), (.repeatPhrase, 1.5), (.mirror, 1)],
        brightness: 0.6, reverb: 0.75, melodyScale: 0.65, density: -0.1, keyLift: 0, vamp: 0.12, stepBias: 0.8)

    static let epic = MoodTraits(
        scales: [(.naturalMinor, 3), (.harmonicMinor, 2), (.dorian, 1), (.phrygian, 1), (.major, 1), (.lydian, 0.6)],
        bars: [(2, 1.5), (1, 1), (4, 0.5)],
        colors: [(.triad, 3), (.sus4, 1), (.add9, 1), (.seventh, 0.8)],
        drums: [(.epic, 4), (.fourOnFloor, 1), (.backbeat, 1), (.halfTime, 1)],
        bass: [(.sustained, 2), (.rolling, 1.5), (.rootFifth, 1.5)],
        contours: [(.rising, 2.5), (.arch, 2.5), (.falling, 1), (.zigzag, 1)],
        answers: [(.sequence, 2.5), (.repeatPhrase, 2), (.mirror, 1), (.free, 0.8)],
        brightness: 0.6, reverb: 0.7, melodyScale: 0.9, density: 0.1, keyLift: 0.2, vamp: 0.02, stepBias: 0.7)

    static let raw = MoodTraits(
        scales: [(.phrygian, 3), (.naturalMinor, 2), (.harmonicMinor, 1.5), (.dorian, 0.8)],
        bars: [(1, 2), (2, 0.8)],
        colors: [(.triad, 3), (.sus4, 0.8), (.sus2, 0.6), (.seventh, 0.5)],
        drums: [(.breakbeat, 3), (.fourOnFloor, 2), (.halfTime, 1)],
        bass: [(.rolling, 2.5), (.syncopated, 1.5), (.sustained, 1)],
        contours: [(.zigzag, 2.5), (.flat, 1.5), (.falling, 1.5), (.arch, 1)],
        answers: [(.repeatPhrase, 3), (.mirror, 1.5), (.sequence, 1.5), (.free, 0.8)],
        brightness: 0.4, reverb: 0.4, melodyScale: 1.0, density: 0.12, keyLift: 0, vamp: 0.03, stepBias: 0.5)
}
