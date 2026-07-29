#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_DIR="$ROOT_DIR/scripts/quick_switch_layout_harness"
APPKIT_HARNESS_DIR="$ROOT_DIR/scripts/quick_switch_appkit_layout_harness"
OUTPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/altp-quick-switch-layout.XXXXXX")"
APPKIT_OUTPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/altp-quick-switch-appkit-layout.XXXXXX")"
trap 'rm -f "$OUTPUT_FILE" "$APPKIT_OUTPUT_FILE"' EXIT

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
if [[ -z "${SDKROOT:-}" && -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi

swiftc \
    "$ROOT_DIR/Sources/Altp/QuickSwitchLayoutPolicy.swift" \
    "$HARNESS_DIR/main.swift" \
    -o "$OUTPUT_FILE"
"$OUTPUT_FILE"

swiftc \
    "$ROOT_DIR/Sources/Altp/AppSettings.swift" \
    "$ROOT_DIR/Sources/Altp/QuickSwitchLayoutPolicy.swift" \
    "$ROOT_DIR/Sources/Altp/QuickSwitchCollectionViewport.swift" \
    "$APPKIT_HARNESS_DIR/main.swift" \
    -framework AppKit \
    -o "$APPKIT_OUTPUT_FILE"
"$APPKIT_OUTPUT_FILE"
