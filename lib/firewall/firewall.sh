#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

source "${BOX_LIB_DIR}/firewall/backend_iptables.sh"
source "${BOX_LIB_DIR}/firewall/backend_nft.sh"

firewall_state_file() {
  init_runtime_paths
  printf '%s/firewall.state\n' "${BOX_RUN_DIR}"
}

firewall_write_state() {
  local mode="${1:?missing mode}"
  local status="${2:?missing status}"
  local state_file
  state_file="$(firewall_state_file)"
  cat >"${state_file}" <<EOF
mode=${mode}
status=${status}
backend=${BOX_FIREWALL_BACKEND}
dns_hijack_mode=${BOX_DNS_HIJACK_MODE}
dns_coexist_mode=${BOX_DNS_COEXIST_MODE}
route_table=${BOX_ROUTE_TABLE}
route_pref=${BOX_ROUTE_PREF}
fwmark=${BOX_FWMARK}
tailscale_iface=${BOX_TAILSCALE_IFACE}
tailscale_dns_resolver=${BOX_TAILSCALE_DNS_RESOLVER}
tailscale_fwmark=${BOX_TAILSCALE_FWMARK}
tailscale_route_table=${BOX_TAILSCALE_ROUTE_TABLE}
timestamp=$(timestamp_utc)
EOF
}

firewall_read_state_value() {
  local key="${1:?missing key}"
  local state_file
  state_file="$(firewall_state_file)"
  if [[ ! -f "${state_file}" ]]; then
    return 1
  fi
  awk -F= -v k="${key}" '$1==k {print substr($0, index($0, "=")+1); exit}' "${state_file}"
}

firewall_enable_locked() {
  require_root || return 1
  load_config

  case "${BOX_FIREWALL_BACKEND}" in
    iptables)
      if ! backend_iptables_apply_mode "${BOX_NETWORK_MODE}"; then
        log "ERROR" "firewall" "E_FW_APPLY" "firewall apply failed: ${FW_LAST_ERROR:-unknown}"
        return "${E_FIREWALL_APPLY}"
      fi
      ;;
    nftables)
      if ! backend_nft_apply_mode "${BOX_NETWORK_MODE}"; then
        log "ERROR" "firewall" "E_FW_APPLY" "firewall apply failed: ${FW_LAST_ERROR:-unknown}"
        return "${E_FIREWALL_APPLY}"
      fi
      ;;
    *)
      log "ERROR" "firewall" "E_FW_BACKEND" "unsupported firewall backend: ${BOX_FIREWALL_BACKEND}"
      return "${E_FIREWALL_APPLY}"
      ;;
  esac

  firewall_write_state "${BOX_NETWORK_MODE}" "enabled"
  log "INFO" "firewall" "FW_ENABLED" \
    "firewall enabled mode=${BOX_NETWORK_MODE} dns=${BOX_DNS_HIJACK_MODE} backend=${BOX_FIREWALL_BACKEND}"
}

firewall_disable_locked() {
  require_root || return 1
  load_config

  case "${BOX_FIREWALL_BACKEND}" in
    iptables) backend_iptables_cleanup ;;
    nftables) backend_nft_cleanup ;;
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

firewall_renew_locked() {
  require_root || return 1
  firewall_disable_locked
  firewall_enable_locked
}

firewall_renew() {
  with_lock "firewall" 30 firewall_renew_locked
}

firewall_dry_run() {
  local rc=0
  load_config
  export BOX_FIREWALL_DRY_RUN=1
  case "${BOX_FIREWALL_BACKEND}" in
    iptables) backend_iptables_apply_mode "${BOX_NETWORK_MODE}" || rc=$? ;;
    nftables) backend_nft_apply_mode "${BOX_NETWORK_MODE}" || rc=$? ;;
    *)
      log "ERROR" "firewall" "E_FW_BACKEND" "unsupported firewall backend: ${BOX_FIREWALL_BACKEND}"
      rc="${E_FIREWALL_APPLY}"
      ;;
  esac
  unset BOX_FIREWALL_DRY_RUN
  return "${rc}"
}

firewall_status_diag_defaults() {
  FW_BACKEND_AVAILABLE="false"
  FW_CHAIN_MANGLE="false"
  FW_CHAIN_NAT="false"
  FW_CHAIN_DNS_MANGLE="false"
  FW_CHAIN_DNS_NAT="false"
  FW_ROUTE_RULE="false"
  FW_ROUTE_TABLE_INSTALLED="false"
  FW_CAP_TPROXY="false"
  FW_TAILSCALE_MARK_RULE="false"
  FW_TAILSCALE_TABLE_PRESENT="false"
  FW_TAILSCALE_BYPASS_APPLIED="false"
  FW_CAP_IPV4="false"
  FW_CAP_IPV6="false"
  FW_DRY_RUN_SUPPORTED="true"
  FW_DNS_COEXIST_MODE_ACTIVE="${BOX_DNS_COEXIST_MODE}"
  FW_CAP_DETAILS="backend=${BOX_FIREWALL_BACKEND},available=false"
  FW_LAST_ERROR=""
}

firewall_collect_status() {
  firewall_status_diag_defaults
  case "${BOX_FIREWALL_BACKEND}" in
    iptables) backend_iptables_collect_status ;;
    nftables) backend_nft_collect_status ;;
    *)
      FW_BACKEND_AVAILABLE="false"
      FW_LAST_ERROR="unsupported backend: ${BOX_FIREWALL_BACKEND}"
      ;;
  esac
}

firewall_status_text() {
  local current_status current_mode
  current_status="$(firewall_read_state_value "status" || printf 'disabled')"
  current_mode="$(firewall_read_state_value "mode" || printf '%s' "${BOX_NETWORK_MODE}")"
  firewall_collect_status

  printf 'status=%s\n' "${current_status}"
  printf 'mode=%s\n' "${current_mode}"
  printf 'backend=%s\n' "${BOX_FIREWALL_BACKEND}"
  printf 'backend_selected=%s\n' "${BOX_FIREWALL_BACKEND}"
  printf 'backend_available=%s\n' "${FW_BACKEND_AVAILABLE}"
  printf 'dns_hijack_mode=%s\n' "${BOX_DNS_HIJACK_MODE}"
  printf 'dns_coexist_mode=%s\n' "${BOX_DNS_COEXIST_MODE}"
  printf 'dns_coexist_mode_active=%s\n' "${FW_DNS_COEXIST_MODE_ACTIVE}"
  printf 'tailscale_iface=%s\n' "${BOX_TAILSCALE_IFACE}"
  printf 'tailscale_dns_resolver=%s\n' "${BOX_TAILSCALE_DNS_RESOLVER}"
  printf 'tailscale_fwmark=%s\n' "${BOX_TAILSCALE_FWMARK}"
  printf 'tailscale_route_table=%s\n' "${BOX_TAILSCALE_ROUTE_TABLE}"
  printf 'backend_capabilities=%s\n' "${FW_CAP_DETAILS:-unknown}"
  printf 'cap_ipv4=%s\n' "${FW_CAP_IPV4}"
  printf 'cap_ipv6=%s\n' "${FW_CAP_IPV6}"
  printf 'dry_run_supported=%s\n' "${FW_DRY_RUN_SUPPORTED}"
  printf 'tailscale_bypass_applied=%s\n' "${FW_TAILSCALE_BYPASS_APPLIED}"
  printf 'cap_tproxy=%s\n' "${FW_CAP_TPROXY}"
  printf 'tailscale_mark_rule=%s\n' "${FW_TAILSCALE_MARK_RULE}"
  printf 'tailscale_table_present=%s\n' "${FW_TAILSCALE_TABLE_PRESENT}"
  printf 'chain_mangle=%s\n' "${FW_CHAIN_MANGLE}"
  printf 'chain_nat=%s\n' "${FW_CHAIN_NAT}"
  printf 'chain_dns_mangle=%s\n' "${FW_CHAIN_DNS_MANGLE}"
  printf 'chain_dns_nat=%s\n' "${FW_CHAIN_DNS_NAT}"
  printf 'route_rule=%s\n' "${FW_ROUTE_RULE}"
  printf 'route_table_installed=%s\n' "${FW_ROUTE_TABLE_INSTALLED}"
  printf 'last_error=%s\n' "${FW_LAST_ERROR:-}"
}

firewall_status_json() {
  local current_status current_mode
  local fields
  local error_part=""
  current_status="$(firewall_read_state_value "status" || printf 'disabled')"
  current_mode="$(firewall_read_state_value "mode" || printf '%s' "${BOX_NETWORK_MODE}")"
  firewall_collect_status

  fields=(
    "$(json_pair "status" "${current_status}")"
    "$(json_pair "mode" "${current_mode}")"
    "$(json_pair "backend" "${BOX_FIREWALL_BACKEND}")"
    "$(json_pair "backend_selected" "${BOX_FIREWALL_BACKEND}")"
    "$(json_pair "dns_hijack_mode" "${BOX_DNS_HIJACK_MODE}")"
    "$(json_pair "dns_coexist_mode" "${BOX_DNS_COEXIST_MODE}")"
    "$(json_pair "dns_coexist_mode_active" "${FW_DNS_COEXIST_MODE_ACTIVE}")"
    "$(json_pair "tailscale_iface" "${BOX_TAILSCALE_IFACE}")"
    "$(json_pair "tailscale_dns_resolver" "${BOX_TAILSCALE_DNS_RESOLVER}")"
    "$(json_pair "tailscale_fwmark" "${BOX_TAILSCALE_FWMARK}")"
    "$(json_pair "tailscale_route_table" "${BOX_TAILSCALE_ROUTE_TABLE}")"
    "$(json_pair "backend_capabilities" "${FW_CAP_DETAILS:-unknown}")"
    "$(json_pair "last_error" "${FW_LAST_ERROR:-}")"
    "$(json_bool_pair "backend_available" "${FW_BACKEND_AVAILABLE}")"
    "$(json_bool_pair "cap_tproxy" "${FW_CAP_TPROXY}")"
    "$(json_bool_pair "cap_ipv4" "${FW_CAP_IPV4}")"
    "$(json_bool_pair "cap_ipv6" "${FW_CAP_IPV6}")"
    "$(json_bool_pair "dry_run_supported" "${FW_DRY_RUN_SUPPORTED}")"
    "$(json_bool_pair "tailscale_bypass_applied" "${FW_TAILSCALE_BYPASS_APPLIED}")"
    "$(json_bool_pair "tailscale_mark_rule" "${FW_TAILSCALE_MARK_RULE}")"
    "$(json_bool_pair "tailscale_table_present" "${FW_TAILSCALE_TABLE_PRESENT}")"
    "$(json_bool_pair "chain_mangle" "${FW_CHAIN_MANGLE}")"
    "$(json_bool_pair "chain_nat" "${FW_CHAIN_NAT}")"
    "$(json_bool_pair "chain_dns_mangle" "${FW_CHAIN_DNS_MANGLE}")"
    "$(json_bool_pair "chain_dns_nat" "${FW_CHAIN_DNS_NAT}")"
    "$(json_bool_pair "route_rule" "${FW_ROUTE_RULE}")"
    "$(json_bool_pair "route_table_installed" "${FW_ROUTE_TABLE_INSTALLED}")"
  )

  if [[ -n "${FW_LAST_ERROR:-}" ]]; then
    error_part=",$(json_pair "error" "${FW_LAST_ERROR}")"
  fi

  local IFS=,
  printf '{%s%s}\n' "${fields[*]}" "${error_part}"
}

firewall_status() {
  load_config
  if [[ "${BOX_OUTPUT_FORMAT}" == "json" ]]; then
    firewall_status_json
  else
    firewall_status_text
  fi
}

firewall_cmd() {
  local action="${1:-}"
  case "${action}" in
    enable) firewall_enable ;;
    disable) firewall_disable ;;
    renew) firewall_renew ;;
    dry-run) firewall_dry_run ;;
    status) firewall_status ;;
    *)
      printf 'usage: boxctl firewall <enable|disable|renew|status|dry-run> [--json]\n' >&2
      return 2
      ;;
  esac
}
