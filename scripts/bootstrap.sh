#!/bin/bash
set -e

# Downloads Sparkle framework if not present
# Run this before building: ./scripts/bootstrap.sh

SPARKLE_VERSION="2.9.0"
FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)/OpenIn/Resources/Sparkle.framework"

if [ -d "$FRAMEWORK_DIR" ]; then
    echo "Sparkle.framework already exists, skipping download"
    exit 0
fi

echo "Downloading Sparkle $SPARKLE_VERSION..."
TMPDIR=$(mktemp -d)
cd "$TMPDIR"

gh release download "$SPARKLE_VERSION" -R sparkle-project/Sparkle -p "Sparkle-${SPARKLE_VERSION}.tar.xz"
xz -d "Sparkle-${SPARKLE_VERSION}.tar.xz"
mkdir extract && tar xf "Sparkle-${SPARKLE_VERSION}.tar" -C extract

cp -R extract/Sparkle.framework "$FRAMEWORK_DIR"
rm -rf "$TMPDIR"

echo "Sparkle.framework installed at $FRAMEWORK_DIR"
