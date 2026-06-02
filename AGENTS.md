# AGENTS.md — rpi5-archlinux-image

Bash-скрипт для сборки Arch Linux ARM образа под Raspberry Pi 5.
Полная шифровка LUKS, btrfs + snapper rollback, ZRAM + swap.

## Быстрый старт

```bash
cp build.conf.example build.conf
./scripts/package.sh                                    # упаковать в dist/bin/
bash -n src/lib/*.sh src/lib/core/*.sh src/lib/modules/*.sh tests/*.sh
for t in tests/*.sh; do bash "$t" || echo "FAIL: $t"; done
./dist/bin/rpi5-archlinux-image validate
```

## Команды

```bash
./dist/bin/rpi5-archlinux-image build      # собрать RPi5 образ
./dist/bin/rpi5-archlinux-image build-qemu # собрать QEMU образ (тест на x86_64)
./dist/bin/rpi5-archlinux-image qemu-run   # запустить QEMU
./dist/bin/rpi5-archlinux-image validate   # проверить build.conf
./dist/bin/rpi5-archlinux-image list-steps # показать pipeline
```

## Файловая карта

| Путь | Назначение |
|------|-----------|
| `src/main.sh` | CLI entrypoint |
| `src/lib/bootstrap.sh` | in-target настройка (firstboot, fstab, mkinitcpio, network, sshd, snapper, swap, mcp_server) |
| `src/lib/disk.sh` | loop-устройства, разделы, LUKS, btrfs subvolumes |
| `src/lib/core/` | config, runner, steps, modules, assets |
| `src/lib/modules/` | build-модули: disk_image, base_system, boot_config, services |
| `src/conf/boot/` | config.txt, cmdline.txt |
| `src/conf/systemd/` | firstboot unit, zram-generator.conf, arch-ops-mcp.service |
| `src/conf/pacman/` | pacman-arm.conf (aria2c, стабильные зеркала) |
| `src/conf/nftables/` | nftables.conf (firewall) |
| `src/conf/fail2ban/` | sshd jail |
| `src/conf/initcpio/` | telegram-unlock hook/install для LUKS |
| `build.conf.example` | шаблон конфига |
| `scripts/package.sh` | упаковщик в один файл |
| `tests/` | 13 shell-тестов |
| `os_list.json` | для Network Install (RPi Imager) |
| `docs/` | документация по всем аспектам |

## Ключевые правила

1. **Сборка на нативном aarch64 (RPi5)** — qemu-user-static на x86_64 ломает `unshare` в pacstrap
2. **Не удаляй `config.txt`** — он статический, правки напрямую
3. **Пароли не хранить в коде** — `BUILD_ROOT_PASSWORD` и `BUILD_LUKS_PASSWORD` в `build.conf`, пользователей создавать вручную после первой загрузки (`useradd -m -G wheel user`)
4. **Отступ 4 пробела** в .sh, функции с namespace `module::function`
5. **Пуш в `dev`** триггерит ARM-сборку в CI. **В `main` без разрешения НЕ пушить.**
   ```bash
   git branch -f dev main && git push origin dev --force
   ```
6. **Релиз:** когда пользователь говорит «релиз» или «выпускаем» — коммит, тег `v*`, пуш:
   ```bash
   git tag v0.13.0 && git push origin main --tags
   ```

## LUKS + btrfs + snapper rollback

### Шифрование диска

Весь root-раздел шифруется через LUKS2. Три режима разблокировки:

| Режим | Параметр | Как работает |
|-------|----------|-------------|
| `keyboard` | `BUILD_LUKS_UNLOCK_MODE=keyboard` | Пароль вводится с HDMI/USB клавиатуры на tty1 |
| `ssh` | `BUILD_LUKS_UNLOCK_MODE=ssh` | tinysshd в initramfs, разблокировка по SSH |
| `telegram` | `BUILD_LUKS_UNLOCK_MODE=telegram` | Poll Telegram Bot API для пароля |

**Важно для keyboard mode:**
- Хук `kms` убран из mkinitcpio — на RPi5 `vc4-kms-v3d` сбрасывает framebuffer в initramfs, пряча LUKS prompt
- `rd.luks.options=cryptroot=tty1` в cmdline — явный TTY для sd-encrypt
- Модули в initramfs: `aes_ce_blk usbhid xhci_hcd` (AES-ускорение RPi5 + USB-клава)
- `console=tty1` (не `tty0`) — фиксированный VT, переживает KMS reset

### Snapper rollback (openSUSE layout)

Снапшоты и rollback работают «из коробки»:

```bash
# Создать снапшот
snapper -c root create -d "before-upgrade"

# Откатиться (после reboot система в выбранном снапшоте)
snapper -c root rollback 5
reboot
```

**Архитектура:**
- `.snapshots` внутри `@` (не на уровне btrfs root) — openSUSE-way
- fstab без `subvol=@` для `/` — система грузится из default subvolume
- `snapper create-config` + `snapper create --read-write` в chroot создают начальный RW-снапшот
- Rollback меняет default subvolume через `btrfs subvolume set-default`

**Subvolume layout:**
```
subvolid=5 (btrfs root)
├── @              # основной subvolume
│   └── .snapshots # снапшоты snapper (внутри @)
│       └── 1/snapshot  # начальный RW-снапшот (= default)
├── @home          # /home
├── @swap          # swap-файл (независим от rollback)
├── @var_log       # /var/log
├── @var_cache     # /var/cache
└── @var_tmp       # /var/tmp
```

### ZRAM + swap

Двухуровневый своп:
1. **ZRAM** (zstd, приоритетный) — `systemd-zram-generator`, размер через `BUILD_ZRAM_SIZE` (в МБ!)
2. **Btrfs swapfile** (вторичный) — на `@swap` subvolume, создаётся при первой загрузке

Swap-файл на отдельном subvolume не затрагивается снапшотами и rollback.

### First boot flow

```
sysinit.target
  └─ systemd-firstboot.service      # hostname, timezone, root password
  └─ systemd-repart.service         # расширяет root-раздел
  └─ systemd-growfs-root.service    # расширяет btrfs

multi-user.target
  └─ rpi5-firstboot.service:
       1. cryptsetup resize cryptroot
       2. btrfs filesystem resize max /
       3. btrfs filesystem mkswapfile --size 16G /swap/swapfile
       4. swapon --fixpgsz /swap/swapfile
```

## /arch_audit

Comprehensive system audit using all MCP tools. Type `/arch_audit` to get a structured report: system overview, health, packages, configs, mirrors, news, orphans, boot logs. Useful after new image releases.

## CI/CD

- **x86 (всегда):** bash -n + shellcheck + 10 тестов в CI
- **ARM (`dev`):** полная сборка + валидация boot-файлов
- **Release (теги `v*`):** ARM сборка → .img.xz + os_list.json → GitHub Release

## Границы

- `src/conf/boot/config.txt` и `cmdline.txt` — точечные правки по согласованию
- Не менять формат `build.conf` без обновления `config::validate`
- Не добавлять пароли/секреты в репо
- HOOKS без `kms` — vc4-kms-v3d грузится после загрузки через device tree

## MCP arch-linux (remote HTTP через arch-ops-server)

23 инструмента для управления RPi5 Arch Linux через opencode.

Сервер: [dryamovvv/arch-mcp](https://github.com/dryamovvv/arch-mcp) (форк с Bearer auth), systemd unit `arch-ops-mcp.service`, ключ в `~/.config/opencode/api-key`. MCP-сервер встраивается в образ автоматически (`bootstrap::mcp_server()`). API-ключ → `<image>.mcp-key`.

## Бэкапы (btrbk)

Инкрементальные бэкапы через btrbk. Сценарии в `docs/backup.md`:
- **local** — на внешний диск (самый простой)
- **raw_target** — холодное хранение (образ диска)
- **SSH** — на удалённый хост
- **full BTRFS remote** — btrfs send/receive на удалённый btrfs

```bash
# Быстрый локальный бэкап
btrbk -c /etc/btrbk/btrbk.conf run

# Восстановление
mount /dev/backup-disk /mnt/backup
btrfs send /mnt/backup/@.20260602 | btrfs receive /mnt/restore/
```

## Подробные доки

- [build-pipeline.md](docs/build-pipeline.md) — 12 шагов сборки
- [configuration.md](docs/configuration.md) — build.conf, config.txt, cmdline.txt
- [first-boot.md](docs/first-boot.md) — firstboot flow, swap, resize
- [arch-mcp.md](docs/arch-mcp.md) — arch-ops-server (HTTP + Bearer auth)
- [backup.md](docs/backup.md) — btrbk сценарии и восстановление
- [homectl.md](docs/homectl.md) — откат на useradd (v0.5.0)
- [qemu-testing.md](docs/qemu-testing.md) — QEMU тестирование
