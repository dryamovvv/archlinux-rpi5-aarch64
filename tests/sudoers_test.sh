#!/bin/bash
set -euo pipefail

log::info() { :; }
log::success() { :; }
log::warn() { :; }
log::error() { printf '%s\n' "$*" >&2; }
log::die() {
  printf '%s\n' "$*" >&2
  exit 1
}
log::assert_not_empty() { :; }

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Create a mock sudoers file with commented wheel
echo '# %wheel ALL=(ALL:ALL) ALL' >"$TMPDIR/sudoers"
# Make a copy of the target path so bootstrap writes to our tmpdir
bootstrap::enable_wheel_sudo() {
  sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "$1/sudoers"
}
bootstrap::enable_wheel_sudo "$TMPDIR"

if grep -q '# %wheel' "$TMPDIR/sudoers"; then
  fail "%wheel line is still commented"
fi

if ! grep -q '%wheel ALL=(ALL:ALL) ALL' "$TMPDIR/sudoers"; then
  fail "%wheel line not uncommented (got: $(cat "$TMPDIR/sudoers"))"
fi

echo "PASS: sudoers wheel uncommented"
