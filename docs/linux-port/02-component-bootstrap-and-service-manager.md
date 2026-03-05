# 02 - Component: Bootstrap and Service Manager

## Objective
Replace Magisk/KSU/APatch boot glue with Linux-native service lifecycle.

## Baseline Behavior
Current boot/install pieces:
- `box-reference/box/customize.sh` installs payload and boot hook
- `box-reference/box/box_service.sh` waits for boot completion and triggers `box-reference/box/box/scripts/start.sh`
- `box-reference/box/box/scripts/start.sh` starts service/firewall and watchers
- `box-reference/box/action.sh` toggles start/stop manually

## Linux Replacement Design
Use systemd units:
1. `box.service`
- `Type=notify` (or `simple` first)
- `ExecStart=/usr/lib/box/boxctl service start`
- `ExecStop=/usr/lib/box/boxctl service stop`
- `ExecReload=/usr/lib/box/boxctl service reload`
- `After=network-online.target`

2. `box-firewall.service`
- `ExecStart=/usr/lib/box/boxctl firewall enable`
- `ExecStop=/usr/lib/box/boxctl firewall disable`
- `PartOf=box.service`

3. Optional policy watcher:
- `box-policy.service`

## Startup Sequence (Linux)
1. Load and validate config.
2. Preflight checks (binary exists, capability support, permissions).
3. Start selected core and wait healthy.
4. Apply firewall rules for selected mode.
5. Start policy watcher (if enabled).
6. Publish runtime state.

## Shutdown Sequence
1. Stop policy watcher.
2. Remove firewall/routing/ipset state.
3. Stop core process gracefully; force after timeout.
4. Clear pid + runtime snapshots.

## CLI Wrapper (`boxctl`)
Must remain idempotent:
- repeat `start`: no duplicate processes/rules
- repeat `enable firewall`: no duplicate chains/rules
- repeat `stop/disable`: clean success even if already stopped

## Reliability Requirements
- Fail fast if firewall setup fails after core start: either rollback core or keep core in non-transparent mode with explicit warning.
- Structured logs per component.
- Exit codes consistent for systemd (`0` success, non-zero failure class).

## Immediate Porting Deltas
- Remove Android boot wait gates (`bootanim`, `packages.xml`).
- Replace inotifyd process-kill heuristics with dedicated services.
- Avoid recursive restart patterns observed in current `start_box` flow.

## Example `box.service` (systemd)
```ini
[Unit]
Description=Box Core Supervisor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/boxctl service start
ExecStop=/usr/bin/boxctl service stop
ExecReload=/usr/bin/boxctl service reload
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
```

## Control Flow Pseudocode
```bash
service_start() {
  load_config
  validate_config
  acquire_lock service
  preflight
  start_core
  wait_core_healthy
  boxctl firewall enable
  start_optional_policy_watcher
  write_runtime_state
}
```

## Failure Classification
- `E_CONFIG`: invalid config
- `E_CORE_START`: binary/config runtime failure
- `E_FIREWALL_APPLY`: rule application failed
- `E_POLICY`: watcher/policy subsystem failed

Return codes must map to these classes for automation.
