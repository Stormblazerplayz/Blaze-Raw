import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: SongLibrary
    @EnvironmentObject var player: AudioPlayerModel
    @EnvironmentObject var generator: GeneratorModel
    @EnvironmentObject var router: Router

    var body: some View {
        NavigationStack {
            Group {
                if library.songs.isEmpty {
                    emptyState
                } else {
                    songList
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("My Songs")
            .safeAreaInset(edge: .bottom) { NowPlayingBar() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🎧").font(.system(size: 56))
            Text("No songs yet").font(.title3.bold())
            Text("Go to Create and tap Generate.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var songList: some View {
        List {
            ForEach(library.songs) { song in
                row(song)
                    .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func isPlaying(_ song: SavedSong) -> Bool {
        player.current?.id == song.id && player.isPlaying
    }

    private func detail(_ song: SavedSong) -> String {
        var parts: [String] = []
        if let genre = song.settings.genre { parts.append(genre.title) }
        parts.append(song.settings.mood.title)
        parts.append("\(Int(song.settings.tempo)) BPM")
        parts.append("\(song.keyName) \(song.scaleName)")
        parts.append(mmss(song.duration))
        return parts.joined(separator: " · ")
    }

    private func row(_ song: SavedSong) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: isPlaying(song) ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.headline)
                    Text(detail(song))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if player.current?.id == song.id {
                    player.toggle()
                } else {
                    player.play(song, url: library.url(for: song))
                }
            }
            ShareLink(item: library.url(for: song)) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Share or save to Files")
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                player.stopIfPlaying(song)
                library.delete(song)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                generator.load(song.settings)
                router.tab = .create
            } label: {
                Label("Remix", systemImage: "wand.and.stars")
            }
            .tint(Theme.orange)
        }
    }
}
