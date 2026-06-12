#!/bin/sh
# Generates BuildVersion.xcconfig from the nearest git tag.
# Run before archiving or let the Xcode build phase handle it.
set +e
cd "$(dirname "$0")"
TAG=$(git describe --tags --abbrev=0 2>/dev/null)
VERSION=$(echo "$TAG" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*' | head -1)
[ -z "$VERSION" ] && VERSION="1.0.0"
BUILD=$(git rev-list --count HEAD 2>/dev/null)
[ -z "$BUILD" ] && BUILD="1"
echo "// Auto-generated from git tag: $TAG" > BuildVersion.xcconfig
echo "MARKETING_VERSION = $VERSION" >> BuildVersion.xcconfig
echo "CURRENT_PROJECT_VERSION = $BUILD" >> BuildVersion.xcconfig
echo "BeatZone version: $VERSION ($BUILD) from tag: $TAG"
