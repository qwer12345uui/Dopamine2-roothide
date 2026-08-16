#!/usr/bin/env bash
# Validate the packaged app and retain a small regression guard for iOS 15.0
# arm64e watchdog/spinlock safety changes.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <path-to-tipa-or-ipa>" >&2
    exit 64
fi

artifact="$1"
if [[ ! -f "$artifact" ]]; then
    echo "artifact does not exist: $artifact" >&2
    exit 66
fi

case "$artifact" in
    *.tipa|*.ipa) ;;
    *)
        echo "expected a .tipa or .ipa artifact, received: $artifact" >&2
        exit 65
        ;;
esac

# A .tipa is a zip-compatible iOS app archive. Verify central-directory and
# payload integrity before extracting the metadata needed for further checks.
unzip -tq "$artifact" >/dev/null
app_info_path="$(unzip -Z1 "$artifact" | grep -E '^Payload/[^/]+\.app/Info\.plist$' | head -n 1 || true)"
app_binary_path="$(unzip -Z1 "$artifact" | grep -E '^Payload/[^/]+\.app/[^/]+$' | grep -vE '/(Info\.plist|_CodeSignature/|embedded\.mobileprovision)' | head -n 1 || true)"

if [[ -z "$app_info_path" || -z "$app_binary_path" ]]; then
    echo "archive does not contain a complete Payload/*.app bundle" >&2
    exit 1
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
unzip -qq "$artifact" -d "$temp_dir"

info_path="$temp_dir/$app_info_path"

plist_value() {
    local key="$1"
    local plist_path="$2"

    if command -v plutil >/dev/null 2>&1; then
        plutil -lint "$plist_path" >/dev/null
        plutil -extract "$key" raw "$plist_path"
        return
    fi

    python3 - "$key" "$plist_path" <<'PY'
import plistlib
import sys

key, path = sys.argv[1:]
with open(path, "rb") as file:
    plist = plistlib.load(file)
value = plist.get(key)
if not isinstance(value, str) or not value:
    raise SystemExit(1)
print(value)
PY
}

bundle_id="$(plist_value CFBundleIdentifier "$info_path")"
short_version="$(plist_value CFBundleShortVersionString "$info_path")"

if [[ -z "$bundle_id" || -z "$short_version" ]]; then
    echo "app metadata is incomplete" >&2
    exit 1
fi

# Ensure the in-tree protections being packaged have not regressed. These
# checks are source-level by design: they catch accidental removal before a
# hardware regression test can be performed on an iOS 15 arm64e device.
grep -Fq 'Failed to create watchdog safe-mode marker' BaseBin/launchdhook/src/jbserver/jbdomain_watchdog.c
grep -Fq 'skip injection for iOS 15 app prewarm' BaseBin/launchdhook/src/roothider.m
grep -Fq 'IOSurface image unavailable; skip iosConnect refresh' BaseBin/launchdhook/src/roothider.m
grep -Fq '"/usr/libexec/installd"' BaseBin/systemhook/src/common.c
grep -Fq '"/usr/libexec/appstored"' BaseBin/systemhook/src/common.c
grep -Fq 'shouldAutoUICacheAfterDatabaseRebuild' BaseBin/roothidehooks/lsd.x
grep -Fq '.enable_auto_uicache_ios15' BaseBin/roothidehooks/lsd.x
grep -Fq 'static dispatch_once_t autoUICacheOnce' BaseBin/roothidehooks/lsd.x
grep -Fq 'NSDataWritingAtomic' Application/Dopamine/Jailbreak/DOEnvironmentManager.m
grep -Fq 'maxBootLogoDimension = 2048.0' Application/Dopamine/UI/Settings/DOSettingsController.m
grep -Fq 'memchr(inputStruct' BaseBin/watchdoghook/src/main.m

printf 'validated artifact=%s bundle_id=%s version=%s\n' "$artifact" "$bundle_id" "$short_version"
