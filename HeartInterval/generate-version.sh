#!/bin/sh
# Generates BuildVersion.xcconfig from the nearest git tag.
# Run before archiving or let the Xcode build phase handle it.
set +e
cd "$(dirname "$0")"
TAG=$(git describe --tags --abbrev=0 2>/dev/null)
# Extract version numbers, then trim to at most 3 parts (X.Y.Z) — App Store requirement
FULL_VER=$(echo "$TAG" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*' | head -1)
VERSION=$(echo "$FULL_VER" | cut -d. -f1-3)
[ -z "$VERSION" ] && VERSION="1.0.0"
BUILD=$(git rev-list --count HEAD 2>/dev/null)
[ -z "$BUILD" ] && BUILD="1"
echo "// Auto-generated from git tag: $TAG" > BuildVersion.xcconfig
echo "MARKETING_VERSION = $VERSION" >> BuildVersion.xcconfig
echo "CURRENT_PROJECT_VERSION = $BUILD" >> BuildVersion.xcconfig
echo "BeatZone version: $VERSION ($BUILD) from tag: $TAG"
