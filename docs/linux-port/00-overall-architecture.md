# 00 - Overall Architecture

## Goal
Port Box from Android/Magisk execution model to a Linux-native service stack while preserving feature parity:
- Core lifecycle management (`mihomo`, `sing-box`, `xray`, `v2fly`, `hysteria`)
- Transparent proxy modes (`tun`, `tproxy`, `redirect`, `mixed`, `enhance`)
- Subscription and geodata updates
- Optional network-state based auto control

## Current Runtime Topology (Observed)
Primary call graph in current project:
1. Boot hook runs `box-reference/box/box_service.sh`.
2. `box-reference/box/box_service.sh` launches `box-reference/box/box/scripts/start.sh`.
3. `start.sh` calls:
- `box.service start`
- `box.iptables enable`
- watchers: `box.inotify`, `net.inotify`, `ctr.inotify`
4. `box.service` handles core process, config mutation, crond, cgroup helpers.
5. `box.iptables` builds/tears down policy-routing and iptables rules.
6. `box.tool` handles updates, cgroup operations, web UI helpers.

Reference files:
- `box-reference/box/box/scripts/start.sh`
- `box-reference/box/box/scripts/box.service`
- `box-reference/box/box/scripts/box.iptables`
- `box-reference/box/box/scripts/box.tool`
- `box-reference/box/box/scripts/*.inotify`, `box-reference/box/box/scripts/ctr.utils`

## Linux Target Topology
Use explicit components with stable interfaces:
1. `boxd-supervisor` (core process supervisor)
2. `boxd-firewall` (transparent proxy/network rules)
3. `boxd-updater` (core binaries, subscriptions, geodata, dashboards)
4. `boxd-policy` (network/Wi-Fi policy control)
5. `boxctl` CLI (user entrypoint)
6. `systemd` units and timers (boot, restart, scheduled jobs)

## Proposed Filesystem Layout
- `/etc/box/`
- `box.toml` (main settings)
- `profiles/` (core-specific configs)
- `/var/lib/box/`
- `bin/` (managed binaries)
- `providers/`, `geodata/`, `dashboard/`
- `/var/run/box/`
- pid, locks, runtime snapshots
- `/var/log/box/`
- service, firewall, updater, policy logs

## Component Boundaries
- Supervisor owns core process state only.
- Firewall owns all rules, routing tables, fwmarks, ipsets.
- Updater owns remote fetches and local artifact replacement.
- Policy engine only decides start/stop intent based on network context.

## Command Contract
`boxctl <component> <action>`
- `boxctl service start|stop|restart|status|reload`
- `boxctl firewall enable|disable|renew|status`
- `boxctl update kernel|subs|geo|dashboard|all`
- `boxctl policy evaluate|enable|disable|status`

## Hard Porting Constraints
- Replace Android-only commands (`getprop`, `dumpsys`, `cmd wifi`).
- Replace Magisk paths (`/data/adb/...`) with Linux paths.
- Replace BusyBox-specific assumptions with distro tooling or bundled utilities.
- Add cgroup v2 support first-class (not just cgroup v1).

## Architecture Decisions
1. Keep shell implementation (bash) for near-term parity.
2. Introduce backend abstraction for firewall (`iptables-nft` first, `nftables` optional).
3. Treat config mutation as deterministic transform step before core launch.
4. Use systemd timers instead of embedded `crond` where available.

## Linux-Native Quality Bar (Avoid \"Machine-Transpiled\" Feel)
The port should behave like a first-class Linux service, not an Android script bundle moved to Linux.

Required characteristics:
1. Linux control plane first: `systemd` units/timers and clear `boxctl` subcommands.
2. Linux filesystem contracts: `/etc/box`, `/var/lib/box`, `/run/box`, `/var/log/box`.
3. No Android-only primitives in runtime path (`getprop`, `cmd wifi`, `/data/adb/*`).
4. Runtime overlays, not in-place config mutation of source files.
5. cgroup v2-first resource controls with explicit v1 fallback behavior.
6. Structured logs and machine-readable status (`boxctl ... --json`).
7. Strict idempotency and rollback for start/stop/firewall/update paths.
8. Capability-driven behavior (probe kernel features, then choose mode or downgrade).

## Detailed Component API Boundaries
### Supervisor -> Firewall
- Input: selected core, network mode, proxy mode, port map, owner identity
- Contract: `firewall enable` only after core health is `healthy`
- Failure: if firewall apply fails, supervisor marks service degraded and can optionally stop core

### Updater -> Supervisor
- After binary/config replacement, updater triggers `boxctl service reload`.
- If reload not supported by current core, updater triggers controlled restart.

### Policy -> Supervisor/Firewall
- Policy emits target state transitions only: `enabled` or `disabled`.
- Policy does not edit config directly.

## Required Shared Library
Implement `/usr/lib/box/lib/common.sh` with:
- lock helpers (`with_lock`, `try_lock`, lock timeout)
- structured logging (`level`, `component`, `event_id`)
- preflight checks (`require_cmd`, `require_root`)
- config snapshot loader

## Proposed Source Tree (Linux Port)
All new source lives at repository root.

- `cmd/boxctl`
- `lib/common.sh`
- `lib/config.sh`
- `lib/supervisor/*.sh`
- `lib/firewall/*.sh`
- `lib/updater/*.sh`
- `lib/policy/*.sh`
- `systemd/*.service`, `systemd/*.timer`
- `tests/integration/*.bats`
