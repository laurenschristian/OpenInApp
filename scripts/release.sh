#!/bin/bash
set -e

# OpenIn Release Script
# Usage: ./scripts/release.sh 1.5.0

VERSION="$1"
if [ -z "$VERSION" ]; then
    echo "Usage: ./scripts/release.sh <version>"
    echo "Example: ./scripts/release.sh 1.5.0"
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$PROJECT_DIR/release"
SPARKLE_SIGN="/tmp/sparkle-extract/bin/sign_update"

echo "==> Building OpenIn v$VERSION..."

# Update version in pbxproj
sed -i '' "s/MARKETING_VERSION = [0-9]*\.[0-9]*\.[0-9]*/MARKETING_VERSION = $VERSION/g" "$PROJECT_DIR/OpenIn.xcodeproj/project.pbxproj"

# Update version in About tab
find "$PROJECT_DIR/OpenIn/Sources" -name "*.swift" -exec sed -i '' "s/v[0-9]*\.[0-9]*\.[0-9]*\"/v$VERSION\"/g" {} +

# Build Release
cd "$PROJECT_DIR"
xcodebuild -project OpenIn.xcodeproj -scheme OpenIn -configuration Release \
    CODE_SIGN_IDENTITY="Apple Development: lg@mail12.me (ZRP7TYYLP8)" \
    CODE_SIGN_STYLE=Manual build 2>&1 | tail -3

BUILD_APP="$HOME/Library/Developer/Xcode/DerivedData/OpenIn-fxycohgyqzmibsgfmyjexqnzusch/Build/Products/Release/OpenIn.app"

if [ ! -d "$BUILD_APP" ]; then
    echo "ERROR: Build failed - app not found"
    exit 1
fi

echo "==> Creating release assets..."
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR/dmg_contents"

cp -R "$BUILD_APP" "$RELEASE_DIR/dmg_contents/"
ln -s /Applications "$RELEASE_DIR/dmg_contents/Applications"

# Create DMG
hdiutil create -volname "OpenIn" \
    -srcfolder "$RELEASE_DIR/dmg_contents" \
    -ov -format UDZO \
    "$RELEASE_DIR/OpenIn-v$VERSION.dmg" 2>&1 | tail -1

# Create ZIP (for Sparkle)
cd "$RELEASE_DIR/dmg_contents"
zip -qr "$RELEASE_DIR/OpenIn-v$VERSION.zip" OpenIn.app
cd "$PROJECT_DIR"

rm -rf "$RELEASE_DIR/dmg_contents"

echo "==> Signing update for Sparkle..."
if [ -x "$SPARKLE_SIGN" ]; then
    SIGNATURE=$("$SPARKLE_SIGN" "$RELEASE_DIR/OpenIn-v$VERSION.zip" 2>&1 | grep "sparkle:edSignature" || true)
    if [ -n "$SIGNATURE" ]; then
        echo "Sparkle signature: $SIGNATURE"
    else
        # Try alternate output format
        SIGNATURE=$("$SPARKLE_SIGN" "$RELEASE_DIR/OpenIn-v$VERSION.zip" 2>&1)
        echo "Sparkle signature output: $SIGNATURE"
    fi
else
    echo "WARNING: Sparkle sign_update not found at $SPARKLE_SIGN"
    echo "Run: gh release download 2.9.0 -R sparkle-project/Sparkle to get it"
fi

ZIP_SIZE=$(stat -f%z "$RELEASE_DIR/OpenIn-v$VERSION.zip")

echo "==> Updating appcast.xml..."
cat > "$PROJECT_DIR/appcast.xml" << APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>OpenIn Updates</title>
        <link>https://github.com/laurenschristian/OpenInApp</link>
        <description>OpenIn update feed</description>
        <language>en</language>
        <item>
            <title>v$VERSION</title>
            <pubDate>$(date -R)</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url="https://github.com/laurenschristian/OpenInApp/releases/download/v$VERSION/OpenIn-v$VERSION.zip"
                       type="application/octet-stream"
                       length="$ZIP_SIZE"
                       $SIGNATURE />
        </item>
    </channel>
</rss>
APPCAST

echo "==> Installing to /Applications..."
killall OpenIn 2>/dev/null || true
rm -rf /Applications/OpenIn.app
cp -R "$BUILD_APP" /Applications/OpenIn.app
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R /Applications/OpenIn.app

echo "==> Committing..."
cd "$PROJECT_DIR"
git add -A
git commit -m "v$VERSION release"
git push

echo "==> Creating GitHub release..."
git tag -a "v$VERSION" -m "v$VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" \
    "release/OpenIn-v$VERSION.dmg" \
    "release/OpenIn-v$VERSION.zip" \
    --title "OpenIn v$VERSION" \
    --generate-notes

# Update homebrew tap
BREW_TAP="$HOME/Documents/GitHub/Personal/homebrew-tap"
if [ -d "$BREW_TAP" ]; then
    SHA=$(shasum -a 256 "$RELEASE_DIR/OpenIn-v$VERSION.dmg" | awk '{print $1}')
    sed -i '' "s/version \".*\"/version \"$VERSION\"/" "$BREW_TAP/Casks/openin.rb"
    sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" "$BREW_TAP/Casks/openin.rb"
    cd "$BREW_TAP"
    git add -A && git commit -m "Update OpenIn to v$VERSION" && git push
    cd "$PROJECT_DIR"
    echo "==> Homebrew tap updated"
fi

echo "==> Launching..."
open /Applications/OpenIn.app

echo ""
echo "==> OpenIn v$VERSION released!"
ls -lh "$RELEASE_DIR/"
