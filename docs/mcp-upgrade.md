# MCP Upgrade Proposals (v0.13+)

Based on real-world experience building and testing rpi5-archlinux-image
with LUKS + btrfs + snapper rollback + ZRAM/swap.

## Current MCP: 48 tools, 8 prompts, 24 resources

All existing tools cover basic operations well. Below are gaps discovered during
image build/testing that are NOT covered by current tools.

---

## Priority 1: snapper rollback workflow

Current `manage_btrfs_snapshots` only does list/create/delete. Missing the
critical **rollback** operation that we spent hours debugging.

### `snapper_rollback` (NEW)

```yaml
tool: snapper_rollback
description: >
  Perform snapper rollback to a specific snapshot. Creates read-only backup of
  current default, read-write clone of target snapshot, sets it as new default
  btrfs subvolume. Requires reboot to take effect.
parameters:
  config: root|home  # snapper config name
  snapshot_number: int  # target snapshot to rollback to
returns:
  new_default_id: int  # btrfs subvolume ID of new default
  backup_snapshot: int  # backup snapshot created from current state
  reboot_required: true
safety: confirm before executing (destructive, requires reboot)
```

### `snapper_status` (NEW)

```yaml
tool: snapper_status
description: >
  Show current booted subvolume vs btrfs default subvolume. Warns if they differ
  (pending rollback that hasn't been rebooted into).
returns:
  current_subvol_id: int
  current_subvol_path: string
  default_subvol_id: int
  default_subvol_path: string
  pending_rollback: bool  # true if current != default
```

### `snapper_configs` (NEW)

```yaml
tool: snapper_configs
description: List all snapper configurations with their status.
returns:
  configs:
    - name: root
      subvolume: "/"
      snapshots_count: 5
      timeline_enabled: true
      cleanup_enabled: true
```

---

## Priority 2: First boot validation

After flashing an image, first boot runs `rpi5-firstboot.service` which does
LUKS resize + btrfs resize + swap creation. Failures here are silent and
hard to debug remotely.

### `verify_firstboot` (NEW)

```yaml
tool: verify_firstboot
description: >
  Validate that first boot provisioning completed successfully. Checks:
  rpi5-firstboot.service exit code, cryptsetup resize result, btrfs resize
  result, swap file creation, ZRAM activation.
returns:
  service_status: { exited, failed, not_found }
  luks_resized: bool
  btrfs_resized: bool
  swap_created: bool
  swap_active: bool
  zram_active: bool
  errors: [string]
```

### `luks_resize` (NEW)

```yaml
tool: luks_resize
description: >
  Resize LUKS container to fill underlying partition. Needed after systemd-repart
  expands the root partition on first boot. Requires LUKS passphrase (prompted
  or from key file).
parameters:
  mapper_name: "cryptroot"
  passphrase: string  # will prompt if not provided
safety: requires explicit confirmation with warning
```

---

## Priority 3: ZRAM & swap management

Current tools don't cover ZRAM or swap at all. Critical for RPi5 where ZRAM
is the primary swap layer.

### `manage_zram` (NEW)

```yaml
tool: manage_zram
description: Show ZRAM configuration and statistics.
actions:
  - status: show all zram devices, compression, size, usage
  - configure: update zram-generator.conf size/algorithm
returns:
  devices:
    - name: /dev/zram0
      size: "4G"
      compression: zstd
      used: "0B"
      priority: 100
```

### `manage_swap` (ENHANCE existing)

```yaml
tool: manage_swap
description: >
  Show all swap devices (zram + files + partitions) with priority ordering.
  Enable/disable specific swap devices.
actions:
  - status: list all swap with priority, size, usage
  - create: create btrfs swap file (mkswapfile + swapon)
  - disable: swapoff specific device
```

---

## Priority 4: Initramfs & boot verification

LUKS boot issues (missing kms hook, wrong console tty, missing modules) were
the single hardest bug to diagnose. No tool helps with this.

### `verify_initramfs` (NEW)

```yaml
tool: verify_initramfs
description: >
  Parse mkinitcpio.conf and compare against best practices for LUKS/btrfs on
  RPi5. Validates: HOOKS order, MODULES presence, compression, missing hooks.
returns:
  config_file: /etc/mkinitcpio.conf
  hooks: [base, systemd, ...]
  modules: [aes_ce_blk, ...]
  warnings:
    - "kms hook present: will reset framebuffer on RPi5"
    - "sd-encrypt hook missing: LUKS won't prompt"
    - "usbhid module missing: USB keyboard won't work in initramfs"
  recommendations: [string]
```

### `verify_kernel_cmdline` (NEW)

```yaml
tool: verify_kernel_cmdline
description: >
  Parse /proc/cmdline and /boot/cmdline.txt. Validate LUKS parameters
  (rd.luks.name, rd.luks.options), console settings, root flags against
  RPi5 best practices.
returns:
  active_cmdline: string
  stored_cmdline: string
  warnings:
    - "console=tty0 should be tty1 for HDMI LUKS prompt"
    - "rd.luks.options missing: add rd.luks.options=cryptroot=tty1"
    - "rootflags=subvol=@ present: breaks snapper rollback"
```

---

## Priority 5: Snapshot space monitoring

Snapper snapshots can fill the disk. Cleanup timer may be disabled. No tool
to warn about this.

### `check_snapshot_usage` (NEW)

```yaml
tool: check_snapshot_usage
description: >
  Analyze btrfs snapshot disk usage. Show space used by each snapshot,
  cleanup timer status, and warn if snapshots exceed threshold.
returns:
  snapshots_total_size: "2.3G"
  snapshots_count: 12
  cleanup_timer_enabled: true
  warnings:
    - "Snapshot #3 uses 1.2G (largest)"
    - "10 snapshots older than cleanup policy"
```

---

## Priority 6: Backup (btrbk) integration

btrbk is pre-installed but not configured. No tool to help set up or verify
backups.

### `manage_btrbk` (NEW)

```yaml
tool: manage_btrbk
description: >
  Manage btrbk incremental backups. Show config, run dry-run, execute backup,
  verify last backup integrity.
actions:
  - status: show config, last backup time, target
  - dry_run: simulate backup without executing
  - run: execute backup (with optional safety prompt)
  - verify: check last backup integrity
returns:
  config_exists: bool
  last_backup: "2026-06-02 15:30"
  target: "/mnt/backup"
  last_status: success|failed
```

---

## Summary: 11 new tools proposed

| Priority | Tool | Replaces/Extends |
|----------|------|-----------------|
| P1 | `snapper_rollback` | New |
| P1 | `snapper_status` | New |
| P1 | `snapper_configs` | New |
| P2 | `verify_firstboot` | New |
| P2 | `luks_resize` | Extends `manage_luks` |
| P3 | `manage_zram` | New |
| P3 | `manage_swap` | New |
| P4 | `verify_initramfs` | New |
| P4 | `verify_kernel_cmdline` | New |
| P5 | `check_snapshot_usage` | New |
| P6 | `manage_btrbk` | New |
