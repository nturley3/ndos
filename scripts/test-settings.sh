#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/ndos-settings.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "$build_dir/SettingsTests.app/Contents/MacOS" "$build_dir/SettingsTests.app/Contents/Resources"
cp "$repo_dir/Resources/Settings.plist" "$build_dir/SettingsTests.app/Contents/Resources/Settings.plist"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
    -framework Foundation -framework GameController -I "$repo_dir/dospad/Main" -I "$repo_dir/SDL/include" \
    "$repo_dir/scripts/test-settings.m" "$repo_dir/dospad/Main/DPSettings.m" \
    "$repo_dir/dospad/Main/DPKeyboardManager.m" \
    -o "$build_dir/SettingsTests.app/Contents/MacOS/test-settings"
"$build_dir/SettingsTests.app/Contents/MacOS/test-settings"
