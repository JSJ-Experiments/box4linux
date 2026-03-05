# box4linux workspace

Linux-native MVP control plane (phase 1 + firewall skeleton) lives in:
- `cmd/boxctl`
- `lib/common.sh`
- `lib/config.sh`
- `lib/supervisor/`
- `lib/firewall/`
- `systemd/`

Android reference artifacts are kept untouched in `box-reference/`.

## Quick run (dev)
1. Use repo-local fallback config at `etc/box/box.toml` (auto-used when `/etc/box/box.toml` is missing).
2. Run status commands:
   - `./cmd/boxctl service status`
   - `./cmd/boxctl firewall status`
3. Run privileged actions as root:
   - `sudo ./cmd/boxctl service start|stop|restart`
   - `sudo ./cmd/boxctl firewall enable|disable|renew`

## Systemd units
- `systemd/box.service`
- `systemd/box-firewall.service`

Copy/symlink these to your systemd unit path and ensure `boxctl` is installed as `/usr/bin/boxctl`.

## MVP notes
- Supported cores: `mihomo`, `sing-box`
- Firewall backend: `iptables` skeleton with idempotent cleanup
- TODO(phase-2): full mode parity (`tproxy` target behavior, policy filters, nft backend, JSON status, config mutators)
