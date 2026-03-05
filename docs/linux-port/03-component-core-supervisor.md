# 03 - Component: Core Supervisor

## Objective
Implement Linux `box.service` equivalent for process lifecycle and config prep.

## Baseline Responsibilities
Current `box-reference/box/box/scripts/box.service` does:
- Build UID list from app/gid config
- Validate and mutate core config
- Start selected core binary
- Manage cron tasks
- Apply cgroup tuning through `box.tool`
- Health/status logging

## Linux Supervisor Modules
1. `supervisor.sh`
- command dispatcher: `start|stop|restart|status|reload`
2. `core_adapter_<name>.sh`
- per-core check/start args
3. `config_mutator_<name>.sh`
- deterministic config transformations
4. `health_probe.sh`
- pid, sockets, optional API check

## Core Adapter Contract
Each adapter exposes:
- `core_check_config()`
- `core_start()`
- `core_stop()`
- `core_version()`
- `core_reload()`

## Config Mutation Plan
### Sing-box
- Maintain tun/tproxy/redirect inbound blocks by mode.
- Keep port sync (`tproxy_port`, `redir_port`).
- Replace Android-only fields (`include_android_user`) with Linux-compatible UID rules.

### Mihomo
- Ensure controller and UI path.
- Keep tun block only for tun/mixed modes.
- Keep `enhanced-mode` policy logic but avoid silent forced rewrites; emit warnings + explicit override option.

### Xray/V2Fly/Hysteria
- Enforce supported mode mapping through validator.
- Do not silently mutate persisted config; write runtime overlay config in `/var/run/box/rendered/`.

## Linux User/Group Policy
Current Android app UID model (`/data/system/packages.list`) should be replaced by:
- explicit `include_uids`, `exclude_uids`
- `include_gids`, `exclude_gids`
- optional process-owner rule sets

## cgroup Strategy
- Implement cgroup v2 first:
- memory: `memory.max`
- cpuset: `cpuset.cpus`, `cpuset.mems`
- io: `io.weight`
- Add v1 fallback only if required by target distro.

## Known Baseline Defects To Fix During Port
- Undefined `${settings}` writes.
- `state` variable used without definition in status output.
- status path depends on Android-specific battery and DNS sources.
- crond start/stop path mismatch.

## Adapter Command Details
### Mihomo
- check: `mihomo -t -d <workdir> -f <config>`
- run: `mihomo -d <workdir> -f <config>`
- reload: REST API call to external-controller (if configured)

### Sing-box
- check: `sing-box check -c <config> -D <workdir>`
- run: `sing-box run -c <config> -D <workdir>`
- reload: REST API call where supported

### Xray / V2Fly
- prefer restart reload strategy
- check before restart to prevent dead config deployment

## Rendered Runtime Config Policy
Do not mutate `/etc/box/profiles/*` in place at runtime.
Generate per-start rendered config files:
- `/var/run/box/rendered/<core>/config.*`

Benefits:
- deterministic diff
- safe rollback
- user config source remains clean

## Health Model
- `starting`: process spawned, waiting probe
- `healthy`: probes pass
- `degraded`: process alive but one or more checks failed
- `stopped`: no pid
- `failed`: startup failed
