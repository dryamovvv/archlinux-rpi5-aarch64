# mkinitcpio-systemd-tool

Пакет из официального репозитория Arch Linux (extra): `pacman -S mkinitcpio-systemd-tool`
Upstream: https://github.com/random-archer/mkinitcpio-systemd-tool

## Архитектура

Один хук `systemd-tool` вместо нескольких `sd-*`. Автоматически обнаруживает включённые
systemd unit'ы в `/etc/systemd/system/`, содержащие маркер `/etc/initrd-release`, и
провижионит их зависимости (бинарники, файлы, модули ядра) в initramfs через секцию
`[X-SystemdTool]` в юнитах.

```ini
HOOKS=(base systemd autodetect ... systemd-tool)
# sd-encrypt, sd-network, sd-tinyssh НЕ нужны — убираются
```

## Service unit'ы и их назначение

### LUKS/шифрование — `initrd-cryptsetup.{path,service}`

- Замена `sd-encrypt`. Работает через `systemd-cryptsetup-generator` и `/etc/crypttab`
- Использует `initrd-shell.sh` как password agent (query → reply через systemd ask-password)
- Автоматически провижионит: `dm-crypt`, `dm-integrity`, `/crypto/` модули, cryptsetup udev rules
- Может работать с LUKS2, требует ручной `systemctl enable initrd-cryptsetup.path`

### SSH-доступ — `initrd-tinysshd.service` или `initrd-dropbear.service`

- **tinysshd** (ed25519 только): конвертирует openssh ключи через `initrd-build.sh`,
  использует `busybox tcpsvd`
- **dropbear** (rsa/ecdsa): альтернатива с поддержкой root-login опционально
- Оба стартуют после `initrd-network.service`, до `cryptsetup-pre.target`
- Взаимоисключающие (включить можно только один)

### Сеть — `initrd-network.service`

- Поднимает сетевые интерфейсы (ip link set up) и запускает `systemd-networkd` + `systemd-resolved`
- DHCPv4 по умолчанию через `initrd-network.network`
- Провижионит /etc/systemd/network/ + модули `/drivers/net/`

### Shell/password agent — `initrd-shell.service` + `initrd-shell.sh`

Центральный скрипт (~350 строк ash), работает в 3 режимах:

- **service (crypto_terminal)** — password agent для LUKS через TTY
- **service (crypto_plymouth)** — password agent через plymouth
- **console (ssh/tty)** — интерактивное меню: `a) secret agent | s) shell | r) reboot | q) quit`

Логирует всё через `systemd-cat` → `journalctl -b -t shell`. Обрабатывает HUP/INT/QUIT/TSTP/TERM.
Автоматически подхватывает `authorized_keys` для SSH.

### Отладка — `initrd-debug-progs.service` + `initrd-debug-shell.service`

- **progs**: strace, cryptsetup, journalctl, less, swapon/off, midnight commander + terminfo
- **shell**: отдельный shell на tty8 (`/dev/tty8`) с `Restart=always`

### Emergency — `initrd-emergency.{service,target}`

- Заменяет стандартный `emergency.target` на свой, который не теряет сеть (важно для SSH-режима)
- Открывает `initrd-debug-shell.service` вместе с собой
- Даёт panic shell с возможностью продолжить загрузку

### NTP — `initrd-ntpd.service`

- `busybox ntpd -n -q` (однократная синхронизация) после `initrd-network.service`, до
  `cryptsetup-pre.target`
- Конфиг из `/etc/mkinitcpio-systemd-tool/config/ntp.conf`

### Firewall — `initrd-nftables.service`

- nftables в initramfs, запускается **до** `initrd-network.service`
- Конфиг из `/etc/mkinitcpio-systemd-tool/config/initrd-nftables.conf`
- Провижионит модули `/netfilter/nft_*` и `nf_tables*`

### Plymouth — `initrd-plymouth.{path,service}`

- Графический password agent для LUKS вместо TTY
- Взаимоисключающий с `initrd-cryptsetup.path` — выбор через kernel cmdline `plymouth.enable=0/1`
- Требует `sd-plymouth` в HOOKS (из AUR plymouth)

### Sysroot — `initrd-sysroot-mount.service`

- Binds to `sysroot.mount`, активирует `initrd-root-fs.target`
- Фикс для корректного switch-root

### USB HCD — `initrd-util-usb-hcd.service`

- Принудительная загрузка `xhci_hcd`, `xhci_pci`, `ehci_hcd`, `ehci_pci`, `hid_generic`
- - modprobe.d конфиг для порядка загрузки (фикс USB-клавиатур)

### PC Beeper — `initrd-util-pc-beep.service`

- Три коротких звуковых сигнала при старте initramfs (через `beep` + `pcspkr`)

## Система провижионинга (секция `[X-SystemdTool]`)

Каждый юнит декларирует что нужно включить в initramfs:

| Директива                                  | Назначение                                              |
| ------------------------------------------ | ------------------------------------------------------- |
| `InitrdBinary=/usr/bin/foo`                | Включить бинарник в initramfs                           |
| `InitrdPath=/etc/foo`                      | Включить файл/директорию                                |
| `InitrdPath=/target source=/host mode=700` | Скопировать с переименованием/правами                   |
| `InitrdPath=/target/ create=yes`           | Создать пустую директорию                               |
| `InitrdPath=/target/ glob=*.example`       | Отфильтровать содержимое                                |
| `InitrdPath=... optional=yes`              | Не падать, если файла нет                               |
| `InitrdLink=/link target=/target`          | Создать symlink                                         |
| `InitrdBuild=./script.sh command=fn`       | Запустить скрипт сборки                                 |
| `InitrdCall=add_module foo`                | Вызвать mkinitcpio API функцию                          |
| `InitrdUnit=...`                           | Рекурсивно включить другой юнит                         |
| `replace=yes`                              | Перезаписать существующий файл                          |
| `source=...`                               | Источник для копирования (по умолчанию путь назначения) |

## Конфигурация

```
/etc/mkinitcpio-systemd-tool/
├── mkinitcpio-systemd-tool.conf   # openssh_key_convert, preserve_additional_accounts
├── config/
│   ├── crypttab                   # /etc/crypttab для initramfs
│   ├── fstab                      # /etc/fstab для initramfs
│   ├── ntp.conf                   # для initrd-ntpd.service
│   ├── initrd-nftables.conf       # nftables ruleset
│   ├── initrd-util-usb-hcd.conf   # modprobe.d порядок USB
│   └── authorized_keys            # SSH ключи для initrd
└── network/
    └── initrd-network.network     # systemd-networkd конфиг
```

## Сравнение с текущим проектом

| Возможность       | `systemd-tool`                            | Текущий проект                                    |
| ----------------- | ----------------------------------------- | ------------------------------------------------- |
| LUKS              | `initrd-cryptsetup` (свой password agent) | `sd-encrypt` + кастомный `telegram-unlock`        |
| SSH               | `initrd-tinysshd` или `initrd-dropbear`   | `sd-tinyssh` (из `mkinitcpio-systemd-extras` AUR) |
| Сеть              | `initrd-network`                          | `sd-network` (из AUR)                             |
| Отладка в initrd  | ✅ `initrd-debug-shell`, mc, strace, tty8 | ❌                                                |
| Emergency с сетью | ✅ `initrd-emergency` (не теряет SSH)     | ❌                                                |
| NTP в initrd      | ✅ `initrd-ntpd`                          | ❌                                                |
| Firewall в initrd | ✅ `initrd-nftables`                      | ❌ (nftables только в основной системе)           |
| Plymouth          | ✅ `initrd-plymouth`                      | ❌                                                |
| USB HCD фикс      | ✅ `initrd-util-usb-hcd`                  | ❌ (модули в MODULES, но без modprobe.d)          |
| PC beep           | ✅ `initrd-util-pc-beep`                  | ❌                                                |
| Telegram unlock   | ❌ (кастомный)                            | ✅                                                |
| Источник пакета   | Официальный extra (pacman)                | AUR (mkinitcpio-systemd-extras) + кастомный хук   |
