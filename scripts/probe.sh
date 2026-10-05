#!/usr/bin/env bash
# macOS grants Bluetooth only to app bundles, so the probe runs as a tiny .app launched via `open`.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
package="$root/ScaleKit"

swift build --package-path "$package" --product scale-probe >/dev/null

app="$package/.build/ScaleProbe.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$package/Sources/scale-probe/Info.plist" "$app/Contents/Info.plist"
cp "$(swift build --package-path "$package" --show-bin-path)/scale-probe" "$app/Contents/MacOS/scale-probe"
codesign --force --sign - "$app" >/dev/null 2>&1

log="$package/.build/probe.log"
: > "$log"
tail -f "$log" &
tail_pid=$!
trap 'kill $tail_pid 2>/dev/null' EXIT

open -W -n --stdout "$log" --stderr "$log" "$app" --args --captures "$root/captures" "$@"
sleep 0.5
