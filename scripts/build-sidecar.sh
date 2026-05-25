#!/usr/bin/env bash
#
# Build the Python sidecar bundled into the .app.
#
# Output: build/python-runtime/   relocatable Python + imvault CLI
#
# Idempotent: if build/python-runtime/.sidecar-manifest matches the
# desired (PBS, imvault) versions, this script exits immediately.
# Pass --force to rebuild unconditionally.
#
# Run manually before opening Xcode, or let Xcode's Run Script phase
# invoke it as part of the normal build.

set -euo pipefail

# --- Configuration -----------------------------------------------------------

PBS_RELEASE="20260510"
PYTHON_VERSION="3.12.13"
PYTHON_ARCH="aarch64-apple-darwin"
IMVAULT_VERSION="0.3.0"

ASSET="cpython-${PYTHON_VERSION}+${PBS_RELEASE}-${PYTHON_ARCH}-install_only.tar.gz"
ASSET_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE}/${ASSET}"

# --- Paths -------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
CACHE_DIR="${BUILD_DIR}/cache"
RUNTIME_DIR="${BUILD_DIR}/python-runtime"
MANIFEST="${RUNTIME_DIR}/.sidecar-manifest"

# Expected manifest content. If this matches the existing manifest, skip.
MANIFEST_CONTENT="pbs=${PBS_RELEASE} python=${PYTHON_VERSION} arch=${PYTHON_ARCH} imvault=${IMVAULT_VERSION}"

# --- Args --------------------------------------------------------------------

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        -h|--help)
            sed -n '2,/^$/{ /^# /s/^# \{0,1\}//p; }' "$0"
            exit 0
            ;;
        *) echo "Unknown arg: $arg" >&2; exit 2 ;;
    esac
done

# --- Short-circuit if already built ------------------------------------------

if [ "$FORCE" -eq 0 ] && [ -f "$MANIFEST" ] && [ "$(cat "$MANIFEST")" = "$MANIFEST_CONTENT" ]; then
    echo "[sidecar] up-to-date (${MANIFEST_CONTENT}); skipping."
    exit 0
fi

echo "[sidecar] building: ${MANIFEST_CONTENT}"

# --- Download python-build-standalone ----------------------------------------

mkdir -p "$CACHE_DIR"
TARBALL="${CACHE_DIR}/${ASSET}"

if [ ! -f "$TARBALL" ]; then
    echo "[sidecar] downloading ${ASSET_URL}"
    curl -fsSL --retry 3 -o "${TARBALL}.tmp" "$ASSET_URL"
    mv "${TARBALL}.tmp" "$TARBALL"
fi

# --- Extract into a clean runtime dir ----------------------------------------

echo "[sidecar] extracting to ${RUNTIME_DIR}"
rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"
# The tarball's top-level dir is `python/`; --strip-components 1 flattens it.
tar -xzf "$TARBALL" -C "$RUNTIME_DIR" --strip-components 1

PYTHON="${RUNTIME_DIR}/bin/python3"
if [ ! -x "$PYTHON" ]; then
    echo "[sidecar] ERROR: ${PYTHON} not found after extract" >&2
    exit 1
fi

# --- Install imvault into the runtime ----------------------------------------

echo "[sidecar] installing imvault==${IMVAULT_VERSION}"
"$PYTHON" -m pip install --upgrade --no-warn-script-location pip >/dev/null
# imvault is not on PyPI; install from the git tag.
"$PYTHON" -m pip install --no-warn-script-location \
    "imvault @ git+https://github.com/reznto/imvault.git@v${IMVAULT_VERSION}"

IMVAULT_BIN="${RUNTIME_DIR}/bin/imvault"
if [ ! -x "$IMVAULT_BIN" ]; then
    echo "[sidecar] ERROR: ${IMVAULT_BIN} not found after pip install" >&2
    exit 1
fi

# --- Replace entry-point shebang with a relocatable wrapper ------------------
# pip bakes the build-time absolute path into the shebang (e.g.
# "#!/tmp/.../build/python-runtime/bin/python3"). That path exists during the
# build but is brittle: even when it's still on disk, Foundation's Process
# refuses to launch a script whose interpreter lives outside the .app bundle
# when the .app is launched via LaunchServices. Replace with a bash wrapper
# that resolves python3 relative to its own location.
cat > "$IMVAULT_BIN" <<'WRAPPER'
#!/bin/bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${HERE}/python3" -m imvault.cli "$@"
WRAPPER
chmod +x "$IMVAULT_BIN"

# --- Smoke test --------------------------------------------------------------

INSTALLED_VERSION="$("$IMVAULT_BIN" --version 2>&1 | awk '{print $NF}')"
if [ "$INSTALLED_VERSION" != "$IMVAULT_VERSION" ]; then
    echo "[sidecar] ERROR: installed imvault reports '${INSTALLED_VERSION}', expected '${IMVAULT_VERSION}'" >&2
    exit 1
fi

# --- Write manifest ----------------------------------------------------------

echo "$MANIFEST_CONTENT" > "$MANIFEST"
echo "[sidecar] done: ${MANIFEST_CONTENT}"
