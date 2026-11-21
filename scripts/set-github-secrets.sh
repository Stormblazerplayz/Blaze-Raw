#!/usr/bin/env bash
# Saves your Apple keys into this GitHub repository as secrets, so the workflow can upload to TestFlight.
#
# Run this on YOUR computer (the one where you downloaded the .p8 key). You need:
#   - the GitHub CLI:  https://cli.github.com   (then run:  gh auth login)
#   - the 4 things from App Store Connect (see README.md, "Step 3")
#
# Easiest: just run it and answer the questions:
#     ./scripts/set-github-secrets.sh
#
# Or give everything at once:
#     ./scripts/set-github-secrets.sh /path/to/AuthKey_ABC123DEFG.p8 ABC123DEFG 69a6de70-xxxx-xxxx-xxxx-xxxxxxxxxxxx TEAM123456 owner/repo
#
# Nothing is printed or saved anywhere except GitHub's encrypted secret store.

set -euo pipefail

REPO_DEFAULT="stormblazerplayz/blaze-raw"

P8_PATH="${1:-}"
KEY_ID="${2:-}"
ISSUER_ID="${3:-}"
TEAM_ID="${4:-}"
REPO="${5:-$REPO_DEFAULT}"

if ! command -v gh >/dev/null 2>&1; then
  echo "The GitHub CLI (gh) is not installed. Get it from https://cli.github.com and run: gh auth login" >&2
  exit 1
fi

if [ -z "$P8_PATH" ]; then
  read -r -p "Path to your AuthKey_XXXXXXXXXX.p8 file (you can drag the file into this window): " P8_PATH
fi
# Remove quotes or trailing spaces that drag-and-drop can add.
P8_PATH="${P8_PATH%\"}"; P8_PATH="${P8_PATH#\"}"; P8_PATH="${P8_PATH%\'}"; P8_PATH="${P8_PATH#\'}"
P8_PATH="${P8_PATH%"${P8_PATH##*[![:space:]]}"}"

if [ ! -f "$P8_PATH" ]; then
  echo "I can't find the file: $P8_PATH" >&2
  exit 1
fi
if ! grep -q "BEGIN PRIVATE KEY" "$P8_PATH"; then
  echo "That file does not look like an App Store Connect .p8 key (no 'BEGIN PRIVATE KEY' inside)." >&2
  exit 1
fi

# The key ID is part of the file name: AuthKey_<KEYID>.p8
if [ -z "$KEY_ID" ]; then
  guess="$(basename "$P8_PATH")"
  guess="${guess#AuthKey_}"
  guess="${guess%.p8}"
  if [[ "$guess" =~ ^[A-Z0-9]{10}$ ]]; then
    read -r -p "Key ID [$guess]: " KEY_ID
    KEY_ID="${KEY_ID:-$guess}"
  else
    read -r -p "Key ID (10 letters/numbers, shown next to your key in App Store Connect): " KEY_ID
  fi
fi
if [ -z "$ISSUER_ID" ]; then
  read -r -p "Issuer ID (a long code like 69a6de70-03db-47e3-e053-5b8c7c11a4d1): " ISSUER_ID
fi
if [ -z "$TEAM_ID" ]; then
  read -r -p "Team ID (10 letters/numbers, from developer.apple.com > Membership details): " TEAM_ID
fi

if ! [[ "$KEY_ID" =~ ^[A-Za-z0-9]{10}$ ]]; then
  echo "The Key ID should be 10 letters/numbers. You gave: $KEY_ID" >&2
  exit 1
fi
if ! [[ "$ISSUER_ID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
  echo "The Issuer ID should look like 69a6de70-03db-47e3-e053-5b8c7c11a4d1. You gave: $ISSUER_ID" >&2
  exit 1
fi
if ! [[ "$TEAM_ID" =~ ^[A-Za-z0-9]{10}$ ]]; then
  echo "The Team ID should be 10 letters/numbers. You gave: $TEAM_ID" >&2
  exit 1
fi

echo "Saving 4 secrets to $REPO ..."
gh secret set APP_STORE_CONNECT_API_KEY_P8 --repo "$REPO" < "$P8_PATH"
gh secret set APP_STORE_CONNECT_KEY_ID --repo "$REPO" --body "$KEY_ID"
gh secret set APP_STORE_CONNECT_ISSUER_ID --repo "$REPO" --body "$ISSUER_ID"
gh secret set APPLE_TEAM_ID --repo "$REPO" --body "$TEAM_ID"

echo
echo "Done! The secrets now in $REPO:"
gh secret list --repo "$REPO"
echo
echo "Next: open the Actions tab on GitHub, pick 'iOS build and TestFlight', press 'Run workflow'."
