# arch-mcp-server: Техзадание на v0.10

## Обоснование

После v0.9.0 в rpi5-archlinux-image добавлены: LUKS-шифрование (3 режима разблокировки), nftables firewall, btrbk-бэкапы, native snapper rollback, journal-gatewayd, Telegram unlock в initramfs. Для удалённого управления этими компонентами через opencode нужны новые MCP-инструменты.

---

## 1. `manage_luks` — управление LUKS

### Описание
Проверка статуса, изменение пароля, добавление/удаление ключей, информация о LUKS-разделе.

### Actions
| Action | Параметры | Описание |
|--------|-----------|----------|
| `status` | — | `cryptsetup luksDump`, статус `/dev/mapper/cryptroot` |
| `change_password` | `device`, `old_pass`, `new_pass` | Смена пароля LUKS |
| `add_key` | `device`, `pass`, `key_file?` | Добавить ключ (файл или пароль) |
| `remove_key` | `device`, `pass`, `slot?` | Удалить ключ по слоту |
| `is_unlocked` | — | Проверить активен ли `/dev/mapper/cryptroot` |

### Приоритет: HIGH

---

## 2. `manage_firewall` — управление nftables

### Описание
Просмотр правил, добавление/удаление, проверка конфига.

### Actions
| Action | Параметры | Описание |
|--------|-----------|----------|
| `list_rules` | `chain?` | `nft list ruleset` или конкретная цепочка |
| `add_port` | `port`, `proto=tcp`, `interface?` | Добавить порт в INPUT (временное) |
| `remove_port` | `port`, `proto=tcp` | Удалить порт из INPUT |
| `validate` | — | `nft -c -f /etc/nftables.conf` — проверка синтаксиса |
| `reload` | — | `systemctl reload nftables` |

### Приоритет: HIGH

---

## 3. `manage_backup` — btrbk бэкапы

### Описание
Запуск, проверка статуса, история бэкапов через btrbk.

### Actions
| Action | Параметры | Описание |
|--------|-----------|----------|
| `run` | `config?`, `dry_run=false` | `btrbk run` с конфигом (или стандартный) |
| `list` | — | `btrbk list` — история бэкапов |
| `status` | — | Проверить наличие btrbk + конфиг |
| `restore_info` | `snapshot_id` | Информация для восстановления из снапшота |

### Приоритет: MEDIUM

---

## 4. `manage_snapper` — snapper rollback и снапшоты

### Описание
Расширенное управление snapper: rollback, сравнение, дифф файлов.

### Actions (дополнить существующий `manage_snapshots`)
| Action | Параметры | Описание |
|--------|-----------|----------|
| `diff` | `snap1`, `snap2`, `config=root` | `snapper diff` между двумя снапшотами |
| `rollback` | `snap_num`, `config=root` | Запуск `snapper -c root rollback` (native, требует `set-default @`)
| `rollback_dry` | `snap_num` | Показать что изменится без выполнения |
| `create_config` | `name`, `subvolume`, `timeline?` | `snapper create-config` для нового subvolume |

### Приоритет: HIGH

---

## 5. `manage_boot_config` — загрузочная конфигурация

### Описание
Чтение/запись config.txt, cmdline.txt, проверка boot-файлов.

### Actions
| Action | Параметры | Описание |
|--------|-----------|----------|
| `read_config` | — | `cat /boot/config.txt` |
| `read_cmdline` | — | `cat /boot/cmdline.txt` |
| `verify_boot` | — | Проверить наличие kernel8.img, initramfs, dtb, config.txt, cmdline.txt |
| `check_initramfs_hooks` | — | `lsinitcpio /boot/initramfs-linux.img \| grep -E 'boot-mount\|sd-encrypt\|telegram'` |
| `check_boot_order` | — | `rpi-eeprom-config \| grep BOOT_ORDER` |

### Приоритет: HIGH

---

## 6. `manage_recovery` — восстановление системы

### Описание
Инструменты для диагностики и восстановления после сбоев, работа с emergency mode.

### Actions
| Action | Параметры | Описание |
|--------|-----------|----------|
| `check_emergency` | — | Проверить, не в emergency ли система |
| `system_state` | — | `systemctl is-system-running`, failed units |
| `last_boot_issues` | — | Анализ прошлых загрузок на ошибки |
| `repair_fstab` | `dry_run=true` | Проверить UUID в fstab vs blkid |

### Приоритет: MEDIUM

---

## 7. `manage_hardware` — RPi5 железо

### Описание
Температура, частоты, throttling, EEPROM, NVMe.

### Actions
| Action | Параметры | Описание |
|--------|-----------|----------|
| `health` | — | Температура (vcgencmd), throttling, частоты |
| `eeprom_info` | — | `rpi-eeprom-config` — полный вывод |
| `eeprom_update` | `channel=default` | Обновление EEPROM с проверкой |
| `nvme_info` | — | `nvme list` + `nvme smart-log` |
| `benchmark_disk` | `path=/`, `size=1G` | `fio` бенчмарк диска |

### Приоритет: MEDIUM

---

## 8. `manage_telegram_unlock` — Telegram-разблокировка LUKS

### Описание
Проверка и настройка Telegram-бота для LUKS initramfs unlock.

### Actions
| Action | Параметры | Описание |
|--------|-----------|----------|
| `status` | — | Проверить наличие telegram-unlock хука в initramfs |
| `test_bot` | `token`, `chat_id` | `curl` к Bot API — проверить связь |
| `send_unlock` | `token`, `chat_id`, `password` | Отправить пароль через бота |

### Приоритет: LOW (специфично, редко используется)

---

## 9. `manage_journal_gateway` — journal-gatewayd

### Описание
Проверка статуса, тестовый запрос логов.

### Actions
| Action | Параметры | Описание |
|--------|-----------|----------|
| `status` | — | `systemctl status systemd-journal-gatewayd` |
| `query` | `filter?`, `boot?` | `curl http://127.0.0.1:19531/entries?...` |
| `recent_errors` | `boot=-1` | Ошибки и предупреждения из последней загрузки |

### Приоритет: LOW

---

## Итого

| # | Инструмент | Приоритет | Сложность |
|---|-----------|-----------|-----------|
| 1 | `manage_luks` | HIGH | Средняя |
| 2 | `manage_firewall` | HIGH | Низкая |
| 3 | `manage_snapper` (расширение) | HIGH | Средняя |
| 4 | `manage_boot_config` | HIGH | Низкая |
| 5 | `manage_backup` | MEDIUM | Средняя |
| 6 | `manage_recovery` | MEDIUM | Средняя |
| 7 | `manage_hardware` | MEDIUM | Средняя |
| 8 | `manage_telegram_unlock` | LOW | Низкая |
| 9 | `manage_journal_gateway` | LOW | Низкая |

**Всего: 9 новых/расширенных инструментов.**

## Текущие возможности (v0.9.0, 28 инструментов)

Уже есть: `get_system_info`, `diagnose_system`, `run_system_health_check`, `analyze_storage`, `get_official_package_info`, `check_updates_dry_run`, `install_package_secure`, `remove_packages`, `query_file_ownership`, `query_package_history`, `verify_package_integrity`, `manage_install_reason`, `manage_orphans`, `manage_groups`, `search_aur`, `audit_package_security`, `analyze_pacman_conf`, `analyze_makepkg_conf`, `optimize_mirrors`, `fetch_news`, `check_database_freshness`, `search_archwiki`, `check_failed_services`, `get_boot_logs`.
