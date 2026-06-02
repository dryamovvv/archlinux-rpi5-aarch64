# Build Pipeline

12-шаговый процесс сборки образа. Каждый шаг — функция в соответствующем модуле.

```
prepare_image → map_loop → partition_image → create_filesystems → mount_filesystems
→ prepare_base_config → install_base → configure_boot → configure_system
→ configure_services → validate_boot_files → shrink_image
```

| Шаг | Модуль | Что делает |
|-----|--------|------------|
| `prepare_image` | `disk_image.sh` | `truncate -s 4g archlinux-rpi5-aarch64.img` |
| `map_loop` | `disk_image.sh` | `losetup --find -P --show` |
| `partition_image` | `disk_image.sh` | GPT: 512M ESP (vfat) + остальное root (ext4 или btrfs) |
| `create_filesystems` | `disk_image.sh` | `mkfs.vfat` + ext4/btrfs; LUKS: `cryptsetup luksFormat` + `open`; btrfs: 6 subvolume (`@`, `@home`, `@swap`, `@var_log`, `@var_cache`, `@var_tmp`) |
| `mount_filesystems` | `disk_image.sh` | root `@` → `/mnt/arch_build`, boot ESP → `/mnt/arch_build/boot`, subvolumes (`@home`, `@swap`, `@var_*`) |
| `prepare_base_config` | `base_system.sh` | `/etc/vconsole.conf` |
| `install_base` | `base_system.sh` | `pacstrap` пакетов + `mkinitcpio` (LUKS: `sd-encrypt`, без `kms`; btrfs: без `fsck`) + `fstab` (btrfs: вручную, без `subvol=@` для `/`) |
| `configure_boot` | `boot_config.sh` | `cmdline.txt` (UUID + LUKS: `rd.luks.name`, `rd.luks.options=tty1`) и `config.txt` |
| `configure_system` | `services.sh` | `systemd-firstboot` (locale/root/hostname), `locale-gen`, `pacman-key --init`, `firstboot_service` |
| `configure_services` | `services.sh` | network, sshd, sudo, ZRAM, nftables, fstrim, cpu_boost, LUKS initramfs, repart/growfs, **snapper** (create-config + initial RW snapshot + default subvol), EEPROM, fail2ban, journal-gatewayd, MCP server |
| `validate_boot_files` | `release_validation.sh` | Проверка 5 boot-файлов |
| `shrink_image` | `image_shrink.sh` | `resize2fs -M` → `truncate` → `sgdisk -e` (ext4 only; btrfs пропускается) |

## Snapper rollback setup (step: configure_services)

```bash
# 1. Создать конфиги (.snapshots subvolume внутри @)
snapper --no-dbus -c root create-config /
snapper --no-dbus -c home create-config /home

# 2. Создать начальный read-write снапшот
snapper --no-dbus -c root create --read-write -d "initial"

# 3. Установить снапшот как default subvolume
btrfs subvolume set-default <snap_id> /
```

`--no-dbus` нужен потому что в chroot нет D-Bus.
`--read-write` обязателен — иначе система загрузится в read-only.

## Важные нюансы

- `BUILD_ROOT_UUID` сохраняется при форматировании и подставляется в `cmdline.txt` через `sed`
- `genfstab -U` для ext4; для btrfs: fstab записывается вручную (без `subvol=@` для `/`, с `subvol=@/.snapshots` для `/.snapshots`)
- `bootstrap::mkinitcpio_conf`: для btrfs добавляет `MODULES=(vfat btrfs)`, убирает `fsck`; для LUKS: `sd-encrypt` + `dm_crypt aes_ce_blk usbhid xhci_hcd`
- HOOKS без `kms`: vc4-kms-v3d загружается через device tree после загрузки
- `btrfs filesystem resize max` в firstboot делается ДО swap-файла (сначала расширяем, потом создаём)
- QEMU-сборка пропускает `boot_config` и `release_validation`, добавляет `qemu_boot_config`
