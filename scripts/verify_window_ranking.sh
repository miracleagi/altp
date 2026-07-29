#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_DIR="$ROOT_DIR/scripts/window_ranking_harness"
IDENTITY_HARNESS_DIR="$ROOT_DIR/scripts/window_identity_harness"
MEMORY_HARNESS_DIR="$ROOT_DIR/scripts/window_selection_memory_harness"
OUTPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/altp-window-ranking.XXXXXX")"
IDENTITY_OUTPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/altp-window-identity.XXXXXX")"
MEMORY_OUTPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/altp-window-memory.XXXXXX")"
trap 'rm -f "$OUTPUT_FILE" "$IDENTITY_OUTPUT_FILE" "$MEMORY_OUTPUT_FILE"' EXIT

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
if [[ -z "${SDKROOT:-}" && -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi

swiftc \
    "$ROOT_DIR/Sources/Altp/WindowRankingPolicy.swift" \
    "$HARNESS_DIR/main.swift" \
    -o "$OUTPUT_FILE"
"$OUTPUT_FILE"

swiftc \
    "$ROOT_DIR/Sources/Altp/WindowIdentityPolicy.swift" \
    "$IDENTITY_HARNESS_DIR/main.swift" \
    -o "$IDENTITY_OUTPUT_FILE"
"$IDENTITY_OUTPUT_FILE"

swiftc \
    "$ROOT_DIR/Sources/Altp/SearchText.swift" \
    "$ROOT_DIR/Sources/Altp/WindowIdentityPolicy.swift" \
    "$ROOT_DIR/Sources/Altp/WindowRankingPolicy.swift" \
    "$ROOT_DIR/Sources/Altp/WindowSelectionMemory.swift" \
    "$MEMORY_HARNESS_DIR/main.swift" \
    -o "$MEMORY_OUTPUT_FILE"
"$MEMORY_OUTPUT_FILE"
