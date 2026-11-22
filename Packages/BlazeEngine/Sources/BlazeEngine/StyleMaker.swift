import Foundation

/// Turns (genre, mood, seed) into a StyleProfile: every musical and sonic choice for one song.
///
/// All randomness comes from forks of the song's base generator with fixed salts. The salts used here
/// are 40...49 for the composition choices; the sound, effects, mastering and drum-kit makers get their
/// own generators (salts 240, 250, 260 and 340). Nothing in here looks at which instruments the user
/// ticked, so adding or removing an instrument never changes the other instruments' notes or sounds.
enum StyleMaker {
    static func make(settings s: SongSettings, rng: SeededRNG) -> StyleProfile {
        let genre = s.genre
        let mood = s.mood
        let gt = GenreTraits.traits(for: genre)
        let mt = MoodTraits.traits(for: mood)

        // MARK: harmony
        var scaleRNG = rng.fork(40)
        let scale = scaleRNG.pickWeighted(combineWeights(gt.scales, mt.scales))

        var progRNG = rng.fork(41)
        let vampChance = min(max(gt.vamp + mt.vamp, 0), 0.6)
        let progs = Banks.progressions(scale: scale, vampChance: vampChance, rng: &progRNG)

        var barsRNG = rng.fork(42)
        let barsPerChord = barsRNG.pickWeighted(combineWeights(gt.bars, mt.bars))

        var colorRNG = rng.fork(43)
        let colorWeights = combineWeights(gt.colors, mt.colors)
        let colorVerse = colorRNG.pickWeighted(colorWeights)
        var colorChorus = colorVerse
        if !colorRNG.chance(0.5) { colorChorus = colorRNG.pickWeighted(colorWeights) }

        var voiceRNG = rng.fork(44)
        let openVoicings = voiceRNG.chance(gt.openVoicing)

        var liftRNG = rng.fork(45)
        let liftChance = min(max(gt.keyLift + mt.keyLift, 0), 0.5)
        var keyLift = 0
        if liftRNG.chance(liftChance) { keyLift = liftRNG.pick([2, 2, 2, 1]) }

        // MARK: rhythm and bass
        var drumRNG = rng.fork(46)
        let drumStyle = drumRNG.pickWeighted(combineWeights(gt.drums, mt.drums))
        let grooveVariant = drumRNG.int(0...7)

        var bassRNG = rng.fork(47)
        let bassStyle = bassRNG.pickWeighted(combineWeights(gt.bass, mt.bass))
        let bassVariant = bassRNG.int(0...3)

        var feelRNG = rng.fork(48)
        let swing = min(max(feelRNG.value(gt.swing), 0), 0.4)
        let duck: Float = min(max(feelRNG.valueF(gt.duck), 0), 0.8)
        let brightJitter = Float(feelRNG.value(-0.08...0.08))
        let reverbJitter = Float(feelRNG.value(-0.08...0.08))
        let brightness = min(max(mt.brightness + gt.brightness + brightJitter, 0.1), 1)
        let reverb = min(max(mt.reverb + gt.reverb + reverbJitter, 0.15), 0.95)
        let intensityShift = Float(s.intensity - 0.7) * 0.3
        let density = min(max(gt.density + mt.density + intensityShift, 0.15), 1)

        // MARK: melodies
        var melodyRNG = rng.fork(49)
        var melody = MelodySpec()
        melody.density = min(max(melodyRNG.value(gt.melodyDensity) * mt.melodyScale, 0.06), 0.95)
        melody.syncopation = melodyRNG.value(gt.melodySync)
        melody.stepBias = min(max(mt.stepBias + melodyRNG.value(-0.08...0.08), 0.3), 0.92)
        melody.leapChance = 0.06 + (1 - melody.stepBias) * 0.25
        melody.contour = melodyRNG.pickWeighted(mt.contours)
        melody.answer = melodyRNG.pickWeighted(mt.answers)
        melody.maxLen = melodyRNG.int(gt.melodyLen)
        melody.rangeLow = melodyRNG.int(-3...0)
        melody.rangeHigh = melody.rangeLow + melodyRNG.int(6...9)

        var verseMelody = melody
        verseMelody.density = max(melody.density * 0.55, 0.06)
        verseMelody.maxLen = min(melody.maxLen + 2, 16)
        verseMelody.contour = melodyRNG.pickWeighted(mt.contours)
        verseMelody.answer = melodyRNG.pickWeighted(mt.answers)
        verseMelody.rangeLow = melody.rangeLow - 1
        verseMelody.rangeHigh = max(melody.rangeHigh - 2, verseMelody.rangeLow + 4)

        // MARK: the parts that play chords and riffs
        var partRNG = rng.fork(50)
        let stabRhythm = partRNG.pick(gt.stabs)
        var stabAlt = partRNG.pick(gt.stabs)
        var tries = 0
        while stabAlt == stabRhythm && gt.stabs.count > 1 && tries < 6 {
            stabAlt = partRNG.pick(gt.stabs)
            tries += 1
        }
        let arpRhythm = partRNG.pick(gt.arps)
        let arpOrder = partRNG.pick(Banks.arpOrders)
        let useBusyPluck = partRNG.chance(0.75) ? gt.pluckBusy : !gt.pluckBusy
        let pluckRhythm = partRNG.pick(useBusyPluck ? Banks.pluckBusy : Banks.pluckSparse)
        let strumIndex = partRNG.pick(gt.strums)
        let strumPattern = Banks.strumPatterns[min(max(strumIndex, 0), Banks.strumPatterns.count - 1)]
        let padStyle = partRNG.pickWeighted(gt.padStyles)
        let pianoMode = partRNG.pickWeighted(gt.piano)
        let guitarMode = partRNG.pickWeighted(gt.guitar)
        let leadInVerse = partRNG.chance(gt.leadVerse)

        // MARK: sound design (each maker gets its own independent generator)
        let palette = Palette.make(genre: genre, mood: mood, brightness: brightness, rng: rng.fork(240))
        let kit = DrumKitSpec.make(genre: genre, mood: mood, style: drumStyle, rng: rng.fork(340))
        let fx = FXSpec.make(genre: genre, mood: mood, reverb: reverb, tempo: s.tempo, rng: rng.fork(250))
        let master = MasterSpec.make(genre: genre, mood: mood, rng: rng.fork(260))

        var p = StyleProfile(genre: genre, mood: mood, palette: palette, kit: kit, fx: fx, master: master)
        p.scale = scale
        p.barsPerChord = barsPerChord
        p.progA = progs.a
        p.progB = progs.b
        p.progC = progs.c
        p.progOutro = progs.outro
        p.colorVerse = colorVerse
        p.colorChorus = colorChorus
        p.openVoicings = openVoicings
        p.keyLift = keyLift
        p.drumStyle = drumStyle
        p.grooveVariant = grooveVariant
        p.bassStyle = bassStyle
        p.bassVariant = bassVariant
        p.swing = swing
        p.duck = duck
        p.humanize = gt.humanize
        p.brightness = brightness
        p.reverb = reverb
        p.density = density
        p.melody = melody
        p.verseMelody = verseMelody
        p.stabRhythm = stabRhythm
        p.stabRhythmAlt = stabAlt
        p.arpRhythm = arpRhythm
        p.arpOrder = arpOrder
        p.pluckRhythm = pluckRhythm
        p.strumPattern = strumPattern
        p.padStyle = padStyle
        p.pianoMode = pianoMode
        p.guitarMode = guitarMode
        p.leadInVerse = leadInVerse
        return p
    }
}
