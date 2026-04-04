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

Current Linux-native implementation:
- `lib/policy/context.sh`
- `lib/policy/engine.sh`
- `lib/policy/policy.sh`
- `systemd/box-policy.service`

Implemented control surface:
- `boxctl policy evaluate|enable|disable|status`
- hidden `boxctl policy monitor` action for `systemd`

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

## DNS Orchestrator Coexistence (resolved + Tailscale + Proxy TUN)
On Linux hosts like this one, DNS can be simultaneously influenced by:
- `systemd-resolved` link domains and per-link DNS
- Tailscale MagicDNS (`tailscale0`, `100.100.100.100`, `*.ts.net`)
- Proxy TUN DNS default route domains (for example `~.` on a proxy tunnel)

Policy/watcher implications:
- Do not assume a single DNS authority.
- Detect and log current per-link DNS owners before applying DNS interception.
- Add a `dns_coexist_mode` policy:
  - accepted values: `preserve_tailnet|strict_box`
  - `preserve_tailnet` (default): do not hijack Tailscale resolver/domain path; preserve MagicDNS/system resolver flow.
  - `strict_box`: explicit opt-in for full Box DNS hijack behavior.
- If `preserve_tailnet`, route `*.ts.net`/MagicDNS via system resolver path and bypass proxy DNS interception for Tailscale resolver.

## Concurrency and Locking
- Keep lock directory semantics under `/var/run/box/locks`.
- one active policy evaluation at a time.
- coalesce rapid network events.
- address-triggered firewall refresh runs as a separate background `firewall renew` worker so policy evaluation does not block on full firewall reapply.

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

## Status Contract
`boxctl policy status --json` includes:
- `status`
- `policy_enabled`
- `watcher_running`
- `pid`
- `desired_state`
- `applied_state`
- `proxy_mode`
- `debounce_seconds`
- `active_ifaces`
- `wifi_connected`
- `ssid`
- `bssid`
- `disable_marker_present`
- `last_reason`
- `last_error`
- `last_event`
- `last_event_ts`
- `last_refresh_ts`
