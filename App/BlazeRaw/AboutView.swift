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
                        Text("Blaze Raw makes music right on your phone. Every song gets its own random recipe: a key and scale, a chord loop, a beat, a bass line, a melody and a sound for every instrument. Your genre picks the rules, your mood tilts them, and the variation number makes the choices. Then built-in synthesizers and a singing-voice synth play it. It works with no internet and needs no downloaded AI model. Every song is at least one minute long.")
                    }
                    Card("Genres and moods") {
                        Text("Pick a genre (Electronic, Synthpop, Pop, Chillwave, Downtempo, Ambient, Dream Pop, Indietronica, Lo-fi, Nu-Disco or EDM) to choose the kind of music, then a mood (Relaxed, Introspective, Melancholic, Romantic, Uplifting and more) to choose the feeling. The tempo follows your genre and mood until you move the slider yourself. Choose Any to let the mood decide on its own.")
                    }
                    Card("The Aloboi-style preset") {
                        Text("This style is inspired by public information about Aloboi's \"Intermodulation\": electronic, house, downtempo and vocal. It makes brand-new music in that spirit and does not copy any song. Use Tap tempo to match the real song's speed, then change the mood, instruments and vocals to make it your own.")
                    }
                    Card("The Aloboi sound") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Aloboi relies heavily on MPE-capable virtual synths like Vital and Serum inside Logic Pro to make unstable oscillators, Reese basses and rich synth pads. The Aloboi sound switch brings those ideas to Blaze Raw:")
                            Text("• Unstable oscillators: every voice wanders slowly out of tune by itself.")
                            Text("• Reese bass: detuned saws that slowly breathe in and out.")
                            Text("• Rich pads: wide, drifting synth stacks, plus the built-in \"Aloboi Synth\" sound (a looped sample from a SoundFont).")
                            Text("• Alobend tuning: Aloboi built Alobend, a custom MIDI retuning tool that bends standard keyboard chords into mathematically pure just-intonation ratios. Pick Alobend under Tuning and every chord is tuned that way, so a major chord becomes exactly 4:5:6 with no beating.")
                        }
                    }
                    Card("About the vocals") {
                        Text("The voices are synthesized and wordless (aah, ooh, choir, chops, robot, whisper). They do not sing real words.")
                    }
                    Card("Saving and sharing") {
                        Text("Every song is saved as a WAV file. Open the Files app, then On My iPhone, then Blaze Raw to find them. Tap the share button on a song to AirDrop it, save it to Files or send it to a friend.")
                    }
                    Card("Tips") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• Tap 🎲 New variation to get a different song in the same genre and mood.")
                            Text("• Try one genre with different moods, and one mood with different genres.")
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
