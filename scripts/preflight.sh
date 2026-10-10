#!/bin/sh
# Release checklist for dist/SmartWork.app. Run before every notarization submit; exits non-zero on any failure.
set -eu
cd "$(dirname "$0")/.."
A=dist/SmartWork.app
fail() { echo "PREFLIGHT FAIL: $1" >&2; exit 1; }

swift test >/dev/null 2>&1 || fail "unit tests"
plutil -lint "$A/Contents/Info.plist" "$A/Contents/Library/LaunchDaemons/"*.plist >/dev/null || fail "plist lint"
codesign --verify --deep --strict "$A" 2>/dev/null || fail "codesign verify"
for f in SmartWork smart-work smart-work-helper; do
  B="$A/Contents/MacOS/$f"
  I=$(codesign -dvv "$B" 2>&1)
  echo "$I" | grep -q 'Authority=Developer ID Application' || fail "$f not signed with Developer ID"
  echo "$I" | grep -q 'flags=0x10000(runtime)' || fail "$f missing hardened runtime"
  echo "$I" | grep -q '^Timestamp=' || fail "$f missing secure timestamp"
  codesign -d --entitlements - "$B" 2>&1 | grep -q get-task-allow && fail "$f has get-task-allow"
  lipo -archs "$B" | grep -q arm64 || fail "$f lacks arm64"
done
[ -x "$A/Contents/MacOS/smart-work-helper" ] || fail "helper missing"
[ "$(codesign -dv "$A" 2>&1 | sed -n 's/^TeamIdentifier=//p')" = "$(codesign -dv "$A/Contents/MacOS/smart-work-helper" 2>&1 | sed -n 's/^TeamIdentifier=//p')" ] || fail "app/helper Team ID differ (XPC check would reject the app)"
echo "preflight ok"
