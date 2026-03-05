# box4linux workspace

Linux-native control plane (phase 2) lives in:
- `cmd/boxctl`
- `lib/common.sh`
- `lib/config.sh`
- `lib/supervisor/`
- `lib/firewall/`
- `systemd/`
- `tests/integration/`

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
   - `sudo ./tests/integration/test_real_kernel.sh` (skips automatically when root/CAP_SYS_ADMIN/CAP_NET_ADMIN or backend tooling is unavailable)

## Systemd units

- `systemd/box.service`
- `systemd/box-firewall.service`

Copy/symlink these to your systemd unit path and ensure `boxctl` is installed as `/usr/bin/boxctl`.

## Phase 3 notes

- Supported cores: `mihomo`, `sing-box`
- Core overlay mutators render runtime configs under `/run/box/rendered` (or dev fallback).
- Firewall backends:
  - `iptables`: parity path with staged apply/rollback
  - `nftables`: MVP parity path with staged apply/rollback
- Supported modes on both backends: `tun`, `tproxy`, `redirect`, `mixed`, `enhance`.
- DNS strategy handling: `tproxy`, `redirect`, `disable`.
- Tailscale coexistence defaults to `dns_coexist_mode=preserve_tailnet`.
- Coexistence mode semantics:
  - `preserve_tailnet`: apply tailscale bypass (`tailscale0`, `100.64.0.0/10`) and MagicDNS resolver exclusion (`100.100.100.100:53`).
  - `strict_box`: do not add tailscale bypass/MagicDNS exclusion rules; still never delete non-BOX routes/rules.
- Tailscale safeguards include:
  - bypass `tailscale0`
  - bypass `100.64.0.0/10` and preserve `fd7a:115c:a1e0::/48` by not touching ip6tables in this backend
  - bypass `100.100.100.100:53` (MagicDNS resolver)
  - preserve table `52` / fwmark `0x80000/0xff0000` ownership
- Route convergence: renew/reapply prunes stale BOX fwmark rules for the same fwmark+table (any old pref) and installs exactly one rule with current `route_pref`.
- `enable|renew|disable` paths are idempotent and lock-protected.
- `boxctl firewall dry-run` prints intended backend operations without applying.
- `BOX_TRACE_COMMANDS=1` logs external command execution with `component`, `action`, and command string.
- `boxctl firewall status --json` is side-effect free and includes stable diagnostics:
  - `backend` / `backend_selected`
  - `backend_available`
  - `mode`
  - `dns_hijack_mode`
  - `dns_coexist_mode`
  - `dns_coexist_mode_active`
  - `cap_ipv4`, `cap_ipv6`, `cap_tproxy`
  - `dry_run_supported`
  - `last_error`

## Backend capability notes

- `iptables`:
  - `cap_ipv4=true`
  - `cap_ipv6=false` (no ip6tables graph yet)
- `nftables`:
  - `cap_ipv4=true`
  - `cap_ipv6=false` (full IPv6 interception/hijack graph still pending)

## Remaining TODO

- Full UID/GID/interface/MAC policy graph in firewall (currently placeholder stage).
- Full kernel-capability probing for nft/iptables modules across all distro variants.
- API-based reload hooks for `mihomo` and `sing-box`.
- Explicit IPv6 tailnet bypass/interception parity for both backends.
