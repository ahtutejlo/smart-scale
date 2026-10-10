#!/usr/bin/env bash
# A free Apple ID signs the app for 7 days only, so this reinstalls it on the iPhone before the signature runs out.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

root="$(cd "$(dirname "$0")/.." && pwd)"
config="$root/Config/Local.xcconfig"
[[ -f "$config" ]] || { echo "Copy Config/Local.xcconfig.example to Config/Local.xcconfig and fill it in" >&2; exit 1; }
setting() { awk -F ' *= *' -v key="$1" '$1 == key { print $2; exit }' "$config" "$root/Config/App.xcconfig"; }
device="$(setting IPHONE_UDID)"
bundle_id="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
team_id="$(setting DEVELOPMENT_TEAM)"
derived="$root/.build/DerivedData"
app="$derived/Build/Products/Debug-iphoneos/SmartScale.app"
state="$root/.build/iphone-refresh"
local_profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
refresh_below_hours=72
warn_below_hours=36

force=0
[[ "${1:-}" == "--force" ]] && force=1
mkdir -p "$state"

log() { echo "$(date '+%F %T') $*"; }
when() { date -r "$1" '+%-d.%m %H:%M'; }
hours_until() { echo $(( ($1 - $(date +%s)) / 3600 )); }
notify() { osascript -e "display notification \"$1\" with title \"Ваги\"" >/dev/null 2>&1 || true; }
warn() { if (( force || left < warn_below_hours )); then notify "$1"; fi; }

installed_profile_expiry() {
  xcrun devicectl device profile list --device "$device" --timeout 30 --quiet --json-output - 2>/dev/null |
    python3 -c '
import json, sys
from datetime import datetime
team, bundle = sys.argv[1:]
profiles = json.load(sys.stdin)["result"]["provisioningProfiles"]
print(max((int(datetime.fromisoformat(p["expirationDate"].replace("Z", "+00:00")).timestamp())
           for p in profiles if p["teamIdentifier"] == team and p["name"].endswith(": " + bundle)), default=0))
' "$team_id" "$bundle_id" 2>/dev/null
}

built_profile_expiry() {
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' \
    "$(security cms -D -i "$app/embedded.mobileprovision" | plutil -extract ExpirationDate raw -o - -)" +%s
}

expires="$(cat "$state/expires" 2>/dev/null || echo 0)"
left="$(hours_until "$expires")"
if (( force || left < refresh_below_hours )); then
  if fresh="$(installed_profile_expiry)"; then
    expires="$fresh"
    echo "$expires" > "$state/expires"
    left="$(hours_until "$expires")"
  else
    log "iPhone not reachable, ${left} h left"
    warn "iPhone недоступний, а Ваги перестануть відкриватися через ${left} год. Підключіть iPhone до тієї ж Wi‑Fi, що й Mac."
    exit "$force"
  fi
fi
if (( !force && left >= refresh_below_hours )); then
  log "${left} h left, nothing to do"
  exit 0
fi

fail() {
  mv "$state"/*.mobileprovision "$local_profiles/" 2>/dev/null || true
  log "FAILED: $1"
  warn "Не вдалося перевстановити Ваги: $1"
  exit 1
}

log "${left} h left, reinstalling"
build_log="$state/build.log"
cd "$root"
xcodegen generate --use-cache >"$build_log" 2>&1 || fail "xcodegen не спрацював"
for profile in "$local_profiles"/*.mobileprovision; do
  if security cms -D -i "$profile" 2>/dev/null | grep -q "<string>$team_id.$bundle_id</string>"; then
    mv "$profile" "$state/"
  fi
done
if ! xcodebuild -project SmartScale.xcodeproj -scheme SmartScale -configuration Debug \
  -destination generic/platform=iOS -derivedDataPath "$derived" -allowProvisioningUpdates build >>"$build_log" 2>&1; then
  reason="$(grep -m1 -o 'error: .*' "$build_log" | sed -e 's/^error: //' -e 's/ (in target.*//')" || true
  fail "${reason:-збірка не вдалася}"
fi
rm -f "$state"/*.mobileprovision

new_expires="$(built_profile_expiry)" || fail "у збірці немає дозволу"
(( new_expires > expires )) || fail "Apple не видав новий дозвіл, старий діє до $(when "$expires")"
xcrun devicectl device install app --device "$device" "$app" >>"$build_log" 2>&1 || fail "iPhone не прийняв застосунок"
echo "$new_expires" > "$state/expires"
log "reinstalled, valid until $(when "$new_expires")"
notify "Ваги перевстановлено. Працюватимуть до $(when "$new_expires")."
