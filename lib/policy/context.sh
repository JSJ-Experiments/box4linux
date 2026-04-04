#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

POLICY_CTX_HAS_NETWORK="false"
POLICY_CTX_WIFI_CONNECTED="false"
POLICY_CTX_WIFI_CANDIDATE="false"
POLICY_CTX_SSID=""
POLICY_CTX_BSSID=""
declare -a POLICY_CTX_IFACES=()

policy_ip_cmd() {
  printf '%s\n' "${BOX_IP_CMD:-ip}"
}

policy_nmcli_cmd() {
  printf '%s\n' "${BOX_NMCLI_CMD:-nmcli}"
}

policy_iw_cmd() {
  printf '%s\n' "${BOX_IW_CMD:-iw}"
}

policy_bool_true() {
  case "${1:-false}" in
    true|1|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

policy_reset_context() {
  POLICY_CTX_HAS_NETWORK="false"
  POLICY_CTX_WIFI_CONNECTED="false"
  POLICY_CTX_WIFI_CANDIDATE="false"
  POLICY_CTX_SSID=""
  POLICY_CTX_BSSID=""
  POLICY_CTX_IFACES=()
}

policy_collect_ifaces() {
  local ip_tool line iface
  local -a ifaces=()

  ip_tool="$(policy_ip_cmd)"
  if ! command -v "${ip_tool}" >/dev/null 2>&1; then
    return 0
  fi

  while IFS= read -r line; do
    iface="$(sed -n 's/^[0-9][0-9]*: \([^:[:space:]]\+\).*/\1/p' <<<"${line}")"
    iface="${iface%@*}"
    [[ -n "${iface}" && "${iface}" != "lo" ]] || continue
    case "${iface}" in
      wlan*|wl*|wifi*) POLICY_CTX_WIFI_CANDIDATE="true" ;;
    esac
    if [[ " ${ifaces[*]} " != *" ${iface} "* ]]; then
      ifaces+=("${iface}")
    fi
  done < <("${ip_tool}" -o link show up 2>/dev/null || true)

  POLICY_CTX_IFACES=("${ifaces[@]}")
  if [[ "${#POLICY_CTX_IFACES[@]}" -gt 0 ]]; then
    POLICY_CTX_HAS_NETWORK="true"
  fi
}

policy_collect_wifi_nmcli() {
  local nmcli_tool line

  nmcli_tool="$(policy_nmcli_cmd)"
  command -v "${nmcli_tool}" >/dev/null 2>&1 || return 1

  while IFS= read -r line; do
    case "${line}" in
      yes:*|true:*|\**)
        POLICY_CTX_WIFI_CONNECTED="true"
        IFS=: read -r _ POLICY_CTX_SSID POLICY_CTX_BSSID <<<"${line}"
        return 0
        ;;
    esac
  done < <("${nmcli_tool}" -t -f active,ssid,bssid dev wifi 2>/dev/null || true)
  return 1
}

policy_collect_wifi_iw() {
  local iw_tool iface line

  iw_tool="$(policy_iw_cmd)"
  command -v "${iw_tool}" >/dev/null 2>&1 || return 1

  for iface in "${POLICY_CTX_IFACES[@]}"; do
    while IFS= read -r line; do
      case "${line}" in
        Connected\ to\ *)
          POLICY_CTX_WIFI_CONNECTED="true"
          POLICY_CTX_BSSID="$(awk '{print $3}' <<<"${line}")"
          ;;
        SSID:*)
          POLICY_CTX_SSID="${line#SSID: }"
          ;;
      esac
    done < <("${iw_tool}" dev "${iface}" link 2>/dev/null || true)
    if policy_bool_true "${POLICY_CTX_WIFI_CONNECTED}"; then
      return 0
    fi
  done
  return 1
}

policy_collect_context() {
  policy_reset_context
  policy_collect_ifaces
  policy_collect_wifi_nmcli || policy_collect_wifi_iw || true
}
