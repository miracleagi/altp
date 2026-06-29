#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Altp"
APP_VERSION="${ALTP_VERSION:-0.1.0}"
APP_BUILD="${ALTP_BUILD:-1}"
BUNDLE_ID="${ALTP_BUNDLE_ID:-com.miracleagi.altp}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
if [[ -z "${SDKROOT:-}" && -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi

swift build -c release \
    --disable-sandbox \
    --cache-path "$ROOT_DIR/.build/cache" \
    --scratch-path "$ROOT_DIR/.build"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
    CODESIGN_IDENTITY="${ALTP_CODESIGN_IDENTITY:-}"

    if [[ -z "$CODESIGN_IDENTITY" ]] && command -v security >/dev/null 2>&1; then
        CODESIGN_IDENTITY="$(
            security find-identity -v -p codesigning 2>/dev/null \
                | sed -nE 's/.*"(Apple Development:[^"]+)".*/\1/p' \
                | head -n 1
        )"
    fi

    if [[ -z "$CODESIGN_IDENTITY" ]] && command -v security >/dev/null 2>&1; then
        CODESIGN_IDENTITY="$(
            security find-identity -v -p codesigning 2>/dev/null \
                | sed -nE 's/.*"(Developer ID Application:[^"]+)".*/\1/p' \
                | head -n 1
        )"
    fi

    if [[ -n "$CODESIGN_IDENTITY" ]]; then
        CODESIGN_TIMESTAMP="${ALTP_CODESIGN_TIMESTAMP:-none}"
        if [[ "$CODESIGN_TIMESTAMP" == "1" || "$CODESIGN_TIMESTAMP" == "true" ]]; then
            codesign --force --deep --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
        else
            codesign --force --deep --timestamp=none --sign "$CODESIGN_IDENTITY" "$APP_DIR"
        fi
        echo "Signed with: $CODESIGN_IDENTITY"
    elif [[ "${ALTP_ALLOW_ADHOC:-}" == "1" ]]; then
        codesign --force --deep --sign - "$APP_DIR"
        echo "Signed with: ad-hoc"
        echo "Warning: ad-hoc signing changes the Accessibility permission identity on every rebuild." >&2
    else
        echo "No stable code-signing identity found." >&2
        echo "Set ALTP_CODESIGN_IDENTITY or run with ALTP_ALLOW_ADHOC=1 for a throwaway local build." >&2
        exit 1
    fi
fi

echo "$APP_DIR"
