#!/usr/bin/env bash
# Installs or updates Atelier in /Applications.
#
#   curl -fsSL https://edi-edi.github.io/atelier-releases/install.sh | bash
#
# It downloads the latest release from GitHub, checks that the app is signed
# with Atelier's own certificate (the fingerprint below is pinned when each
# release is published), copies it to /Applications and opens it. Because the
# download is made by curl rather than a browser, macOS doesn't show the
# "can't verify the developer" warning. Later updates arrive inside the app.
set -euo pipefail

APP_NAME="Atelier"
DMG_URL="https://github.com/edi-edi/atelier-releases/releases/latest/download/Atelier.dmg"
CERT_SHA256="0d1e6814ef596a872d4474300fc1810a376f1a0bd5038807621f8731ecbbd2f1"
MIN_MACOS=15
DESTINATION="/Applications/$APP_NAME.app"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

# Global so the EXIT trap can still read them after main() returns.
work=""
mount=""
cleanup() {
  if [[ -n "$mount" ]]; then hdiutil detach -quiet "$mount" >/dev/null 2>&1 || true; fi
  if [[ -n "$work" ]]; then rm -rf "$work"; fi
}

main() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "$APP_NAME runs on macOS only."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  (( major >= MIN_MACOS )) || fail "$APP_NAME needs macOS $MIN_MACOS or later (this Mac has $(sw_vers -productVersion))."

  work="$(mktemp -d)"
  trap cleanup EXIT

  say "Downloading ${APP_NAME}…"
  curl -fL --progress-bar "$DMG_URL" -o "$work/$APP_NAME.dmg"

  mount="$work/volume"
  mkdir -p "$mount"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$work/$APP_NAME.dmg"
  local app="$mount/$APP_NAME.app"
  [[ -d "$app" ]] || fail "The download doesn't contain $APP_NAME.app."

  say "Checking the signature…"
  codesign --verify --deep --strict "$app" 2>/dev/null || fail "The app's signature is invalid. Nothing was installed."
  codesign -d --extract-certificates="$work/cert" "$app" 2>/dev/null
  local fingerprint
  fingerprint="$(shasum -a 256 "$work/cert0" | cut -d ' ' -f 1)"
  if [[ "$(printf '%s' "$fingerprint" | tr 'A-F' 'a-f')" != "$(printf '%s' "$CERT_SHA256" | tr 'A-F' 'a-f')" ]]; then
    fail "The app isn't signed with $APP_NAME's certificate. Nothing was installed."
  fi

  if pgrep -xq -U "$(id -u)" "$APP_NAME"; then
    say "Quitting the running copy of ${APP_NAME}…"
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    local waited=0
    while pgrep -xq -U "$(id -u)" "$APP_NAME" && (( waited < 20 )); do sleep 1; waited=$((waited + 1)); done
    if pgrep -xq -U "$(id -u)" "$APP_NAME"; then
      fail "$APP_NAME is still running (it may be waiting for you). Quit it and run this again. Nothing was installed."
    fi
  fi

  [[ -w /Applications ]] || fail "Your user account can't write to /Applications. Log in as an administrator and run this again."

  say "Installing to ${DESTINATION}…"
  local staging="/Applications/.$APP_NAME-install.app"
  rm -rf "$staging"
  ditto "$app" "$staging"
  rm -rf "$DESTINATION"
  mv "$staging" "$DESTINATION"
  xattr -dr com.apple.quarantine "$DESTINATION" 2>/dev/null || true

  hdiutil detach -quiet "$mount" >/dev/null 2>&1 || true
  mount=""

  say "Done. Opening $APP_NAME."
  say "The first time, it shows a code for this Mac: send it to the person who gave you $APP_NAME to get your activation link."
  open "$DESTINATION"
}

main "$@"
