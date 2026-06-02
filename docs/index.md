# rpi5-archlinux-image

Сборка Arch Linux ARM образа для Raspberry Pi 5 с полным шифрованием диска, btrfs и snapper rollback.

## Возможности

- **LUKS2** полное шифрование диска (keyboard / SSH / Telegram разблокировка)
- **btrfs** с 6 subvolume (`@`, `@home`, `@swap`, `@var_log`, `@var_cache`, `@var_tmp`)
- **snapper** — автоматические снапшоты (timeline + snap-pac) и native rollback
- **ZRAM + swap** — двухуровневый своп (ZRAM zstd + btrfs swapfile на @swap)
- **nftables** firewall (drop-default, SSH+HTTP+HTTPS+ICMP)
- **MCP server** — arch-ops-server для AI-диагностики (Bearer auth)
- **fail2ban** — защита SSH от брутфорса
- **btrbk** — инкрементальные бэкапы (локальные / SSH / cold storage)
- **systemd-networkd** + **resolved** — сетевое управление без NetworkManager
- **NVMe** готовность — PCIe Gen 3, fstrim.timer
- Безопасный разгон CPU: `arm_freq=2800`, `over_voltage_delta=25000`

## Быстрый старт

```bash
git clone https://github.com/dryamovvv/archlinux-rpi5-aarch64.git
cd archlinux-rpi5-aarch64
cp build.conf.example build.conf

# Настроить build.conf под себя
vim build.conf

# Собрать (только на aarch64!)
./scripts/package.sh
sudo ./dist/bin/rpi5-archlinux-image build
```

Образ: `dist/images/archlinux-rpi5-aarch64.img`

## Прошивка на SD-карту

```bash
# Записать образ
sudo dd if=dist/images/archlinux-rpi5-aarch64.img of=/dev/mmcblk0 bs=4M status=progress conv=fsync

# Или через Raspberry Pi Imager (выбрать .img файл)
```

## Первая загрузка

1. Подключить HDMI и USB-клавиатуру (для LUKS keyboard mode)
2. Ввести LUKS пароль при появлении приглашения
3. Дождаться полной загрузки (~30 секунд)
4. SSH: `ssh root@<ip>` (пароль из `BUILD_ROOT_PASSWORD`)
5. Создать пользователя: `useradd -m -G wheel user && passwd user`

```bash
# Проверить систему
snapper list                  # снапшоты
free -h                       # ZRAM + swap
btrfs subvolume list /        # subvolume
cryptsetup status cryptroot   # LUKS
```

## Архитектура

```
firmware → kernel + initramfs
  ├─ sd-encrypt → LUKS prompt (tty1, HDMI)
  ├─ монтирование root (default btrfs subvolume = .snapshots/1/snapshot)
  └─ switch_root → systemd

subvolid=5 (btrfs root)
├── @                        # основной subvolume
│   └── .snapshots           # snapper (внутри @)
│       └── 1/snapshot       # начальный RW-снапшот (= default)
├── @home                    # /home
├── @swap                    # swap-файл (отдельно от снапшотов)
├── @var_log                 # /var/log
├── @var_cache               # /var/cache
└── @var_tmp                 # /var/tmp
```

## Снапшоты и откат

```bash
# Создать снапшот перед изменениями
snapper -c root create -d "before-upgrade"

# Откатиться
snapper -c root rollback 3
reboot
```

Снапшоты создаются автоматически: timeline (раз в час) + snap-pac (до/после каждого pacman).

## Бэкапы

```bash
# Локальный бэкап на внешний диск
mount /dev/sda1 /mnt/backup
btrbk -c /etc/btrbk/btrbk.conf run

# Восстановление
btrfs send /mnt/backup/@.20260602 | btrfs receive /mnt/restore/
```

## Требования

- **Сборка только на aarch64** (RPi5 или эквивалент)
- qemu-user-static на x86_64 **не работает** (ломает `unshare` в pacstrap)
- Рекомендуется активное охлаждение для RPi5 (overclock до 2.8 GHz)
- 4+ GB SD-карта (образ занимает ~2 GB после установки)
