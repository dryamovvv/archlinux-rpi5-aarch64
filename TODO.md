# TODO: Новая архитектура initramfs на базе mkinitcpio-systemd-tool

На основе анализа `docs/mkinitcpio-systemd-tool.md` нужно спроектировать новую
архитектуру initramfs для проекта. Текущая система использует комбинацию
`sd-encrypt` + `mkinitcpio-systemd-extras` (AUR) + кастомный `telegram-unlock` хук.

## Что нужно спроектировать

### 1. HOOKS и замена sd-\*

- Переход с `sd-encrypt sd-network sd-tinyssh` на единый `systemd-tool`
- Определить полный список HOOKS после миграции
- Убрать зависимость от `mkinitcpio-systemd-extras` (AUR)

### 2. Telegram unlock поверх `initrd-cryptsetup`

- Кастомный `telegram-unlock` хук сейчас завязан на `sd-network` и `sd-encrypt`
- Как переписать его под архитектуру `initrd-cryptsetup.path`?
- Либо как отдельный `initrd-telegram.service` со своим `[X-SystemdTool]`
- Как именно Telegram бот будет отвечать на password request systemd?

### 3. Какие новые unit'ы включить

- `initrd-emergency` — чтобы SSH не умирал при ошибке LUKS
- `initrd-debug-shell` — shell на tty8
- `initrd-debug-progs` — mc, strace в initrd
- `initrd-ntpd` — синхронизация времени (важно для Telegram)
- `initrd-nftables` — firewall в initramfs
- `initrd-util-usb-hcd` — USB HCD fix (сейчас модули в MODULES, но без modprobe.d)
- `initrd-util-pc-beep` — аудио-индикация загрузки

### 4. Конфигурация

- `/etc/mkinitcpio-systemd-tool/config/crypttab` — перенос параметров LUKS
- `/etc/mkinitcpio-systemd-tool/config/fstab` — fstab для initramfs
- `/etc/mkinitcpio-systemd-tool/config/authorized_keys` — SSH ключи
- `/etc/mkinitcpio-systemd-tool/config/initrd-nftables.conf` — nftables
- `/etc/mkinitcpio-systemd-tool/config/ntp.conf` — NTP
- `/etc/mkinitcpio-systemd-tool/mkinitcpio-systemd-tool.conf` — openssh_key_convert, preserve_additional_accounts

### 5. build.conf

- Новые переменные для управления unit'ами (какие включать/отключать)
- `BUILD_INITRD_DEBUG_SHELL`, `BUILD_INITRD_NTP`, `BUILD_INITRD_NFTABLES`, etc.
- Переименование/удаление `BUILD_AUR_PKG_URL` (больше не нужен)

### 6. bootstrap.sh

- Установка `mkinitcpio-systemd-tool` вместо `mkinitcpio-systemd-extras`
- `bootstrap::mkinitcpio_conf()` — новый алгоритм мутации HOOKS
- `bootstrap::systemd_tool_config()` — новая функция генерации конфигов
- `bootstrap::enable_initrd_units()` — включение нужных `.path`/`.service`

### 7. Миграция telegram-unlock

- Вариант А: `initrd-telegram.service` с собственным `[X-SystemdTool]`
- Вариант Б: модификация `initrd-shell.sh` для поддержки Telegram как источника пароля
- Вариант В: интеграция напрямую в `initrd-cryptsetup.service` через ExecStartPre

### 8. Тесты

- Обновить тесты HOOKS в `tests/`
- Тест генерации конфигов
- Тест включения unit'ов

### 9. Документация

- Обновить `docs/luks.md`
- Обновить `docs/configuration.md`
- Дополнить AGENTS.md
