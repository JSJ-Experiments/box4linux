# 01 - Component: Config and Runtime Model

## Objective
Define portable Linux config/state contracts replacing Android-centric `settings.ini` assumptions.

## Baseline Inputs
`box-reference/box/box/settings.ini` currently combines:
- Paths and runtime files
- Core/network mode
- Subscription definitions
- Update toggles
- App UID/GID and interface allow/ignore lists
- cgroup toggles

## Linux Config Layout
Current Linux-native implementation uses one canonical file:
1. `/etc/box/box.toml`
- `[core]`
- `[network]`
- `[firewall]`
- `[policy]`
- `[updater]`
- `[updater.kernel]`
- `[updater.subs]`
- `[updater.geo]`
- `[updater.dashboard]`

Rationale:
- one loader/validator path
- easier packaged upgrades
- simpler systemd unit integration

## Runtime State Files
Under `/var/run/box/`:
- `box.pid`
- `runtime.firewall.env` (or JSON)
- `state/appuid.list`
- `locks/*`

Under `/var/log/box/`:
- `service.log`
- `firewall.log`
- `updater.log`
- `policy.log`

## Data Model Notes
- Keep existing semantic keys (`network_mode`, `proxy_mode`, `dns_hijack_mode`) for migration ease.
- Replace Android package-based UID discovery with Linux user/group policy input.
- Keep interface allow/ignore and MAC filtering as-is conceptually.

## Migration Strategy
1. Parse old `settings.ini` into internal map.
2. Generate TOML files with defaults.
3. Preserve unknown keys in `box.toml` under `[legacy]` section.

## Validation Rules
- `network_mode` in `{tun,tproxy,redirect,mixed,enhance}`
- `dns_enhanced_mode` in `{fake-ip,redir-host}`
- `ipv6` in `{true,false,1,0}`
- `campus_dns_mode` in `{auto,campus,public}`
- `proxy_mode` in `{core,blacklist,whitelist}`
- Port ranges 1..65535 and no collision with reserved core APIs.
- If `bypass_cn_ip=true`, require a readable IPv4 CIDR file (`bypass_cn_file`) at runtime.
- `bypass_private_ip=true` is safe as a default and should install early kernel bypass rules for RFC1918/link-local/loopback/reserved IPv4 ranges.

## Compatibility Warnings From Current Scripts
Observed issues worth fixing in Linux schema/loader:
- Undefined `${settings}` used in multiple scripts for `sed -i` writes.
- Mixed implicit defaults and runtime mutation of persistent config.
- Arrays parsed via shell expansion are fragile across shells.

Implementation requirement:
- one canonical `config load -> validate -> normalize -> immutable runtime snapshot` step before actions.

## Example Normalized Config (TOML)
```toml
[core]
selected = "mihomo"
bin_dir = "/usr/local/bin"
workdir = "/var/lib/box"
config_source = "/etc/box/profiles/config.yaml"

[network]
mode = "tun"
tproxy_port = 9898
redir_port = 9797
dns_hijack_mode = "tproxy"
dns_enhanced_mode = "fake-ip"
dns_coexist_mode = "preserve_tailnet"
ipv6 = true
campus_dns_mode = "auto"
campus_dns_suffixes = ["+.bit.edu.cn"]
campus_dns_probe_hosts = ["lexue.bit.edu.cn", "xk.bit.edu.cn"]
campus_dns_public_servers = [
  "https://dns.alidns.com/dns-query",
  "https://cloudflare-dns.com/dns-query",
  "https://dns.google/dns-query",
]

[policy]
enabled = false
proxy_mode = "core"
allow_ifaces = ["wlan+", "eth+"]
ignore_ifaces = []

[updater]
checksum_policy = "optional"
fetch_retries = 3
fetch_retry_backoff_ms = 750
use_ghproxy = false
ghproxy_url = "https://ghfast.top"

[updater.subs]
preset = "mihomo_phone"
provider_names = ["proxy1", "proxy3"]
provider_urls = ["https://example.invalid/sub-a", "https://example.invalid/sub-b"]

[updater.geo]
preset = "auto"
```

## Runtime Snapshot Contract
Write immutable runtime snapshot before apply:
- file: `/var/run/box/runtime.snapshot.json`
- fields: `config_hash`, `core`, `network_mode`, `ports`, `timestamp`, `pid`

This snapshot is used by:
- `disable` path when config file changed during runtime
- post-crash cleanup

## Key Migration Map (`settings.ini` -> TOML)
- `bin_name` -> `[core].selected`
- `network_mode` -> `[network].mode`
- `proxy_mode` -> `[policy].proxy_mode`
- `ap_list`/`ignore_ap_list` -> `[policy].allow_ifaces`/`ignore_ifaces`
- `subscription_url_*` + provider names -> `[updater.subs.provider_urls]` + `[updater.subs.provider_names]`
- `cgroup_*` -> `[resource_limits]`

## Updater-Specific Runtime Notes
- `updater.subs.preset = "mihomo_phone"` renders a sanitized template from `/etc/box/profiles/phone-mihomo-config.yml`
- `updater.geo.preset = "auto"` derives the correct MetaCubeX bundle for the selected core
- GitHub-backed updater downloads can be mirrored via `use_ghproxy = true`
- subscription updates prefer controller API reload when the rendered config exposes a controller endpoint

## IPv6 Runtime Notes
- Linux-native config follows the reference boolean model with `network.ipv6 = true|false`.
- There is no separate `prefer_ipv4|prefer_ipv6|default` selector in the reference tree.
- Current Linux-native effective behavior is:
  - `mode=tun` + `ipv6=true`: IPv6 is handled by the core TUN path.
  - `mode!=tun` + `ipv6=true`: IPv6 remains direct because the firewall graph is still IPv4-only.
  - `ipv6=false`: runtime disables IPv6 in the core/DNS layer so clients fall back to IPv4.
- `network.dns_enhanced_mode = "fake-ip" | "redir-host"` is exposed explicitly for Mihomo overlay rendering.
- `network.campus_dns_mode = "auto" | "campus" | "public"` controls campus suffix DNS rendering for Mihomo.
- `network.campus_dns_suffixes` should contain only the suffixes that must follow campus/public split logic.
- In `campus_dns_mode = "auto"`, Mihomo overlay rendering inspects the active default-route interface, reads its live DNS servers via `resolvectl`, and probes `network.campus_dns_probe_hosts`.
- If any probe host resolves to RFC1918 space, those suffixes render to the current link DNS servers.
- Otherwise the suffixes render to `network.campus_dns_public_servers`, which should be DoH endpoints rather than a hardcoded campus resolver IP.
- While the service is running, a lightweight service-owned monitor watches link/route/address changes and triggers a safe reload plus firewall renew when that campus/public signature changes.
- Operational presets:
  - `mixed + ipv6=true + fake-ip`: default desktop compromise, IPv4 proxied and IPv6 direct
  - `mixed + ipv6=false + fake-ip`: force IPv4 preference without changing firewall mode
  - `tun + ipv6=true + fake-ip`: closest to phone-style full-device behavior
  - `mixed + redir-host`: avoid fake-IP answers and keep real-address DNS responses
