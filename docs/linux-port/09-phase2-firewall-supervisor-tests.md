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
  - `dns_enhanced_mode`
  - `dns_coexist_mode`
  - `dns_coexist_mode_active`
  - `ipv6_enabled`
  - `ipv6_effective_mode`
  - `cap_ipv4`, `cap_ipv6`, `cap_tproxy`
  - `dry_run_supported`
  - `last_error`
- Status path is read-only and must not create firewall objects.
- If `BOX_CONFIG_FILE` is explicitly set but missing, commands fail fast with `E_CONFIG_FILE` (no dev/system fallback).

## Status JSON Contract

- `boxctl service status --json`
  - required fields: `status`, `core`, `pid`, `mode`, `dns_hijack_mode`, `dns_enhanced_mode`, `ipv6_enabled`, `ipv6_effective_mode`, `rendered_config`, `config`
  - conditional fields: none
  - healthy example:
```json
{"status":"healthy","core":"mihomo","pid":1234,"mode":"mixed","dns_hijack_mode":"redirect","dns_enhanced_mode":"fake-ip","ipv6_enabled":true,"ipv6_effective_mode":"direct","rendered_config":"/run/box/rendered/mihomo/config.yaml","config":"/etc/box/box.toml"}
```
- `boxctl firewall status --json`
  - required fields: `status`, `mode`, `backend`, `backend_selected`, `dns_hijack_mode`, `dns_enhanced_mode`, `dns_coexist_mode`, `dns_coexist_mode_active`, `ipv6_enabled`, `ipv6_effective_mode`, `backend_capabilities`, `last_error`, `backend_available`, `cap_tproxy`, `cap_ipv4`, `cap_ipv6`, `dry_run_supported`, `tailscale_bypass_applied`, `tailscale_mark_rule`, `tailscale_table_present`, `chain_mangle`, `chain_nat`, `chain_dns_mangle`, `chain_dns_nat`, `route_rule`, `route_table_installed`
  - conditional fields: `error` is emitted only when `last_error` is non-empty
  - healthy example:
```json
{"status":"enabled","mode":"mixed","backend":"iptables","backend_selected":"iptables","dns_hijack_mode":"redirect","dns_enhanced_mode":"fake-ip","dns_coexist_mode":"preserve_tailnet","dns_coexist_mode_active":"preserve_tailnet","ipv6_enabled":true,"ipv6_effective_mode":"direct","backend_capabilities":"backend=iptables,available=true,ipv4=true,ipv6=false,tproxy=true,dry_run=true","last_error":"","backend_available":true,"cap_tproxy":true,"cap_ipv4":true,"cap_ipv6":false,"dry_run_supported":true,"tailscale_bypass_applied":true,"tailscale_mark_rule":true,"tailscale_table_present":true,"chain_mangle":true,"chain_nat":true,"chain_dns_mangle":true,"chain_dns_nat":true,"route_rule":true,"route_table_installed":true}
```
  - error example:
```json
{"status":"disabled","mode":"tun","backend":"iptables","backend_selected":"iptables","dns_hijack_mode":"disable","dns_enhanced_mode":"redir-host","dns_coexist_mode":"preserve_tailnet","dns_coexist_mode_active":"preserve_tailnet","ipv6_enabled":false,"ipv6_effective_mode":"disabled","backend_capabilities":"backend=iptables,available=false,ipv4=false,ipv6=false,tproxy=false,dry_run=true","last_error":"iptables inspection unavailable (need root/CAP_NET_ADMIN or kernel support)","backend_available":false,"cap_tproxy":false,"cap_ipv4":false,"cap_ipv6":false,"dry_run_supported":true,"tailscale_bypass_applied":false,"tailscale_mark_rule":false,"tailscale_table_present":false,"chain_mangle":false,"chain_nat":false,"chain_dns_mangle":false,"chain_dns_nat":false,"route_rule":false,"route_table_installed":false,"error":"iptables inspection unavailable (need root/CAP_NET_ADMIN or kernel support)"}
```

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

## Package Smoke Validation

- Arch package smoke script:
  - `tests/integration/test_arch_package_smoke.sh <path-to-pkg.tar.zst>`
- Validates packaged install layout and status/dry-run commands without mutating host state:
  - `boxctl service status --json`
  - `boxctl firewall status --json`
  - `boxctl firewall dry-run`
- Verifies unit files exist in package root and runs `systemd-analyze verify` when available.


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
- API reload is implemented when the active rendered config exposes a controller endpoint; restart fallback remains in place for unsupported cases.
