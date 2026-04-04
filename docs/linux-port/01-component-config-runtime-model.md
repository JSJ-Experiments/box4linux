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
bin_dir = "/usr/local/bin"
workdir = "/var/lib/box"
config_source = "/etc/box/profiles/config.yaml"

[network]
mode = "tun"
tproxy_port = 9898
redir_port = 9797
dns_hijack_mode = "tproxy"
dns_coexist_mode = "preserve_tailnet"

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
