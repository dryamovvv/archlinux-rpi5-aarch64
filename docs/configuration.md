# Configuration

## build.conf

Основной конфиг сборки. Шаблон: `build.conf.example`. Локальный `build.conf` в `.gitignore`.

### Обязательные поля

```bash
BUILD_IMAGE_PATH="$BUILD_PROJECT_ROOT/dist/images/archlinux-rpi5-aarch64.img"
BUILD_IMAGE_SIZE="4g"
BUILD_MOUNT_ROOT="/mnt/arch_build"
BUILD_MOUNT_BOOT="$BUILD_MOUNT_ROOT/boot"
BUILD_MKINITCPIO_HOOKS="HOOKS=(base systemd autodetect modconf keyboard sd-vconsole block filesystems)"
BUILD_MODULES=(...)   # минимум 1 модуль
BUILD_PACKAGES=(...)  # минимум 1 пакет
```

**Важно для HOOKS:** `kms` и `keymap` убраны. На RPi5 `kms` загружает `vc4-kms-v3d` в initramfs и сбрасывает framebuffer, пряча LUKS prompt. `sd-vconsole` заменяет `keymap` в systemd initramfs.

### Опциональные поля

```bash
BUILD_HOSTNAME="archlinux-develop"
BUILD_TIMEZONE="Europe/Moscow"
BUILD_ROOT_PASSWORD="root"
BUILD_FILESYSTEM="btrfs"         # btrfs (subvol + snapper) | ext4
BUILD_SWAPFILE_SIZE="16G"        # btrfs swapfile; пусто = без swapfile
BUILD_IMAGE_SHRINK_MARGIN="256M" # запас места при shrink
BUILD_EEPROM_CHANNEL="latest"    # default | latest
BUILD_MKINITCPIO_COMPRESSION="cat"  # gzip | cat (быстрее дев-сборки)

# SSH
BUILD_SSH_USER="dryam"           # пусто = только root
BUILD_SSH_PERMIT_ROOT_LOGIN="yes" # yes | prohibit-password | no
BUILD_ROOT_SSH_KEY=""            # публичный ключ для root
BUILD_SSH_ALLOW_USERS="dryam"    # доп. пользователи для AllowUsers
BUILD_SSH_PORT=""                # пусто = 22

# ZRAM + swap
BUILD_ENABLE_ZRAM=1
BUILD_ZRAM_SIZE="4096"           # в МЕГАБАЙТАХ (не G!)
BUILD_SWAPFILE_SIZE="16G"

# Безопасность
BUILD_ENABLE_FIREWALL=1          # nftables: SSH+80+443+estab+lo
BUILD_ENABLE_FSTRIM=1            # fstrim.timer для NVMe/SSD

# LUKS шифрование (btrfs only)
BUILD_ENABLE_ENCRYPTION=1
BUILD_LUKS_PASSWORD="test1234"
BUILD_LUKS_UNLOCK_MODE="keyboard" # keyboard | ssh | telegram

# Сервисы
BUILD_ENABLE_WIFI=0
BUILD_ENABLE_JOURNAL_GATEWAY=1   # HTTP логи на 127.0.0.1:19531
BUILD_ENABLE_MCP_SERVER=1        # arch-ops-server на 8080 (Bearer auth)
```

### LUKS unlock modes

| Режим | Параметр | Требования |
|-------|----------|------------|
| `keyboard` | HDMI/USB клавиатура | Без доп. пакетов |
| `ssh` | tinysshd в initramfs | `BUILD_AUR_PKG_URL` (mkinitcpio-systemd-extras) |
| `telegram` | Poll Telegram Bot API | `BUILD_TELEGRAM_BOT_TOKEN`, `BUILD_TELEGRAM_CHAT_ID` |

### ZRAM + swap

Двухуровневый своп:
1. **ZRAM** (zstd, приоритетный) через `systemd-zram-generator`, размер в МБ
2. **Btrfs swapfile** на `@swap` subvolume, создаётся при первой загрузке

Swap-файл на отдельном `@swap` subvolume не затрагивается снапшотами и rollback.

## config.txt

Статический файл `src/conf/boot/config.txt`. Правки напрямую.

Текущие настройки для `[pi5]`:
- `arm_freq=2800`, `over_voltage_delta=25000` — безопасный разгон
- `disable_splash=1` — без rainbow screen
- `dtoverlay=disable-wifi`, `dtoverlay=disable-bt` — headless
- `dtparam=pciex1_gen=3` — PCIe Gen 3 для NVMe
- `dtoverlay=vc4-kms-v3d` — KMS GPU драйвер (загружается ПОСЛЕ initramfs)

## cmdline.txt

Шаблон `src/conf/boot/cmdline.txt` с плейсхолдером `__ROOT_UUID__`.

Текущие параметры:
- `console=serial0,115200 console=tty1` — tty1 для HDMI (переживает KMS reset)
- `systemd.show_status=1 loglevel=3` — показывать статус systemd, скрывать `[drm]`
- `mitigations=off` — +5-10% CPU (Cortex-A76 не подвержен Spectre/Meltdown)
- `nowatchdog` — без watchdog-таймеров
- UUID подставляется при сборке из `BUILD_ROOT_UUID`

**LUKS keyboard mode добавляет:**
- `rd.luks.name=<LUKS_UUID>=cryptroot` — привязка LUKS к /dev/mapper/cryptroot
- `rd.luks.options=cryptroot=tty1` — явный TTY для пароля

## Snapper rollback

fstab без `subvol=@` для `/` — система грузится из default subvolume btrfs.
При rollback snapper меняет default subvolume → после reboot система в выбранном снапшоте.

```bash
snapper -c root create -d "my-snapshot"
snapper -c root rollback 3
reboot
```

Снапшоты создаются автоматически: `snapper-timeline.timer` (раз в час) + `snap-pac` (до/после pacman).
