#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_DIR="$ROOT_DIR/scripts/window_ranking_harness"
OUTPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/altp-window-ranking.XXXXXX")"
trap 'rm -f "$OUTPUT_FILE"' EXIT

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
if [[ -z "${SDKROOT:-}" && -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi

swiftc \
    "$ROOT_DIR/Sources/Altp/WindowRankingPolicy.swift" \
    "$HARNESS_DIR/main.swift" \
    -o "$OUTPUT_FILE"
"$OUTPUT_FILE"
