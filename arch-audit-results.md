# Arch Linux RPi5 — System Audit Report

**Host:** `archlinux-develop` | **Kernel:** `6.18.33-4-rpi-16k` | **Arch:** `aarch64`  
**Uptime:** ~48 min | **RAM:** 15.8G free / 16.2G total  
**Date:** 2026-06-01

---

## Quick Health Table

| Category | Metric | Status |
|----------|--------|--------|
| System | Failed services | ✅ 0 |
| System | System state | ✅ running |
| Storage | Disk usage | ✅ 1% (237G free) |
| Storage | Pacman cache | ✅ 539 MB (257 pkgs) |
| Packages | Pending updates | ✅ 0 |
| Packages | Orphans | ✅ 0 |
| Packages | DB freshness (community) | ❌ 26603h |
| Packages | DB freshness (aur) | ❌ 53h |
| Packages | DB freshness (alarm) | ❌ 30h |
| Packages | DB freshness (core) | ❌ 28h |
| Packages | DB freshness (extra) | ✅ 0.7h |
| Mirrors | Health score | ❌ 45/100 |
| BTRFS | Device errors | ✅ 0 |
| BTRFS | Scrub | ✅ clean |
| Boot | Boot artifacts | ✅ all present |
| Boot | cmdline.txt | ✅ valid (LUKS + UUID + subvol) |
| Boot | rpi-eeprom-config | ❌ not installed |
| Security | Firewall | ❌ 0 rules |
| Security | SSH root login | ❌ enabled |
| Security | fail2ban | ❌ not installed |
| Security | MCP server | ❌ inactive |
| Services | sshd, networkd, resolved | ✅ active |
| Services | snapper-timeline | ❌ inactive |
| FSTAB | @var_lib subvolume | ❌ missing |
| FSTAB | /var/log nodatacow | ❌ missing |

---

## 🔴 CRITICAL (Fix Immediately)

### 1. SSH Root Login Enabled
**File:** `/etc/ssh/sshd_config`
```
PermitRootLogin yes
AllowUsers root
```
Root can log in directly over SSH. Combined with potentially password-based auth, this is a severe security risk.
- **Fix:** Set `PermitRootLogin prohibit-password` (or `no`), create a non-root user with `sudo`.

### 2. No Firewall Protection
**nftables ruleset is empty — 0 rules.** All ports exposed to the network.
- **Fix:** Enable and configure `nftables`:
  ```bash
  sudo systemctl enable --now nftables
  sudo nft add table inet filter
  sudo nft add chain inet filter input { type filter hook input priority 0\; policy drop\; }
  sudo nft add rule inet filter input iif lo accept
  sudo nft add rule inet filter input ct state established,related accept
  sudo nft add rule inet filter input tcp dport 22 accept
  ```

### 3. Stale Pacman Databases
| Repo | Age | Last Sync |
|------|-----|-----------|
| community | **26603h (~3 years)** | 2023-05-20 |
| aur | 53h | 2026-05-30 |
| alarm | 30h | 2026-05-31 |
| core | 28h | 2026-05-31 |
| extra | 0.7h | 2026-06-01 |

The `community` repo was merged into `extra` in 2023. Having it still configured is a misconfiguration.
- **Fix:** 
  1. Remove `[community]` from `/etc/pacman.conf`
  2. Run `sudo pacman -Syu` to refresh databases and update

### 4. Mirrors Critical (45/100)
Only 1 active mirror (`mirror.archlinuxarm.org`). 12 mirrors commented out. Mirror speed tests fail (404 on fallback mirrors).
- **Fix:** Update mirrorlist with `sudo pacman -Syu` or manually from [archlinuxarm.org](https://archlinuxarm.org/about/mirrors).

### 5. Snapper Timeline Inactive
`snapper-timeline.timer` is inactive — automatic BTRFS snapshots are not running.
- **Fix:** `sudo systemctl enable --now snapper-timeline.timer`

---

## 🟡 WARNING (Fix Soon)

### 6. Missing @var_lib Subvolume in fstab
BTRFS has `@var_lib` subvolume (ID 263 as `var/lib/portables`, ID 264 as `var/lib/machines`) but `/etc/fstab` has no entry for `/var/lib`.
- **Fix:** Add fstab entry:
  ```
  UUID=d4a7ca99-a312-435e-984a-3726935f3bd0 /var/lib btrfs rw,noatime,nodatacow,subvol=@var_lib 0 0
  ```

### 7. /var/log Missing nodatacow
`/var/log` is mounted with `compress=zstd` but without `nodatacow`. Log directories benefit from `nodatacow` to avoid CoW overhead.
- **Fix:** Add `nodatacow` to `/var/log` mount options in `/etc/fstab`.

### 8. fail2ban Not Installed
No brute-force protection for SSH or other services.
- **Fix:** `sudo pacman -S fail2ban && sudo systemctl enable --now fail2ban`

### 9. MCP Server Inactive
`arch-ops-mcp.service` is not running. The MCP API key is not set. Remote management via opencode is unavailable.
- **Fix:** `sudo systemctl enable --now arch-ops-mcp.service` and configure API key.

### 10. rpi-eeprom-config Not Installed
Cannot check BOOT_ORDER or EEPROM status. Overclock is configured (2.8 GHz) but EEPROM state is unknown.
- **Fix:** `sudo pacman -S rpi-eeprom` (from alarm repo).

### 11. pacman-contrib Not Installed
`checkupdates` tool unavailable — cannot check for pending updates without `-Syy`.
- **Fix:** `sudo pacman -S pacman-contrib`

---

## 🟢 POSITIVE FINDINGS

- **LUKS encryption active** — `rd.luks.name=...=cryptroot` in cmdline.txt
- **UUID-based boot** — `root=UUID=d4a7ca99-...` (no device names)
- **BTRFS with proper subvolume layout** — 9 subvolumes, compress=zstd on /
- **No failed services** — All systemd units healthy
- **No orphaned packages** — Clean package database
- **Boot artifacts complete** — kernel8.img, initramfs, dtb, config.txt, cmdline.txt all present
- **System state: running** — No emergency or degraded mode
- **Overclock configured** — 2.8 GHz with voltage delta (safe with Active Cooler)
- **WiFi/BT disabled via dt-overlay** — Reduced attack surface

---

## 🔧 BOOT CONFIGURATION

| Parameter | Value |
|-----------|-------|
| `arm_freq` | 2800 MHz (overclock) |
| `over_voltage_delta` | 25000 |
| `dtoverlay` | vc4-kms-v3d, disable-wifi, disable-bt |
| `dtparam` | pciex1_gen=3, audio=on |
| `auto_initramfs` | 1 |
| `kernel` | kernel8.img (4K pages, auto-detected) |

**cmdline.txt:** `rd.luks.name=... cryptroot root=UUID=... rw rootwait console=tty1 quiet loglevel=3 mitigations=off nowatchdog rootflags=subvol=@`

- `mitigations=off` — Spectre/Meltdown mitigations disabled (performance; acceptable on RPi5)
- `nowatchdog` — Hardware watchdog disabled

---

## PRIORITY ACTION PLAN

| # | Action | Priority | Effort |
|---|--------|----------|--------|
| 1 | Remove `[community]` from pacman.conf, run `pacman -Syu` | 🔴 Critical | Low |
| 2 | Disable SSH root login, create non-root user | 🔴 Critical | Medium |
| 3 | Enable and configure nftables firewall | 🔴 Critical | Medium |
| 4 | Install fail2ban | 🔴 Critical | Low |
| 5 | Fix mirrorlist / add more mirrors | 🔴 Critical | Low |
| 6 | Enable snapper-timeline.timer | 🔴 Critical | Low |
| 7 | Add @var_lib to fstab | 🟡 Warning | Low |
| 8 | Add nodatacow to /var/log fstab options | 🟡 Warning | Low |
| 9 | Install rpi-eeprom, check BOOT_ORDER | 🟡 Warning | Low |
| 10 | Install pacman-contrib | 🟡 Warning | Low |
| 11 | Enable arch-ops-mcp.service | 🟡 Warning | Low |

---

## POTENTIAL CONFIG ISSUE: `aur` Repository

`pacman.conf` lists `[aur]` as a repository using the same mirrorlist. There is no official `aur` repository in Arch Linux — AUR is the *Arch User Repository* accessed via helpers (paru/yay). This may be a custom repo or a misconfiguration. **Verify what this repo provides** and consider removing it to avoid conflicts.
