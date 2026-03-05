# 05 - Component: Updater and Assets

## Objective
Port `box.tool` update capabilities with stronger integrity and Linux artifact selection.

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

## Timed Execution
Replace embedded crond logic with systemd timers:
- `box-update-subscriptions.timer`
- `box-update-geodata.timer`
- optional combined `box-update-all.timer`

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

## Subscription Validation
Before activation:
- parse output format
- ensure provider content non-empty
- run core-specific config check
- only then trigger reload/restart
