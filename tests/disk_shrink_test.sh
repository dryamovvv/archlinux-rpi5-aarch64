#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

source "$repo_root/src/lib/disk.sh"

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

calls_file="$tmpdir/calls.log"
sfdisk_dump_file="$tmpdir/sfdisk.dump"
image_path="$tmpdir/arch.img"
loop_dev="$tmpdir/loop0"
root_part="$tmpdir/loop0p2"

truncate -s 4G "$image_path"
touch "$loop_dev" "$root_part"
CURRENT_LOOP_DEV="$loop_dev"
CURRENT_IMAGE_PATH="$image_path"

mountpoint() {
    return 1
}

sync() {
    :
}

e2fsck() {
    printf 'e2fsck %s\n' "$*" >>"$calls_file"
}

resize2fs() {
    printf 'resize2fs %s\n' "$*" >>"$calls_file"
}

dumpe2fs() {
    cat <<'EOF'
Block count:              500000
Block size:               4096
EOF
}

blockdev() {
    printf '512\n'
}

sfdisk() {
    if [[ "$1" == "--dump" ]]; then
        cat <<EOF
label: gpt
${loop_dev}p1 : start=        2048, size=     1048576, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
${loop_dev}p2 : start=     1050624, size=     7337984, type=B921B045-1DF0-41C3-AF44-4C6F280D3FAE
EOF
        return 0
    fi

    if [[ "$1" == "--force" ]]; then
        cat >"$sfdisk_dump_file"
        printf 'sfdisk write %s\n' "$*" >>"$calls_file"
        return 0
    fi

    fail "unexpected sfdisk call: $*"
}

sgdisk() {
    printf 'sgdisk %s\n' "$*" >>"$calls_file"
}

losetup() {
    printf 'losetup %s\n' "$*" >>"$calls_file"
}

partprobe() {
    printf 'partprobe %s\n' "$*" >>"$calls_file"
}

partx() {
    printf 'partx %s\n' "$*" >>"$calls_file"
}

udevadm() {
    printf 'udevadm %s\n' "$*" >>"$calls_file"
}

disk::shrink_image "$image_path" "$loop_dev" 2 "256M"

grep -q 'resize2fs -M' "$calls_file" ||
    fail "shrink must minimize ext4 before changing the partition"
grep -q 'size= *4526080' "$sfdisk_dump_file" ||
    fail "root partition must be resized to filesystem size plus margin"
grep -q 'sgdisk -e' "$calls_file" ||
    fail "shrink must relocate the GPT backup header after truncating"
actual_size="$(stat -c '%s' "$image_path")"
[[ "$actual_size" == "2856321024" ]] ||
    fail "image must be truncated to the shrunken partition plus GPT slack, got $actual_size"
