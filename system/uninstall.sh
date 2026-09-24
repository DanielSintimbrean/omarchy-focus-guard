#!/usr/bin/env bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/bin

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'Focus Guard removal needs administrator privileges.\n' >&2
  exit 1
fi

systemctl disable --now focus-guard.timer 2>/dev/null || true
rm -f /etc/NetworkManager/dnsmasq.d/90-focus-guard.conf
rm -f /etc/NetworkManager/conf.d/90-focus-guard-dns.conf

zen_extension_path=/var/lib/focus-guard/zen-browser-extension.path
if [[ -r $zen_extension_path ]]; then
  read -r zen_extension_file < "$zen_extension_path"
  case $zen_extension_file in
    */distribution/extensions/focus-guard@danielsintimbrean.xpi)
      rm -f -- "$zen_extension_file"
      rmdir --ignore-fail-on-non-empty "$(dirname -- "$zen_extension_file")" 2>/dev/null || true
      ;;
  esac
fi

chromium_extension_id_file=/var/lib/focus-guard/chromium-browser-extension.id
if [[ -r $chromium_extension_id_file ]]; then
  read -r chromium_extension_id < "$chromium_extension_id_file"
  if [[ $chromium_extension_id =~ ^[a-p]{32}$ ]]; then
    rm -f "/usr/share/chromium/extensions/$chromium_extension_id.json"
  fi
fi
rm -f /usr/lib/mozilla/native-messaging-hosts/io.github.danielsintimbrean.focus_guard.json
rm -f /etc/chromium/native-messaging-hosts/io.github.danielsintimbrean.focus_guard.json
rm -f /usr/local/bin/focus-guard-browser-host /usr/share/focus-guard/focus-guard.crx
rmdir --ignore-fail-on-non-empty /usr/share/focus-guard 2>/dev/null || true

if [[ -x /usr/local/bin/focus-guard-nsswitch ]]; then
  /usr/local/bin/focus-guard-nsswitch restore || true
fi

resolver_backup=/var/lib/focus-guard/resolv.conf.original
resolver_missing=/var/lib/focus-guard/resolv.conf.was-missing
if [[ -L /etc/resolv.conf && $(readlink /etc/resolv.conf) == /run/NetworkManager/resolv.conf ]]; then
  if [[ -e $resolver_backup || -L $resolver_backup ]]; then
    cp -a --no-dereference --remove-destination "$resolver_backup" /etc/resolv.conf
  elif [[ -e $resolver_missing ]]; then
    rm -f /etc/resolv.conf
  fi
fi

rm -f /etc/systemd/system/focus-guard.service
rm -f /etc/systemd/system/focus-guard.timer
rm -f /usr/lib/systemd/system-sleep/focus-guard
rm -f /usr/share/polkit-1/actions/io.github.danielsintimbrean.focus-guard.policy
rm -f /usr/local/bin/focus-guardctl
rm -f /usr/local/bin/focus-guard-nsswitch
rm -rf /etc/focus-guard /var/lib/focus-guard

systemctl daemon-reload
if command -v nmcli >/dev/null 2>&1; then
  nmcli general reload conf,dns-full >/dev/null
else
  systemctl reload NetworkManager
fi

if command -v resolvectl >/dev/null 2>&1; then
  resolvectl flush-caches >/dev/null 2>&1 || true
fi

printf 'Focus Guard system helper removed. The dnsmasq package was left installed.\n'
