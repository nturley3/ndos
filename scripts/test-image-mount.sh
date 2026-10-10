#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/ndos-image-mount.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -Wno-unused-parameter -framework Foundation \
    -I "$repo_dir/dosbox/include" \
    "$repo_dir/scripts/test-image-mount.m" \
    "$repo_dir/dospad/Main/DPImageMountBridge.m" \
    -o "$build_dir/test-image-mount"
"$build_dir/test-image-mount"
