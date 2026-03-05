# 09 - Linux Firewall/Supervisor Notes

## Scope Implemented

- Firewall staged apply/rollback in:
  - `lib/firewall/backend_iptables.sh`
  - `lib/firewall/backend_nft.sh`
- Modes on both backends: `tun`, `tproxy`, `redirect`, `mixed`, `enhance`
- DNS hijack strategies: `tproxy`, `redirect`, `disable`
- Tailscale coexistence safeguards:
  - preserve existing tailscale policy/routing ownership
  - never flush non-BOX rules/routes
  - bypass `tailscale0`, `100.64.0.0/10`, and resolver `100.100.100.100:53`
  - expose tailscale preservation flags in `firewall status --json`
- Core runtime overlays for `mihomo` and `sing-box`:
  - `lib/supervisor/mutator_mihomo.sh`
  - `lib/supervisor/mutator_sing_box.sh`
- JSON status output:
  - `boxctl service status --json`
  - `boxctl firewall status --json`
- Dry-run:
  - `boxctl firewall dry-run`
- Command tracing:
  - `BOX_TRACE_COMMANDS=1 ./cmd/boxctl firewall enable`
  - `BOX_TRACE_COMMANDS=1 ./cmd/boxctl service start`
- Integration test harness:
  - `tests/integration/test_phase2.sh`
  - `tests/integration/test_real_kernel.sh` (privileged netns suite)

## Firewall Apply Order

1. Cleanup existing BOX-owned objects.
2. Create base BOX chains and attach table jumps.
3. Apply anti-loop guards.
4. Apply tailscale bypass and DNS exclusions.
5. Apply policy placeholder stage.
6. Apply mode-specific rules.
7. Apply DNS strategy rules.
8. Ensure policy routing for mark-based paths.
9. On any failure: full cleanup rollback.

## Coexistence Modes

- `preserve_tailnet` (default):
  - apply tailscale bypass for `tailscale0`
  - bypass tailnet CIDR `100.64.0.0/10`
  - exclude `100.100.100.100:53` from DNS hijack
- `strict_box`:
  - skip tailscale bypass and MagicDNS exclusion rule insertion
  - still keep non-destructive cleanup boundaries (BOX-owned objects only)

## Route Pref Convergence

- Renew/reapply path prunes stale BOX policy rules matching the configured Box fwmark+table regardless of previous `pref`.
- After apply there must be exactly one BOX fwmark rule at the current `route_pref`.
- Tailscale rules (e.g., `fwmark 0x80000/0xff0000` and table `52`) are never targeted.

## Backend Matrix

- `iptables`:
  - mature path in this repo
  - status includes capability and tailscale coexist flags
  - `cap_ipv4=true`, `cap_ipv6=false` (no ip6tables graph yet)
- `nftables`:
  - MVP parity with iptables modes/DNS/coexist behavior
  - cleanup only deletes BOX-owned nft tables (`inet box_mangle`, `ip box_nat`)
  - `cap_ipv4=true`, `cap_ipv6=false` (full IPv6 parity still pending)

## Status Diagnostics Schema

- `boxctl firewall status --json` includes stable diagnostics:
  - `backend` / `backend_selected`
  - `backend_available`
  - `mode`
  - `dns_hijack_mode`
  - `dns_coexist_mode`
  - `dns_coexist_mode_active`
  - `cap_ipv4`, `cap_ipv6`, `cap_tproxy`
  - `dry_run_supported`
  - `last_error`
- Status path is read-only and must not create firewall objects.
- If `BOX_CONFIG_FILE` is explicitly set but missing, commands fail fast with `E_CONFIG_FILE` (no dev/system fallback).

## Real-Kernel Validation

- Run with root privileges:
  - `sudo ./tests/integration/test_real_kernel.sh`
- Suite behavior:
  - creates an isolated network namespace for safety
  - runs backend checks for `iptables` and `nftables` when each is usable
  - validates `enable|renew|disable` idempotency and BOX artifact cleanup
  - verifies tailscale coexistence invariants (fwmark rule + table `52` route) remain intact
  - verifies coexistence differences between `preserve_tailnet` and `strict_box`
- Skip semantics:
  - exits with `SKIP: ...` when root/CAP_SYS_ADMIN/CAP_NET_ADMIN or backend tools are unavailable.


## Overlay Contract

- Source config files are never edited in place.
- Rendered runtime config path:
  - `${BOX_RUN_DIR}/rendered/mihomo/config.yaml`
  - `${BOX_RUN_DIR}/rendered/sing-box/config.json`
- Default run dir is `/run/box`, with repo-local fallback via runtime path resolver.

## Known Gaps

- UID/GID/interface/MAC policy filters are placeholders.
- nftables IPv6-specific tailnet chain rules are pending.
- Kernel feature probing remains lightweight (tool-level + basic tproxy probe).
- API reload is still TODO for both cores.
