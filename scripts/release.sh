#!/usr/bin/env bash
#
# Build a signed, notarized, stapled .dmg of imvault. Apple Silicon only
# for now (matches build-sidecar.sh's PYTHON_ARCH); add an x86_64 slice in
# a polish pass.
#
# Prerequisites (one-time):
#   - Developer ID Application cert in a dedicated CI keychain. On this Mac,
#     login keychain codesigning fails from non-interactive shells with
#     errSecInternalComponent (errKCInteractionNotAllowed). The fix is the
#     ci-signing.keychain-db pattern documented in myvota-ios at
#     docs/headless-codesign-setup.md — a dedicated keychain that can be
#     unlocked programmatically.
#   - CI_KEYCHAIN_PASSWORD env var set to that keychain's password. Add to
#     your ~/.zshrc:  export CI_KEYCHAIN_PASSWORD='your-password'
#   - notarytool profile cached:
#       xcrun notarytool store-credentials imvault-notary \
#         --key <path-to-AuthKey.p8> --key-id <KEY_ID> --issuer <ISSUER_UUID>
#
# Options:
#   --skip-notarize   Stop after the DMG is created and signed; skip the
#                     5-minute notary submission + staple. Useful for
#                     iterating on signing locally.
#   --identity STR    Override the Developer ID identity (default below).
#   --profile STR     Override the notarytool keychain profile name.
#
# Outputs build/imvault-<VERSION>.dmg.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Appdromeda Technologies Inc. (42WA4984A7)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-imvault-notary}"
SKIP_NOTARIZE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-notarize) SKIP_NOTARIZE=1; shift ;;
        --identity)      SIGN_IDENTITY="$2"; shift 2 ;;
        --profile)       NOTARY_PROFILE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^$/{ /^# /s/^# \{0,1\}//p; }' "$0"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

# --- Sanity checks ------------------------------------------------------------

echo "[release] checking prerequisites..."
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
    echo "[release] ERROR: no 'Developer ID Application' cert visible to codesign." >&2
    echo "  Verify with: security find-identity -v -p codesigning" >&2
    exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "[release] ERROR: xcodegen not installed. brew install xcodegen" >&2
    exit 1
fi

# --- Unlock CI keychain -------------------------------------------------------
# Local keychain policy on this Mac requires an unlocked dedicated keychain
# for code signing — login keychain falls back to user-interaction prompts
# that can't show in non-interactive shells. See header comment.
CI_KEYCHAIN="${CI_KEYCHAIN:-$HOME/Library/Keychains/ci-signing.keychain-db}"
if [ -f "$CI_KEYCHAIN" ]; then
    if [ -z "${CI_KEYCHAIN_PASSWORD:-}" ]; then
        echo "[release] ERROR: $(basename "$CI_KEYCHAIN") found but CI_KEYCHAIN_PASSWORD env var not set." >&2
        echo "  Add to ~/.zshrc:  export CI_KEYCHAIN_PASSWORD='your-password'" >&2
        exit 1
    fi
    echo "[release] unlocking $(basename "$CI_KEYCHAIN")..."
    security unlock-keychain -p "$CI_KEYCHAIN_PASSWORD" "$CI_KEYCHAIN"
    # Ensure ci-signing is first in the user search list so codesign finds the
    # CI-keychain version of the Developer ID identity (login keychain has
    # restrictive ACLs from Xcode-driven cert creation).
    security list-keychains -d user -s \
        "$CI_KEYCHAIN" \
        $(security list-keychains -d user | tr -d '"' | grep -v "$(basename "$CI_KEYCHAIN")") \
        >/dev/null
fi

# --- Generate Xcode project ---------------------------------------------------

echo "[release] xcodegen generate..."
xcodegen generate >/dev/null

# --- Build Release ------------------------------------------------------------

BUILD_DIR="${REPO_ROOT}/build/release"
rm -rf "$BUILD_DIR"

echo "[release] xcodebuild Release (this includes the sidecar build + codesigning the runtime)..."
xcodebuild \
    -project ImvaultApp.xcodeproj \
    -scheme ImvaultApp \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    build 2>&1 | grep -E "(error:|warning:|\\*\\* BUILD|Codesign|codesign-runtime|sidecar)" || true

APP_PATH="${BUILD_DIR}/Build/Products/Release/imvault.app"
if [ ! -d "$APP_PATH" ]; then
    echo "[release] ERROR: $APP_PATH not produced by xcodebuild" >&2
    exit 1
fi

# --- Verify the .app signature chain ------------------------------------------

echo "[release] verifying .app signature (deep + strict)..."
codesign --verify --deep --strict --verbose=1 "$APP_PATH" 2>&1 | grep -v "^--" || true

if ! codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    echo "[release] ERROR: .app signature verification failed" >&2
    exit 1
fi

# Confirm hardened runtime + Developer ID on the outer .app.
codesign --display --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|flags" | head -5

# --- Build the DMG ------------------------------------------------------------

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="${REPO_ROOT}/build/imvault-${VERSION}.dmg"
STAGING_DIR="${BUILD_DIR}/dmg-staging"

rm -f "$DMG_PATH"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "[release] hdiutil create $DMG_PATH ..."
hdiutil create \
    -volname "imvault" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -fs APFS \
    "$DMG_PATH" >/dev/null

# --- Sign the DMG -------------------------------------------------------------

echo "[release] signing DMG..."
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"

if [ "$SKIP_NOTARIZE" -eq 1 ]; then
    echo ""
    echo "[release] --skip-notarize set; stopping after sign."
    echo "[release] DMG (signed, NOT notarized): $DMG_PATH"
    exit 0
fi

# --- Notarize -----------------------------------------------------------------

echo "[release] submitting to notarytool (typically 1–5 minutes)..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# --- Staple -------------------------------------------------------------------

echo "[release] stapling..."
xcrun stapler staple "$DMG_PATH"

# --- Final verification -------------------------------------------------------

echo "[release] verifying with Gatekeeper..."
spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH"

echo ""
echo "[release] ✅ DONE"
echo "[release]    DMG: $DMG_PATH"
echo "[release]    Size: $(du -h "$DMG_PATH" | awk '{print $1}')"
echo "[release]    Version: $VERSION"
echo ""
echo "Attach to a GitHub release with:"
echo "  gh release create v$VERSION --repo appdromeda-tech/imvault-mac \\"
echo "    --title \"imvault $VERSION\" --notes \"...\" \\"
echo "    $DMG_PATH"
