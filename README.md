# box4linux workspace

Linux-native control plane lives in:
- `cmd/boxctl`
- `lib/common.sh`
- `lib/config.sh`
- `lib/supervisor/`
- `lib/firewall/`
- `lib/updater/`
- `systemd/`
- `tests/integration/`
- `packaging/arch/`

Android reference artifacts are kept untouched in `box-reference/`.

## Quick run (dev)

1. Use repo-local fallback config at `etc/box/box.toml` (auto-used when `/etc/box/box.toml` is missing).
   - If `BOX_CONFIG_FILE` is explicitly set, it must exist; commands fail fast instead of falling back.
2. Run status commands:
   - `./cmd/boxctl service status`
   - `./cmd/boxctl service status --json`
   - `./cmd/boxctl firewall status`
   - `./cmd/boxctl firewall status --json`
   - `./cmd/boxctl policy status`
   - `./cmd/boxctl policy status --json`
   - `./cmd/boxctl update status`
   - `./cmd/boxctl update status --json`
3. Run privileged actions as root:
   - `sudo ./cmd/boxctl service start|stop|restart|reload`
   - `sudo ./cmd/boxctl firewall enable|disable|renew`
   - `sudo ./cmd/boxctl policy evaluate|enable|disable`
   - `sudo ./cmd/boxctl update kernel|subs|geo|dashboard|all`
   - `./cmd/boxctl firewall dry-run`
4. Run integration checks:
   - `./tests/integration/test_phase2.sh`
   - `./tests/integration/test_campus_dns.sh`
   - `./tests/integration/test_policy.sh`
   - `./tests/integration/test_updater.sh`
   - `sudo ./tests/integration/test_real_kernel.sh`
   - `./tests/integration/test_docker_privileged.sh`

## Updater

Commands:
- `boxctl update kernel`
- `boxctl update subs`
- `boxctl update geo`
- `boxctl update dashboard`
- `boxctl update all`
- `boxctl update status --json`

Update sources are configured in `/etc/box/box.toml` under:
- `[updater]`
- `[updater.kernel]`
- `[updater.subs]`
- `[updater.geo]`
- `[updater.dashboard]`

Supported inputs:
- `url`
- `file`
- `source = "release"` for `kernel` and `geo`
- `checksum`
- `checksum_file`
- `target`

Release resolver fields for `kernel` and `geo`:
- `source = "release"`
- `release_api_url` or `release_repo`
- `release_channel = stable|prerelease|any`
- `release_tag`
- `asset_regex`
- `checksum_asset_regex`
- `release_os`
- `release_arch`
- `archive_member_regex`

Failure semantics:
- downloads go to staging first
- checksum verification follows `checksum_policy = off|optional|required`
- URL fetches retry with exponential backoff controlled by `fetch_retries` and `fetch_retry_backoff_ms`
- `use_ghproxy = true` rewrites GitHub and raw GitHub download URLs through `ghproxy_url`
- staged payload is validated before install
- install stages beside the target and renames into place with backup/restore on failure
- runtime handoff prefers reload when supported, otherwise controlled restart
- `mihomo` and `sing-box` subscription updates use controller API reload when the rendered config exposes `external-controller`/`external_controller`; otherwise they fall back to controlled restart
- release resolution requires `jq`
- `source = "auto"` does not implicitly enable release downloads; set `source = "release"` explicitly
- kernel release assets support raw binaries, `.gz`, `.tar`, `.tar.gz`, `.tgz`, and `.tar.xz`
- dashboard archives support `.zip`, `.tar.gz`, `.tgz`, `.tar`, `.tar.xz`
- nested dashboard archive roots are flattened automatically when a single top-level directory is present
- dashboard target and download URL can be derived from core config (`external-ui` / `external_ui`, `external-ui-download-url` / `external_ui_download_url`)
- if the core config omits a dashboard target, updater falls back to `./dashboard` relative to the core config path
- `updater.subs.preset = "mihomo_phone"` renders a sanitized Mihomo phone profile template from `/etc/box/profiles/phone-mihomo-config.yml`
- `updater.geo.preset` supports `auto`, `metacubex_mihomo`, `metacubex_sing_box`, and `metacubex_legacy`
- `geo` updates do not restart the running core
- `kernel` updates restart only when the updated target matches the active core binary

Timer units shipped in `systemd/`:
- `box-update-kernel.service` + `.timer`
- `box-update-subs.service` + `.timer`
- `box-update-geo.service` + `.timer`
- `box-update-dashboard.service` + `.timer`
- `box-update-all.service` + `.timer`

Enable only the timers you actually want. Do not enable both the per-component timers and `box-update-all.timer` unless duplicate update attempts are acceptable in your environment.

## Policy Watcher

Commands:
- `boxctl policy evaluate`
- `boxctl policy enable`
- `boxctl policy disable`
- `boxctl policy status --json`

Config is under `[policy]` in `/etc/box/box.toml`:
- `enabled = true|false`
- `proxy_mode = core|whitelist|blacklist`
- `debounce_seconds`
- `use_module_on_wifi_disconnect`
- `disable_marker`
- `allow_ifaces`, `ignore_ifaces`
- `allow_ssids`, `ignore_ssids`
- `allow_bssids`, `ignore_bssids`

Behavior:
- policy watcher uses `ip monitor link route address` for Linux-native event intake
- active Wi-Fi identity prefers `nmcli`, then falls back to `iw`
- `wlan+`-style patterns are treated as prefix wildcards
- address-change refresh is decoupled from policy evaluation and triggers a background `firewall renew`
- `box-policy.service` is optional and should only be enabled when `[policy].enabled = true`

## Docker Test Harness

- Local docker-backed privileged validation:
  - `./tests/integration/test_docker_privileged.sh`
- Optional secret/env input is loaded from ignored file:
  - `.box-test-subscription.env`
- Tracked template:
  - `.box-test-subscription.env.example`
- The harness runs:
  - `./tests/integration/test_phase2.sh`
  - `./tests/integration/test_real_kernel.sh`
- It uses a privileged Arch container and still shares the host kernel, so nftables kernel/runtime gaps will reproduce there too.

## Arch Package Build/Install

Build package from repo root:
- `cd packaging/arch && makepkg --noconfirm -f`

Install package:
- `sudo pacman -U ./box4linux-*.pkg.tar.zst`

Installed layout:
- `/usr/bin/boxctl`
- `/usr/lib/box4linux/cmd/boxctl`
- `/usr/lib/box4linux/lib/...`
- `/etc/box/box.toml`
- `/etc/box/profiles/phone-mihomo-config.yml`
- `/usr/lib/systemd/system/box.service`
- `/usr/lib/systemd/system/box-firewall.service`
- `/usr/lib/systemd/system/box-policy.service`
- `/usr/lib/systemd/system/box-update-*.service`
- `/usr/lib/systemd/system/box-update-*.timer`
- `/usr/share/doc/box4linux/`

Config upgrade behavior:
- Package marks `/etc/box/box.toml` as backup config.
- Package also marks `/etc/box/profiles/phone-mihomo-config.yml` as backup config.
- Local edits are preserved across upgrades.
- New template versions land as `.pacnew` when needed.

Packaged first-run defaults:
- `/etc/box/box.toml` already points `config_source` at `/etc/box/profiles/phone-mihomo-config.yml`
- default `bin_dir` is `/usr/bin`
- default runtime mode is `mixed` with `dns_hijack_mode = "redirect"`
- default Mihomo DNS mode is `fake-ip`
- default runtime IPv6 is enabled
- default firewall backend is `nftables`
- default private-range kernel bypass is enabled
- optional CN kernel bypass reads `/var/lib/box/china_ipv4.txt`
- `updater.geo.preset = "auto"` is enabled by default
- `updater.subs.target` already points at the shipped Mihomo profile
- you can either edit the shipped Mihomo profile directly or enable `updater.subs.preset = "mihomo_phone"` in `box.toml`

## Service Lifecycle (Packaged Install)

Use helper script from package docs:
- `sudo /usr/share/doc/box4linux/systemd-lifecycle.sh enable`
- `sudo /usr/share/doc/box4linux/systemd-lifecycle.sh status`
- `sudo /usr/share/doc/box4linux/systemd-lifecycle.sh disable`
- The lifecycle helper enables `box-update-all.timer` by default and only enables `box-policy.service` when the loaded config has `[policy].enabled = true`.

Manual equivalent:
- `sudo systemctl daemon-reload`
- `sudo systemctl enable --now box.service box-firewall.service`
- `sudo systemctl enable --now box-policy.service` only when `[policy].enabled = true`
- `sudo systemctl enable --now box-update-all.timer` for the default scheduled updater path
- `sudo systemctl disable --now box-policy.service box-firewall.service box.service box-update-all.timer`

## Packaged Operational Quickstart

1. Verify command and units:
   - `boxctl service status --json`
   - `boxctl firewall status --json`
2. Edit the shipped Mihomo profile or updater source:
   - replace `<SUBSCRIPTION_URL_...>` placeholders in `/etc/box/profiles/phone-mihomo-config.yml`
   - or set `[updater.subs] preset = "mihomo_phone"` and fill `provider_names` / `provider_urls` in `/etc/box/box.toml`
3. Preview firewall operations:
   - `boxctl firewall dry-run`
4. Materialize optional managed assets:
   - `sudo boxctl update geo`
   - `sudo boxctl update dashboard`
   - if you enable `firewall.bypass_cn_ip = true`, `update geo` populates `/var/lib/box/china_ipv4.txt` for kernel-side CN bypass
5. Start runtime:
   - `sudo systemctl start box.service`
6. Renew firewall policy safely:
   - `sudo systemctl reload box-firewall.service`
7. Run or schedule updates:
   - `sudo systemctl start box-update-all.service`
   - `sudo systemctl enable --now box-update-subs.timer`

## CI/Release Flow

Workflow file: `.github/workflows/ci.yml`

On push/PR:
- `./tests/lint_shell.sh`
- mock integration: `./tests/integration/test_phase2.sh`
- privileged integration: `sudo ./tests/integration/test_real_kernel.sh` (suite prints `SKIP` when capabilities/tooling are unavailable)
- Arch package build in Arch container
- package smoke test: `./tests/integration/test_arch_package_smoke.sh <pkg>`

On tags (`v*`):
- built package artifact is published to GitHub Releases

## Phase 3 Notes

- Supported cores: `mihomo`, `sing-box`
- Runtime overlays rendered under `/run/box/rendered` (or dev fallback)
- Updater components: `kernel`, `subs`, `geo`, `dashboard`
- Policy watcher commands: `evaluate`, `enable`, `disable`, `status`
- `kernel` and `geo` can resolve release assets by channel/tag/arch when explicitly configured with `source = "release"`
- Firewall backends:
  - `iptables` (mature path)
  - `nftables` (MVP parity)
- Supported modes on both backends: `tun`, `tproxy`, `redirect`, `mixed`, `enhance`
- DNS strategies: `tproxy`, `redirect`, `disable`
- Coexistence modes:
  - `preserve_tailnet` (default): apply tailscale and MagicDNS bypasses
  - `strict_box`: skip tailscale/MagicDNS bypass insertion
- Kernel bypass:
  - `firewall.bypass_private_ip = true` installs early private-range bypass rules by default
  - `firewall.bypass_cn_ip = true` installs early CN IPv4 bypass rules from `firewall.bypass_cn_file`
  - `boxctl update geo` with the default preset now ships `china_ipv4.txt` alongside geo assets
- IPv6 and DNS controls:
  - `network.ipv6 = true|false` controls whether Mihomo and its DNS answer IPv6 at all
  - `network.dns_enhanced_mode = "fake-ip" | "redir-host"` controls Mihomo DNS behavior
  - `network.org_dns_mode = "auto" | "org" | "public"` controls how org-specific suffixes resolve
  - `network.org_dns_suffixes` lists the suffixes that should follow org/public split DNS logic
  - `network.org_dns_probe_hosts` lists the hosts used to decide whether the current network is returning internal org addresses
  - `network.org_dns_public_servers` lists the DoH resolvers used for those suffixes when the current network is not returning internal org addresses
  - legacy `campus_dns_*` keys are still accepted as aliases
  - effective IPv6 behavior today is:
    - `mode = "tun"` and `ipv6 = true`: IPv6 is proxied by the core TUN stack
    - `mode != "tun"` and `ipv6 = true`: IPv6 stays direct outside the Linux firewall graph
    - `ipv6 = false`: runtime disables IPv6 in the core/DNS path so clients prefer IPv4
  - practical selection matrix:
    - `mixed + ipv6=true + fake-ip`: current default, IPv4 proxied and IPv6 direct
    - `mixed + ipv6=false + fake-ip`: prefer IPv4 while keeping transparent IPv4 proxying
    - `tun + ipv6=true + fake-ip`: closest to phone-style full-device behavior, including proxied IPv6
    - `mixed + redir-host`: real-address DNS answers instead of fake-IP
  - browser/devtools may still show the real upstream server address even when local DNS is `fake-ip`; the fake-IP is only the local interception hop
- Route convergence: renew/reapply prunes stale BOX fwmark rules and enforces one current `route_pref` rule
- Idempotent + lock-protected: `enable|renew|disable`
- `BOX_TRACE_COMMANDS=1` logs external command executions with component/action context
- `boxctl firewall status --json` exposes stable diagnostics (backend, capabilities, coexist fields, errors)
- `boxctl policy status --json` exposes watcher/runtime intent, active interfaces, Wi-Fi identity, and last refresh metadata

## Backend Capability Notes

- `iptables`:
  - `cap_ipv4=true`
  - `cap_ipv6=false` (full ip6tables graph pending)
- `nftables`:
  - `cap_ipv4=true`
  - `cap_ipv6=false` (full IPv6 interception/hijack graph pending)

## Live Behavior Notes

- `boxctl service status --json` reports:
  - `dns_enhanced_mode`
  - `ipv6_enabled`
  - `ipv6_effective_mode`
  - `org_dns_mode_configured`
  - `org_dns_mode_active`
  - `org_dns_iface`
  - `org_dns_servers`
  - `org_dns_suffixes`
  - `org_dns_probe_hosts`
- `boxctl firewall status --json` reports the same IPv6/DNS fields plus backend capability flags.
- If `dns_enhanced_mode = "fake-ip"`, local name resolution can return fake-IP ranges such as `198.18.0.0/16` while browser/devtools still show the real remote server address used by Mihomo's outbound connection.
- There is no reference-backed `prefer_ipv4|prefer_ipv6|default` selector. The supported family control is `network.ipv6 = true|false`.
- This repo's shipped `etc/box/box.toml` is already preconfigured for a BIT org/public split DNS policy:
  - `+.bit.edu.cn` auto-switches between current org-local DNS and the configured DoH resolvers
  - `+.edu.cn` stays on `dhcp://system` / `system`
  - the running service also watches link/route/address changes and safely reloads the rendered Mihomo DNS policy when the detected org/public environment signature changes
- Org suffix handling is adaptive rather than pinned:
  - in `org_dns_mode = "auto"`, Box inspects the active default-route interface, reads its live DNS servers, and probes the configured org hosts
  - if those probes resolve to RFC1918 addresses, configured suffixes such as `+.bit.edu.cn` render to the current link DNS servers
  - otherwise those suffixes render to the configured DoH resolvers so the same suffixes still work off campus without hardcoding an org resolver IP

## Rollback/Uninstall

Safe uninstall (keeps config backups/data unless manually removed):
- `sudo pacman -R box4linux`

Optional manual purge of local state:
- `sudo rm -rf /etc/box /var/lib/box /run/box /var/log/box`

## Remaining TODO

- Full UID/GID/interface/MAC policy graph in firewall.
- Full IPv6 firewall interception/hijack parity outside `tun` mode.
- Richer built-in geo/subscription preset coverage beyond the default Mihomo phone and MetaCubeX bundles.
- Broader kernel-capability probing across distro variants.
