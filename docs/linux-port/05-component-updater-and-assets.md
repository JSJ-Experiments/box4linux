# 05 - Component: Updater and Assets

## Objective
Port `box.tool` update capabilities with stronger integrity and Linux artifact selection.

## Linux-Native Command Surface

- `boxctl update kernel`
- `boxctl update subs`
- `boxctl update geo`
- `boxctl update dashboard`
- `boxctl update all`
- `boxctl update status [--json]`

## Baseline Commands to Preserve
- `upkernel`, `upkernels`
- `subs`, `geox`, `geosub`, `upgeox_all`
- `upyq`, `upcurl`
- `upxui`, `upcnip`
- `reload`, `check`, `all`

## Updater Architecture
1. `fetcher`
- HTTP client abstraction (curl preferred)
- mirror rewrite support
- retry/backoff
2. `artifact resolver`
- resolve release asset by core + arch + channel
3. `installer`
- unpack + atomically replace binary/file
4. `rollback`
- `.bak` restore on failure

Implementation split in the Linux-native tree:
- `lib/updater/resolver.sh`
- `lib/updater/fetcher.sh`
- `lib/updater/verifier.sh`
- `lib/updater/installer.sh`
- `lib/updater/updater.sh`

## Critical Linux Port Changes
- Select Linux binaries for all architectures; remove Android-only downloads.
- `upyq` must use Linux yq release assets.
- `aarch64` mapping must not default to Android build.
- Replace grep-only GitHub JSON parsing with `jq` where available.

## Integrity Requirements
- Download to temp path first.
- Verify checksum when upstream publishes checksums.
- Verify non-empty executable and expected file type.
- Atomic move into final location.

Current Linux-native behavior:
- `checksum_policy = off|optional|required`
- verification supports literal sha256 or `checksum_file`
- file, archive, and directory payloads are staged before install
- runtime handoff happens only after validation + install succeed
- failed handoff restores the pre-update target from backup

## Subscription Pipeline
For mihomo:
1. download each source
2. detect base64 URI list vs YAML
3. normalize provider output
4. optionally extract `rules`
5. regenerate `proxy-providers` section

For sing-box:
- replace target config with downloaded file
- validate then reload/restart

## Geodata + CN IP
- Keep separate toggles for core geodata and CN IP lists.
- Store last-updated metadata (`/var/lib/box/state/update.json`).

## Dashboard Update
- Keep external-ui URL override behavior.
- Extract archive to temp dir; move only validated payload.

Current Linux-native install kinds:
- `kernel`: file -> executable target
- `subs`: file -> config source target
- `geo`: file -> data target
- `dashboard`: archive or directory -> target directory

## Config Model

Single file for now: `/etc/box/box.toml`

```toml
[updater]
artifact_dir = "/var/lib/box/artifacts"
staging_dir = "/var/lib/box/staging"
checksum_policy = "optional"
kernel_interval = "daily"
subs_interval = "hourly"
geo_interval = "daily"
dashboard_interval = "weekly"

[updater.kernel]
url = ""
file = ""
checksum = ""
checksum_file = ""
target = ""
```

Accepted source fields per component:
- `url` or `file`
- optional `checksum` or `checksum_file`
- optional `target`

Failure rules:
- no configured source => component update fails safely
- explicit checksum mismatch => install aborted
- download failure => install aborted
- unchanged payload => status becomes `unchanged` and no runtime handoff runs

## Timed Execution
Replace embedded crond logic with systemd timers:
- `box-update-subscriptions.timer`
- `box-update-geodata.timer`
- optional combined `box-update-all.timer`

Implemented units:
- `box-update-kernel.service` + `.timer`
- `box-update-subs.service` + `.timer`
- `box-update-geo.service` + `.timer`
- `box-update-dashboard.service` + `.timer`
- `box-update-all.service` + `.timer`

Timer notes:
- shipped timers use conservative fixed schedules matching the default config intervals
- if you need different schedules, override the timer units with normal systemd drop-ins
- do not enable per-component timers together with `box-update-all.timer` unless repeated update attempts are acceptable

## Resolver Strategy by Core
1. Query release metadata (GitHub API).
2. Select tag by policy (`stable`, `prerelease`).
3. Select asset by `{os, arch, libc}`.
4. Fetch artifact + optional checksum.
5. Validate and install atomically.

## Atomic Install Procedure
```bash
download -> verify -> unpack(tmp) -> smoke-check(version) -> move(final) -> chmod/chown -> cleanup
```

## Security Hardening
- reject downloads over insecure transport unless explicitly configured
- support pinned checksum files
- store last successful artifact metadata for rollback

## Update State File
`/var/lib/box/state/update-state.json`:
- `last_success_by_component`
- `last_attempt_by_component`
- `installed_versions`
- `failed_reason`

Current Linux-native status file shape:
- top-level runtime metadata: `timestamp`, `artifact_dir`, `staging_dir`, `checksum_policy`, `core`
- per-component state:
  - `configured`
  - `status`
  - `last_error`
  - `last_attempt_ts`
  - `last_success_ts`
  - `source_ref`
  - `target_path`
  - `installed_sha256`
  - `last_handoff`
  - `interval`

## Subscription Validation
Before activation:
- parse output format
- ensure provider content non-empty
- run core-specific config check
- only then trigger reload/restart

Current handoff behavior:
- `sing-box` subscriptions: controlled restart
- `mihomo` subscriptions: controlled restart
- `kernel` and `geo`: controlled restart when service is running
- `dashboard`: no runtime handoff

TODO:
- replace restart fallback with real API-driven reloads once core-specific reload endpoints are implemented
