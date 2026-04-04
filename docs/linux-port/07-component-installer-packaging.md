# 07 - Component: Installer and Packaging

## Objective

Deliver Linux-native packaging/install lifecycle for repo-root implementation (`cmd/`, `lib/`, `etc/`, `systemd/`, `tests/`) with safe upgrade and uninstall semantics.

## Arch Packaging (Implemented)

Package assets:
- `packaging/arch/PKGBUILD`
- `packaging/arch/box4linux.install`

Install paths:
- `/usr/bin/boxctl`
- `/usr/lib/box4linux/cmd/boxctl`
- `/usr/lib/box4linux/lib/...`
- `/etc/box/box.toml`
- `/usr/lib/systemd/system/box.service`
- `/usr/lib/systemd/system/box-firewall.service`
- `/usr/share/doc/box4linux/`

Build/install:
1. `cd packaging/arch`
2. `makepkg --noconfirm -f`
3. `sudo pacman -U ./box4linux-*.pkg.tar.zst`

## Config Upgrade Behavior

- `/etc/box/box.toml` is registered as a backup config in PKGBUILD.
- Upgrades do not clobber local edits.
- New upstream defaults are provided as `.pacnew` when necessary.

## Unit Lifecycle Safety

Helper script:
- `packaging/scripts/systemd-lifecycle.sh`
- Installed to `/usr/share/doc/box4linux/systemd-lifecycle.sh`

Safe operations:
- `enable`: daemon-reload, enable `box.service` and `box-firewall.service`, enable `box-policy.service` only when `[policy].enabled = true`, enable `box-update-all.timer` as the default scheduled updater timer, then start service
- `disable`: stop/disable service, firewall, policy, and shipped updater units/timers, then daemon-reload
- `restart`: restart service/policy units without touching config/data

Pacman hook behavior (`box4linux.install`):
- `post_install`/`post_upgrade`: daemon-reload, operator guidance
- `pre_remove`: best-effort `boxctl policy disable`, `boxctl firewall disable`, `boxctl service stop`, disable all shipped units/timers
- `post_remove`: leave config/data unless manually purged

## CI/Release Automation

Workflow:
- `.github/workflows/ci.yml`

On push/PR:
- shell syntax checks (`bash -n`)
- shellcheck (when available)
- `./tests/integration/test_phase2.sh`
- `sudo ./tests/integration/test_real_kernel.sh` (skip-capable)
- Arch package build in container
- package smoke test (`./tests/integration/test_arch_package_smoke.sh`)

On tag (`v*`):
- publish built `.pkg.tar.*` artifact to GitHub Release

## Smoke Validation

Script:
- `tests/integration/test_arch_package_smoke.sh`

What it verifies:
1. package can be extracted into a clean temp root
2. installed paths/files exist
3. `boxctl service status --json` works in installed layout
4. `boxctl firewall status --json` works in installed layout
5. `boxctl firewall dry-run` prints planned operations
6. `systemd-analyze verify` runs when available

## Uninstall / Rollback Notes

- Default uninstall: `sudo pacman -R box4linux`
- Keeps operator-managed data/config backups by default.
- Explicit purge is manual and should be deliberate:
  - `sudo rm -rf /etc/box /var/lib/box /run/box /var/log/box`
