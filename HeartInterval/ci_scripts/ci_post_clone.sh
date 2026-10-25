#!/bin/sh
# Xcode Cloud: generate BuildVersion.xcconfig (gitignored) before the build reads it.
set -e
"$(dirname "$0")/../generate-version.sh"
