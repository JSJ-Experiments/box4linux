# 09 - Phase 2 Implementation Notes

## Scope Implemented
- Firewall staged apply/rollback in `lib/firewall/backend_iptables.sh`
- Modes: `tun`, `tproxy`, `redirect`, `mixed`, `enhance`
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
- Integration test harness:
  - `tests/integration/test_phase2.sh`

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


## Overlay Contract
- Source config files are never edited in place.
- Rendered runtime config path:
  - `${BOX_RUN_DIR}/rendered/mihomo/config.yaml`
  - `${BOX_RUN_DIR}/rendered/sing-box/config.json`
- Default run dir is `/run/box`, with repo-local fallback via runtime path resolver.

## Known Gaps
- UID/GID/interface/MAC policy filters are placeholders.
- No nftables backend yet.
- ip6tables-tailnet explicit bypass chains are pending (current backend avoids ip6tables modifications).
- API reload is still TODO for both cores.
