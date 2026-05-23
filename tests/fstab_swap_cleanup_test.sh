#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

source "$repo_root/src/lib/bootstrap.sh"

log::info() { :; }
log::success() { :; }
log::warn() { :; }
log::error() { printf '%s\n' "$*" >&2; }
log::die() { printf '%s\n' "$*" >&2; exit 1; }
log::assert_not_empty() {
    if [[ -z "${1:-}" ]]; then
        log::die "empty arg: ${2:-unknown}"
    fi
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

target="$tmpdir/root"
mkdir -p "$target/etc/systemd" "$target/swap"
cat >"$target/etc/fstab" <<'EOF'
UUID=root / ext4 rw 0 1
/dev/zram0 none swap defaults,pri=5 0 0
/swap/swapfile none swap defaults 0 0
UUID=boot /boot vfat rw 0 2
EOF
printf '[zram0]\nzram-size = 8192\n' >"$target/etc/systemd/zram-generator.conf"
touch "$target/swap/swapfile"

bootstrap::disable_swap "$target"

if grep -q 'swap' "$target/etc/fstab"; then
    fail "disable_swap must remove all swap entries from fstab"
fi
[[ ! -e "$target/etc/systemd/zram-generator.conf" ]] ||
    fail "disable_swap must remove zram-generator config"
[[ ! -e "$target/swap" ]] ||
    fail "disable_swap must remove stale swap directory"
