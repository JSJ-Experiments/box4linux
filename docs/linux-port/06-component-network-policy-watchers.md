# 06 - Component: Network Policy and Watchers

## Objective
Port watcher/inotify behavior (`ctr.inotify`, `ctr.utils`, `net.inotify`, `box.inotify`) to Linux-native event handling.

## Baseline Behaviors
1. `box.inotify`
- reacts to module `disable` file create/delete to stop/start services
2. `net.inotify`
- updates `LOCAL_IP_V4/V6` anti-loop chains when network files change
3. `ctr.inotify` + `ctr.utils`
- evaluates Wi-Fi status/SSID/BSSID policy and toggles service

## Linux Watcher Design
Use separate daemons or systemd path/network units:
1. `box-policyd`
- subscribes to netlink events (`ip monitor link/route/address`)
- debounced evaluation window (keep current 3s concept)
2. `box-firewall-refreshd`
- recompute local IP anti-loop chains on address changes
3. optional file-triggered control
- if needed for manual disable marker compatibility

## Policy Engine Contract
Input:
- network status
- SSID/BSSID (optional; only on Wi-Fi capable hosts)
- policy config (`use_module_on_wifi*`, list mode, allow/deny lists)

Output:
- desired state: `enabled` or `disabled`

Action:
- call `boxctl service start/stop`
- call `boxctl firewall enable/disable`

## Linux Data Source Replacement
- Android `cmd wifi status` -> `nmcli`, `iw`, or NetworkManager DBus
- interface/IP detection remains via `ip` tooling

## Concurrency and Locking
- Keep lock directory semantics under `/var/run/box/locks`.
- one active policy evaluation at a time.
- coalesce rapid network events.

## Baseline Defects to Correct
- `ctr.inotify` references undefined `RUN_DIR`.
- process matching via cmdline greps is brittle.
- watcher boot order currently coupled to filesystem probe race.

## Policy State Machine
- `S_INIT`
- `S_WAIT_STABLE`
- `S_EVALUATE`
- `S_APPLY_ENABLE`
- `S_APPLY_DISABLE`
- `S_IDLE`

Transitions are triggered by network events and debounce timers.

## Event Loop Pseudocode
```bash
on_net_event() {
  if within_stability_window; then return; fi
  state = evaluate_policy(current_network_context)
  if state == enabled; then
    boxctl service start && boxctl firewall enable
  else
    boxctl firewall disable && boxctl service stop
  fi
}
```

## Linux SSID/BSSID Resolution Priority
1. NetworkManager DBus (`nmcli -t -f active,ssid,bssid dev wifi`)
2. `iw dev <iface> link`
3. fallback `unknown`

If SSID data unavailable, policy should default based on `use_module_on_wifi_disconnect`.
