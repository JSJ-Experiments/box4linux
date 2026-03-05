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
  - use package removal + manual purge only when full cleanup is explicitly desired.
USAGE
}

enable_units() {
  require_systemctl
  systemctl daemon-reload
  systemctl enable box.service box-firewall.service
  systemctl start box.service
  systemctl reload-or-restart box-firewall.service || true
}

disable_units() {
  require_systemctl
  systemctl stop box-firewall.service box.service || true
  systemctl disable box-firewall.service box.service || true
  systemctl daemon-reload
}

restart_units() {
  require_systemctl
  systemctl daemon-reload
  systemctl restart box.service
  systemctl reload-or-restart box-firewall.service || true
}

status_units() {
  require_systemctl
  systemctl --no-pager --full status box.service box-firewall.service || true
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
