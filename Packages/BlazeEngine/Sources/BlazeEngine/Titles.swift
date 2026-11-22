import Foundation

/// Makes song names like "Velvet Mirrorball #512". The mood picks the first word; the noun comes from the
/// mood or (half of the time) from the genre, so a Nu-Disco song can be a "Mirrorball" and a Lo-fi song a "Cassette".
enum Titles {
    static func make(genre: Genre?, mood: Mood, seed: UInt64) -> String {
        var g = SeededRNG(seed: seed).fork(777)
        let adjectives: [String]
        var nouns: [String]
        switch mood {
        case .relaxed:
            adjectives = ["Easy", "Gentle", "Sunlit", "Calm", "Soft", "Breezy"]
            nouns = ["Afternoon", "Hammock", "Breeze", "Meadow", "Tide", "Porch"]
        case .introspective:
            adjectives = ["Inner", "Quiet", "Thoughtful", "Hushed", "Winter", "Still"]
            nouns = ["Mirror", "Journal", "Window", "Thought", "Echoes", "Corridor"]
        case .melancholic:
            adjectives = ["Fading", "Autumn", "Bittersweet", "Hollow", "Wistful", "Rainy"]
            nouns = ["Leaves", "Photograph", "Season", "Elegy", "Twilight", "Postcard"]
        case .romantic:
            adjectives = ["Velvet", "Tender", "Moonlit", "Honeyed", "Slow", "Candlelit"]
            nouns = ["Dance", "Promise", "Waltz", "Letter", "Kiss", "Evening"]
        case .uplifting:
            adjectives = ["Rising", "Radiant", "Bright", "Open", "Golden", "Soaring"]
            nouns = ["Horizon", "Sunrise", "Wings", "Morning", "Light", "Skyline"]
        case .dark:
            adjectives = ["Midnight", "Obsidian", "Static", "Hollow", "Shadow", "Neon"]
            nouns = ["Signal", "Echo", "Voltage", "Circuit", "Pulse", "Drift"]
        case .happy:
            adjectives = ["Sunny", "Golden", "Bright", "Bouncy", "Sparkling", "Lucky"]
            nouns = ["Morning", "Parade", "Skyline", "Summer", "Smile", "Groove"]
        case .chill:
            adjectives = ["Lazy", "Velvet", "Cozy", "Mellow", "Soft", "Slow"]
            nouns = ["Sunday", "Rain", "Window", "Coffee", "Tape", "Lounge"]
        case .energetic:
            adjectives = ["Turbo", "Electric", "Rapid", "Wild", "Blazing", "Hyper"]
            nouns = ["Rush", "Lightning", "Engine", "Sprint", "Spark", "Run"]
        case .sad:
            adjectives = ["Quiet", "Faded", "Blue", "Lonely", "Distant", "Grey"]
            nouns = ["Rain", "Letter", "Memory", "Goodbye", "Evening", "Tears"]
        case .dreamy:
            adjectives = ["Floating", "Pastel", "Cloudy", "Lucid", "Silver", "Gentle"]
            nouns = ["Dream", "Horizon", "Aurora", "Lagoon", "Orbit", "Haze"]
        case .epic:
            adjectives = ["Rising", "Mighty", "Eternal", "Final", "Golden", "Thunder"]
            nouns = ["Empire", "Voyage", "Legend", "Summit", "Dawn", "Crown"]
        case .raw:
            adjectives = ["Raw", "Crushed", "Savage", "Molten", "Feral", "Rusty"]
            nouns = ["Power", "Fury", "Engine", "Rage", "Metal", "Fire"]
        }
        var genreNouns: [String] = []
        if let genre = genre {
            switch genre {
            case .electronic: genreNouns = ["Circuit", "Pulse", "Matrix"]
            case .synthpop: genreNouns = ["Neon", "Arcade", "Chrome"]
            case .pop: genreNouns = ["Confetti", "Radio", "Spotlight"]
            case .chillwave: genreNouns = ["Haze", "Seaside", "Polaroid"]
            case .downtempo: genreNouns = ["Groove", "Velvet", "Lounge"]
            case .ambient: genreNouns = ["Drift", "Expanse", "Aurora"]
            case .dreamPop: genreNouns = ["Daydream", "Shimmer", "Cloud"]
            case .indietronica: genreNouns = ["Marble", "Paper", "Patchwork"]
            case .lofi: genreNouns = ["Cassette", "Rainy Day", "Notebook"]
            case .nuDisco: genreNouns = ["Mirrorball", "Boogie", "Starlight"]
            case .edm: genreNouns = ["Festival", "Laser", "Drop"]
            }
        }
        let adjective = g.pick(adjectives)
        if !genreNouns.isEmpty && g.chance(0.5) { nouns = genreNouns }
        let noun = g.pick(nouns)
        let number = g.int(100...999)
        return "\(adjective) \(noun) #\(number)"
    }
}
