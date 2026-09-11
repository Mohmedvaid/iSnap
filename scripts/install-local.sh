#!/bin/bash

set -euo pipefail

app_name="iSnap"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_path="$repo_root/iSnap.xcodeproj"
build_root="$repo_root/.build"
built_app="$build_root/Build/Products/Release/iSnap.app"
installed_app="/Applications/iSnap.app"

fail() {
    printf '\n%s\n' "iSnap install stopped: $1" >&2
    exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "this installer must run on macOS."
fi

command -v git >/dev/null 2>&1 || fail "Git is not installed."
[[ -d "$project_path" ]] || fail "iSnap.xcodeproj was not found at $project_path."

cd "$repo_root"

if ! git diff --quiet || ! git diff --cached --quiet; then
    fail "you have tracked changes. Commit or stash them before installing."
fi

developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "$developer_dir" || "$developer_dir" == *CommandLineTools* || ! -x "$developer_dir/usr/bin/xcodebuild" ]]; then
    fail "Terminal is not using full Xcode. Run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
fi

if [[ "${ISNAP_INSTALL_UPDATE_COMPLETE:-false}" != "true" ]]; then
    printf '%s\n' "Updating main..."
    git fetch origin --prune
    if [[ "$(git branch --show-current)" != "main" ]]; then
        git switch main
    fi
    git pull --ff-only origin main

    # Restart from the newly pulled copy so this run always uses the latest installer.
    export ISNAP_INSTALL_UPDATE_COMPLETE=true
    exec "$repo_root/scripts/install-local.sh"
fi

printf '\n%s\n' "Building the Release app with $(xcodebuild -version | head -1)..."
xcodebuild \
    -project "$project_path" \
    -scheme "$app_name" \
    -configuration Release \
    -derivedDataPath "$build_root" \
    clean build

[[ -x "$built_app/Contents/MacOS/iSnap" ]] || fail "the Release build completed without producing iSnap.app."
codesign --verify --deep --strict "$built_app" || fail "the Release app failed code-signature verification."

staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/isnap-install.XXXXXX")"
staged_app="$staging_dir/iSnap.app"
previous_app="$staging_dir/iSnap.previous.app"

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT

ditto "$built_app" "$staged_app"

if pgrep -x "$app_name" >/dev/null 2>&1; then
    printf '\n%s\n' "Quitting running iSnap copies..."
    pkill -TERM -x "$app_name"
    for _ in {1..30}; do
        if ! pgrep -x "$app_name" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
fi

if pgrep -x "$app_name" >/dev/null 2>&1; then
    fail "iSnap did not quit. Quit it from the menu bar or Xcode, then run this installer again."
fi

had_previous=false
if [[ -e "$installed_app" ]]; then
    mv "$installed_app" "$previous_app" || fail "the existing app could not be moved. Check your Applications permissions."
    had_previous=true
fi

if ! mv "$staged_app" "$installed_app"; then
    if [[ "$had_previous" == true ]]; then
        mv "$previous_app" "$installed_app"
    fi
    fail "the new app could not be installed in Applications."
fi

rm -rf "$previous_app"

printf '\n%s\n' "Launching /Applications/iSnap.app..."
open "$installed_app"

for _ in {1..30}; do
    if pgrep -x "$app_name" >/dev/null 2>&1; then
        printf '\n%s\n' "Done — iSnap is updated, installed, and running."
        exit 0
    fi
    sleep 0.1
done

fail "the app was installed but did not remain running. Open /Applications/iSnap.app manually and check macOS security prompts."
