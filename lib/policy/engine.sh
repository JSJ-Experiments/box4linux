#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

POLICY_DESIRED_STATE="disabled"
POLICY_APPLIED_STATE="unchanged"
POLICY_REASON=""
POLICY_LAST_ERROR=""

policy_array_matches() {
  local needle="${1:-}"
  shift || true
  local pattern glob
  [[ -n "${needle}" ]] || return 1
  for pattern in "$@"; do
    [[ -n "${pattern}" ]] || continue
    glob="${pattern//+/*}"
    # shellcheck disable=SC2254
    case "${needle}" in
      ${glob}) return 0 ;;
    esac
  done
  return 1
}

policy_ifaces_match_any() {
  local iface
  for iface in "${POLICY_CTX_IFACES[@]}"; do
    if policy_array_matches "${iface}" "$@"; then
      return 0
    fi
  done
  return 1
}

policy_disable_marker_present() {
  [[ -n "${BOX_POLICY_DISABLE_MARKER}" && -e "${BOX_POLICY_DISABLE_MARKER}" ]]
}

policy_service_healthy() {
  local pid
  pid="$(read_pid_file "$(service_pid_file_readonly)" || true)"
  is_pid_alive "${pid}"
}

policy_evaluate_desired_state() {
  POLICY_DESIRED_STATE="disabled"
  POLICY_REASON=""
  POLICY_LAST_ERROR=""

  policy_collect_context

  if ! policy_bool_true "${BOX_POLICY_ENABLED}"; then
    POLICY_REASON="policy disabled in config"
    return 0
  fi

  if policy_disable_marker_present; then
    POLICY_REASON="disable marker present"
    return 0
  fi

  if policy_bool_true "${POLICY_CTX_WIFI_CANDIDATE}" && ! policy_bool_true "${POLICY_CTX_WIFI_CONNECTED}"; then
    if policy_bool_true "${BOX_POLICY_USE_MODULE_ON_WIFI_DISCONNECT}"; then
      POLICY_DESIRED_STATE="enabled"
      POLICY_REASON="wifi identity unavailable; using disconnect fallback"
    else
      POLICY_REASON="wifi identity unavailable; using disconnect fallback"
    fi
    return 0
  fi

  if ! policy_bool_true "${POLICY_CTX_HAS_NETWORK}" && ! policy_bool_true "${POLICY_CTX_WIFI_CONNECTED}"; then
    if policy_bool_true "${BOX_POLICY_USE_MODULE_ON_WIFI_DISCONNECT}"; then
      POLICY_DESIRED_STATE="enabled"
      POLICY_REASON="wifi disconnect fallback enabled"
    else
      POLICY_REASON="no active network"
    fi
    return 0
  fi

  case "${BOX_POLICY_PROXY_MODE}" in
    core)
      POLICY_DESIRED_STATE="enabled"
      POLICY_REASON="core mode"
      ;;
    whitelist)
      if policy_ifaces_match_any "${BOX_POLICY_ALLOW_IFACES[@]}" || \
        policy_array_matches "${POLICY_CTX_SSID}" "${BOX_POLICY_ALLOW_SSIDS[@]}" || \
        policy_array_matches "${POLICY_CTX_BSSID}" "${BOX_POLICY_ALLOW_BSSIDS[@]}"; then
        POLICY_DESIRED_STATE="enabled"
        POLICY_REASON="whitelist match"
      else
        POLICY_REASON="no whitelist match"
      fi
      ;;
    blacklist)
      if policy_ifaces_match_any "${BOX_POLICY_IGNORE_IFACES[@]}" || \
        policy_array_matches "${POLICY_CTX_SSID}" "${BOX_POLICY_IGNORE_SSIDS[@]}" || \
        policy_array_matches "${POLICY_CTX_BSSID}" "${BOX_POLICY_IGNORE_BSSIDS[@]}"; then
        POLICY_REASON="blacklist match"
      else
        POLICY_DESIRED_STATE="enabled"
        POLICY_REASON="no blacklist match"
      fi
      ;;
  esac
}

policy_apply_desired_state() {
  local state="${1:?missing desired state}"

  POLICY_APPLIED_STATE="unchanged"
  case "${state}" in
    enabled)
      if policy_service_healthy; then
        POLICY_APPLIED_STATE="unchanged"
        return 0
      fi
      if ! service_start; then
        POLICY_LAST_ERROR="failed to start service for desired enabled state"
        return "${E_POLICY}"
      fi
      POLICY_APPLIED_STATE="started"
      ;;
    disabled)
      if ! policy_service_healthy; then
        POLICY_APPLIED_STATE="unchanged"
        return 0
      fi
      if ! service_stop; then
        POLICY_LAST_ERROR="failed to stop service for desired disabled state"
        return "${E_POLICY}"
      fi
      POLICY_APPLIED_STATE="stopped"
      ;;
    *)
      POLICY_LAST_ERROR="unsupported desired state: ${state}"
      return "${E_POLICY}"
      ;;
  esac
}

policy_refresh_firewall_if_running() {
  if policy_service_healthy; then
    policy_spawn_firewall_refresh
  fi
}
