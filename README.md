# Blaze Raw 🔥🎧

An iPhone app that **makes its own music**. Pick a genre, a mood, a tempo, instruments and vocals, hit **Generate**, and get a brand-new song that is **at least one minute long** (up to three minutes). Songs are saved as WAV files you can share. Every song gets its own random recipe, so even the same settings give a different song each time (see [Why songs differ](#why-songs-differ)).

It has an **Aloboi-style** preset, inspired by the public tags of Aloboi's *Intermodulation* (electronic, house, downtempo, vocal) and by how Aloboi works: MPE-capable virtual synths like Vital and Serum inside Logic Pro for unstable oscillators, Reese basses and rich synth pads, and **Alobend**, a custom MIDI retuning tool that bends standard keyboard chords into mathematically pure "just intonation" ratios. See [The Aloboi sound](#the-aloboi-sound). It makes new music in that spirit. It does **not** copy or sample any real song.

> **TL;DR for getting it on your iPhone:** the app code and the GitHub robot are done. You still have to do the Apple account steps in [Step by step: Apple Developer and TestFlight](#step-by-step-apple-developer-and-testflight) (they need your Apple ID, your phone for the login code, and a grown-up for the payment). Then press one button on GitHub.

---

## What the app can do

| Feature | Details |
|---|---|
| **Genre** | Electronic, Synthpop, Pop, Chillwave, Downtempo, Ambient, Dream Pop, Indietronica, Lo-fi, Nu-Disco, EDM, or **Any** (each genre has its own tempo range, drum grooves, bass lines, chords, sounds and song layout) |
| **Mood** | Relaxed, Introspective, Melancholic, Romantic, Uplifting, Dark, Happy, Chill, Energetic, Sad, Dreamy, Epic, Raw (each changes the scale, chords and feel) |
| **Tempo** | 60–200 BPM slider, plus **Tap tempo** (tap along with any song to copy its speed) and a "use this genre's tempo" shortcut. Until you move the slider yourself, the tempo follows your genre and mood, and 🎲 *New variation* also picks a new tempo inside the genre's range |
| **Instruments** (pick any number) | Drums, Sub Bass, Growl Bass, Synth Pad, Lead Synth, E-Piano, Pluck, Guitar, Strings, Bells, Arpeggio |
| **Vocals** (pick any number) | Female Aah, Male Ooh, Choir, Vocal Chops, Robot Voice, Whisper, Duet (wordless synthesized voices) |
| **Style presets** (14) | Aloboi-style, Lo-fi Chill, Dark Techno, Happy Pop, Epic Movie, Dreamy Ambient, Raw Bass, Neon Synthpop, Disco Night, Beach Haze, Dream Pop, Indie Sparkle, Festival Drop, Slow Groove |
| **Length** | 1:00, 1:30, 2:00, 2:30 or 3:00. A song is **never shorter than one minute** |
| **Key, energy, grit** | Pick a key (or Auto), how busy it is, and how crunchy/distorted the synths are |
| **Tuning** | *Piano* (normal), *Just* (every note a pure ratio of the key: 3:2 fifths, 5:4 thirds) or *Alobend* (every **chord** bent into pure ratios of its own root, see [The Aloboi sound](#the-aloboi-sound)) |
| **Aloboi sound** | A switch for unstable oscillators, Reese bass, rich drifting pads and the built-in *Aloboi Synth* sample |
| **Variations** | 🎲 *New variation* (same genre and mood, a brand-new song), 🎰 *Surprise me* (random genre, mood and everything else) |
| **Library** | Play, scrub, share, delete, or swipe to **Remix** an old song's settings (genre included) |
| **Saving** | WAV files appear in the Files app: *On My iPhone → Blaze Raw* |

### Do I need to download a model?

No. The songs are made **on the phone by a built-in music engine** (no internet, no downloaded AI model, no server). That is why it also works on a plane. Bigger AI models (like MusicGen) sound more "real", but they need a big download and a powerful computer; see [Ideas for next versions](#ideas-for-next-versions).

### How the engine makes a song

1. **Recipe** – from your genre, mood and the variation number, the engine makes a long list of choices for this one song (scale, chord loops, drum groove, bass line, melody shape, song layout, the sound of every instrument, effects). See [Why songs differ](#why-songs-differ).
2. **Plan** – picks a key, writes the chord loops, and splits the song into sections such as intro / verse / chorus / breakdown / outro (always enough bars to last at least a minute at your tempo).
3. **Write** – makes a catchy melody "hook" that follows the chords, then writes a part for every instrument you chose (bass lines, pads, arps, guitar strums, piano chords, drum patterns with fills and risers, vocal lines).
4. **Play** – every sound is synthesized from scratch: band-limited saw/square oscillators, FM electric piano and bells, a Karplus-Strong guitar string, a distorted *growl bass* with a wobbling filter and ring-modulation (the "intermodulation" sound), drum samples built from noise and sine sweeps, and a formant voice synth that sings vowels.
5. **Mix** – sidechain "pumping" from the kick, stereo reverb, ping-pong echo, then loudness and a soft limiter so it never clips.

The same settings and the same variation number always give the same song.

### The Aloboi sound

The **Aloboi-style** preset turns all of this on, and you can switch each part on yourself (*Aloboi sound* and *Tuning: Alobend* on the Create screen, `--aloboi-sound` and `--alobend` in `blazecli`).

* **Unstable oscillators.** In an analog or MPE synth the oscillators never sit still. Here every unison voice of a pad or lead wanders slowly out of tune by itself (smoothed random pitch, a few cents, a couple of times a second), on top of the detune and drift the sounds already had (`SynthPatch.unstable`).
* **Reese bass.** Three saws whose detune slowly breathes in and out (about every 5 seconds) through a low-pass filter and a drive stage: the phasing bass of drum and bass (`BassKind.reese`, two characters: *reese* and *dirty reese*).
* **Rich synth pads.** Three new pads: *unstable stack* (five wandering saws), *Aloboi Synth* (the sample below, played twice slightly out of tune) and *intermod drone* (dark gritty saws with a fifth on top and a thick sub). There are Aloboi Synth lead and arp sounds and an *unstable saw* lead too.
* **The Aloboi Synth sample.** `Assets/Aloboi_Synth.sf2` is a SoundFont with one looped sample (a gritty stack of detuned synth tones; the loop holds exactly 20 cycles of its pitch). `scripts/make_aloboi_sample.py` turns it into `AloboiSampleData.swift`, so the engine embeds it and needs no files at run time. `AloboiSample.swift` plays it like a sampler (faster for higher notes, looping at the loop points, with 4-point interpolation). Run `python scripts/make_aloboi_sample.py Assets/Aloboi_Synth.sf2 Packages/BlazeEngine/Sources/BlazeEngine/AloboiSampleData.swift` to rebuild it from a different SoundFont.
* **Alobend tuning.** Alobend is described as a MIDI retuning tool that bends the chords of a normal keyboard into pure just-intonation ratios. The engine does the same thing per chord: the chord's root sits where just intonation puts it, and every other note is a pure ratio above that root (major third 5:4, minor third 6:5, fifth 3:2, sixth 5:3, seventh 15:8; on a major chord with a minor seventh the "harmonic" seventh 7:4, on a minor chord 9:5; tritone 45:32, or 7:5 on a diminished chord). A major chord becomes exactly 4:5:6 and does not beat at all. Because the root follows plain just intonation, the key never drifts.

### Why songs differ

Every time you press **Generate**, the engine first makes a **recipe**: a long list of choices for that one song. The **genre** picks the rules (its usual tempo, drum grooves, bass lines, chords, sounds and song layout). The **mood** tilts them (which scales are likely, how bright, how busy, how slow). The **variation number** (the seed) then makes the actual choices, so two songs with the same genre and mood still come out different.

| Part of the song | What can change from song to song |
|---|---|
| **Key and scale** | Major, minor, Dorian, Lydian, Mixolydian, Phrygian, harmonic and melodic minor |
| **Chords** | The chord loop for the verse, the chorus and the breakdown, how often the chord changes, and how rich the chords are (plain triads, 7ths, 9ths, add9, sus chords, 6ths) |
| **Drums** | The drum style of the genre, one of several grooves inside it, and how much it swings |
| **Bass line** | Steady, funky, walking, offbeat, 808-style or a long drone |
| **Melody** | Its rhythm, its shape (rising, falling, arch, wave) and how the second bar answers the first |
| **Song layout** | Which sections come in which order and how long they are, which instruments play in which section, and sometimes a key change |
| **Sounds** | What each instrument sounds like, the effects (reverb, echo) and the final mastering |

`blazecli` prints a song's genre and its recipe on a second line, so you can see why two songs differ. Pick a genre with `--genre` (and `blazecli --list` shows every genre, mood and preset).

---

## Project layout

```
App/BlazeRaw/             SwiftUI iPhone app (screens, player, library)
Packages/BlazeEngine/     The music engine (pure Swift, no Apple-only code)
  Sources/BlazeEngine/      Composer, Drums, Synths, Vocals, Renderer, WAV ...
                            AloboiSample.swift plays the embedded Aloboi Synth sample (data in AloboiSampleData.swift)
  Sources/blazecli/         Command-line tool: make a song on any computer
  Tests/                    Unit tests (length >= 60 s, all genres/moods/instruments/vocals ...)
Assets/                   Aloboi_Synth.sf2, the SoundFont the Aloboi Synth sample comes from
Config/Info.plist         App settings (audio in background, Files access, no-encryption flag)
project.yml               XcodeGen description (the .xcodeproj is generated, not stored)
.github/workflows/ios.yml GitHub robot: test, build, sign, upload to TestFlight
scripts/                  set-github-secrets.sh, make_icon.py, render-samples.sh (makes ~60 sample songs with blazecli),
                          make_aloboi_sample.py (SoundFont -> AloboiSampleData.swift)
```

## Try the engine on a computer (no iPhone needed)

You need [Swift](https://www.swift.org/install/) (macOS or Linux).

```bash
cd Packages/BlazeEngine
swift run -c release blazecli --preset aloboi --seed 7 --out aloboi.wav
```

Try the Aloboi sound and Alobend tuning on any genre:

```bash
swift run -c release blazecli --genre downtempo --mood introspective --aloboi-sound --alobend --seed 5 --out downtempo-aloboi.wav
```

```bash
swift run -c release blazecli --mood chill --tempo 80 --instruments drums,piano,pad,guitar --vocals choir --length 90 --out chill.wav
```

Pick a genre (and a mood). Without `--tempo` a tempo that fits the genre and mood is chosen, and a different `--seed` gives a different song every time:

```bash
swift run -c release blazecli --genre nuDisco --mood uplifting --instruments drums,subBass,guitar,piano,strings --seed 3 --out disco.wav
swift run -c release blazecli --genre ambient --mood introspective --instruments pad,bells,piano --seed 5 --length 120 --out ambient.wav
swift run -c release blazecli --genre lofi --mood melancholic --instruments drums,piano,subBass,guitar --seed 8 --out lofi.wav
```

Run `blazecli --help` for all options and `blazecli --list` for every genre, mood, preset, instrument and vocal. Run the tests with:

```bash
swift test -c release -Xswiftc -enable-testing
```

## Build the app yourself (Mac with Xcode)

```bash
brew install xcodegen
xcodegen generate
open BlazeRaw.xcodeproj
```

In Xcode: pick the *BlazeRaw* target, *Signing & Capabilities*, choose your Team, then press Run.

---

## Step by step: Apple Developer and TestFlight

### What is already done in this repo (nothing for you to do)

These parts are finished and tested:

1. **Project file generator** – `project.yml` (XcodeGen) so a Mac can build the app without a hand-made `.xcodeproj`.
2. **App settings for the App Store** – `Config/Info.plist` has `ITSAppUsesNonExemptEncryption = NO` (so TestFlight does not ask the encryption question), background audio, and Files-app access. A `PrivacyInfo.xcprivacy` privacy manifest is included.
3. **App icon** – a 1024×1024 PNG with **no transparency** (Apple rejects icons with transparency), made by `scripts/make_icon.py`.
4. **GitHub workflow** – `.github/workflows/ios.yml`:
   - runs the engine tests on Linux,
   - builds the app on a Mac runner,
   - if the four Apple secrets exist (and you are on `main` or pressed *Run workflow*): archives the app, **signs it with Apple's cloud-managed certificate using your App Store Connect API key** (so no certificates or profiles have to be stored in GitHub), exports the `.ipa`, uploads it to **TestFlight**, and keeps a copy of the `.ipa` as a download for 14 days.
5. **Secrets helper** – `scripts/set-github-secrets.sh` saves the four secrets to GitHub for you.
6. **Build numbers** – each run uses the GitHub run number as the build number, so every upload is unique.

### What could NOT be done for you (I have no access to your Apple account)

Creating an Apple Developer account needs your Apple ID password, the login code sent to your phone, a payment, and (for most countries) a grown-up. The App Store Connect API key can only be created by the account holder inside Apple's website and can be downloaded **only once**. I also cannot write GitHub secrets for you without those values. So these steps are yours:

### Step 1 – Join the Apple Developer Program (about 15 minutes, then wait for approval)

1. A parent/guardian (Apple requires members to be adults, usually 18+) makes or uses an Apple ID with **two-factor authentication** on.
2. Go to <https://developer.apple.com/programs/enroll/> and enroll. It costs about **US$99 per year**. Approval can take from minutes to a couple of days. TestFlight needs this paid membership.

### Step 2 – Find your Team ID

Go to <https://developer.apple.com/account> → **Membership details**. Copy the **Team ID** (10 letters/numbers).

### Step 3 – Register the app ID (bundle ID)

1. <https://developer.apple.com/account/resources/identifiers/list> → **+** → **App IDs** → **App** → Continue.
2. Description: `Blaze Raw`. Bundle ID: choose **Explicit** and type `com.stormblazerplayz.blazeraw`.
   (If you want a different one, use your own, then set a GitHub repository **variable** named `BUNDLE_ID` to the same text, see Step 6.)
3. No extra capabilities are needed. Continue → Register.

### Step 4 – Create the app in App Store Connect

1. <https://appstoreconnect.apple.com/apps> → **+** → **New App**.
2. Platform **iOS**, Name **Blaze Raw** (if taken, add something like "Blaze Raw Studio"; the name does not have to match the bundle ID), Language English, **Bundle ID** = the one you registered, SKU = anything (for example `blazeraw1`), User Access *Full Access*. Create.

### Step 5 – Create the API key (this is the "key" GitHub needs)

1. App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys**. If you see a *Request Access* button, the account holder must press it first.
2. Press **+** (Generate API Key). Name: `GitHub TestFlight`. Access: **Admin** (needed for Apple's cloud signing).
3. **Download** the `AuthKey_XXXXXXXXXX.p8` file. Apple only lets you download it **once**, so keep it safe. Never put it in the repo (`.gitignore` blocks `*.p8`).
4. Write down two more things shown on that page: the **Key ID** (10 characters, also in the file name) and the **Issuer ID** (a long code at the top of the page).

### Step 6 – Save the four secrets in GitHub

You now have four things: the `.p8` file, the **Key ID**, the **Issuer ID** and the **Team ID**.

**Easy way** (on the computer with the `.p8` file; needs the [GitHub CLI](https://cli.github.com), then `gh auth login`):

```bash
./scripts/set-github-secrets.sh
```

It asks for the four values, checks them, and saves them.

**By hand:** GitHub repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**. Make these four (names must match exactly):

| Secret name | What to paste |
|---|---|
| `APP_STORE_CONNECT_API_KEY_P8` | The **whole text** of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |
| `APP_STORE_CONNECT_KEY_ID` | The Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | The Issuer ID |
| `APPLE_TEAM_ID` | The Team ID |

Only if you used a different bundle ID: **Settings → Secrets and variables → Actions → Variables → New repository variable** named `BUNDLE_ID`.

### Step 7 – Press the button

GitHub repo → **Actions** → **iOS build and TestFlight** → **Run workflow** (branch `main`). It takes about 10–20 minutes. Green check = uploaded. (Pushing to `main` does the same automatically. Other branches and pull requests only test and build.)

### Step 8 – Get it on your iPhone with TestFlight

1. Wait for Apple to finish processing (about 5–30 minutes). You get an email, and the build appears in App Store Connect → your app → **TestFlight**.
2. In **TestFlight → Internal Testing**, make a group and add yourself. (Internal testers must be people added under *Users and Access* in App Store Connect.)
3. On your iPhone, install **TestFlight** from the App Store, open the invite email on the phone, and tap **Install**. 🎉

### If something goes wrong

| Problem | Fix |
|---|---|
| The workflow says *Apple secrets are missing* | Do Step 6. The names must match exactly. |
| A signing / provisioning / "no profiles" error | Check the API key has **Admin** access (Step 5), the bundle ID is registered (Step 3), and `APPLE_TEAM_ID` is right. Then re-run. |
| *Could not create the app* / name already used | Choose another app name in App Store Connect (Step 4). |
| Upload works but the build never shows up | Wait up to an hour and read the email from Apple (it lists what to fix). |
| *Invalid pre-release train / version already closed* | Raise `MARKETING_VERSION` in `project.yml` (for example to `1.0.1`). |
| The job waits a long time for a runner | Mac runners are busy sometimes. In a *private* repo they also use paid minutes (Mac minutes count 10×), so watch your GitHub billing page. |
| Apple says the app must be built with a newer SDK | The workflow picks the newest Xcode on the runner. If the runner is too old, change `runs-on: macos-latest` to a newer macOS image. |

---

## Ideas for next versions

1. **AI mode:** an optional "ask a big model" button that sends your mood/tempo/instruments as a text prompt to MusicGen (running on your own computer) for a more realistic sound, while keeping the built-in engine as the offline default.
2. **Real singing with words:** add a downloadable on-device voice model so vocals can sing your lyrics.
3. **Listen & match:** use the microphone to detect the tempo and key of a song you're playing, and set the sliders for you (analysis only, nothing is recorded or copied).
4. **More export options:** M4A/MP3, separate stems per instrument, and MIDI to open in GarageBand.
5. **Lock-screen controls**, Now Playing info and AirPlay buttons.
6. **Song structure editor:** drag to rearrange verse / chorus / breakdown and set how long each is.
7. **More sounds:** sampled drum kits, saxophone, choir "words", more genres and presets (Trap, Drum & Bass, Synthwave, Jazz, House).
8. **Visualizer videos** to share on social apps.
9. **iPad layout, widgets and haptics**; iCloud sync of your library.
10. **Live preview:** start playing while the rest of the song is still rendering.

## Honest notes

* I could not listen to the original *Intermodulation Demo*, and I did not copy it. The Aloboi-style preset is built from public information about the track and the artist, and its tempo is a starting guess. Use **Tap tempo** to match the real song.
* The engine is checked by automated tests and by analysing the rendered audio (length, level, no clipping, vowel formants, and how much songs with the same settings differ in brightness, bass weight and busyness). It has not been judged by ears, so tweak the grit, energy and instruments until it sounds right to you.
* The genres are built from general musical knowledge of each style (a typical tempo range, drum feel, bass line, chords and sounds). They are not copied from any song or artist, and, like everything else here, they have not been judged by ears yet. If a genre does not sound right to you, that is useful feedback for the next version.
* The iPhone app is built by the GitHub workflow on a real Mac runner (Xcode 26, iOS 26 SDK) on every push, including the unsigned Release archive and checks of the app package (bundle id, icon without transparency, encryption flag). The only part that has **not** been run is the signing and upload, because it needs your Apple account (see above).
* This repository is public. That is fine: GitHub secrets are encrypted and are never given to pull requests from other people's forks. Still, never commit your `.p8` key (`.gitignore` blocks it).
