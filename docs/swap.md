# ZRAM + swap

Двухуровневый своп для Raspberry Pi 5: быстрый ZRAM в памяти + btrfs swapfile на диске.

## Архитектура

```
Приоритет:
  1. ZRAM (zstd, в RAM)    — приоритет 100, заполняется первым
  2. Btrfs swapfile (@swap) — приоритет 1, вторичный

swapon:
  /dev/zram0  priority=100
  /swap/swapfile priority=1
```

## Настройка

```bash
# build.conf
BUILD_ENABLE_ZRAM=1
BUILD_ZRAM_SIZE="4096"       # 4 GiB (в МЕГАБАЙТАХ, не G!)
BUILD_SWAPFILE_SIZE="16G"    # 16 GiB swap-файл
```

**Важно:** `BUILD_ZRAM_SIZE` в мегабайтах. Не использовать `G` — fasteval на RPi5
обрабатывает `G` как 10^9, а не 2^30, что даёт неправильный размер.

## Проверка после загрузки

```bash
free -h                    # общая память и swap
swapon --show              # активные swap-устройства
zramctl                    # статус ZRAM
ls -lh /swap/swapfile      # swap-файл
```

## Swap-файл и btrfs

Swap-файл создаётся при первой загрузке на отдельном `@swap` subvolume:

```
subvolid=5
├── @swap   ← swap-файл здесь
└── @       ← системный root (не содержит swap)
```

```bash
# fstab
UUID=xxx /swap  btrfs  subvol=@swap,noatime,nodatacow  0  0
/swap/swapfile  none  swap  defaults,pri=1              0  0
```

**Преимущества отдельного subvolume:**
- Snapper не трогает `@swap` — swap не попадает в снапшоты
- Rollback не затрагивает swap
- `nodatacow` на subvolume (swap не должен использовать CoW)

## First boot flow

```bash
# rpi5-firstboot.service:
1. cryptsetup resize cryptroot       # расширить LUKS
2. btrfs filesystem resize max /      # расширить btrfs
3. mount /swap (@swap subvolume)
4. btrfs filesystem mkswapfile --size 16G /swap/swapfile
5. swapon --fixpgsz /swap/swapfile    # fixpgsz для 16K page size RPi5
```

## RPi5-specific

- `--fixpgsz` — RPi5 использует 16K страницы (не стандартные 4K)
- ZRAM с zstd — эффективное сжатие на Cortex-A76
- AES-ускорение (`aes_ce_blk`) улучшает производительность LUKS + swap

## Ручное управление

```bash
# Отключить swap
swapoff -a

# Включить
swapon -a

# Изменить размер ZRAM (требует перезагрузки сервиса)
systemctl restart systemd-zram-setup@zram0
```
