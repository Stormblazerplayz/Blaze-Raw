import BlazeEngine
import Foundation

// Command-line version of the song generator. Handy for testing on a computer.
//
//   swift run -c release blazecli --preset aloboi --seed 7 --out song.wav
//   swift run -c release blazecli --mood chill --tempo 80 --instruments drums,piano,pad --vocals choir --out chill.wav

func usage() {
    print("""
    blazecli - make a song and save it as a WAV file

      --preset NAME       \(StylePreset.allCases.map { $0.rawValue }.joined(separator: " | "))
      --mood NAME         \(Mood.allCases.map { $0.rawValue }.joined(separator: " | "))
      --tempo BPM         60...200
      --instruments LIST  comma list: \(InstrumentKind.allCases.map { $0.rawValue }.joined(separator: ","))
      --vocals LIST       comma list: \(VocalStyle.allCases.map { $0.rawValue }.joined(separator: ","))  (or "none")
      --key N             0 = C ... 11 = B (default: automatic)
      --length SECONDS    60...180
      --intensity 0...1
      --grit 0...1
      --just              use just intonation tuning
      --seed N
      --out FILE.wav
    """)
}

var args = Array(CommandLine.arguments.dropFirst())
if args.contains("--help") || args.contains("-h") {
    usage()
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
    guard let mood = Mood(rawValue: m) else { print("Unknown mood \(m)"); exit(1) }
    settings.mood = mood
}
if let t = value("--tempo"), let d = Double(t) { settings.tempo = d }
if let l = value("--length"), let d = Double(l) { settings.lengthSeconds = d }
if let v = value("--intensity"), let d = Double(v) { settings.intensity = d }
if let v = value("--grit"), let d = Double(v) { settings.grit = d }
if let k = value("--key"), let i = Int(k) { settings.key = i }
if args.contains("--just") { settings.justIntonation = true }
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
print(String(format: "\"%@\"  key %@ %@  %d bars  %.1f s of audio  rendered in %.1f s  -> %@",
             song.title, song.keyName, song.scaleName, song.bars, song.durationSeconds, secs, out))
