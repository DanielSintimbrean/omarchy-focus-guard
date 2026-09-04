#!/usr/bin/env bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/bin

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'Focus Guard setup needs administrator privileges.\n' >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if ! command -v pacman >/dev/null 2>&1; then
  printf 'Focus Guard currently supports Arch Linux systems with pacman.\n' >&2
  exit 1
fi

if ! command -v dnsmasq >/dev/null 2>&1; then
  pacman --noconfirm --needed -S dnsmasq
fi

install -Dm755 "$script_dir/focus-guardctl" /usr/local/bin/focus-guardctl
install -Dm755 "$script_dir/focus-guard-nsswitch" /usr/local/bin/focus-guard-nsswitch
install -Dm644 "$script_dir/focus-guard.service" /etc/systemd/system/focus-guard.service
install -Dm644 "$script_dir/focus-guard.timer" /etc/systemd/system/focus-guard.timer
install -Dm755 "$script_dir/focus-guard-sleep" /usr/lib/systemd/system-sleep/focus-guard
install -Dm644 "$script_dir/focus-guard.policy" /usr/share/polkit-1/actions/io.github.danielsintimbrean.focus-guard.policy
install -Dm644 "$script_dir/90-focus-guard-dns.conf" /etc/NetworkManager/conf.d/90-focus-guard-dns.conf

mkdir -p /etc/focus-guard /var/lib/focus-guard /etc/NetworkManager/dnsmasq.d
chmod 755 /etc/focus-guard /var/lib/focus-guard /etc/NetworkManager/dnsmasq.d

resolver_backup=/var/lib/focus-guard/resolv.conf.original
resolver_missing=/var/lib/focus-guard/resolv.conf.was-missing
if [[ ! -e $resolver_backup && ! -L $resolver_backup && ! -e $resolver_missing ]]; then
  if [[ -e /etc/resolv.conf || -L /etc/resolv.conf ]]; then
    cp -a --no-dereference /etc/resolv.conf "$resolver_backup"
  else
    touch "$resolver_missing"
  fi
fi
ln -sfn /run/NetworkManager/resolv.conf /etc/resolv.conf
/usr/local/bin/focus-guard-nsswitch enable

systemctl daemon-reload
systemctl enable --now focus-guard.timer
/usr/local/bin/focus-guardctl reconcile >/dev/null

if command -v nmcli >/dev/null 2>&1; then
  nmcli general reload conf,dns-full >/dev/null
else
  systemctl reload NetworkManager
fi

if command -v resolvectl >/dev/null 2>&1; then
  resolvectl flush-caches >/dev/null 2>&1 || true
fi

printf 'Focus Guard system helper installed.\n'
