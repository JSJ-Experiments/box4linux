# 08 - Delivery Plan and Risk Register

## Implementation Phases
1. Foundation
- config loader/validator
- `boxctl` skeleton
- logging + lock utility

2. Core Supervisor
- adapters for `mihomo` and `sing-box` first
- start/stop/status/reload

3. Firewall
- `iptables-nft` backend for `tproxy`, `redirect`, `tun`
- add `mixed` and `enhance`

4. Updater
- kernel updater + yq/curl installer
- subscription and geodata pipeline

5. Policy Watchers
- netlink-based policy daemon
- anti-loop refresh worker

6. Packaging/Operations
- systemd units/timers
- deb/rpm or install script

## Acceptance Criteria
- feature parity with current command surface
- idempotent start/stop/firewall operations
- restart-safe and reboot-safe behavior
- no Android-only command dependency

## High-Risk Areas
1. Netfilter backend variance (`iptables-nft` vs legacy)
2. TPROXY support differences across kernels
3. cgroup v1/v2 behavior mismatch
4. core config mutation compatibility across core versions
5. remote release asset naming changes

## Known Baseline Issues (from source audit)
- undefined `${settings}` writes in `box.service` and `box.iptables`
- `ctr.inotify` undefined `RUN_DIR`
- recursive restart pattern in `start_box`
- Android-only assumptions in status telemetry and boot gates
- architecture mapping downloads Android binaries in multiple update paths

## Test Matrix
- Distros: Debian/Ubuntu, Arch, OpenWrt-like minimal shell target
- Architectures: `x86_64`, `aarch64`
- Modes: `tun`, `tproxy`, `redirect`, `mixed`, `enhance`
- Cores: `mihomo`, `sing-box` (phase 1), then `xray`, `v2fly`, `hysteria`
- IPv4-only / dual-stack

## Suggested Initial Milestone
Deliver MVP with:
- `mihomo` + `sing-box`
- `tun` and `tproxy`
- updater for kernel + subscriptions + geodata
- systemd-managed lifecycle
Then expand to remaining cores/modes.

## Deliverables by Phase
### Phase 1
- `boxctl` + config loader + supervisor for `mihomo`/`sing-box`
- basic systemd service

### Phase 2
- firewall backend with `tun`, `tproxy`, `redirect`
- integration tests for apply/cleanup idempotency

### Phase 3
- updater (kernel/subscriptions/geodata)
- timers

### Phase 4
- policy watcher + anti-loop refresher
- packaging for target distros

## CI Requirements
- shell lint (`shellcheck`)
- unit tests for config parser and policy evaluator
- integration tests in privileged container/VM for firewall modes
- release artifact test matrix by architecture

## Exit Criteria for Linux Port v1
- all critical commands implemented
- no Android-only command/path usage
- documented upgrade and rollback path
- reproducible installation on at least two Linux distributions

## Linux-Native Implementation Checklist
Use this checklist during review to keep the port \"native\":
- `boxctl` is the only public control surface (not direct script internals).
- `systemd` starts/stops service and firewall; no boot-hook compatibility glue in core path.
- Firewall backend is modular (`iptables` now, `nftables` ready path later).
- UID/GID policy comes from Linux user/group model, not Android package database logic.
- Network policy uses Linux event sources (netlink/NetworkManager/iw), not Android probes.
- Updates resolve Linux artifacts by OS/arch/libc with checksum-aware install flow.
- Health/status are exportable as JSON for operations tooling.
- Integration tests cover mode transitions and full cleanup after failures.

## Suggested Build Start (Practical)
1. Build `cmd/boxctl` + config loader + lock/log utilities.
2. Add `lib/firewall` with one backend (`iptables-nft`) and full cleanup guarantees.
3. Support only `mihomo` and `sing-box` first, then expand cores.
4. Add updater + timers after service and firewall are stable.
