import BlazeEngine
import Foundation

// Command-line version of the song generator. Handy for testing on a computer.
//
//   swift run -c release blazecli --preset aloboi --seed 7 --out song.wav
//   swift run -c release blazecli --genre nuDisco --mood uplifting --seed 3 --out disco.wav
//   swift run -c release blazecli --mood chill --tempo 80 --instruments drums,piano,pad --vocals choir --out chill.wav
//   swift run -c release blazecli --list

func usage() {
    print("""
    blazecli - make a song and save it as a WAV file

      --preset NAME       \(StylePreset.allCases.map { $0.rawValue }.joined(separator: " | "))
      --genre NAME        \(Genre.allCases.map { $0.rawValue }.joined(separator: " | "))  (or "any")
      --mood NAME         \(Mood.allCases.map { $0.rawValue }.joined(separator: " | "))
      --tempo BPM         60...200  (with --genre and no --tempo, a tempo that fits the genre and mood is picked)
      --instruments LIST  comma list: \(InstrumentKind.allCases.map { $0.rawValue }.joined(separator: ","))
      --vocals LIST       comma list: \(VocalStyle.allCases.map { $0.rawValue }.joined(separator: ","))  (or "none")
      --key N             0 = C ... 11 = B (default: automatic)
      --length SECONDS    60...180
      --intensity 0...1
      --grit 0...1
      --just              use just intonation tuning
      --alobend           bend every chord into pure ratios of its own (also switches --just on)
      --aloboi-sound      the raw Aloboi Synth SoundFont plays the piano, pad, lead and arp
      --seed N
      --out FILE.wav
      --list              show every genre, mood, preset, instrument and vocal with its name
    """)
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func printList() {
    print("Genres (--genre):")
    for g in Genre.allCases {
        let lo = Int(g.tempoRange.lowerBound)
        let hi = Int(g.tempoRange.upperBound)
        print("  \(pad(g.rawValue, 13)) \(pad(g.title, 13)) \(lo)-\(hi) BPM   \(g.blurb)")
    }
    print("\nMoods (--mood):")
    for m in Mood.allCases {
        print("  \(pad(m.rawValue, 13)) \(pad(m.title, 13)) about \(Int(m.suggestedTempo)) BPM")
    }
    print("\nPresets (--preset):")
    for p in StylePreset.allCases {
        print("  \(pad(p.rawValue, 13)) \(pad(p.title, 15)) \(p.blurb)")
    }
    print("\nInstruments (--instruments):")
    for i in InstrumentKind.allCases {
        print("  \(pad(i.rawValue, 13)) \(i.title)")
    }
    print("\nVocals (--vocals):")
    for v in VocalStyle.allCases {
        print("  \(pad(v.rawValue, 13)) \(v.title)")
    }
}

/// Lower-case and without dashes, spaces or underscores, so "Nu-Disco", "nu_disco" and "nuDisco" all match.
func normalized(_ text: String) -> String {
    text.lowercased()
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: " ", with: "")
}

var args = Array(CommandLine.arguments.dropFirst())
if args.contains("--help") || args.contains("-h") {
    usage()
    exit(0)
}
if args.contains("--list") {
    printList()
    exit(0)
}

func value(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let seed = UInt64(value("--seed") ?? "1") ?? 1
var settings: SongSettings
if let name = value("--preset") {
    guard let preset = StylePreset(rawValue: name) else {
        print("Unknown preset \(name)")
        usage()
        exit(1)
    }
    settings = preset.settings(seed: seed)
} else {
    settings = SongSettings(seed: seed)
}

if let m = value("--mood") {
    guard let mood = Mood(rawValue: m) else {
        print("Unknown mood \(m)")
        usage()
        exit(1)
    }
    settings.mood = mood
}
if let name = value("--genre") {
    let wanted = normalized(name)
    if wanted == "any" || wanted == "none" {
        settings.genre = nil
    } else {
        guard let genre = Genre.allCases.first(where: { normalized($0.rawValue) == wanted }) else {
            print("Unknown genre \(name)")
            usage()
            exit(1)
        }
        settings.genre = genre
        // No --tempo given: use a tempo that fits this genre and mood.
        if value("--tempo") == nil {
            settings.tempo = genre.tempo(for: settings.mood, seed: seed)
        }
    }
}
if let t = value("--tempo"), let d = Double(t) { settings.tempo = d }
if let l = value("--length"), let d = Double(l) { settings.lengthSeconds = d }
if let v = value("--intensity"), let d = Double(v) { settings.intensity = d }
if let v = value("--grit"), let d = Double(v) { settings.grit = d }
if let k = value("--key"), let i = Int(k) { settings.key = i }
if args.contains("--just") { settings.justIntonation = true }
if args.contains("--alobend") { settings.alobend = true; settings.justIntonation = true }
if args.contains("--aloboi-sound") { settings.aloboiSound = true }
if let list = value("--instruments") {
    var set = Set<InstrumentKind>()
    for name in list.split(separator: ",") {
        guard let i = InstrumentKind(rawValue: String(name)) else { print("Unknown instrument \(name)"); exit(1) }
        set.insert(i)
    }
    settings.instruments = set
}
if let list = value("--vocals") {
    var set = Set<VocalStyle>()
    if list != "none" {
        for name in list.split(separator: ",") {
            guard let v = VocalStyle(rawValue: String(name)) else { print("Unknown vocal \(name)"); exit(1) }
            set.insert(v)
        }
    }
    settings.vocals = set
}

let out = value("--out") ?? "song.wav"
let start = Date()
var lastPrinted = -1
guard let song = SongEngine.render(settings, progress: { p in
    let pct = Int(p * 10)
    if pct != lastPrinted { lastPrinted = pct; FileHandle.standardError.write(Data("  \(pct * 10)%\n".utf8)) }
}) else {
    print("Cancelled")
    exit(1)
}
do {
    try WAV.write(song, to: URL(fileURLWithPath: out))
} catch {
    print("Could not write \(out): \(error)")
    exit(1)
}
let secs = Date().timeIntervalSince(start)
// (String interpolation instead of "%@": it builds the same on Linux and on Apple platforms.)
let audioSeconds = String(format: "%.1f", song.durationSeconds)
let renderSeconds = String(format: "%.1f", secs)
print("\"\(song.title)\"  key \(song.keyName) \(song.scaleName)  \(song.bars) bars  \(audioSeconds) s of audio  rendered in \(renderSeconds) s  -> \(out)")
// Second line: the genre and the "recipe" (every random choice made for this song).
let details = [song.genreTitle, song.recipe].filter { !$0.isEmpty }.joined(separator: " · ")
if !details.isEmpty {
    print("  \(details)")
}
