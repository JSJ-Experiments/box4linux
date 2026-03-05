#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

source "${BOX_LIB_DIR}/firewall/backend_iptables.sh"

firewall_state_file() {
  init_runtime_paths
  printf '%s/firewall.state\n' "${BOX_RUN_DIR}"
}

firewall_write_state() {
  local state_file mode status
  mode="${1:?missing mode}"
  status="${2:?missing status}"
  state_file="$(firewall_state_file)"
  cat >"${state_file}" <<EOF
mode=${mode}
status=${status}
backend=${BOX_FIREWALL_BACKEND}
route_table=${BOX_ROUTE_TABLE}
route_pref=${BOX_ROUTE_PREF}
fwmark=${BOX_FWMARK}
timestamp=$(timestamp_utc)
EOF
}

firewall_print_state() {
  local state_file
  state_file="$(firewall_state_file)"

  if [[ -f "${state_file}" ]]; then
    cat "${state_file}"
  else
    printf 'status=disabled\n'
    printf 'mode=%s\n' "${BOX_NETWORK_MODE}"
    printf 'backend=%s\n' "${BOX_FIREWALL_BACKEND}"
  fi
}

firewall_enable_locked() {
  require_root || return 1
  load_config

  case "${BOX_FIREWALL_BACKEND}" in
    iptables)
      backend_iptables_apply_mode "${BOX_NETWORK_MODE}"
      ;;
    *)
      log "ERROR" "firewall" "E_FW_BACKEND" "unsupported firewall backend: ${BOX_FIREWALL_BACKEND}"
      return "${E_FIREWALL_APPLY}"
      ;;
  esac

  firewall_write_state "${BOX_NETWORK_MODE}" "enabled"
  log "INFO" "firewall" "FW_ENABLED" "firewall enabled with mode=${BOX_NETWORK_MODE} backend=${BOX_FIREWALL_BACKEND}"
}

firewall_disable_locked() {
  require_root || return 1
  load_config

  case "${BOX_FIREWALL_BACKEND}" in
    iptables) backend_iptables_cleanup ;;
    *)
      log "WARN" "firewall" "FW_BACKEND_UNKNOWN" "unknown backend on disable: ${BOX_FIREWALL_BACKEND}"
      ;;
  esac

  firewall_write_state "${BOX_NETWORK_MODE}" "disabled"
  log "INFO" "firewall" "FW_DISABLED" "firewall disabled"
}

firewall_enable() {
  with_lock "firewall" 30 firewall_enable_locked
}

firewall_disable() {
  with_lock "firewall" 30 firewall_disable_locked
}

firewall_renew() {
  with_lock "firewall" 30 firewall_renew_locked
}

firewall_renew_locked() {
  require_root || return 1
  firewall_disable_locked
  firewall_enable_locked
}

firewall_status() {
  load_config || true
  firewall_print_state

  case "${BOX_FIREWALL_BACKEND}" in
    iptables)
      backend_iptables_status
      ;;
    *)
      printf 'backend=%s available=false reason="unsupported backend"\n' "${BOX_FIREWALL_BACKEND}"
      ;;
  esac
}

firewall_cmd() {
  local action="${1:-}"
  case "${action}" in
    enable) firewall_enable ;;
    disable) firewall_disable ;;
    renew) firewall_renew ;;
    status) firewall_status ;;
    *)
      printf 'usage: boxctl firewall <enable|disable|renew|status>\n' >&2
      return 2
      ;;
  esac
}
