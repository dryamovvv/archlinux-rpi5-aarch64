# LUKS шифрование

Полное шифрование root-раздела через LUKS2 на Raspberry Pi 5.

## Режимы разблокировки

| Режим | Параметр | Как работает |
|-------|----------|-------------|
| `keyboard` | `BUILD_LUKS_UNLOCK_MODE=keyboard` | Пароль с HDMI/USB клавиатуры на tty1 |
| `ssh` | `BUILD_LUKS_UNLOCK_MODE=ssh` | tinysshd в initramfs, разблокировка по SSH |
| `telegram` | `BUILD_LUKS_UNLOCK_MODE=telegram` | Poll Telegram Bot API, пароль в чат |

## Настройка в build.conf

```bash
BUILD_ENABLE_ENCRYPTION=1
BUILD_LUKS_PASSWORD="test1234"
BUILD_LUKS_UNLOCK_MODE="keyboard"
```

## Keyboard mode — как это работает

**Проблема:** на RPi5 `vc4-kms-v3d` драйвер сбрасывает framebuffer при инициализации.
Если хук `kms` присутствует в mkinitcpio, он загружает драйвер в initramfs — и LUKS prompt исчезает.

**Решение:**

1. **Хук `kms` убран из HOOKS** — vc4 загружается через device tree ПОСЛЕ загрузки
   ```
   HOOKS=(base systemd autodetect modconf keyboard sd-vconsole block sd-encrypt filesystems)
   ```

2. **`rd.luks.options=cryptroot=tty1` в cmdline** — явно указывает TTY для ввода пароля

3. **`console=tty1`** (не `tty0`) — фиксированный VT, переживает переключение режимов

4. **Модули в initramfs:** `aes_ce_blk usbhid xhci_hcd` — AES-ускорение + USB-клавиатура

## SSH mode

Требует предварительно собранный `mkinitcpio-systemd-extras` из AUR.

```bash
BUILD_LUKS_UNLOCK_MODE="ssh"
BUILD_AUR_PKG_URL="https://example.com/mkinitcpio-systemd-extras.pkg.tar.zst"
```

В initramfs: `sd-network` получает IP по DHCP, `sd-tinyssh` запускает SSH-сервер.
Разблокировка: `ssh root@<ip>`, пароль = LUKS пароль.

## Telegram mode

```bash
BUILD_LUKS_UNLOCK_MODE="telegram"
BUILD_TELEGRAM_BOT_TOKEN="123:abc"
BUILD_TELEGRAM_CHAT_ID="456"
```

В initramfs: `sd-network` → DHCP → curl poll Telegram Bot API.
Пользователь отправляет пароль боту в Telegram — хук пытается разблокировать LUKS.

## Проверка после загрузки

```bash
cryptsetup status cryptroot
lsblk -f
dmsetup table
```

## Изменение пароля

```bash
cryptsetup luksChangeKey /dev/mmcblk0p2
```
