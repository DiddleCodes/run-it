#!/usr/bin/env bash
# Builds a signed Android release and sends it to testers through Firebase
# App Distribution — see android/DISTRIBUTION.md.
#
#   tool/distribute_android.sh "What changed"          # production backend
#   API_BASE_URL=https://staging.example tool/distribute_android.sh "…"
#
# Optional: TESTER_GROUPS (default "testers"), ALLOW_LOCAL_BACKEND=1 to ship a
# build that talks to http://localhost:3000 (only useful over USB with
# `adb reverse tcp:3000 tcp:3000` — a tester's phone can't reach it).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_ID="1:694264652054:android:a577129dc2130ec91f7037"  # com.bridgitcampus.app
PROJECT="run-it-febca"
TESTER_GROUPS="${TESTER_GROUPS:-testers}"
# The upload key's certificate (android/SIGNING.md) — never ship anything else.
EXPECTED_SIGNER="e8e078270d62d1ec688259e015c0eb8fdf70aac7f853b614adf004dad95abe8b"
NOTES="${1:-$(git log -1 --pretty=%s)}"

if [[ -z "${API_BASE_URL:-}" ]]; then
  if [[ "${ALLOW_LOCAL_BACKEND:-}" == 1 ]]; then
    API_BASE_URL="http://localhost:3000"
  else
    API_BASE_URL="https://api.bridgitcampus.com"
  fi
fi
if [[ "$API_BASE_URL" != https://* && "${ALLOW_LOCAL_BACKEND:-}" != 1 ]]; then
  echo "API_BASE_URL must be https:// for a tester build (got $API_BASE_URL)." >&2
  exit 1
fi

if command -v firebase >/dev/null; then
  firebase=(firebase)
else
  firebase=(npx --yes firebase-tools@latest)
fi

# Each build gets a higher versionCode than the last, so testers can install
# it over the previous one.
BUILD_NUMBER="$(git rev-list --count HEAD)"

flutter build apk --release \
  --build-number="$BUILD_NUMBER" \
  --dart-define=API_BASE_URL="$API_BASE_URL"

APK="build/app/outputs/flutter-apk/app-release.apk"
APKSIGNER="$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/*/apksigner | sort -V | tail -1)"
SIGNER="$("$APKSIGNER" verify --print-certs "$APK" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
if [[ "$SIGNER" != "$EXPECTED_SIGNER" ]]; then
  echo "Refusing to distribute: $APK is signed by $SIGNER, not the Bridgit upload key." >&2
  exit 1
fi

"${firebase[@]}" appdistribution:distribute "$APK" \
  --app "$APP_ID" \
  --project "$PROJECT" \
  --groups "$TESTER_GROUPS" \
  --release-notes "$NOTES (build $BUILD_NUMBER, backend $API_BASE_URL)"
