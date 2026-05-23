#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ ! -f "$repo_root/scripts/main.sh" ]] || fail "legacy scripts/main.sh should be removed"
[[ -f "$repo_root/src/main.sh" ]] || fail "missing src/main.sh"
[[ -d "$repo_root/dist/bin" ]] || fail "missing dist/bin directory"
[[ -d "$repo_root/dist/images" ]] || fail "missing dist/images directory"
[[ -x "$repo_root/dist/bin/rpi5-archlinux-image" ]] || fail "missing executable dist/bin/rpi5-archlinux-image"
[[ -f "$repo_root/scripts/package.sh" ]] || fail "missing scripts/package.sh"
[[ -f "$repo_root/build.conf.example" ]] || fail "missing build config example"
grep -q '^build\.conf$' "$repo_root/.gitignore" || fail ".gitignore must exclude local build.conf"
[[ ! -e "$repo_root/conf" ]] || fail "legacy root conf directory should be removed"
[[ -d "$repo_root/src/lib/core" ]] || fail "missing core library directory"
[[ -d "$repo_root/src/lib/modules" ]] || fail "missing module directory"
[[ -d "$repo_root/src/conf/pacman" ]] || fail "missing pacman config directory"
[[ -d "$repo_root/src/conf/boot" ]] || fail "missing boot config directory"
[[ -d "$repo_root/src/conf/systemd" ]] || fail "missing systemd config directory"
[[ ! -f "$repo_root/main.sh" ]] || fail "legacy root main.sh should be removed"
[[ ! -e "$repo_root/main_n.sh" ]] || fail "main_n.sh should be removed"
[[ ! -e "$repo_root/disk_n.sh" ]] || fail "disk_n.sh should be removed"
[[ ! -e "$repo_root/tmp2" ]] || fail "tmp2 should be removed"
[[ -f "$repo_root/src/conf/pacman/pacman-arm.conf" ]] || fail "missing active pacman config"
[[ -f "$repo_root/src/conf/boot/config.txt" ]] || fail "missing active config.txt"
[[ -f "$repo_root/src/conf/boot/cmdline.txt" ]] || fail "missing active cmdline.txt"
[[ -f "$repo_root/src/conf/systemd/rpi5-firstboot.service" ]] || fail "missing active firstboot service"
grep -q 'Complete first boot provisioning' "$repo_root/src/conf/systemd/rpi5-firstboot.service" ||
    fail "firstboot service asset must be non-empty and active"
[[ -f "$repo_root/.gitignore" ]] || fail "missing .gitignore"
grep -q '^archlinuxarm-rpi5-aarch64\.img$' "$repo_root/.gitignore" || fail ".gitignore must exclude raw image artifacts"
grep -q '^archlinuxarm-rpi5-aarch64-.*\.img\.xz$' "$repo_root/.gitignore" || fail ".gitignore must exclude compressed release image artifacts"
grep -q '^archlinuxarm-rpi5-aarch64-.*\.img\.xz\.sha256$' "$repo_root/.gitignore" || fail ".gitignore must exclude release checksum artifacts"
grep -q '^dist/$' "$repo_root/.gitignore" || fail ".gitignore must exclude packaged dist artifacts"

grep -q './dist/bin/rpi5-archlinux-image' "$repo_root/README.md" || fail "README must reference ./dist/bin/rpi5-archlinux-image"
grep -Fq 'archlinuxarm-rpi5-aarch64.img' "$repo_root/README.md" || fail "README must document canonical local image name"
grep -Fq "archlinuxarm-rpi5-aarch64-\${TAG}.img.xz" "$repo_root/README.md" || fail "README must document tagged release image name"
grep -q 'list-steps' "$repo_root/README.md" || fail "README must mention list-steps"
grep -q 'src/conf/boot/' "$repo_root/README.md" || fail "README must mention boot configs"
grep -q 'embedded' "$repo_root/README.md" || fail "README must mention packaged embedded configs"
grep -q -- '--config ./my-build.conf build' "$repo_root/README.md" ||
    fail "README must document explicit config override"
grep -q 'cp build.conf.example build.conf' "$repo_root/README.md" ||
    fail "README must document creating local build.conf"
grep -q 'src/main.sh' "$repo_root/AGENTS.md" || fail "AGENTS must reference src/main.sh"
grep -q 'dist/bin/rpi5-archlinux-image' "$repo_root/AGENTS.md" || fail "AGENTS must reference dist/bin/rpi5-archlinux-image"
grep -q '.github/workflows' "$repo_root/README.md" || fail "README must mention GitHub Actions"
