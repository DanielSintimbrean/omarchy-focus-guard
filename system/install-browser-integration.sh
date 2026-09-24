#!/usr/bin/env bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/bin

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'Browser integration setup needs administrator privileges.\n' >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if ! command -v pacman >/dev/null 2>&1; then
  printf 'Focus Guard currently supports Arch Linux systems with pacman.\n' >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  pacman --noconfirm --needed -S python
fi

python3 "$script_dir/install-browser-integration.py"
