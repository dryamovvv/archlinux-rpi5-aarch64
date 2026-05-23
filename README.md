# rpi5-archlinux
Raspberry Pi 5 Arch Linux image build script.

## Structure
- `src/main.sh` — исходный CLI entrypoint сборки.
- `src/lib/core/` — CLI/runtime framework: config loading, module loading, step registry, runner, dependency checks.
- `src/lib/modules/` — build-модули, которые регистрируют шаги pipeline.
- `src/lib/` — низкоуровневые Bash-модули (`disk.sh`, `bootstrap.sh`, `log.sh`).
- `scripts/package.sh` — собирает один исполняемый файл в `dist/bin/` и создает `dist/images/`.
- `dist/bin/rpi5-archlinux-image` — generated packaged CLI для запуска сборки образа.
- `dist/images/` — generated каталог для локального `archlinuxarm-rpi5-aarch64.img` и release artifacts вида `archlinuxarm-rpi5-aarch64-${TAG}.img.xz`; каталог `dist/` не коммитится.
- `build.conf.example` — шаблон build-конфигурации.
- `build.conf` — локальный ignored config; `scripts/package.sh` требует этот файл и embedded-встраивает его значения в `dist/bin/rpi5-archlinux-image` как default config.
- `src/conf/pacman/` — active pacman-конфигурация, embedded в packaged builder и реально используемая `pacstrap`.
- `src/conf/boot/` — active boot-файлы, embedded в packaged builder и записываемые в boot partition.
- `src/conf/systemd/` — active systemd unit для first-boot provisioning, embedded в packaged builder и записываемый в root filesystem.

## Usage
```bash
cp build.conf.example build.conf
./scripts/package.sh
./dist/bin/rpi5-archlinux-image help
./dist/bin/rpi5-archlinux-image list-steps
./dist/bin/rpi5-archlinux-image validate
./dist/bin/rpi5-archlinux-image build
./dist/bin/rpi5-archlinux-image --config ./my-build.conf build
```

## Validation
```bash
bash -n scripts/*.sh src/main.sh src/lib/*.sh src/lib/core/*.sh src/lib/modules/*.sh tests/*.sh
shellcheck scripts/*.sh src/main.sh src/lib/*.sh src/lib/core/*.sh src/lib/modules/*.sh tests/*.sh
./scripts/package.sh
./dist/bin/rpi5-archlinux-image validate
```

## GitHub Actions
- `.github/workflows/ci.yml` проверяет shell-скрипты и smoke-тесты.
- `.github/workflows/release.yml` запускается на тегах `v*`, собирает образ на native `arm64` runner и публикует `archlinuxarm-rpi5-aarch64-${TAG}.img.xz` вместе с `archlinuxarm-rpi5-aarch64-${TAG}.img.xz.sha256`.
- Локальный сценарий релиза:
```bash
git tag v0.1.0
git push origin v0.1.0
```

## GitHub Actions Build Environment
- Release workflow использует native `arm64` runner `ubuntu-24.04-arm`.
- Build dependencies ставятся напрямую через `apt`, после чего workflow запускает `./dist/bin/rpi5-archlinux-image build` без собственного builder-контейнера. Builder сам повышает права через `sudo` только для привилегированных команд. Образ и release artifacts создаются в `dist/images/`.
- `pacstrap` и post-install hooks выполняются без `qemu-user-static` и `binfmt`.
- Основная пост-конфигурация вынесена в `systemd-firstboot` и `rpi5-firstboot.service`, чтобы минимизировать build-time `arch-chroot`.
