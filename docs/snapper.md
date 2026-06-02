# Snapper rollback

Автоматические btrfs снапшоты и native rollback (openSUSE-style).

## Как это работает

Snapper создаёт read-only снапшоты btrfs subvolume. Rollback создаёт read-write клон
выбранного снапшота и устанавливает его как **default subvolume** btrfs.
При следующей загрузке ядро монтирует новый default subvolume как `/`.

## Архитектура

```
subvolid=5 (btrfs root)
├── @                        # основной subvolume (не монтируется как /)
│   └── .snapshots           # снапшоты snapper
│       ├── 1/snapshot       # начальный RW-снапшот (= default, = /)
│       ├── 2/snapshot       # timeline/pre/post снапшоты
│       └── ...
├── @home                    # /home
├── @swap                    # /swap (независим от rollback)
└── ...
```

**Ключевое отличие от «suggested layout»:**
- `/.snapshots` внутри `@` (не на уровне btrfs root) — openSUSE-way
- fstab для `/` **без** `subvol=@` — система грузится из default subvolume
- fstab для `/.snapshots` с `subvol=@/.snapshots`

## Использование

```bash
# Посмотреть все снапшоты
snapper list

# Ручной снапшот
snapper -c root create -d "before-upgrade"

# Откат (работает из загруженной системы)
snapper -c root rollback 3
reboot    # обязательно!

# После ребута система в снапшоте 3
snapper list   # 3* = текущий
```

## Автоматические снапшоты

| Механизм | Когда | Конфиг |
|----------|-------|--------|
| **timeline** | Раз в час | `snapper-timeline.timer` |
| **snap-pac** | До/после pacman | `snap-pac` package |
| **cleanup** | По расписанию | `snapper-cleanup.timer` |

```bash
# Статус таймеров
systemctl status snapper-timeline.timer snapper-cleanup.timer
```

## Откат из unbootable системы

Если система не грузится — загрузиться с live USB:

```bash
# Разблокировать LUKS
cryptsetup open /dev/mmcblk0p2 cryptroot

# Смонтировать btrfs root (subvolid=5)
mount -o subvolid=5 /dev/mapper/cryptroot /mnt

# Создать RW клон нужного снапшота
btrfs subvolume snapshot /mnt/@/.snapshots/3/snapshot /mnt/@/.snapshots/N/snapshot

# Установить как default
SNAP_ID=$(btrfs subvolume show /mnt/@/.snapshots/N/snapshot | awk '/Subvolume ID:/{print $NF}')
btrfs subvolume set-default $SNAP_ID /mnt

umount /mnt
reboot
```

## Home снапшоты

```bash
snapper -c home create -d "before-config-change"
snapper -c home list
```

Снапшоты `/home` независимы от root — rollback `/` не трогает `/home`.

## Ограничения

- `/var` не должен быть отдельным subvolume (иначе `/var/lib/pacman` не в снапшотах)
- `@swap` — отдельный subvolume, не входит в снапшоты
- Нельзя снапшотить subvolume с активным swap-файлом
