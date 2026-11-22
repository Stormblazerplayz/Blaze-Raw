import BlazeEngine
import Foundation

/// A song you made. The audio lives in a WAV file; this is the information about it.
struct SavedSong: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var settings: SongSettings
    var duration: Double
    var fileName: String
    var keyName: String
    var scaleName: String
}

/// Where songs are kept. WAV files go in the Documents folder, which shows up in the
/// Files app under "On My iPhone > Blaze Raw", so you can share or copy them anywhere.
enum SongStorage {
    static var songsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var libraryFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("library.json")
    }

    /// A safe, unused file name like "Midnight Signal #123.wav".
    static func uniqueFileName(for title: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        var clean = title.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { clean = "Song" }
        var name = "\(clean).wav"
        var counter = 2
        while FileManager.default.fileExists(atPath: songsDirectory.appendingPathComponent(name).path) {
            name = "\(clean) \(counter).wav"
            counter += 1
        }
        return name
    }
}

@MainActor
final class SongLibrary: ObservableObject {
    @Published private(set) var songs: [SavedSong] = []

    init() {
        load()
    }

    func url(for song: SavedSong) -> URL {
        SongStorage.songsDirectory.appendingPathComponent(song.fileName)
    }

    func add(_ song: SavedSong) {
        songs.insert(song, at: 0)
        save()
    }

    func delete(_ song: SavedSong) {
        try? FileManager.default.removeItem(at: url(for: song))
        songs.removeAll { $0.id == song.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: SongStorage.libraryFile),
              let decoded = try? JSONDecoder().decode([SavedSong].self, from: data) else {
            songs = []
            return
        }
        // Forget songs whose file was deleted from the Files app.
        songs = decoded
            .filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(songs) {
            try? data.write(to: SongStorage.libraryFile, options: .atomic)
        }
    }
}
