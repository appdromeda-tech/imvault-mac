#!/usr/bin/env bash
#
# Recursively codesign every Mach-O file in a directory tree using the given
# Developer ID identity + hardened runtime. This is what makes the bundled
# Python sidecar acceptable to Apple's notary service — every .dylib, .so,
# and executable inside python-runtime/ needs its own Developer ID signature.
# Without this, `notarytool submit` rejects the .app with "code is not
# signed at all" for the first unsigned binary it sees.
#
# Usage:
#   scripts/codesign-runtime.sh \
#       --identity "Developer ID Application: Foo (TEAM)" \
#       --runtime-dir <path>
#
# Called from project.yml's Run Script for Release builds (so Xcode's outer
# .app sign covers a fully signed tree) and indirectly by scripts/release.sh.

set -euo pipefail

IDENTITY=""
RUNTIME_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --identity) IDENTITY="$2"; shift 2 ;;
        --runtime-dir) RUNTIME_DIR="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^$/{ /^# /s/^# \{0,1\}//p; }' "$0"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$IDENTITY" ] || [ -z "$RUNTIME_DIR" ]; then
    echo "Usage: $0 --identity IDENT --runtime-dir DIR" >&2
    exit 2
fi

if [ ! -d "$RUNTIME_DIR" ]; then
    echo "[codesign-runtime] runtime dir does not exist: $RUNTIME_DIR" >&2
    exit 1
fi

echo "[codesign-runtime] scanning $RUNTIME_DIR"

# Find every regular file (skip symlinks — bin/ has python3 -> python3.12,
# pip -> pip3.12, etc. — codesign would error on those), and keep only the
# ones whose Mach-O magic the `file` command recognizes.
mach_o=()
while IFS= read -r f; do
    if [ -L "$f" ]; then continue; fi
    if file -h -- "$f" 2>/dev/null | grep -qi "Mach-O"; then
        mach_o+=("$f")
    fi
done < <(find "$RUNTIME_DIR" -type f)

echo "[codesign-runtime] signing ${#mach_o[@]} Mach-O files with hardened runtime + --timestamp"

# --force overwrites any existing signature (pip-built wheels often ship
# with ad-hoc signatures from the wheel build host).
# --options runtime enables hardened runtime per binary.
# --timestamp embeds a secure timestamp (required by notarization).
for f in "${mach_o[@]}"; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$f"
done

echo "[codesign-runtime] done."
