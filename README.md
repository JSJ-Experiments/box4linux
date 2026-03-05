# box4linux workspace

Linux-native control plane lives in:
- `cmd/boxctl`
- `lib/common.sh`
- `lib/config.sh`
- `lib/supervisor/`
- `lib/firewall/`
- `systemd/`
- `tests/integration/`
- `packaging/arch/`

Android reference artifacts are kept untouched in `box-reference/`.

## Quick run (dev)

1. Use repo-local fallback config at `etc/box/box.toml` (auto-used when `/etc/box/box.toml` is missing).
   - If `BOX_CONFIG_FILE` is explicitly set, it must exist; commands fail fast instead of falling back.
2. Run status commands:
   - `./cmd/boxctl service status`
   - `./cmd/boxctl service status --json`
   - `./cmd/boxctl firewall status`
   - `./cmd/boxctl firewall status --json`
3. Run privileged actions as root:
   - `sudo ./cmd/boxctl service start|stop|restart`
   - `sudo ./cmd/boxctl firewall enable|disable|renew`
   - `./cmd/boxctl firewall dry-run`
4. Run integration checks:
   - `./tests/integration/test_phase2.sh`
   - `sudo ./tests/integration/test_real_kernel.sh`

## Arch Package Build/Install

Build package from repo root:
- `cd packaging/arch && makepkg --noconfirm -f`

Install package:
- `sudo pacman -U ./box4linux-*.pkg.tar.zst`

Installed layout:
- `/usr/bin/boxctl`
- `/usr/lib/box4linux/cmd/boxctl`
- `/usr/lib/box4linux/lib/...`
- `/etc/box/box.toml`
- `/usr/lib/systemd/system/box.service`
- `/usr/lib/systemd/system/box-firewall.service`
- `/usr/share/doc/box4linux/`

Config upgrade behavior:
- Package marks `/etc/box/box.toml` as backup config.
- Local edits are preserved across upgrades.
- New template versions land as `.pacnew` when needed.

## Service Lifecycle (Packaged Install)

Use helper script from package docs:
- `sudo /usr/share/doc/box4linux/systemd-lifecycle.sh enable`
- `sudo /usr/share/doc/box4linux/systemd-lifecycle.sh status`
- `sudo /usr/share/doc/box4linux/systemd-lifecycle.sh disable`

Manual equivalent:
- `sudo systemctl daemon-reload`
- `sudo systemctl enable --now box.service box-firewall.service`
- `sudo systemctl disable --now box-firewall.service box.service`

## Packaged Operational Quickstart

1. Verify command and units:
   - `boxctl service status --json`
   - `boxctl firewall status --json`
2. Preview firewall operations:
   - `boxctl firewall dry-run`
3. Start runtime:
   - `sudo systemctl start box.service`
4. Renew firewall policy safely:
   - `sudo systemctl reload box-firewall.service`

## CI/Release Flow

Workflow file: `.github/workflows/ci.yml`

On push/PR:
- `bash -n` checks on shell scripts
- `shellcheck` when available
- mock integration: `./tests/integration/test_phase2.sh`
- privileged integration: `sudo ./tests/integration/test_real_kernel.sh` (suite prints `SKIP` when capabilities/tooling are unavailable)
- Arch package build in Arch container
- package smoke test: `./tests/integration/test_arch_package_smoke.sh <pkg>`

On tags (`v*`):
- built package artifact is published to GitHub Releases

## Phase 3 Notes

- Supported cores: `mihomo`, `sing-box`
- Runtime overlays rendered under `/run/box/rendered` (or dev fallback)
- Firewall backends:
  - `iptables` (mature path)
  - `nftables` (MVP parity)
- Supported modes on both backends: `tun`, `tproxy`, `redirect`, `mixed`, `enhance`
- DNS strategies: `tproxy`, `redirect`, `disable`
- Coexistence modes:
  - `preserve_tailnet` (default): apply tailscale and MagicDNS bypasses
  - `strict_box`: skip tailscale/MagicDNS bypass insertion
- Route convergence: renew/reapply prunes stale BOX fwmark rules and enforces one current `route_pref` rule
- Idempotent + lock-protected: `enable|renew|disable`
- `BOX_TRACE_COMMANDS=1` logs external command executions with component/action context
- `boxctl firewall status --json` exposes stable diagnostics (backend, capabilities, coexist fields, errors)

## Backend Capability Notes

- `iptables`:
  - `cap_ipv4=true`
  - `cap_ipv6=false` (full ip6tables graph pending)
- `nftables`:
  - `cap_ipv4=true`
  - `cap_ipv6=false` (full IPv6 interception/hijack graph pending)

## Rollback/Uninstall

Safe uninstall (keeps config backups/data unless manually removed):
- `sudo pacman -R box4linux`

Optional manual purge of local state:
- `sudo rm -rf /etc/box /var/lib/box /run/box /var/log/box`

## Remaining TODO

- Full UID/GID/interface/MAC policy graph in firewall.
- Full IPv6 interception/hijack parity.
- API-based reload hooks for `mihomo` and `sing-box`.
- Broader kernel-capability probing across distro variants.
