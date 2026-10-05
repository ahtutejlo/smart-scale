#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
iconset="$root/App/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$iconset"

rsvg-convert -w 1024 -h 1024 "$root/design/AppIcon.svg" \
  | magick - -background '#3987E5' -alpha remove -alpha off "$iconset/AppIcon.png"
