import BlazeEngine
import SwiftUI

struct CreateView: View {
    @EnvironmentObject var model: GeneratorModel
    @EnvironmentObject var library: SongLibrary
    @EnvironmentObject var player: AudioPlayerModel

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 8)]
    private let lengths: [Double] = [60, 90, 120, 150, 180]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    presetsCard
                    genreCard
                    tempoCard
                    moodCard
                    instrumentsCard
                    vocalsCard
                    soundCard
                    variationCard
                    generateSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { NowPlayingBar() }
            .overlay {
                if model.isGenerating { GeneratingOverlay() }
            }
            .alert("Oops", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var keyBinding: Binding<Int> {
        Binding(
            get: { model.settings.key ?? -1 },
            set: { newValue in
                model.settings.key = newValue < 0 ? nil : newValue
                model.selectedPreset = nil
            }
        )
    }

    // MARK: sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Blaze Raw")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.accent)
            Text("Make your own songs. Pick a style or a genre and a mood, then hit Generate.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var presetsCard: some View {
        Card("Start with a style",
             subtitle: model.selectedPreset?.blurb ?? "Custom mix. You changed something, nice!") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StylePreset.allCases) { preset in
                        Chip(emoji: preset.emoji,
                             title: preset.title,
                             selected: model.selectedPreset == preset) {
                            model.apply(preset)
                        }
                        .frame(width: 104)
                    }
                }
            }
        }
    }

    private var genreCard: some View {
        Card("Genre", subtitle: model.settings.genre?.blurb ?? "Open sound: only the mood decides the style.") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(emoji: "🌍",
                         title: "Any",
                         selected: model.settings.genre == nil) {
                        model.setGenre(nil)
                    }
                    .frame(width: 80)
                    ForEach(Genre.allCases) { genre in
                        Chip(emoji: genre.emoji,
                             title: genre.title,
                             selected: model.settings.genre == genre) {
                            model.setGenre(genre)
                        }
                        .frame(width: 104)
                    }
                }
            }
        }
    }

    private var tempoCard: some View {
        Card("Tempo", subtitle: "How fast the song goes (beats per minute).") {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(model.settings.tempo))")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("BPM").font(.headline).foregroundStyle(.secondary)
                Spacer()
            }
            Slider(value: model.tempoBinding, in: SongSettings.minTempo...SongSettings.maxTempo, step: 1)
            HStack {
                Button {
                    model.tapTempo()
                } label: {
                    Label("Tap tempo", systemImage: "hand.tap")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button {
                    model.useSuggestedTempo()
                } label: {
                    Text(model.suggestedTempoTitle)
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
            }
            Text(model.tempoIsManual
                 ? "You set the tempo, so it stays put."
                 : "The tempo follows your genre and mood. Move the slider to set it yourself.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Tip: tap along with a song you like to copy its tempo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var moodCard: some View {
        Card("Mood", subtitle: "Changes the chords, scale and feel.") {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Mood.allCases) { mood in
                    Chip(emoji: mood.emoji, title: mood.title, selected: model.settings.mood == mood) {
                        model.setMood(mood)
                    }
                }
            }
        }
    }

    private var instrumentsCard: some View {
        Card("Instruments", subtitle: "Pick as many as you like.") {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(InstrumentKind.allCases) { inst in
                    Chip(emoji: inst.emoji, title: inst.title,
                         selected: model.settings.instruments.contains(inst)) {
                        model.toggle(inst)
                    }
                }
            }
        }
    }

    private var vocalsCard: some View {
        Card("Vocals", subtitle: "Wordless synthesized voices. Mix and match!") {
            LazyVGrid(columns: columns, spacing: 8) {
                Chip(emoji: "🎼", title: "No vocals", selected: model.settings.vocals.isEmpty) {
                    model.clearVocals()
                }
                ForEach(VocalStyle.allCases) { vocal in
                    Chip(emoji: vocal.emoji, title: vocal.title,
                         selected: model.settings.vocals.contains(vocal)) {
                        model.toggle(vocal)
                    }
                }
            }
        }
    }

    private var soundCard: some View {
        Card("Sound") {
            HStack {
                Text("Key")
                Spacer()
                Picker("Key", selection: keyBinding) {
                    Text("Auto").tag(-1)
                    ForEach(0..<12, id: \.self) { index in
                        Text(SongSettings.keyNames[index]).tag(index)
                    }
                }
                .pickerStyle(.menu)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Length")
                Picker("Length", selection: model.bind(\.lengthSeconds)) {
                    ForEach(lengths, id: \.self) { seconds in
                        Text(mmss(seconds)).tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                Text("Songs are always at least 1 minute long.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Energy: \(Int(model.settings.intensity * 100))%")
                Slider(value: model.bind(\.intensity), in: 0...1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Grit (crunchy distortion): \(Int(model.settings.grit * 100))%")
                Slider(value: model.bind(\.grit), in: 0...1)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Tuning")
                Picker("Tuning", selection: tuningBinding) {
                    Text("Piano").tag(0)
                    Text("Just").tag(1)
                    Text("Alobend").tag(2)
                }
                .pickerStyle(.segmented)
                Text(tuningHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle(isOn: model.bind(\.aloboiSound)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aloboi sound")
                    Text("The Aloboi Synth, raw, plays the piano, pad, melody and arps, like a classical pianist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 0 = piano tuning, 1 = just intonation, 2 = Alobend (every chord bent into pure ratios).
    private var tuningBinding: Binding<Int> {
        Binding(
            get: { model.settings.alobend ? 2 : (model.settings.justIntonation ? 1 : 0) },
            set: { newValue in
                model.settings.justIntonation = newValue >= 1
                model.settings.alobend = newValue == 2
                model.selectedPreset = nil
            }
        )
    }

    private var tuningHint: String {
        if model.settings.alobend {
            return "Every chord is bent into pure ratios of its own, like the Alobend retuning tool: no beating, very smooth."
        }
        if model.settings.justIntonation {
            return "Pure-ratio notes for a smooth, slightly unreal sound."
        }
        return "Normal piano tuning."
    }

    private var variationCard: some View {
        Card("Variations", subtitle: "Same genre and mood, a brand-new song every time.") {
            HStack(spacing: 10) {
                Button {
                    model.newVariation()
                } label: {
                    Text("🎲 New variation")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    model.randomizeAll()
                } label: {
                    Text("🎰 Surprise me")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Text("Variation #\(model.settings.seed)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var generateSection: some View {
        VStack(spacing: 8) {
            Button {
                model.generate(library: library, player: player)
            } label: {
                Text("⚡️ Generate song")
                    .font(.title3.weight(.heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent)
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(model.isGenerating)
            Text(model.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
