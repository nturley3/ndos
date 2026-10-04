#!/bin/bash
set -euo pipefail

: "${SRCROOT:?error: SRCROOT is required}"
: "${DERIVED_FILE_DIR:?error: DERIVED_FILE_DIR is required}"
: "${MARKETING_VERSION:?error: MARKETING_VERSION is required}"

# Avoid refreshing the Git index: inspecting build metadata must be read-only.
export GIT_OPTIONAL_LOCKS=0
ndos_revision=$(git -C "$SRCROOT" rev-parse --short=12 HEAD)
ndos_branch=$(git -C "$SRCROOT" rev-parse --abbrev-ref HEAD)
if [[ "$ndos_branch" == HEAD ]]; then
    ndos_branch=detached
fi
ndos_status=$(git -C "$SRCROOT" status --porcelain --untracked-files=all)
ndos_dirty=
if [[ -n "$ndos_status" ]]; then
    ndos_dirty=-dirty
fi
ndos_label="v${MARKETING_VERSION}-g${ndos_revision}${ndos_dirty} (${ndos_branch})"

mkdir -p "$DERIVED_FILE_DIR"
ndos_header="$DERIVED_FILE_DIR/ndos_build_version.h"
ndos_temp=$(mktemp "$DERIVED_FILE_DIR/ndos_build_version.XXXXXX")
trap 'rm -f "$ndos_temp"' EXIT
{
    printf '#pragma once\n#define NDOS_BUILD_VERSION "'
    # Escape bytes unsafe in C string literals, including trigraph characters.
    printf '%s' "$ndos_label" | /usr/bin/perl -pe 's/([^\x20-\x21\x23-\x3e\x40-\x5b\x5d-\x7e])/sprintf("\\%03o", ord($1))/ge'
    printf '"\n'
} > "$ndos_temp"

if [[ ! -f "$ndos_header" ]] || ! cmp -s "$ndos_temp" "$ndos_header"; then
    mv "$ndos_temp" "$ndos_header"
fi
printf 'nDOS Version %s\n' "$ndos_label"
