# First Boot Flow

## Boot order

```
initramfs
  └─ sd-encrypt → LUKS prompt на tty1 (HDMI/USB keyboard)
  └─ монтирование root из default btrfs subvolume (.snapshots/1/snapshot)

sysinit.target
  └─ systemd-firstboot.service      # hostname, timezone, root password
  └─ systemd-repart.service         # расширяет root-раздел
  └─ systemd-growfs-root.service    # расширяет btrfs

multi-user.target
  └─ rpi5-firstboot.service         # swapfile + финальный resize
```

## systemd-firstboot

**At build time** (`bootstrap::systemd_firstboot`): writes locale, keymap, shell, machine-id with `--force`.
When `BUILD_HOSTNAME`, `BUILD_TIMEZONE`, `BUILD_ROOT_PASSWORD` are set — writes those too.
When unset, the corresponding files are not created, so `systemd-firstboot` prompts interactively at runtime.

## rpi5-firstboot.service

### Script (`/usr/local/lib/rpi5-archlinux/firstboot.sh`)

At build time, `bootstrap::firstboot_service()` writes `firstboot.sh` with `__SWAPFILE_SIZE__` substituted.

At first boot, the script:
1. **Resize** — `cryptsetup resize cryptroot` (LUKS контейнер) → `btrfs filesystem resize max /`
2. **Swap** — mount `@swap`, `btrfs filesystem mkswapfile`, `swapon --fixpgsz`
3. No user creation — root SSH pre-configured; create users manually:

```bash
useradd -m -G wheel user
passwd user
```

### Важный порядок

**Resize ДО swapfile.** Сначала расширяется LUKS и btrfs, затем создаётся swap-файл на расширенном пространстве.

### Swapfile (btrfs only)

Если `SWAPFILE_SIZE` задан:
1. Проверяет, что swap ещё не активирован
2. Монтирует `@swap` subvolume в `/swap`
3. Создаёт swap-файл: `btrfs filesystem mkswapfile --size $SWAPFILE_SIZE --uuid clear /swap/swapfile`
4. Добавляет `/swap/swapfile none swap defaults,pri=1 0 0` в `/etc/fstab`
5. Активирует: `swapon --fixpgsz /swap/swapfile` (fixpgsz для 16K page size RPi5)

`@swap` — отдельный subvolume на уровне btrfs root, не внутри `@`. Snapper его не трогает, rollback не затрагивает.

## Partition / filesystem grow

Native systemd units, enabled at build time:
- `systemd-repart.service` — расширяет root-раздел (`/etc/repart.d/50-root.conf`: `GrowFileSystem=yes`)
- `systemd-growfs-root.service` — расширяет ФС (но btrfs resize происходит в firstboot.sh)

## Locales

`locale-gen` runs at build time (chroot) after `systemd-firstboot`.
`en_US.UTF-8` is added via `bootstrap::locale_gen_file()`.

## Snapper после первой загрузки

После первой загрузки снапшоты работают сразу:
```bash
snapper list              # показать все снапшоты
snapper -c root create -d "before-changes"  # ручной снапшот
```

Timeline (раз в час) и snap-pac (до/после pacman) создают снапшоты автоматически.
