#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../build.sh"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/lifec-lockup.XXXXXX")"
trap '/bin/rm -rf -- "$test_root"' EXIT
install_parent="$test_root/install"
mkdir -p "$install_parent"
printf 'keep\n' > "$install_parent/sibling-sentinel"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_missing() { [ ! -e "$1" ] || fail "expected missing: $1"; }
assert_present() { [ -e "$1" ] || fail "expected present: $1"; }

stage_dir="$(mktemp -d "$install_parent/.LifeClock-install.XXXXXX")"
mkdir "$stage_dir/LifeClock.app"
printf 'partial\n' > "$stage_dir/LifeClock.app/partial"
remove_staging_directory "$stage_dir" "$install_parent"
assert_missing "$stage_dir"
assert_present "$install_parent/sibling-sentinel"

stage_dir="$(mktemp -d "$install_parent/.LifeClock-install.XXXXXX")"
run_dir="$test_root/run"
mkdir "$run_dir"
set +e
(
    stage_dir="$stage_dir"
    install_parent="$install_parent"
    run_dir="$run_dir"
    previous_app="$run_dir/previous.app"
    installed_app="$install_parent/LifeClock.app"
    widget_suffix="Contents/PlugIns/LifeClockWidget.appex"
    replacing=false
    installed_new=false
    finished=false
    trap cleanup EXIT
    exit 37
) >"$test_root/pre-replacement.log" 2>&1
status=$?
set -e
[ "$status" -eq 37 ] || fail "cleanup changed original exit status to $status"
assert_missing "$stage_dir"
assert_present "$install_parent/sibling-sentinel"

stage_dir="$(mktemp -d "$install_parent/.LifeClock-install.XXXXXX")"
moved_stage="$test_root/moved-stage"
mv "$stage_dir" "$moved_stage"
remove_staging_directory "$stage_dir" "$install_parent"
assert_present "$moved_stage"
/bin/rm -rf -- "$moved_stage"

stage_dir="$(mktemp -d "$install_parent/.LifeClock-install.XXXXXX")"
rmdir "$stage_dir"
remove_staging_directory "$stage_dir" "$install_parent"
assert_missing "$stage_dir"

assert_rejected() {
    if remove_staging_directory "$1" "$install_parent" >"$test_root/reject.log" 2>&1; then
        fail "unsafe staging target was accepted: $1"
    fi
}

assert_rejected ""
assert_rejected "/"
assert_rejected "$install_parent"
assert_rejected "$test_root/unrelated"
mkdir "$test_root/unrelated"
assert_rejected "$test_root/unrelated"
mkdir "$test_root/escape"
ln -s "$test_root/escape" "$install_parent/.LifeClock-install-link"
assert_rejected "$install_parent/.LifeClock-install-link"
assert_present "$test_root/escape"
assert_present "$install_parent/sibling-sentinel"

bad_output="$test_root/cleanup-failure.log"
set +e
(
    stage_dir="$install_parent"
    install_parent="$install_parent"
    run_dir="$run_dir"
    previous_app="$run_dir/previous.app"
    installed_app="$install_parent/LifeClock.app"
    widget_suffix="Contents/PlugIns/LifeClockWidget.appex"
    replacing=false
    installed_new=false
    finished=false
    trap cleanup EXIT
    exit 23
) >"$bad_output" 2>&1
status=$?
set -e
[ "$status" -eq 23 ] || fail "unsafe cleanup changed original exit status to $status"
rg -q "Refusing unsafe staging directory" "$bad_output" || fail "cleanup failure was not surfaced"
assert_present "$install_parent/sibling-sentinel"

printf 'Build cleanup harness passed.\n'
