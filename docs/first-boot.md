# First Boot Flow

## Boot order

```
sysinit.target
  └─ systemd-firstboot.service   # interactive tty: hostname, timezone, root password
  └─ systemd-repart.service      # expands root partition
  └─ systemd-growfs-root.service # expands filesystem

multi-user.target
  └─ rpi5-firstboot.service      # swapfile creation (btrfs only)
```

## systemd-firstboot

**At build time** (`bootstrap::systemd_firstboot`): writes locale, keymap, shell, machine-id with `--force`.
When `BUILD_HOSTNAME`, `BUILD_TIMEZONE`, `BUILD_ROOT_PASSWORD` are set — writes those too.
When unset, the corresponding files are not created, so `systemd-firstboot` prompts interactively at runtime.

**tty drop-in** (`src/conf/systemd/systemd-firstboot.service.d/prompt.conf`):
```ini
[Service]
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/console
```
Grabs the console — prompts are not overwritten by log output.

## rpi5-firstboot.service

### Dependencies

```ini
[Unit]
After=systemd-firstboot.service
```

### Script (`/usr/local/lib/rpi5-archlinux/firstboot.sh`)

At build time, `bootstrap::firstboot_service()` writes `firstboot.sh` with `__SWAPFILE_SIZE__` substituted.

At first boot, the script only handles btrfs swapfile creation — no user creation is performed.
Root SSH is pre-configured at build time; create users manually after first login:

```bash
useradd -m -G wheel user
passwd user
```

### Swapfile (btrfs only)

If `SWAPFILE_SIZE` is set, the script:
1. Mounts the `@swap` subvolume.
2. Creates a btrfs swapfile via `btrfs filesystem mkswapfile`.
3. Adds the swapfile to `/etc/fstab`.
4. Activates it via `swapon`.

## Partition / filesystem grow

Native systemd units, enabled at build time:
- `systemd-repart.service` — expands root partition using `/etc/repart.d/50-root.conf` (`GrowFileSystem=yes`)
- `systemd-growfs-root.service` — expands the filesystem to fill the partition

## Locales

`locale-gen` runs at build time (chroot) after `systemd-firstboot`.
`en_US.UTF-8` is added to `/etc/locale.gen` via `bootstrap::locale_gen_file()`.
