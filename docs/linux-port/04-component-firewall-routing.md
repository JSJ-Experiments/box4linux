# 04 - Component: Firewall and Routing

## Objective
Port `box.iptables` behavior with deterministic rule management on Linux.

## What The Firewall Is For
In Box, the firewall layer is the packet steering engine. It makes transparent proxying possible by controlling how kernel networking treats packets before they reach user space.

It is responsible for:
- Intercepting target traffic with `nat`/`mangle`/`filter` chains.
- Selecting steering behavior by mode (`tun`, `tproxy`, `redirect`, `mixed`, `enhance`).
- Marking packets and configuring policy routes (`fwmark`, route table, rule pref) for TPROXY flows.
- Implementing DNS hijack policy (`tproxy`, `redirect`, `disable`) with TCP/UDP control.
- Enforcing include/exclude policy by UID/GID/interface/MAC.
- Preventing traffic loops (self-proxy loops and localhost recursion).
- Cleaning all Box-owned rules/routes on stop, restart, and failure rollback.

## Baseline Features to Preserve
- Modes: `tproxy`, `redirect`, `mixed`, `enhance`, `tun`
- DNS hijack strategies: `tproxy`, `redirect`, `disable`
- Policy routing mark/table/pref defaults:
- `fwmark=16777216/16777216`
- `table=2024`
- `pref=100`
- Include/exclude by UID/GID, interface allow/ignore, optional MAC filter
- Optional CN bypass using ipset

## Linux Backend Architecture
Implement backend abstraction:
1. `backend_iptables.sh` (primary)
2. `backend_nft.sh` (optional phase 2)

High-level API:
- `fw_init`
- `fw_apply_mode <mode>`
- `fw_cleanup`
- `fw_status`

## Rule Ownership Model
- Every rule/chain created must be uniquely prefixed (`BOX_*`).
- All apply operations must be idempotent.
- Cleanup removes only BOX-owned objects.

## Mode-Specific Implementation
1. `tproxy`
- mangle PREROUTING/OUTPUT mark + TPROXY
- policy routes in table `2024`
2. `redirect`
- nat REDIRECT for TCP (+ optional DNS)
3. `mixed`
- forward/tun helper + redirect for TCP
4. `enhance`
- redirect TCP + tproxy UDP
5. `tun`
- forward path only (no local app owner rules)

## DNS Handling Plan
- Separate chains for DNS hijack to avoid duplicated inline rules.
- Support TCP/UDP toggles independently.
- Keep special mihomo DNS-forward behavior, but isolate to core-specific policy function.

## Capability Probe
At enable time:
- probe TPROXY target (v4/v6)
- probe socket match
- probe ipset
- probe ip6 nat
If unsupported, apply controlled downgrade with explicit logs.

## Linux Safety Defaults
- Do not disable host IPv6 globally by default.
- Do not hardcode interface names like `wlan0`.
- Make route table id configurable to avoid collisions.

## Current IPv6 Scope
- Linux-native transparent interception is still IPv4-only for `iptables` and `nftables`.
- `boxctl firewall status --json` reports this as `cap_ipv6=false`.
- Effective runtime behavior today is:
  - `mode=tun` + `network.ipv6=true`: IPv6 is proxied by the core TUN stack.
  - non-`tun` modes + `network.ipv6=true`: IPv6 remains direct outside the firewall graph.
  - `network.ipv6=false`: runtime disables IPv6 in the core/DNS path to prefer IPv4.
- `network.dns_enhanced_mode` controls Mihomo DNS `fake-ip` vs `redir-host` independently from firewall mode.
- This means `mixed` mode on current Linux-native backends is effectively:
  - IPv4: transparent redirect/mark path through Box/Mihomo
  - IPv6: direct host path unless `mode=tun`
- When `dns_enhanced_mode = "fake-ip"`, applications may resolve fake IPv4/IPv6 placeholders locally while observability tools still show the real remote upstream address chosen by Mihomo.

## Tailscale Coexistence Requirements
For hosts that run Tailscale alongside Box, firewall apply/cleanup must preserve Tailscale routing and DNS behavior.

Hard requirements:

- Never flush/delete non-BOX chains or global policy rules.
- Never touch Tailscale policy-routing entries (commonly table `52`, fwmark rules like `0x80000/0xff0000`, or rule priorities around `5210..5270`).
- Add explicit bypass for Tailscale interface traffic:
- `-i tailscale0 -j RETURN` and `-o tailscale0 -j RETURN` in relevant chains.
- Add destination bypass CIDRs for tailnet traffic:
- IPv4 `100.64.0.0/10`
- IPv6 `fd7a:115c:a1e0::/48`
- Exclude Tailscale DNS endpoint from DNS hijack:
- `100.100.100.100:53`
- Keep Box rule/table/pref IDs configurable and in a dedicated namespace to avoid collisions with existing local policy routing (for example `2022`, `2024`, `52` already in use on some hosts).

DNS guidance:

- When transparent DNS interception is enabled, provide `dns_exclude_servers` and `dns_exclude_domains` settings.
- Default excludes should include Tailscale resolver and tailnet domains (`*.ts.net` and local MagicDNS suffix).

## Required Tests
- each mode on IPv4-only and dual-stack
- idempotent enable/renew/disable loops
- no leaked rules after failure path
- concurrent call lock behavior

## Deterministic Rule Apply Order
1. capability probe
2. cleanup old BOX-owned state
3. create base chains
4. apply anti-loop and early kernel bypass (`private_ip`, optional `cn_ip`, tailscale coexist)
5. apply owner/interface/mac policies
6. apply mode-specific redirect/tproxy actions
7. apply DNS strategy rules
8. apply QUIC policy
9. write runtime snapshot

## Rollback Rules
If any step fails:
- remove all newly created BOX chains/rules
- remove policy routes and fwmarks
- restore prior snapshot only if valid

## Linux Preflight Checklist
- kernel modules/features:
- `xt_TPROXY`
- `xt_socket`
- `xt_owner`
- `ip_set`
- `nf_tproxy_core`
- commands present:
- `iptables`/`ip6tables` or `nft`
- `ip`, `sysctl`
- `ipset` optional if the iptables backend later adopts set-backed acceleration; current Linux-native path must not depend on Android-only tooling

## Observability
Expose `boxctl firewall status --json` with:
- active mode
- ipv6 enabled
- capabilities detected
- table/pref in use
- chains installed
- last_apply_ts
