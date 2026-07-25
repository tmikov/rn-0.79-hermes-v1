#!/usr/bin/env bash
# Apply the RN 0.86 Hermes V1 patch set.
#
# Idempotent via a marker file: re-running on an already-patched tree
# is a no-op. To force re-application (e.g., after a `npm install` that
# rewrote node_modules), delete the marker:
#     rm sample86/node_modules/react-native/.hermes-v1-patches-applied
# Or just blow away node_modules and reinstall.
#
# Run from anywhere; resolves paths relative to its own location.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PATCHDIR="$REPO_ROOT/patches"
RN_DIR="$REPO_ROOT/sample86/node_modules/react-native"
MARKER="$RN_DIR/.hermes-v1-patches-applied"

if [ ! -d "$RN_DIR" ]; then
    echo "error: $RN_DIR does not exist." >&2
    echo "       Run 'cd sample86 && npm install' first." >&2
    exit 1
fi

if [ -f "$MARKER" ]; then
    echo "Patches already applied (marker: $MARKER)."
    echo "  $(cat "$MARKER")"
    echo "Delete the marker to force re-application."
    exit 0
fi

# apply_patch <patch-filename> <apply-dir>
apply_patch() {
    local patch_file="$PATCHDIR/$1"
    local apply_dir="$2"
    if [ ! -f "$patch_file" ]; then
        echo "error: missing patch file: $patch_file" >&2
        return 1
    fi
    ( cd "$apply_dir" && patch -p1 --silent <"$patch_file" )
    echo "  applied: $1"
}

echo "RN-side patches (under $RN_DIR):"
apply_patch 01-hermes-v1-bump.patch "$RN_DIR"

# Record success
{
    echo "Applied $(date -u '+%Y-%m-%dT%H:%M:%SZ') by scripts/apply-patches.sh"
    for p in 01-hermes-v1-bump; do
        if command -v shasum >/dev/null 2>&1; then
            echo "  $p.patch  sha256=$(shasum -a 256 "$PATCHDIR/$p.patch" | cut -d' ' -f1)"
        fi
    done
} > "$MARKER"

echo
echo "Done. Patch 01-hermes-v1-bump.patch in place. Marker: $MARKER"
