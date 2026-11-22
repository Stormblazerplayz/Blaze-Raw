#!/usr/bin/env bash
# Renders a set of sample songs with the command-line tool so the variety can be checked by ear.
#
#   scripts/render-samples.sh [path-to-blazecli] [output-folder]
#
# It writes one WAV per song plus report.txt (the title, key, length and the "recipe" of every song).
# The GitHub workflow "Render sample songs" runs this and turns the WAVs into small MP3 files.
set -euo pipefail

CLI="${1:-Packages/BlazeEngine/.build/release/blazecli}"
OUT="${2:-samples}"
mkdir -p "$OUT"
REPORT="$OUT/report.txt"
: > "$REPORT"

render() {
  local name="$1"
  shift
  echo "== $name" >> "$REPORT"
  "$CLI" "$@" --length 60 --out "$OUT/$name.wav" 2>/dev/null >> "$REPORT"
}

# 1. Every style preset (each one picks instruments that fit its genre), three different variations.
for preset in aloboi lofiChill darkTechno happyPop epicCinema dreamyAmbient rawBass \
              synthpop nuDisco chillwave dreamPop indietronica edm downtempo; do
  for seed in 1 2 3; do
    render "preset-${preset}-${seed}" --preset "$preset" --seed "$seed"
  done
done

# 2. One genre with every mood: the mood changes the scale, the chords and the feel.
for mood in relaxed introspective melancholic romantic uplifting dark happy chill energetic sad dreamy epic raw; do
  render "mood-${mood}" --genre pop --mood "$mood" --seed 5 \
    --instruments drums,subBass,pad,piano,guitar,lead --vocals duet
done

# 3. Identical settings, eight different variation numbers: they must not sound the same.
for seed in 1 2 3 4 5 6 7 8; do
  render "same-settings-${seed}" --genre edm --mood energetic --seed "$seed" \
    --instruments drums,subBass,pad,lead,arp,pluck --vocals vocalChops
done

echo "Rendered $(ls "$OUT"/*.wav | wc -l) songs into $OUT"
