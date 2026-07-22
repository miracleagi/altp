#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Altp"
APP_VERSION="${ALTP_VERSION:-0.1.10}"
APP_BUILD="${ALTP_BUILD:-11}"
BUNDLE_ID="${ALTP_BUNDLE_ID:-com.miracleagi.altp}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
RELEASE_DIR="$DIST_DIR/release"
NOTARY_ZIP="$RELEASE_DIR/$APP_NAME-$APP_VERSION-notary.zip"
FINAL_ZIP="$RELEASE_DIR/$APP_NAME-$APP_VERSION-macOS.zip"

cd "$ROOT_DIR"

create_clean_zip() {
    local source_path="$1"
    local zip_path="$2"

    COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent "$source_path" "$zip_path"
}

developer_id_identity="${ALTP_DEVELOPER_ID_IDENTITY:-${ALTP_CODESIGN_IDENTITY:-}}"
if [[ -z "$developer_id_identity" ]] && command -v security >/dev/null 2>&1; then
    developer_id_identity="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -nE 's/.*"(Developer ID Application:[^"]+)".*/\1/p' \
            | head -n 1
    )"
fi

if [[ -z "$developer_id_identity" ]]; then
    echo "No Developer ID Application signing identity found." >&2
    echo "Set ALTP_DEVELOPER_ID_IDENTITY='Developer ID Application: ...' before running release." >&2
    exit 1
fi

notary_args=()
if [[ -n "${ALTP_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    notary_args=(--keychain-profile "$ALTP_NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${ALTP_NOTARY_APPLE_ID:-}" && -n "${ALTP_NOTARY_TEAM_ID:-}" && -n "${ALTP_NOTARY_PASSWORD:-}" ]]; then
    notary_args=(
        --apple-id "$ALTP_NOTARY_APPLE_ID"
        --team-id "$ALTP_NOTARY_TEAM_ID"
        --password "$ALTP_NOTARY_PASSWORD"
    )
else
    echo "No notarization credentials configured." >&2
    echo "Use one of:" >&2
    echo "  xcrun notarytool store-credentials altp-notary --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>" >&2
    echo "  ALTP_NOTARY_KEYCHAIN_PROFILE=altp-notary ./scripts/release.sh" >&2
    echo "or set ALTP_NOTARY_APPLE_ID, ALTP_NOTARY_TEAM_ID, and ALTP_NOTARY_PASSWORD." >&2
    exit 1
fi

mkdir -p "$RELEASE_DIR"

ALTP_BUNDLE_ID="$BUNDLE_ID" \
ALTP_VERSION="$APP_VERSION" \
ALTP_BUILD="$APP_BUILD" \
ALTP_CODESIGN_IDENTITY="$developer_id_identity" \
ALTP_CODESIGN_TIMESTAMP=1 \
    "$ROOT_DIR/scripts/build_app.sh"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
codesign --display --verbose=2 "$APP_DIR"

rm -f "$NOTARY_ZIP" "$FINAL_ZIP"
create_clean_zip "$APP_DIR" "$NOTARY_ZIP"

echo "Submitting $NOTARY_ZIP for notarization..."
xcrun notarytool submit "$NOTARY_ZIP" "${notary_args[@]}" --wait

xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"

create_clean_zip "$APP_DIR" "$FINAL_ZIP"

echo "Release artifact: $FINAL_ZIP"
