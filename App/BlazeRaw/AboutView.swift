import SwiftUI

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Card("How it works") {
                        Text("Blaze Raw makes music right on your phone. It picks a key, chords, a melody and a beat that fit your mood and tempo, then plays them with built-in synthesizers and a singing-voice synth. It works with no internet and needs no downloaded AI model. Every song is at least one minute long.")
                    }
                    Card("The Aloboi-style preset") {
                        Text("This style is inspired by public information about Aloboi's \"Intermodulation\": electronic, house, downtempo and vocal, with gritty saw-wave synths and just-intonation tuning. It makes brand-new music in that spirit and does not copy any song. Use Tap tempo to match the real song's speed, then change the mood, instruments and vocals to make it your own.")
                    }
                    Card("About the vocals") {
                        Text("The voices are synthesized and wordless (aah, ooh, choir, chops, robot, whisper). They do not sing real words.")
                    }
                    Card("Saving and sharing") {
                        Text("Every song is saved as a WAV file. Open the Files app, then On My iPhone, then Blaze Raw to find them. Tap the share button on a song to AirDrop it, save it to Files or send it to a friend.")
                    }
                    Card("Tips") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• Tap 🎲 New variation to get a different song with the same settings.")
                            Text("• Swipe a song right in My Songs to Remix it.")
                            Text("• Turn up Grit for a rougher, crunchier sound.")
                            Text("• Try Just intonation with the Pad and Bells for a dreamy feel.")
                        }
                    }
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .font(.subheadline)
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("About")
            .safeAreaInset(edge: .bottom) { NowPlayingBar() }
        }
    }
}
