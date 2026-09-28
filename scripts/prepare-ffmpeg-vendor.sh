#!/usr/bin/env bash
# Prepares Vendor/FFmpeg layout for NATIVE_FFMPEG builds.
# Does NOT download binaries automatically (license / size). Place XCFrameworks yourself.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/FFmpeg"
mkdir -p "$DEST"
echo "Expected XCFrameworks in $DEST:"
for name in libavformat libavcodec libavutil libswresample libswscale; do
  echo "  - $name.xcframework"
done
echo ""
echo "Then set SWIFT_ACTIVE_COMPILATION_CONDITIONS=NATIVE_FFMPEG on the PlexiOS target."
echo "See docs/ffmpeg-integration.md"
ls -la "$DEST" || true
