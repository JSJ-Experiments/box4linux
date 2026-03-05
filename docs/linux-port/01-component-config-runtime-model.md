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

## Linux Config Split
Create explicit files:
1. `/etc/box/box.toml`
- global options (paths, mode, selected core)
2. `/etc/box/network.toml`
- mode, ports, dns hijack policy, ipv6, cn bypass
3. `/etc/box/policy.toml`
- include/exclude users/groups/interfaces/mac rules
4. `/etc/box/subscriptions.toml`
- provider URLs and output files
5. `/etc/box/update.toml`
- channel/stability, mirrors, schedule

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
- `proxy_mode` in `{core,blacklist,whitelist}`
- Port ranges 1..65535 and no collision with reserved core APIs.
- If `bypass_cn_ip=true`, require ipset availability at runtime.

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
auto_modify_config = true

[network]
mode = "tun"
tproxy_port = 9898
redir_port = 9797
ipv6 = true
dns_hijack_mode = "tproxy"
proxy_tcp = true
proxy_udp = true

[policy]
proxy_mode = "core"
include_uids = []
exclude_uids = []
include_gids = []
exclude_gids = []
allow_ifaces = ["wlan+", "eth+"]
ignore_ifaces = []

[updates]
enabled_subscription = false
enabled_geo = false
use_ghproxy = false
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
- `subscription_url_*` + provider names -> `[subscriptions]`
- `cgroup_*` -> `[resource_limits]`
