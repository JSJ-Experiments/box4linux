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
- Local edits are preserved across upgrades.
- New template versions land as `.pacnew` when needed.

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
2. Preview firewall operations:
   - `boxctl firewall dry-run`
3. Start runtime:
   - `sudo systemctl start box.service`
4. Renew firewall policy safely:
   - `sudo systemctl reload box-firewall.service`
5. Run or schedule updates:
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

## Rollback/Uninstall

Safe uninstall (keeps config backups/data unless manually removed):
- `sudo pacman -R box4linux`

Optional manual purge of local state:
- `sudo rm -rf /etc/box /var/lib/box /run/box /var/log/box`

## Remaining TODO

- Full UID/GID/interface/MAC policy graph in firewall.
- Full IPv6 interception/hijack parity.
- Richer built-in geo/subscription preset coverage beyond the default Mihomo phone and MetaCubeX bundles.
- Broader kernel-capability probing across distro variants.
