#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

BOX_CHAIN_MANGLE="BOX_MANGLE"
BOX_CHAIN_NAT="BOX_NAT"

iptables_cmd() {
  command -v iptables >/dev/null 2>&1 && printf '%s\n' "iptables"
}

ip_cmd() {
  command -v ip >/dev/null 2>&1 && printf '%s\n' "ip"
}

backend_iptables_init() {
  if [[ -z "$(iptables_cmd)" || -z "$(ip_cmd)" ]]; then
    log "ERROR" "firewall" "E_FW_PREREQ" "iptables/ip command not found"
    return "${E_FIREWALL_APPLY}"
  fi
}

iptables_ensure_chain() {
  local table="${1:?missing table}"
  local chain="${2:?missing chain}"
  local ipt

  ipt="$(iptables_cmd)"
  if ! "${ipt}" -t "${table}" -S "${chain}" >/dev/null 2>&1; then
    "${ipt}" -t "${table}" -N "${chain}"
  fi
}

iptables_add_if_missing() {
  local table="${1:?missing table}"
  shift
  local ipt

  ipt="$(iptables_cmd)"
  if ! "${ipt}" -t "${table}" -C "$@" >/dev/null 2>&1; then
    "${ipt}" -t "${table}" -A "$@"
  fi
}

backend_iptables_cleanup() {
  local ipt ip_tool

  ipt="$(iptables_cmd || true)"
  ip_tool="$(ip_cmd || true)"

  if [[ -n "${ipt}" ]]; then
    "${ipt}" -t mangle -D PREROUTING -j "${BOX_CHAIN_MANGLE}" >/dev/null 2>&1 || true
    "${ipt}" -t mangle -D OUTPUT -j "${BOX_CHAIN_MANGLE}" >/dev/null 2>&1 || true
    "${ipt}" -t nat -D PREROUTING -j "${BOX_CHAIN_NAT}" >/dev/null 2>&1 || true
    "${ipt}" -t nat -D OUTPUT -j "${BOX_CHAIN_NAT}" >/dev/null 2>&1 || true

    "${ipt}" -t mangle -F "${BOX_CHAIN_MANGLE}" >/dev/null 2>&1 || true
    "${ipt}" -t mangle -X "${BOX_CHAIN_MANGLE}" >/dev/null 2>&1 || true
    "${ipt}" -t nat -F "${BOX_CHAIN_NAT}" >/dev/null 2>&1 || true
    "${ipt}" -t nat -X "${BOX_CHAIN_NAT}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${ip_tool}" ]]; then
    "${ip_tool}" rule del fwmark "${BOX_FWMARK}" table "${BOX_ROUTE_TABLE}" pref "${BOX_ROUTE_PREF}" >/dev/null 2>&1 || true
    "${ip_tool}" route del local default dev lo table "${BOX_ROUTE_TABLE}" >/dev/null 2>&1 || true
  fi
}

backend_iptables_apply_mode() {
  local mode="${1:?missing network mode}"
  local ipt ip_tool

  backend_iptables_init
  backend_iptables_cleanup

  ipt="$(iptables_cmd)"
  ip_tool="$(ip_cmd)"

  iptables_ensure_chain mangle "${BOX_CHAIN_MANGLE}"
  iptables_ensure_chain nat "${BOX_CHAIN_NAT}"

  iptables_add_if_missing mangle PREROUTING -j "${BOX_CHAIN_MANGLE}"
  iptables_add_if_missing mangle OUTPUT -j "${BOX_CHAIN_MANGLE}"
  iptables_add_if_missing nat PREROUTING -j "${BOX_CHAIN_NAT}"
  iptables_add_if_missing nat OUTPUT -j "${BOX_CHAIN_NAT}"

  case "${mode}" in
    tun)
      # TODO(phase-2): add full tun path rules and owner/interface policies.
      "${ipt}" -t mangle -A "${BOX_CHAIN_MANGLE}" -j RETURN
      ;;
    tproxy|mixed|enhance)
      # Skeleton only: mark packets and install policy route. Full TPROXY target in phase 2.
      "${ipt}" -t mangle -A "${BOX_CHAIN_MANGLE}" -p tcp -j MARK --set-xmark "${BOX_FWMARK}"
      "${ipt}" -t mangle -A "${BOX_CHAIN_MANGLE}" -p udp -j MARK --set-xmark "${BOX_FWMARK}"
      "${ip_tool}" rule add fwmark "${BOX_FWMARK}" table "${BOX_ROUTE_TABLE}" pref "${BOX_ROUTE_PREF}" >/dev/null 2>&1 || true
      "${ip_tool}" route add local default dev lo table "${BOX_ROUTE_TABLE}" >/dev/null 2>&1 || true
      ;;
    redirect)
      "${ipt}" -t nat -A "${BOX_CHAIN_NAT}" -p tcp -j REDIRECT --to-ports "${BOX_REDIR_PORT}"
      ;;
    *)
      log "ERROR" "firewall" "E_FW_MODE" "unsupported network mode: ${mode}"
      return "${E_FIREWALL_APPLY}"
      ;;
  esac

  return 0
}

backend_iptables_status() {
  local ipt
  ipt="$(iptables_cmd || true)"
  if [[ -z "${ipt}" ]]; then
    printf 'backend=iptables available=false reason="iptables command not found"\n'
    return 0
  fi

  if "${ipt}" -t mangle -S "${BOX_CHAIN_MANGLE}" >/dev/null 2>&1; then
    printf 'backend=iptables available=true chain_mangle=present chain_nat='
  else
    printf 'backend=iptables available=true chain_mangle=absent chain_nat='
  fi

  if "${ipt}" -t nat -S "${BOX_CHAIN_NAT}" >/dev/null 2>&1; then
    printf 'present\n'
  else
    printf 'absent\n'
  fi
}
