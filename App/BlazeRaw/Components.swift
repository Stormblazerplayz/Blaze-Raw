import SwiftUI

/// A rounded box with a title, used to group controls.
struct Card<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle = subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A tappable choice with an emoji (for moods, instruments, vocals and styles).
struct Chip: View {
    let emoji: String
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(emoji).font(.title2)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.horizontal, 4)
            .background(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card))
            .foregroundStyle(selected ? Color.black : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(selected ? 0 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The little player at the bottom of the screen.
struct NowPlayingBar: View {
    @EnvironmentObject var player: AudioPlayerModel
    @EnvironmentObject var library: SongLibrary

    var body: some View {
        if let song = player.current {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                        Text("\(mmss(player.position)) / \(mmss(player.duration))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 38))
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    ShareLink(item: library.url(for: song)) {
                        Image(systemName: "square.and.arrow.up").font(.title3)
                    }
                    .accessibilityLabel("Share or save to Files")
                }
                Slider(
                    value: Binding(get: { player.position }, set: { player.seek(to: $0) }),
                    in: 0...max(player.duration, 1)
                )
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }
}

/// Shown while a song is being made.
struct GeneratingOverlay: View {
    @EnvironmentObject var model: GeneratorModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Making your song…").font(.title3.weight(.bold))
                ProgressView(value: min(max(model.progress, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(Theme.orange)
                Text("\(Int(model.progress * 100))%")
                    .font(.headline.monospacedDigit())
                Text("It is all made right on your phone. Longer songs take a little more time.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Cancel", role: .cancel) {
                    model.cancel()
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(24)
        }
    }
}
