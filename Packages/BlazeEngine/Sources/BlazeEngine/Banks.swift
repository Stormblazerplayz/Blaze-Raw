import Foundation

// MARK: - Libraries of musical ingredients
//
// Everything in here is plain data: chord loops, rhythms, melody rhythm cells, arpeggio orders,
// strum patterns and song layouts. The style maker picks from these lists using the genre, the
// mood and the seed, so the more choices there are, the more different two songs can be.

enum ProgFamily: Int {
    case bright, minor, dorian, phrygian
}

/// A song layout: which kinds of sections follow each other and how long each one is (relative).
struct SectionTemplate {
    let base: String
    let kinds: [SectionKind]
    let weights: [Double]
    /// The template only applies when the song has between `minPhrases` and `maxPhrases` phrases (4 bars each).
    let minPhrases: Int
    let maxPhrases: Int
}

enum Banks {
    // MARK: chord loops (scale degrees, 0 = the first degree of the scale)

    static let brightProgressions: [[Int]] = [
        [0, 4, 5, 3], [5, 3, 0, 4], [0, 5, 3, 4], [0, 3, 4, 3], [3, 0, 4, 5], [0, 2, 3, 4],
        [0, 3, 5, 4], [1, 4, 0, 0], [0, 5, 1, 4], [0, 2, 5, 3], [3, 4, 2, 5], [0, 4, 3, 4],
        [0, 1, 4, 0], [5, 4, 3, 4], [0, 3, 0, 4]
    ]

    static let minorProgressions: [[Int]] = [
        [0, 5, 2, 6], [0, 3, 5, 4], [0, 6, 5, 6], [0, 2, 6, 3], [5, 6, 0, 0], [0, 3, 6, 2],
        [0, 5, 6, 4], [0, 4, 5, 3], [0, 5, 3, 6], [2, 5, 0, 6], [0, 6, 2, 5], [5, 3, 0, 4],
        [0, 3, 4, 0], [0, 2, 3, 6]
    ]

    static let dorianProgressions: [[Int]] = [
        [0, 3, 0, 3], [0, 3, 2, 3], [0, 2, 3, 0], [1, 3, 0, 0], [0, 6, 3, 0], [0, 3, 6, 3],
        [0, 1, 3, 0], [0, 5, 3, 6], [2, 3, 0, 0]
    ]

    static let phrygianProgressions: [[Int]] = [
        [0, 1, 0, 6], [0, 1, 6, 5], [0, 5, 6, 1], [0, 6, 5, 1], [0, 1, 2, 1], [0, 1, 5, 6]
    ]

    /// Two- and three-chord loops: calm and hypnotic.
    static let vampProgressions: [[Int]] = [
        [0, 3], [0, 1], [0, 6], [0, 4], [0, 5], [0, 2], [0, 3, 4], [0, 5, 3], [0, 6, 3]
    ]

    static func family(for scale: Scale) -> ProgFamily {
        switch scale {
        case .major, .lydian, .mixolydian: return .bright
        case .naturalMinor, .harmonicMinor, .melodicMinor: return .minor
        case .dorian: return .dorian
        case .phrygian: return .phrygian
        }
    }

    static func bank(for scale: Scale) -> [[Int]] {
        switch family(for: scale) {
        case .bright: return brightProgressions
        case .minor: return minorProgressions
        case .dorian: return dorianProgressions
        case .phrygian: return phrygianProgressions
        }
    }

    /// Picks the chord loops for a song: verse, chorus, breakdown and outro.
    static func progressions(scale: Scale, vampChance: Double, rng g: inout SeededRNG)
        -> (a: [Int], b: [Int], c: [Int], outro: [Int]) {
        let bank = Banks.bank(for: scale)
        let vamp = g.chance(vampChance)
        var a: [Int]
        var b: [Int]
        if vamp {
            a = g.pick(vampProgressions)
            b = a
            var tries = 0
            while b == a && tries < 8 {
                b = g.pick(vampProgressions)
                tries += 1
            }
        } else {
            a = g.pick(bank)
            b = a
            var tries = 0
            while b == a && tries < 8 {
                b = g.pick(bank)
                tries += 1
            }
        }
        // The breakdown plays the verse loop backwards, or starts halfway through it.
        let c: [Int]
        switch g.int(0...2) {
        case 0: c = Array(a.reversed())
        case 1: c = rotate(a, by: max(1, a.count / 2))
        default: c = rotate(b, by: 1)
        }
        // The outro settles on the home chord: either straight there or via the "IV" chord.
        let outro: [Int] = g.chance(0.5) ? [3, 0] : [0, 0]
        return (a, b, c, outro)
    }

    static func rotate(_ items: [Int], by n: Int) -> [Int] {
        guard !items.isEmpty else { return items }
        let k = ((n % items.count) + items.count) % items.count
        return Array(items[k...]) + Array(items[..<k])
    }

    // MARK: rhythm cells (onset steps inside one bar of sixteenth notes)

    static let sparseCells: [[Int]] = [
        [0, 8], [0, 6, 10], [0, 10], [0, 4, 12], [2, 10], [0, 7, 12], [0, 12], [4, 10]
    ]

    static let midCells: [[Int]] = [
        [0, 3, 6, 10], [0, 4, 8, 12], [0, 3, 8, 11], [0, 6, 8, 14], [2, 6, 10, 14], [0, 2, 6, 8, 11],
        [0, 3, 6, 8, 11, 14], [0, 4, 6, 10, 14], [0, 2, 8, 10, 12]
    ]

    static let busyCells: [[Int]] = [
        [0, 2, 4, 6, 8, 11, 12, 14], [0, 2, 3, 6, 8, 10, 12, 14], [0, 1, 3, 4, 6, 8, 9, 11, 12, 14],
        [0, 3, 4, 6, 8, 11, 12, 15], [0, 2, 4, 7, 8, 10, 12, 15]
    ]

    static let all16: [Int] = Array(0..<16)
    static let eighths: [Int] = [0, 2, 4, 6, 8, 10, 12, 14]
    static let quarters: [Int] = [0, 4, 8, 12]
    static let dotted: [Int] = [0, 3, 6, 8, 11, 14]
    static let dottedBusy: [Int] = [0, 2, 3, 6, 8, 10, 11, 14]
    static let hemiola: [Int] = [2, 5, 8, 11, 14]

    // MARK: arpeggio note orders (indexes into the chord tones, repeating)

    static let arpOrders: [[Int]] = [
        [0, 1, 2, 3, 2, 1], [0, 1, 2, 3], [3, 2, 1, 0], [0, 2, 1, 3, 2, 3, 1, 2], [0, 0, 2, 1, 3, 2, 1, 3],
        [0, 1, 2, 1, 3, 2], [0, 3, 1, 2], [0, 2, 3, 1], [0, 1, 0, 2, 0, 3], [0, 2, 1, 2, 3, 2, 1, 2]
    ]

    // MARK: pluck riffs (steps inside one bar)

    static let pluckSparse: [[Int]] = [
        [0, 6, 10], [0, 8], [2, 6, 10, 14], [0, 3, 10], [0, 4, 8, 12], [0, 6, 8, 14]
    ]

    static let pluckBusy: [[Int]] = [
        [0, 3, 6, 8, 11, 14], [0, 2, 6, 8, 10, 14], [0, 4, 6, 10, 12, 15], [1, 3, 6, 9, 11, 14],
        [0, 2, 4, 6, 8, 10, 12, 14], [0, 3, 4, 7, 8, 11, 12, 15]
    ]

    // MARK: guitar strums: (16th step, strength). Steps on the beat are down-strokes, the others up-strokes.

    static let strumPatterns: [[(Int, Float)]] = [
        [(0, 1.0), (6, 0.7), (8, 0.9), (14, 0.7)],
        [(0, 1.0), (4, 0.7), (8, 0.9), (12, 0.7)],
        [(0, 1.0), (3, 0.6), (6, 0.7), (8, 0.9), (11, 0.6), (14, 0.7)],
        [(0, 1.0), (2, 0.5), (4, 0.8), (6, 0.5), (8, 0.9), (10, 0.5), (12, 0.8), (14, 0.5)],
        [(0, 1.0), (8, 0.9)],
        [(0, 1.0), (5, 0.6), (8, 0.9), (13, 0.6)],
        [(0, 1.0), (4, 0.6), (6, 0.7), (10, 0.8), (12, 0.6), (14, 0.7)]
    ]

    // MARK: finger-picking orders (indexes into low root + chord tones)

    static let pickOrders: [[Int]] = [
        [0, 2, 3, 2, 1, 2, 3, 2], [0, 1, 2, 3, 2, 1, 2, 3], [0, 3, 2, 3, 1, 3, 2, 3], [0, 2, 1, 2, 3, 2, 1, 2]
    ]

    // MARK: song layouts

    static let templates: [SectionTemplate] = [
        // short songs (4 or 5 phrases)
        SectionTemplate(base: "classic", kinds: [.intro, .verse, .chorus, .outro], weights: [1, 1, 2, 1], minPhrases: 4, maxPhrases: 5),
        SectionTemplate(base: "teaser", kinds: [.intro, .chorus, .verse, .chorus], weights: [1, 2, 1, 2], minPhrases: 4, maxPhrases: 5),
        SectionTemplate(base: "noIntro", kinds: [.verse, .chorus, .breakdown, .chorus], weights: [1.5, 2, 1, 2], minPhrases: 4, maxPhrases: 5),
        SectionTemplate(base: "float", kinds: [.intro, .verse, .breakdown, .outro], weights: [1, 2, 2, 1], minPhrases: 4, maxPhrases: 5),
        SectionTemplate(base: "drops", kinds: [.intro, .breakdown, .chorus, .outro], weights: [1, 1, 2, 1], minPhrases: 4, maxPhrases: 5),
        SectionTemplate(base: "loop", kinds: [.intro, .verse, .breakdown, .verse], weights: [1, 2, 1, 2], minPhrases: 4, maxPhrases: 5),
        SectionTemplate(base: "twoChoruses", kinds: [.intro, .chorus, .breakdown, .chorus], weights: [1, 2, 1, 2], minPhrases: 4, maxPhrases: 5),
        SectionTemplate(base: "twoVerses", kinds: [.verse, .verse, .chorus, .outro], weights: [1, 1, 2, 1], minPhrases: 4, maxPhrases: 5),
        // medium songs (6 to 13 phrases)
        SectionTemplate(base: "classic", kinds: [.intro, .verse, .chorus, .breakdown, .chorus, .outro],
                        weights: [1, 1.5, 2, 1, 2, 1], minPhrases: 6, maxPhrases: 13),
        SectionTemplate(base: "twoVerses", kinds: [.intro, .verse, .chorus, .verse, .chorus, .breakdown, .chorus, .outro],
                        weights: [1, 1.5, 1.5, 1.5, 2, 1, 2, 1], minPhrases: 8, maxPhrases: 13),
        SectionTemplate(base: "teaser", kinds: [.intro, .chorus, .verse, .chorus, .breakdown, .chorus, .outro],
                        weights: [1, 1.5, 1.5, 2, 1, 2, 1], minPhrases: 7, maxPhrases: 13),
        SectionTemplate(base: "drops", kinds: [.intro, .verse, .breakdown, .chorus, .breakdown, .chorus, .outro],
                        weights: [1, 1.5, 1, 2, 1, 2, 1], minPhrases: 7, maxPhrases: 13),
        SectionTemplate(base: "loop", kinds: [.intro, .verse, .verse, .breakdown, .verse, .outro],
                        weights: [1, 1.5, 1.5, 1, 1.5, 1], minPhrases: 6, maxPhrases: 13),
        SectionTemplate(base: "float", kinds: [.intro, .breakdown, .verse, .breakdown, .outro],
                        weights: [1.5, 1.5, 2, 1.5, 1], minPhrases: 6, maxPhrases: 13),
        SectionTemplate(base: "twoChoruses", kinds: [.intro, .verse, .chorus, .breakdown, .verse, .chorus, .outro],
                        weights: [1, 1.5, 2, 1, 1.5, 2, 1], minPhrases: 7, maxPhrases: 13),
        SectionTemplate(base: "noIntro", kinds: [.verse, .chorus, .verse, .chorus, .breakdown, .chorus, .outro],
                        weights: [1, 1.5, 1, 2, 1, 2, 1], minPhrases: 7, maxPhrases: 13),
        // long songs (14 or more phrases)
        SectionTemplate(base: "classic", kinds: [.intro, .verse, .chorus, .breakdown, .verse, .chorus, .breakdown, .chorus, .outro],
                        weights: [1, 1.5, 1.5, 1, 1.5, 2, 1, 2, 1], minPhrases: 14, maxPhrases: 99),
        SectionTemplate(base: "twoVerses", kinds: [.intro, .verse, .chorus, .verse, .chorus, .breakdown, .chorus, .chorus, .outro],
                        weights: [1, 1.5, 1.5, 1.5, 1.5, 1, 2, 2, 1], minPhrases: 14, maxPhrases: 99),
        SectionTemplate(base: "drops", kinds: [.intro, .breakdown, .verse, .chorus, .breakdown, .verse, .chorus, .breakdown, .outro],
                        weights: [1, 1, 1.5, 2, 1, 1.5, 2, 1, 1], minPhrases: 14, maxPhrases: 99),
        SectionTemplate(base: "float", kinds: [.intro, .verse, .breakdown, .verse, .breakdown, .verse, .breakdown, .outro],
                        weights: [1, 1.5, 1.5, 1.5, 1.5, 1.5, 1.5, 1], minPhrases: 14, maxPhrases: 99),
        SectionTemplate(base: "loop", kinds: [.intro, .verse, .verse, .breakdown, .verse, .verse, .breakdown, .verse, .outro],
                        weights: [1, 1.5, 1.5, 1, 1.5, 1.5, 1, 1.5, 1], minPhrases: 14, maxPhrases: 99),
        SectionTemplate(base: "teaser", kinds: [.intro, .chorus, .verse, .chorus, .breakdown, .verse, .chorus, .chorus, .outro],
                        weights: [1, 1.5, 1.5, 2, 1, 1.5, 2, 2, 1], minPhrases: 14, maxPhrases: 99),
        SectionTemplate(base: "twoChoruses", kinds: [.intro, .verse, .chorus, .breakdown, .chorus, .verse, .chorus, .breakdown, .chorus, .outro],
                        weights: [1, 1.5, 1.5, 1, 2, 1.5, 2, 1, 2, 1], minPhrases: 14, maxPhrases: 99),
        SectionTemplate(base: "noIntro", kinds: [.verse, .chorus, .verse, .chorus, .breakdown, .verse, .chorus, .outro],
                        weights: [1, 1.5, 1, 2, 1, 1.5, 2, 1], minPhrases: 14, maxPhrases: 99)
    ]
}
