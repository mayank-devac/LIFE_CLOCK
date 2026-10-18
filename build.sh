#!/bin/bash
# One local workflow: verify, build, install, register the widget, then launch.
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$project_dir/.build"
derived_data="$build_dir/DerivedData"
run_dir="$build_dir/logs/$(date +%Y%m%d-%H%M%S)-$$"
install_parent="${LIFECLOCK_INSTALL_DIR:-/Applications}"
installed_app="$install_parent/LifeClock.app"
built_app="$derived_data/Build/Products/Debug/LifeClock.app"
widget_suffix="Contents/PlugIns/LifeClockWidget.appex"
previous_app="$run_dir/previous.app"
backup_zip="$run_dir/LifeClock-before-install.zip"
stage_dir=""
replacing=false
installed_new=false
finished=false

mkdir -p "$run_dir"

cleanup() {
    result=$?
    if [ "$replacing" = true ] && [ "$finished" = false ]; then
        printf 'Installation failed; restoring the previous app.\n' >&2
        if [ -d "$previous_app" ]; then
            if [ -d "$installed_app" ]; then
                mv "$installed_app" "$run_dir/failed-install.app" || true
            fi
            mv "$previous_app" "$installed_app" || true
            /usr/bin/pluginkit -a "$installed_app/$widget_suffix" || true
        elif [ "$installed_new" = true ] && [ -d "$installed_app" ]; then
            mv "$installed_app" "$run_dir/failed-install.app" || true
        fi
    fi
    if [ "$result" -ne 0 ]; then
        printf 'Stopped. Logs and any backup: %s\n' "$run_dir" >&2
    fi
}
trap cleanup EXIT

run_xcode() {
    phase="$1"
    shift
    printf '%s…\n' "$phase"
    if ! /usr/bin/xcodebuild -project "$project_dir/LifeClock.xcodeproj" \
        -scheme LifeClock -configuration Debug -destination 'platform=macOS' \
        -derivedDataPath "$derived_data" "$@" > "$run_dir/$phase.log" 2>&1; then
        tail -n 60 "$run_dir/$phase.log" >&2
        return 1
    fi
}

printf 'Checking Xcode and install target…\n'
/usr/bin/xcode-select -p > "$run_dir/xcode-path.txt"
if [ ! -d "$install_parent" ] || [ ! -w "$install_parent" ]; then
    printf 'Cannot write to %s. Run with the required permission, or set LIFECLOCK_INSTALL_DIR="$HOME/Applications" after creating that folder.\n' "$install_parent" >&2
    exit 1
fi
if [ -e "$installed_app" ]; then
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Contents/Info.plist")
    if [ "$identifier" != 'com.mayank.LifeClock' ]; then
        printf 'Refusing to replace an app with a different bundle identifier: %s\n' "$identifier" >&2
        exit 1
    fi
fi

run_xcode tests -only-testing:LifeClockTests -resultBundlePath "$run_dir/Tests.xcresult" test
# A normal build restores ordinary app signing after Xcode's test instrumentation.
run_xcode build build

printf 'Checking signatures and widget configuration…\n'
/usr/bin/codesign --verify --deep --strict "$built_app"
/usr/bin/codesign -d --entitlements :- "$built_app" > "$run_dir/app-entitlements.plist" 2>/dev/null
/usr/bin/codesign -d --entitlements :- "$built_app/$widget_suffix" > "$run_dir/widget-entitlements.plist" 2>/dev/null
/usr/bin/python3 - "$built_app" "$run_dir" <<'PY'
import json
import plistlib
import sys
from pathlib import Path

app, logs = map(Path, sys.argv[1:])
extension = app / 'Contents/PlugIns/LifeClockWidget.appex'
data = json.loads((extension / 'Contents/Resources/Metadata.appintents/extract.actionsdata').read_bytes())
intent = data['actions']['LifeClockConfiguration']
names = {parameter['name'] for parameter in intent['parameters']}
required = {'birthDay', 'birthMonth', 'birthYear', 'birthTime', 'timeZoneID', 'format'}
if not required.issubset(names):
    raise SystemExit('Widget settings metadata is missing: ' + ', '.join(sorted(required - names)))
for name in ('app', 'widget'):
    entitlements = plistlib.loads((logs / (name + '-entitlements.plist')).read_bytes())
    if entitlements.get('com.apple.security.application-groups'):
        raise SystemExit(name + ' unexpectedly requires an App Group')
print('Birthday, time, timezone and format metadata present; no App Group required.')
PY

printf 'Staging app and backing up the current installation…\n'
stage_dir="$(mktemp -d "$install_parent/.LifeClock-install.XXXXXX")"
/usr/bin/ditto "$built_app" "$stage_dir/LifeClock.app"
/usr/bin/codesign --verify --deep --strict "$stage_dir/LifeClock.app"
if [ -d "$installed_app" ]; then
    /usr/bin/ditto -c -k --keepParent "$installed_app" "$backup_zip"
fi

printf 'Stopping Life Clock before replacement…\n'
if /usr/bin/pgrep -x LifeClock > /dev/null; then
    /usr/bin/pkill -TERM -x LifeClock
    for attempt in 1 2 3 4 5; do
        if ! /usr/bin/pgrep -x LifeClock > /dev/null; then break; fi
        sleep 1
    done
    if /usr/bin/pgrep -x LifeClock > /dev/null; then
        printf 'Life Clock did not quit. Close it and rerun this command.\n' >&2
        exit 1
    fi
fi

replacing=true
if [ -d "$installed_app" ]; then
    mv "$installed_app" "$previous_app"
fi
mv "$stage_dir/LifeClock.app" "$installed_app"
installed_new=true
rmdir "$stage_dir"
/usr/bin/codesign --verify --deep --strict "$installed_app"

printf 'Registering the installed widget and launching Life Clock…\n'
/usr/bin/pluginkit -r "$built_app/$widget_suffix"
/usr/bin/pluginkit -a "$installed_app/$widget_suffix"
/usr/bin/pluginkit -m -A -D -v -i com.mayank.LifeClock.Widget > "$run_dir/widget-registration.txt"
if ! /usr/bin/grep -F "$installed_app/$widget_suffix" "$run_dir/widget-registration.txt" > /dev/null; then
    printf 'The installed widget was not registered.\n' >&2
    exit 1
fi
/usr/bin/open "$installed_app"
finished=true
if [ -d "$previous_app" ]; then
    # The complete backup is already in backup_zip; avoid a second discoverable widget bundle.
    /bin/rm -rf "$previous_app"
fi

printf '\nChecks, tests, build, installation and widget registration passed.\n'
printf 'Installed: %s\nLogs: %s\n' "$installed_app" "$run_dir"
if [ -f "$backup_zip" ]; then printf 'Backup: %s\n' "$backup_zip"; fi
printf '\nOne-time desktop step: right-click desktop → Edit Widgets → Life Clock.\n'
printf 'Then right-click the widget → Edit Widget → enter your birthday.\n'
printf 'If an old widget still says “Open Life Clock”, remove it and add Life Clock again.\n'
printf 'macOS provides no supported CLI to place or configure desktop widgets automatically.\n'
