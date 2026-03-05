# 07 - Component: Installer and Packaging

## Objective
Replace Magisk module installation/update/uninstall flow with Linux package/deploy logic.

## Baseline Installer Functions
Current `box-reference/box/customize.sh` provides:
- install payload
- preserve old configs/binaries
- optional interactive downloads
- set permissions
- install boot hook

## Linux Packaging Targets
Provide at least one of:
1. Debian package (`.deb`)
2. RPM package (`.rpm`)
3. tarball installer (`install.sh`) fallback

## Package Contents
- `/usr/lib/box/` scripts
- `/etc/box/` default configs
- `/var/lib/box/` managed artifacts
- `/usr/bin/boxctl` CLI
- systemd unit/timer files

## Install Script Responsibilities
1. create service user/group (or root mode with capabilities)
2. create directories and ownership
3. install config templates without clobbering local overrides
4. run migration for legacy config keys
5. enable/start selected units

## Upgrade Strategy
- preserve `/etc/box/*.toml`
- preserve `/var/lib/box/bin/*` if newer than packaged versions
- write migration report at `/var/log/box/migration.log`

## Uninstall Strategy
Equivalent of `box-reference/box/uninstall.sh` but safe:
- stop and disable all units
- remove generated firewall/routing state
- optionally keep config/data (`--purge` removes all)

## Non-Interactive First
Do not require interactive key events (volume key flow in `box-reference/box/customize.sh` is Android-only).
Use explicit CLI flags instead:
- `boxctl update --bootstrap`
- `boxctl install --with-core sing-box`

## Install Transaction Steps
1. precheck root + dependencies
2. create users/groups and directories
3. deploy binaries/scripts
4. install config templates if missing
5. migrate old config if present
6. daemon-reload + enable units
7. optional bootstrap update (`boxctl update kernel`)
8. health check

On failure, rollback to previous known package state where possible.

## Post-Install Verification
- `boxctl service status`
- `boxctl firewall status`
- `boxctl update check` (dry-run)
- ensure required dirs exist with expected permissions

## Package Upgrade Hooks
- `preinst`: stop services safely
- `postinst`: run migration + restart
- `prerm`: disable timers/services
- `postrm`: optional purge
