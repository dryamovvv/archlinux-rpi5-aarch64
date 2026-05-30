# homectl integration

> **STATUS: Rolled back (v0.5.0).** `homectl create --storage=subvolume` proved too slow on RPi5
> (10+ min on Ed25519 key generation) and too fragile (hashedPassword format issues, interactive
> hangs in headless/QEMU). User creation was removed from firstboot entirely — only root SSH is
> configured at boot time. Use `useradd` manually after first boot.

## What was attempted

Replace `useradd` with `homectl --storage=subvolume` in the RPi5 image build pipeline.
Three-tier user creation at first boot:

1. **Pre-configured** — `user.json` generated at build time, `homectl create --identity`
2. **Interactive** — no `user.json`, `homectl firstboot` wizard on TTY
3. **Headless fallback** — no TTY, `useradd` + `chpasswd` (for QEMU/CI)

## Why it was rolled back

1. **Ed25519 key generation** on homectl create took 10+ minutes on RPi5 (`rng-tools` installed
   but homed uses its own RNG path). Second create attempt was equally slow.
2. **hashedPassword format** changed between systemd versions. We tried `["$6$..."]` and
   `[["password", "", {"crypt": {"salted": "$6$..."}}]]` — both formats failed silently with
   homectl falling to interactive mode.
3. **Interactive fallback (`homectl firstboot`)** hung in headless QEMU with no TTY.
4. **QEMU testing** became impossible — user creation at boot always blocked on TTY or RNG.

## What we kept

- **Snapper subvolume snapshotting** — tested 3 times (rollback + reboot), always successful.
  Snapper configs (root + user_home) are created at build time.
- **Rollback script** (`/usr/local/lib/rpi5-archlinux/rollback.sh`) — can roll back to any snapshot.
- **BTRFS subvolume layout** — 8 subvolumes unchanged.
- **MCP server** — embedded at build time, auto-starts via systemd.

## Future

`homectl` may be revisited when systemd-homed matures on Arch ARM. For now, user creation
is manual after first boot via root SSH:

```bash
useradd -m -G wheel user
passwd user
# Or if systemd-homed is desired:
homectl create --storage=subvolume user
```

## Implementation files (historical)

| File | Change |
|------|--------|
| `src/conf/systemd/firstboot.sh` | Only swapfile creation (no homectl, no user creation) |
| `src/lib/bootstrap.sh` `bootstrap::firstboot_service()` | Takes only target, no user args, no `user.json` generation |
| `src/conf/systemd/rpi5-firstboot.service` | `After=systemd-firstboot.service` only (no homed dep) |
| `src/lib/modules/services.sh` | No `systemd-homed.service` enablement |
| `build.conf.example` | `BUILD_USER_NAME`, `BUILD_USER_PASSWORD`, `BUILD_SHRINK_IMAGE` removed |

## Key integration: snapper + btrfs

homed creates `~/.identity` files in the user's home subvolume. When homectl takes a snapshot:

- The user's home (e.g., `/home/user.homedir`) is a **btrfs subvolume** (nested inside `@home`).
- Snapper's timeline snapshots on `user_home` config capture the user's home subvolume state.
- The `@home` subvolume itself is NOT snapshotted by the root config (different mount point).
- Root snapper uses a separate top-level subvolume `@snapshots`. No recursive snapshot pollution.

### Snapper config for user home

`snapper -c user_home create-config /home/user.homedir`: The homectl subvolume is created by homed at first boot (a nested subvolume inside `@home`). Snapper creates a `.snapshots/` subvolume inside the user's home subvolume for user-level rollbacks.

### Logind configuration

Arch Linux defaults to `KillUserProcesses=yes` (since systemd v246). When SSH disconnects, systemd kills
the session scope — including tmux server and all processes inside it.

Tested on the target system: `#KillUserProcesses=no` in `/etc/systemd/logind.conf` (commented out = default `yes`),
no linger files in `/var/lib/systemd/linger/`. Without linger, tmux dies on SSH disconnect. With linger, it survives.

The per-user approach is better than `KillUserProcesses=no` (system-wide, weaker security). The firstboot script
enables linger for the created user automatically.

### Service dependencies

```ini
# rpi5-firstboot.service — systemd-homed dependency (removed in v0.5.0)
After=systemd-firstboot.service systemd-homed.service
Wants=systemd-homed.service
```
