#!/usr/bin/env bash

set -euo pipefail

action="${1:-status}"

require_systemctl() {
  if ! command -v systemctl >/dev/null 2>&1; then
    printf 'systemctl not found; this helper requires systemd.\n' >&2
    exit 1
  fi
}

usage() {
  cat <<USAGE
Usage:
  $0 <enable|disable|restart|status>

Notes:
  - disable/restart actions only manage units and do not delete /etc/box or /var/lib/box.
  - enable starts the core units, conditionally enables policy if configured, and enables the default
    scheduled updater timer (`box-update-all.timer`).
  - use package removal + manual purge only when full cleanup is explicitly desired.
USAGE
}

policy_enabled_in_config() {
  local boxctl_path output

  boxctl_path="$(command -v boxctl || true)"
  [[ -n "${boxctl_path}" ]] || return 1

  if ! output="$("${boxctl_path}" policy status --json 2>/dev/null)"; then
    return 1
  fi

  grep -q '"policy_enabled":true' <<<"${output}"
}

enable_units() {
  require_systemctl
  systemctl daemon-reload
  systemctl enable box.service box-firewall.service
  if policy_enabled_in_config; then
    systemctl enable box-policy.service
    systemctl start box-policy.service
  else
    systemctl disable box-policy.service >/dev/null 2>&1 || true
    systemctl stop box-policy.service >/dev/null 2>&1 || true
  fi
  systemctl enable box-update-all.timer
  systemctl start box.service
  systemctl start box-update-all.timer
  systemctl reload-or-restart box-firewall.service || true
}

disable_units() {
  require_systemctl
  systemctl stop \
    box-policy.service \
    box-firewall.service \
    box.service \
    box-update-kernel.timer \
    box-update-subs.timer \
    box-update-geo.timer \
    box-update-dashboard.timer \
    box-update-all.timer || true
  systemctl disable \
    box-policy.service \
    box-firewall.service \
    box.service \
    box-update-kernel.timer \
    box-update-subs.timer \
    box-update-geo.timer \
    box-update-dashboard.timer \
    box-update-all.timer || true
  systemctl daemon-reload
}

restart_units() {
  require_systemctl
  systemctl daemon-reload
  systemctl restart box.service
  if policy_enabled_in_config; then
    systemctl try-restart box-policy.service || true
  else
    systemctl stop box-policy.service >/dev/null 2>&1 || true
  fi
  systemctl reload-or-restart box-firewall.service || true
  systemctl try-restart \
    box-update-kernel.timer \
    box-update-subs.timer \
    box-update-geo.timer \
    box-update-dashboard.timer \
    box-update-all.timer || true
}

status_units() {
  require_systemctl
  systemctl --no-pager --full status \
    box.service \
    box-firewall.service \
    box-policy.service \
    box-update-kernel.timer \
    box-update-subs.timer \
    box-update-geo.timer \
    box-update-dashboard.timer \
    box-update-all.timer || true
}

case "${action}" in
  enable) enable_units ;;
  disable) disable_units ;;
  restart) restart_units ;;
  status) status_units ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
