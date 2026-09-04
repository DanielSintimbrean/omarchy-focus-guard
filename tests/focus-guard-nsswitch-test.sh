#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
controller="$repo_dir/system/focus-guard-nsswitch"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/etc" "$test_root/var/lib/focus-guard"
printf '%s\n' \
  '# Test resolver configuration.' \
  'hosts: mymachines mdns_minimal [NOTFOUND=return] resolve files myhostname dns' \
  'passwd: files systemd' > "$test_root/etc/nsswitch.conf"

export FOCUS_GUARD_ROOT=$test_root

bash "$controller" enable
grep -q '^hosts: mymachines mdns_minimal \[NOTFOUND=return\] files myhostname dns$' \
  "$test_root/etc/nsswitch.conf" || exit 1
grep -q '^passwd: files systemd$' "$test_root/etc/nsswitch.conf" || exit 1

bash "$controller" restore
cmp -s "$test_root/etc/nsswitch.conf" "$test_root/var/lib/focus-guard/nsswitch.conf.original" || exit 1

printf 'focus-guard-nsswitch tests passed\n'
