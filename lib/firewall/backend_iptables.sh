#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

BOX_CHAIN_MANGLE="BOX_MANGLE"
BOX_CHAIN_NAT="BOX_NAT"
BOX_CHAIN_DNS_MANGLE="BOX_DNS_MANGLE"
BOX_CHAIN_DNS_NAT="BOX_DNS_NAT"

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
FW_LAST_ERROR=""

iptables_cmd() {
  if [[ -n "${BOX_IPTABLES_CMD:-}" ]]; then
    printf '%s\n' "${BOX_IPTABLES_CMD}"
    return 0
  fi
  command -v iptables >/dev/null 2>&1 && printf '%s\n' "iptables"
}

ip_cmd() {
  if [[ -n "${BOX_IP_CMD:-}" ]]; then
    printf '%s\n' "${BOX_IP_CMD}"
    return 0
  fi
  command -v ip >/dev/null 2>&1 && printf '%s\n' "ip"
}

iptables_table_has_chain() {
  local table="${1:?missing table}"
  local chain="${2:?missing chain}"
  local ipt
  ipt="$(iptables_cmd)"
  "${ipt}" -t "${table}" -S "${chain}" >/dev/null 2>&1
}

iptables_ensure_chain() {
  local table="${1:?missing table}"
  local chain="${2:?missing chain}"
  local ipt

  ipt="$(iptables_cmd)"
  if ! iptables_table_has_chain "${table}" "${chain}"; then
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

iptables_rule_exists() {
  local table="${1:?missing table}"
  shift
  local ipt
  ipt="$(iptables_cmd)"
  "${ipt}" -t "${table}" -C "$@" >/dev/null 2>&1
}

iptables_delete_all() {
  local table="${1:?missing table}"
  shift
  local ipt

  ipt="$(iptables_cmd || true)"
  [[ -n "${ipt}" ]] || return 0

  while "${ipt}" -t "${table}" -C "$@" >/dev/null 2>&1; do
    "${ipt}" -t "${table}" -D "$@" >/dev/null 2>&1 || break
  done
}

backend_iptables_probe_tproxy() {
  if [[ -n "${BOX_CAP_TPROXY:-}" ]]; then
    [[ "${BOX_CAP_TPROXY}" == "1" || "${BOX_CAP_TPROXY}" == "true" ]] && return 0
    return 1
  fi
  local ipt
  ipt="$(iptables_cmd || true)"
  [[ -n "${ipt}" ]] || return 1
  "${ipt}" -j TPROXY --help >/dev/null 2>&1
}

backend_iptables_init() {
  if [[ -z "$(iptables_cmd)" || -z "$(ip_cmd)" ]]; then
    FW_LAST_ERROR="iptables/ip command not found"
    log "ERROR" "firewall" "E_FW_PREREQ" "${FW_LAST_ERROR}"
    return "${E_FIREWALL_APPLY}"
  fi
  return 0
}

backend_iptables_cleanup() {
  local ipt ip_tool

  ipt="$(iptables_cmd || true)"
  ip_tool="$(ip_cmd || true)"

  if [[ -n "${ipt}" ]]; then
    iptables_delete_all mangle PREROUTING -j "${BOX_CHAIN_MANGLE}"
    iptables_delete_all mangle OUTPUT -j "${BOX_CHAIN_MANGLE}"
    iptables_delete_all nat PREROUTING -j "${BOX_CHAIN_NAT}"
    iptables_delete_all nat OUTPUT -j "${BOX_CHAIN_NAT}"

    "${ipt}" -t mangle -F "${BOX_CHAIN_DNS_MANGLE}" >/dev/null 2>&1 || true
    "${ipt}" -t mangle -X "${BOX_CHAIN_DNS_MANGLE}" >/dev/null 2>&1 || true
    "${ipt}" -t nat -F "${BOX_CHAIN_DNS_NAT}" >/dev/null 2>&1 || true
    "${ipt}" -t nat -X "${BOX_CHAIN_DNS_NAT}" >/dev/null 2>&1 || true
    "${ipt}" -t mangle -F "${BOX_CHAIN_MANGLE}" >/dev/null 2>&1 || true
    "${ipt}" -t mangle -X "${BOX_CHAIN_MANGLE}" >/dev/null 2>&1 || true
    "${ipt}" -t nat -F "${BOX_CHAIN_NAT}" >/dev/null 2>&1 || true
    "${ipt}" -t nat -X "${BOX_CHAIN_NAT}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${ip_tool}" ]]; then
    backend_iptables_prune_box_policy_rules
    while "${ip_tool}" route show table "${BOX_ROUTE_TABLE}" 2>/dev/null | grep -Fq "local default dev lo"; do
      "${ip_tool}" route del local default dev lo table "${BOX_ROUTE_TABLE}" >/dev/null 2>&1 || break
    done
  fi
}

backend_iptables_apply_anti_loop() {
  iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -i lo -j RETURN
  iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -d 127.0.0.0/8 -j RETURN
  iptables_add_if_missing nat "${BOX_CHAIN_NAT}" -i lo -j RETURN
  iptables_add_if_missing nat "${BOX_CHAIN_NAT}" -d 127.0.0.0/8 -j RETURN
}

backend_iptables_apply_tailscale_bypass() {
  # Preserve tailscale transport and route ownership.
  iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -i "${BOX_TAILSCALE_IFACE}" -j RETURN
  iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -o "${BOX_TAILSCALE_IFACE}" -j RETURN
  iptables_add_if_missing nat "${BOX_CHAIN_NAT}" -i "${BOX_TAILSCALE_IFACE}" -j RETURN
  iptables_add_if_missing nat "${BOX_CHAIN_NAT}" -o "${BOX_TAILSCALE_IFACE}" -j RETURN

  iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -d "${BOX_TAILNET_IPV4_CIDR}" -j RETURN
  iptables_add_if_missing nat "${BOX_CHAIN_NAT}" -d "${BOX_TAILNET_IPV4_CIDR}" -j RETURN

  # Keep existing tailscale-marked packets out of Box interception.
  iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -m mark --mark "${BOX_TAILSCALE_FWMARK}" -j RETURN

  # Preserve MagicDNS resolver reachability.
  iptables_add_if_missing mangle "${BOX_CHAIN_DNS_MANGLE}" -d "${BOX_TAILSCALE_DNS_RESOLVER}" -p udp --dport 53 -j RETURN
  iptables_add_if_missing mangle "${BOX_CHAIN_DNS_MANGLE}" -d "${BOX_TAILSCALE_DNS_RESOLVER}" -p tcp --dport 53 -j RETURN
  iptables_add_if_missing nat "${BOX_CHAIN_DNS_NAT}" -d "${BOX_TAILSCALE_DNS_RESOLVER}" -p udp --dport 53 -j RETURN
  iptables_add_if_missing nat "${BOX_CHAIN_DNS_NAT}" -d "${BOX_TAILSCALE_DNS_RESOLVER}" -p tcp --dport 53 -j RETURN

  # IPv6 tailnet bypass is handled by not touching ip6tables in this backend.
  # TODO(phase-3): add dedicated ip6tables/nft backend for explicit v6 chain rules.
}

backend_iptables_apply_policy_placeholders() {
  # TODO(phase-3): UID/GID/interface/MAC policy graph.
  iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -m comment --comment "BOX_POLICY_PLACEHOLDER" -j RETURN
}

backend_iptables_ensure_policy_route() {
  local ip_tool
  ip_tool="$(ip_cmd)"

  backend_iptables_prune_box_policy_rules
  "${ip_tool}" rule add fwmark "${BOX_FWMARK}" table "${BOX_ROUTE_TABLE}" pref "${BOX_ROUTE_PREF}" >/dev/null 2>&1 || true
  if ! "${ip_tool}" route show table "${BOX_ROUTE_TABLE}" 2>/dev/null | grep -Fq "local default dev lo"; then
    "${ip_tool}" route add local default dev lo table "${BOX_ROUTE_TABLE}" >/dev/null 2>&1 || true
  fi
}

backend_iptables_rule_line_matches_box() {
  local line="${1:-}"
  [[ "${line}" == *"fwmark ${BOX_FWMARK}"* ]] && \
    ([[ "${line}" == *" lookup ${BOX_ROUTE_TABLE}"* ]] || [[ "${line}" == *" table ${BOX_ROUTE_TABLE}"* ]])
}

backend_iptables_rule_line_pref() {
  local line="${1:-}"
  if [[ "${line}" =~ (^|[[:space:]])pref[[:space:]]+([0-9]+)($|[[:space:]]) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

backend_iptables_prune_box_policy_rules() {
  local ip_tool line pref
  ip_tool="$(ip_cmd || true)"
  [[ -n "${ip_tool}" ]] || return 0

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    if backend_iptables_rule_line_matches_box "${line}"; then
      if pref="$(backend_iptables_rule_line_pref "${line}" 2>/dev/null || true)" && [[ -n "${pref}" ]]; then
        "${ip_tool}" rule del pref "${pref}" >/dev/null 2>&1 || true
      else
        # Fallback delete pattern when pref is unavailable.
        "${ip_tool}" rule del fwmark "${BOX_FWMARK}" table "${BOX_ROUTE_TABLE}" >/dev/null 2>&1 || true
      fi
    fi
  done < <("${ip_tool}" rule list 2>/dev/null || true)
}

backend_iptables_apply_mode_rules() {
  local mode="${1:?missing mode}"

  case "${mode}" in
    tun)
      iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -j RETURN
      ;;
    redirect)
      iptables_add_if_missing nat "${BOX_CHAIN_NAT}" -p tcp -j REDIRECT --to-ports "${BOX_REDIR_PORT}"
      ;;
    tproxy)
      if backend_iptables_probe_tproxy; then
        iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -p tcp -j TPROXY --on-port "${BOX_TPROXY_PORT}" --tproxy-mark "${BOX_FWMARK}"
        iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -p udp -j TPROXY --on-port "${BOX_TPROXY_PORT}" --tproxy-mark "${BOX_FWMARK}"
      else
        log "WARN" "firewall" "FW_TPROXY_DOWNGRADE" "TPROXY unavailable; using MARK fallback"
        iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -p tcp -j MARK --set-xmark "${BOX_FWMARK}"
        iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -p udp -j MARK --set-xmark "${BOX_FWMARK}"
      fi
      backend_iptables_ensure_policy_route
      ;;
    mixed|enhance)
      iptables_add_if_missing nat "${BOX_CHAIN_NAT}" -p tcp -j REDIRECT --to-ports "${BOX_REDIR_PORT}"
      if backend_iptables_probe_tproxy; then
        iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -p udp -j TPROXY --on-port "${BOX_TPROXY_PORT}" --tproxy-mark "${BOX_FWMARK}"
      else
        log "WARN" "firewall" "FW_TPROXY_DOWNGRADE" "TPROXY unavailable for UDP; using MARK fallback"
        iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -p udp -j MARK --set-xmark "${BOX_FWMARK}"
      fi
      backend_iptables_ensure_policy_route
      ;;
    *)
      FW_LAST_ERROR="unsupported network mode: ${mode}"
      return "${E_FIREWALL_APPLY}"
      ;;
  esac

  return 0
}

backend_iptables_apply_dns_strategy() {
  local dns_mode="${1:?missing dns mode}"

  case "${dns_mode}" in
    disable)
      iptables_add_if_missing mangle "${BOX_CHAIN_DNS_MANGLE}" -j RETURN
      iptables_add_if_missing nat "${BOX_CHAIN_DNS_NAT}" -j RETURN
      ;;
    redirect)
      iptables_add_if_missing nat "${BOX_CHAIN_DNS_NAT}" -p udp --dport 53 -j REDIRECT --to-ports "${BOX_DNS_PORT}"
      iptables_add_if_missing nat "${BOX_CHAIN_DNS_NAT}" -p tcp --dport 53 -j REDIRECT --to-ports "${BOX_DNS_PORT}"
      ;;
    tproxy)
      if backend_iptables_probe_tproxy; then
        iptables_add_if_missing mangle "${BOX_CHAIN_DNS_MANGLE}" -p udp --dport 53 -j TPROXY --on-port "${BOX_DNS_PORT}" --tproxy-mark "${BOX_FWMARK}"
        iptables_add_if_missing mangle "${BOX_CHAIN_DNS_MANGLE}" -p tcp --dport 53 -j TPROXY --on-port "${BOX_DNS_PORT}" --tproxy-mark "${BOX_FWMARK}"
        backend_iptables_ensure_policy_route
      else
        log "WARN" "firewall" "FW_DNS_TPROXY_DOWNGRADE" "DNS tproxy unavailable; redirecting DNS instead"
        iptables_add_if_missing nat "${BOX_CHAIN_DNS_NAT}" -p udp --dport 53 -j REDIRECT --to-ports "${BOX_DNS_PORT}"
        iptables_add_if_missing nat "${BOX_CHAIN_DNS_NAT}" -p tcp --dport 53 -j REDIRECT --to-ports "${BOX_DNS_PORT}"
      fi
      ;;
    *)
      FW_LAST_ERROR="unsupported dns_hijack_mode: ${dns_mode}"
      return "${E_FIREWALL_APPLY}"
      ;;
  esac

  return 0
}

backend_iptables_create_base() {
  iptables_ensure_chain mangle "${BOX_CHAIN_MANGLE}"
  iptables_ensure_chain nat "${BOX_CHAIN_NAT}"
  iptables_ensure_chain mangle "${BOX_CHAIN_DNS_MANGLE}"
  iptables_ensure_chain nat "${BOX_CHAIN_DNS_NAT}"

  iptables_add_if_missing mangle PREROUTING -j "${BOX_CHAIN_MANGLE}"
  iptables_add_if_missing mangle OUTPUT -j "${BOX_CHAIN_MANGLE}"
  iptables_add_if_missing nat PREROUTING -j "${BOX_CHAIN_NAT}"
  iptables_add_if_missing nat OUTPUT -j "${BOX_CHAIN_NAT}"

  iptables_add_if_missing mangle "${BOX_CHAIN_MANGLE}" -j "${BOX_CHAIN_DNS_MANGLE}"
  iptables_add_if_missing nat "${BOX_CHAIN_NAT}" -j "${BOX_CHAIN_DNS_NAT}"
}

backend_iptables_apply_mode() {
  local mode="${1:?missing network mode}"

  backend_iptables_init
  FW_LAST_ERROR=""

  if ! backend_iptables_cleanup; then
    FW_LAST_ERROR="failed to cleanup existing firewall state"
    return "${E_FIREWALL_APPLY}"
  fi

  if ! backend_iptables_create_base; then
    FW_LAST_ERROR="failed to create base chains"
    backend_iptables_cleanup || true
    return "${E_FIREWALL_APPLY}"
  fi

  if ! backend_iptables_apply_anti_loop; then
    FW_LAST_ERROR="failed to apply anti-loop rules"
    backend_iptables_cleanup || true
    return "${E_FIREWALL_APPLY}"
  fi

  if [[ "${BOX_DNS_COEXIST_MODE}" == "preserve_tailnet" ]]; then
    if ! backend_iptables_apply_tailscale_bypass; then
      FW_LAST_ERROR="failed to apply tailscale bypass"
      backend_iptables_cleanup || true
      return "${E_FIREWALL_APPLY}"
    fi
    FW_TAILSCALE_BYPASS_APPLIED="true"
  else
    FW_TAILSCALE_BYPASS_APPLIED="false"
  fi

  if ! backend_iptables_apply_policy_placeholders; then
    FW_LAST_ERROR="failed to apply policy placeholder rules"
    backend_iptables_cleanup || true
    return "${E_FIREWALL_APPLY}"
  fi

  if ! backend_iptables_apply_mode_rules "${mode}"; then
    FW_LAST_ERROR="${FW_LAST_ERROR:-failed to apply mode rules}"
    backend_iptables_cleanup || true
    return "${E_FIREWALL_APPLY}"
  fi

  if ! backend_iptables_apply_dns_strategy "${BOX_DNS_HIJACK_MODE}"; then
    FW_LAST_ERROR="${FW_LAST_ERROR:-failed to apply dns strategy}"
    backend_iptables_cleanup || true
    return "${E_FIREWALL_APPLY}"
  fi

  return 0
}

backend_iptables_collect_status() {
  local ipt ip_tool

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
  FW_LAST_ERROR=""

  ipt="$(iptables_cmd || true)"
  ip_tool="$(ip_cmd || true)"

  if [[ -z "${ipt}" || -z "${ip_tool}" ]]; then
    FW_LAST_ERROR="iptables/ip command not found"
    export FW_BACKEND_AVAILABLE FW_CHAIN_MANGLE FW_CHAIN_NAT FW_CHAIN_DNS_MANGLE FW_CHAIN_DNS_NAT
    export FW_ROUTE_RULE FW_ROUTE_TABLE_INSTALLED FW_CAP_TPROXY FW_TAILSCALE_MARK_RULE FW_TAILSCALE_TABLE_PRESENT FW_TAILSCALE_BYPASS_APPLIED FW_LAST_ERROR
    return 0
  fi

  FW_BACKEND_AVAILABLE="true"
  if iptables_table_has_chain mangle "${BOX_CHAIN_MANGLE}"; then FW_CHAIN_MANGLE="true"; fi
  if iptables_table_has_chain nat "${BOX_CHAIN_NAT}"; then FW_CHAIN_NAT="true"; fi
  if iptables_table_has_chain mangle "${BOX_CHAIN_DNS_MANGLE}"; then FW_CHAIN_DNS_MANGLE="true"; fi
  if iptables_table_has_chain nat "${BOX_CHAIN_DNS_NAT}"; then FW_CHAIN_DNS_NAT="true"; fi

  if "${ip_tool}" rule list 2>/dev/null | grep -Eq "fwmark[[:space:]]+${BOX_FWMARK}[[:space:]]+(lookup|table)[[:space:]]+${BOX_ROUTE_TABLE}"; then FW_ROUTE_RULE="true"; fi
  if "${ip_tool}" route show table "${BOX_ROUTE_TABLE}" 2>/dev/null | grep -Fq "local default dev lo"; then FW_ROUTE_TABLE_INSTALLED="true"; fi
  if backend_iptables_probe_tproxy; then FW_CAP_TPROXY="true"; fi
  if "${ip_tool}" rule list 2>/dev/null | grep -Eq "fwmark[[:space:]]+${BOX_TAILSCALE_FWMARK}[[:space:]]+(lookup|table)[[:space:]]+${BOX_TAILSCALE_ROUTE_TABLE}"; then
    FW_TAILSCALE_MARK_RULE="true"
  fi
  if "${ip_tool}" route show table "${BOX_TAILSCALE_ROUTE_TABLE}" 2>/dev/null | grep -q '.'; then
    FW_TAILSCALE_TABLE_PRESENT="true"
  fi
  if iptables_rule_exists mangle "${BOX_CHAIN_MANGLE}" -i "${BOX_TAILSCALE_IFACE}" -j RETURN; then
    FW_TAILSCALE_BYPASS_APPLIED="true"
  fi

  export FW_BACKEND_AVAILABLE FW_CHAIN_MANGLE FW_CHAIN_NAT FW_CHAIN_DNS_MANGLE FW_CHAIN_DNS_NAT
  export FW_ROUTE_RULE FW_ROUTE_TABLE_INSTALLED FW_CAP_TPROXY FW_TAILSCALE_MARK_RULE FW_TAILSCALE_TABLE_PRESENT FW_TAILSCALE_BYPASS_APPLIED FW_LAST_ERROR
}
