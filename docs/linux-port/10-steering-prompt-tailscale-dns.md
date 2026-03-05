# 10 - Steering Prompt (Tailscale + DNS Safe)

Use this prompt when asking an AI to implement or modify firewall/network logic for this project.

```text
You are implementing Linux-native Box networking in this repository.

Hard constraints:
1. Do not modify anything under `box-reference/`; it is reference-only.
2. Native code lives at repo root (`cmd/`, `lib/`, `systemd/`, `tests/`, `docs/`).
3. Keep behavior Linux-native (no Android-only commands/paths in runtime flow).

Coexistence requirements (must pass):
1. Preserve Tailscale routing and DNS behavior.
2. Never delete/flush non-BOX policy rules or routes.
3. Never alter Tailscale-owned policy routing entries (commonly table `52` and fwmark rules like `0x80000/0xff0000`).
4. Always bypass interception for `tailscale0` traffic.
5. Always bypass tailnet CIDRs:
   - IPv4: `100.64.0.0/10`
   - IPv6: `fd7a:115c:a1e0::/48`
6. Exclude Tailscale DNS resolver from DNS hijack:
   - `100.100.100.100:53`
7. Keep Box rule/table IDs configurable and namespaced.

DNS behavior constraints:
1. Host may use `systemd-resolved` with per-link DNS and route-only domains.
2. Host may have proxy-tun DNS `~.` on another interface.
3. Implement `dns_coexist_mode` with default `preserve_tailnet`.
4. In `preserve_tailnet`, MagicDNS (`*.ts.net` and local tailnet suffix) must keep working.

Required tests:
1. Repeated `firewall enable|renew|disable` is idempotent.
2. No leaked BOX-owned rules/routes after disable.
3. Tailscale reachability works before/after firewall operations.
4. MagicDNS resolution works before/after firewall operations.

When done:
- Summarize changed files.
- Show exact commands used for verification.
- List residual risks and TODOs.
```
