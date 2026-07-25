#!/usr/bin/env bash
# Fetch the V1 iOS prebuilt tarballs into vendor/hermes-ios/.
# Idempotent: skips files that are already present.
#
# Run from anywhere; resolves paths relative to its own location.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
VENDOR_DIR="$REPO_ROOT/vendor/hermes-ios"

VERSION="250829098.0.13"
BASE_URL="https://repo1.maven.org/maven2/com/facebook/hermes/hermes-ios/$VERSION"

mkdir -p "$VENDOR_DIR"
cd "$VENDOR_DIR"

# fetch <local-name> <classifier>
fetch() {
    local local_name="$1"
    local classifier="$2"
    local url="$BASE_URL/hermes-ios-$VERSION-$classifier.tar.gz"
    if [ -f "$local_name" ]; then
        echo "  skipped (already vendored): $local_name"
    else
        echo "  fetching: $local_name"
        curl -fLo "$local_name" "$url"
    fi
}

fetch "hermes-ios-$VERSION-debug.tar.gz"   "hermes-ios-debug"
fetch "hermes-ios-$VERSION-release.tar.gz" "hermes-ios-release"

echo
echo "Done. Tarballs in $VENDOR_DIR/"
ls -la "$VENDOR_DIR"
