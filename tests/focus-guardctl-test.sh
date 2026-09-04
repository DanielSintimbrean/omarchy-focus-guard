#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
controller="$repo_dir/system/focus-guardctl"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

export TZ=Europe/Madrid
export FOCUS_GUARD_ROOT=$test_root
export FOCUS_GUARD_SKIP_DNS_RELOAD=1

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

epoch() {
  date -d "$1" +%s
}

run_at() {
  local when=$1
  shift
  FOCUS_GUARD_NOW=$(epoch "$when") "$controller" "$@"
}

assert_contains() {
  local text=$1 expected=$2
  [[ $text == *"$expected"* ]] || fail "expected '$expected' in '$text'"
}

block_file="$test_root/etc/NetworkManager/dnsmasq.d/90-focus-guard.conf"

run_at "2026-09-04 10:00" configure 09:00 17:00 reddit.com youtube.com >/dev/null
[[ -f $block_file ]] || fail "scheduled blocking did not create the DNS rules"
grep -q '^address=/reddit.com/0.0.0.0$' "$block_file" || fail "reddit IPv4 rule is missing"
grep -q '^address=/reddit.com/::$' "$block_file" || fail "reddit IPv6 rule is missing"
grep -q '^address=/googlevideo.com/0.0.0.0$' "$block_file" || fail "YouTube CDN IPv4 rule is missing"
grep -q '^address=/googlevideo.com/::$' "$block_file" || fail "YouTube CDN IPv6 rule is missing"

status=$(run_at "2026-09-04 10:01" status)
assert_contains "$status" '"active":true'
assert_contains "$status" '"mode":"scheduled"'
assert_contains "$status" '"domainCount":8'

status=$(run_at "2026-09-04 10:02" disable)
[[ ! -e $block_file ]] || fail "the challenge override did not remove DNS rules"
assert_contains "$status" '"mode":"override"'
assert_contains "$status" '"overrideUntil":1788764400'

run_at "2026-09-07 09:00" reconcile >/dev/null
[[ -f $block_file ]] || fail "blocking did not resume at the next work period"

run_at "2026-09-04 20:00" enable >/dev/null
status=$(run_at "2026-09-05 12:00" status)
assert_contains "$status" '"active":true'
assert_contains "$status" '"mode":"manual"'
assert_contains "$status" '"manualUntil":1788793200'

run_at "2026-09-07 17:00" reconcile >/dev/null
[[ ! -e $block_file ]] || fail "manual blocking did not end with the next work period"

status=$(run_at "2026-09-08 10:00" recover)
[[ ! -e $block_file ]] || fail "recovery did not remove DNS rules"
assert_contains "$status" '"mode":"recovery"'

status=$(run_at "2026-09-08 10:01" resume)
assert_contains "$status" '"active":true'
assert_contains "$status" '"mode":"scheduled"'

if run_at "2026-09-08 10:02" configure 17:00 09:00 reddit.com >/dev/null 2>&1; then
  fail "an inverted schedule was accepted"
fi

if run_at "2026-09-08 10:02" configure 09:00 17:00 'reddit.com;touch-bad' >/dev/null 2>&1; then
  fail "an unsafe domain was accepted"
fi

if run_at "2026-09-08 10:02" configure 09:00 17:00 >/dev/null 2>&1; then
  fail "an empty blocklist was accepted"
fi

printf 'focus-guardctl tests passed\n'
