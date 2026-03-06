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
FW_CAP_IPV4="false"
FW_CAP_IPV6="false"
FW_DRY_RUN_SUPPORTED="true"
FW_DNS_COEXIST_MODE_ACTIVE="preserve_tailnet"
FW_CAP_DETAILS=""
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

fwmark_normalize() {
  local raw="${1:?missing fwmark}"
  local value mask

  if [[ "${raw}" == */* ]]; then
    value="${raw%%/*}"
    mask="${raw##*/}"
  else
    value="${raw}"
    mask="0xffffffff"
  fi

  if ! [[ "${value}" =~ ^(0[xX][0-9a-fA-F]+|[0-9]+)$ ]]; then
    return 1
  fi
  if ! [[ "${mask}" =~ ^(0[xX][0-9a-fA-F]+|[0-9]+)$ ]]; then
    return 1
  fi

  printf '%u/%u\n' "$((value))" "$((mask))"
}

fwmark_equal() {
  local left="${1:?missing left fwmark}"
  local right="${2:?missing right fwmark}"
  local left_norm right_norm

  left_norm="$(fwmark_normalize "${left}" 2>/dev/null || true)"
  right_norm="$(fwmark_normalize "${right}" 2>/dev/null || true)"
  [[ -n "${left_norm}" && -n "${right_norm}" && "${left_norm}" == "${right_norm}" ]]
}

backend_iptables_rule_line_fwmark() {
  local line="${1:-}"
  local i
  read -r -a parts <<<"${line}"
  for ((i = 0; i < ${#parts[@]}; i++)); do
    if [[ "${parts[$i]}" == "fwmark" && $((i + 1)) -lt ${#parts[@]} ]]; then
      printf '%s\n' "${parts[$((i + 1))]}"
      return 0
    fi
  done
  return 1
}

backend_iptables_rule_line_table() {
  local line="${1:-}"
  local i
  read -r -a parts <<<"${line}"
  for ((i = 0; i < ${#parts[@]}; i++)); do
    if [[ ( "${parts[$i]}" == "lookup" || "${parts[$i]}" == "table" ) && $((i + 1)) -lt ${#parts[@]} ]]; then
      printf '%s\n' "${parts[$((i + 1))]}"
      return 0
    fi
  done
  return 1
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
    if ! "${ipt}" -t "${table}" -A "$@"; then
      return 1
    fi
    # iptables-nft can emit append failures on stderr in some kernels while
    # still returning success; verify rule presence to enforce correctness.
    if ! "${ipt}" -t "${table}" -C "$@" >/dev/null 2>&1; then
      return 1
    fi
  fi
  return 0
}

iptables_try_add_if_missing_quiet() {
  local table="${1:?missing table}"
  shift
  local ipt

  ipt="$(iptables_cmd)"
  if "${ipt}" -t "${table}" -C "$@" >/dev/null 2>&1; then
    return 0
  fi
  if ! "${ipt}" -t "${table}" -A "$@" >/dev/null 2>&1; then
    return 1
  fi
  "${ipt}" -t "${table}" -C "$@" >/dev/null 2>&1
}

backend_iptables_rule_desc() {
  local rendered
  printf -v rendered '%q ' "$@"
  printf '%s\n' "${rendered% }"
}

backend_iptables_ensure_chain_checked() {
  local table="${1:?missing table}"
  local chain="${2:?missing chain}"
  if ! iptables_ensure_chain "${table}" "${chain}"; then
    FW_LAST_ERROR="failed to ensure chain table=${table} chain=${chain}"
    return "${E_FIREWALL_APPLY}"
  fi
}

backend_iptables_add_rule_checked() {
  local table="${1:?missing table}"
  shift
  if ! iptables_add_if_missing "${table}" "$@"; then
    FW_LAST_ERROR="failed to add rule table=${table} rule=$(backend_iptables_rule_desc "$@")"
    return "${E_FIREWALL_APPLY}"
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

iptables_flush_chain_if_exists() {
  local table="${1:?missing table}"
  local chain="${2:?missing chain}"
  local ipt
  ipt="$(iptables_cmd || true)"
  [[ -n "${ipt}" ]] || return 0
  if iptables_table_has_chain "${table}" "${chain}"; then
    "${ipt}" -t "${table}" -F "${chain}" >/dev/null 2>&1 || true
  fi
}

iptables_delete_chain_if_exists() {
  local table="${1:?missing table}"
  local chain="${2:?missing chain}"
  local ipt
  ipt="$(iptables_cmd || true)"
  [[ -n "${ipt}" ]] || return 0
  if iptables_table_has_chain "${table}" "${chain}"; then
    "${ipt}" -t "${table}" -X "${chain}" >/dev/null 2>&1 || true
  fi
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

    # Drop internal jumps first, then delete child chains.
    iptables_flush_chain_if_exists mangle "${BOX_CHAIN_MANGLE}"
    iptables_flush_chain_if_exists nat "${BOX_CHAIN_NAT}"
    iptables_flush_chain_if_exists mangle "${BOX_CHAIN_DNS_MANGLE}"
    iptables_flush_chain_if_exists nat "${BOX_CHAIN_DNS_NAT}"

    iptables_delete_chain_if_exists mangle "${BOX_CHAIN_DNS_MANGLE}"
    iptables_delete_chain_if_exists nat "${BOX_CHAIN_DNS_NAT}"
    iptables_delete_chain_if_exists mangle "${BOX_CHAIN_MANGLE}"
    iptables_delete_chain_if_exists nat "${BOX_CHAIN_NAT}"

    # Idempotent second pass for backends that need another round after detach.
    iptables_flush_chain_if_exists mangle "${BOX_CHAIN_DNS_MANGLE}"
    iptables_flush_chain_if_exists nat "${BOX_CHAIN_DNS_NAT}"
    iptables_delete_chain_if_exists mangle "${BOX_CHAIN_DNS_MANGLE}"
    iptables_delete_chain_if_exists nat "${BOX_CHAIN_DNS_NAT}"
    iptables_delete_chain_if_exists mangle "${BOX_CHAIN_MANGLE}"
    iptables_delete_chain_if_exists nat "${BOX_CHAIN_NAT}"
  fi

  if [[ -n "${ip_tool}" ]]; then
    backend_iptables_prune_box_policy_rules
    while "${ip_tool}" route show table "${BOX_ROUTE_TABLE}" 2>/dev/null | grep -Fq "local default dev lo"; do
      "${ip_tool}" route del local default dev lo table "${BOX_ROUTE_TABLE}" >/dev/null 2>&1 || break
    done
  fi
}

backend_iptables_apply_anti_loop() {
  backend_iptables_add_rule_checked mangle "${BOX_CHAIN_MANGLE}" -i lo -j RETURN
  backend_iptables_add_rule_checked mangle "${BOX_CHAIN_MANGLE}" -d 127.0.0.0/8 -j RETURN
  backend_iptables_add_rule_checked nat "${BOX_CHAIN_NAT}" -i lo -j RETURN
  backend_iptables_add_rule_checked nat "${BOX_CHAIN_NAT}" -d 127.0.0.0/8 -j RETURN
}

backend_iptables_apply_tailscale_bypass() {
  # Preserve tailscale transport and route ownership.
  backend_iptables_add_rule_checked mangle "${BOX_CHAIN_MANGLE}" -i "${BOX_TAILSCALE_IFACE}" -j RETURN
  backend_iptables_add_rule_checked mangle "${BOX_CHAIN_MANGLE}" -o "${BOX_TAILSCALE_IFACE}" -j RETURN
  backend_iptables_add_rule_checked nat "${BOX_CHAIN_NAT}" -i "${BOX_TAILSCALE_IFACE}" -j RETURN
  backend_iptables_add_rule_checked nat "${BOX_CHAIN_NAT}" -o "${BOX_TAILSCALE_IFACE}" -j RETURN

  backend_iptables_add_rule_checked mangle "${BOX_CHAIN_MANGLE}" -d "${BOX_TAILNET_IPV4_CIDR}" -j RETURN
  backend_iptables_add_rule_checked nat "${BOX_CHAIN_NAT}" -d "${BOX_TAILNET_IPV4_CIDR}" -j RETURN

  # Keep existing tailscale-marked packets out of Box interception.
  backend_iptables_add_rule_checked mangle "${BOX_CHAIN_MANGLE}" -m mark --mark "${BOX_TAILSCALE_FWMARK}" -j RETURN

  # Preserve MagicDNS resolver reachability.
  backend_iptables_add_rule_checked mangle "${BOX_CHAIN_DNS_MANGLE}" -d "${BOX_TAILSCALE_DNS_RESOLVER}" -p udp --dport 53 -j RETURN
  backend_iptables_add_rule_checked mangle "${BOX_CHAIN_DNS_MANGLE}" -d "${BOX_TAILSCALE_DNS_RESOLVER}" -p tcp --dport 53 -j RETURN
  backend_iptables_add_rule_checked nat "${BOX_CHAIN_DNS_NAT}" -d "${BOX_TAILSCALE_DNS_RESOLVER}" -p udp --dport 53 -j RETURN
  backend_iptables_add_rule_checked nat "${BOX_CHAIN_DNS_NAT}" -d "${BOX_TAILSCALE_DNS_RESOLVER}" -p tcp --dport 53 -j RETURN

  # IPv6 tailnet bypass is handled by not touching ip6tables in this backend.
  # TODO(phase-3): add dedicated ip6tables/nft backend for explicit v6 chain rules.
}

backend_iptables_apply_policy_placeholders() {
  # TODO(phase-3): UID/GID/interface/MAC policy graph.
  backend_iptables_add_rule_checked mangle "${BOX_CHAIN_MANGLE}" -m comment --comment "BOX_POLICY_PLACEHOLDER" -j RETURN
}

backend_iptables_ensure_policy_route() {
  local ip_tool
  ip_tool="$(ip_cmd)"

  backend_iptables_prune_box_policy_rules
  if ! "${ip_tool}" rule add fwmark "${BOX_FWMARK}" table "${BOX_ROUTE_TABLE}" pref "${BOX_ROUTE_PREF}" >/dev/null 2>&1; then
    FW_LAST_ERROR="failed to install ip rule fwmark=${BOX_FWMARK} table=${BOX_ROUTE_TABLE} pref=${BOX_ROUTE_PREF}"
    return "${E_FIREWALL_APPLY}"
  fi
  if ! "${ip_tool}" route show table "${BOX_ROUTE_TABLE}" 2>/dev/null | grep -Fq "local default dev lo"; then
    if ! "${ip_tool}" route add local default dev lo table "${BOX_ROUTE_TABLE}" >/dev/null 2>&1; then
      FW_LAST_ERROR="failed to install local route for table=${BOX_ROUTE_TABLE}"
      return "${E_FIREWALL_APPLY}"
    fi
  fi

  return 0
}

backend_iptables_rule_line_matches_box() {
  local line="${1:-}"
  backend_iptables_rule_line_matches_mark_table "${line}" "${BOX_FWMARK}" "${BOX_ROUTE_TABLE}"
}

backend_iptables_rule_line_matches_mark_table() {
  local line="${1:-}"
  local mark="${2:?missing mark}"
  local table="${3:?missing table}"
  local line_mark line_table
  line_mark="$(backend_iptables_rule_line_fwmark "${line}" 2>/dev/null || true)"
  line_table="$(backend_iptables_rule_line_table "${line}" 2>/dev/null || true)"
  [[ -n "${line_mark}" && "${line_table}" == "${table}" ]] || return 1
  fwmark_equal "${line_mark}" "${mark}"
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

backend_iptables_has_policy_rule() {
  local mark="${1:?missing mark}"
  local table="${2:?missing table}"
  local ip_tool line
  ip_tool="$(ip_cmd || true)"
  [[ -n "${ip_tool}" ]] || return 1
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    if backend_iptables_rule_line_matches_mark_table "${line}" "${mark}" "${table}"; then
      return 0
    fi
  done < <("${ip_tool}" rule list 2>/dev/null || true)
  return 1
}

backend_iptables_apply_mode_rules() {
  local mode="${1:?missing mode}"

  case "${mode}" in
    tun)
      backend_iptables_add_rule_checked mangle "${BOX_CHAIN_MANGLE}" -j RETURN
      ;;
    redirect)
      backend_iptables_add_rule_checked nat "${BOX_CHAIN_NAT}" -p tcp -j REDIRECT --to-ports "${BOX_REDIR_PORT}"
      ;;
    tproxy)
      if backend_iptables_probe_tproxy \
        && iptables_try_add_if_missing_quiet mangle "${BOX_CHAIN_MANGLE}" -p tcp -j TPROXY --on-port "${BOX_TPROXY_PORT}" --tproxy-mark "${BOX_FWMARK}" \
        && iptables_try_add_if_missing_quiet mangle "${BOX_CHAIN_MANGLE}" -p udp -j TPROXY --on-port "${BOX_TPROXY_PORT}" --tproxy-mark "${BOX_FWMARK}"; then
        :
      else
        iptables_delete_all mangle "${BOX_CHAIN_MANGLE}" -p tcp -j TPROXY --on-port "${BOX_TPROXY_PORT}" --tproxy-mark "${BOX_FWMARK}"
        iptables_delete_all mangle "${BOX_CHAIN_MANGLE}" -p udp -j TPROXY --on-port "${BOX_TPROXY_PORT}" --tproxy-mark "${BOX_FWMARK}"
        log "WARN" "firewall" "FW_TPROXY_DOWNGRADE" "TPROXY unavailable; using MARK fallback"
        backend_iptables_add_rule_checked mangle "${BOX_CHAIN_MANGLE}" -p tcp -j MARK --set-xmark "${BOX_FWMARK}"
        backend_iptables_add_rule_checked mangle "${BOX_CHAIN_MANGLE}" -p udp -j MARK --set-xmark "${BOX_FWMARK}"
      fi
      if ! backend_iptables_ensure_policy_route; then
        return "${E_FIREWALL_APPLY}"
      fi
      ;;
    mixed|enhance)
      backend_iptables_add_rule_checked nat "${BOX_CHAIN_NAT}" -p tcp -j REDIRECT --to-ports "${BOX_REDIR_PORT}"
      if backend_iptables_probe_tproxy \
        && iptables_try_add_if_missing_quiet mangle "${BOX_CHAIN_MANGLE}" -p udp -j TPROXY --on-port "${BOX_TPROXY_PORT}" --tproxy-mark "${BOX_FWMARK}"; then
        :
      else
        iptables_delete_all mangle "${BOX_CHAIN_MANGLE}" -p udp -j TPROXY --on-port "${BOX_TPROXY_PORT}" --tproxy-mark "${BOX_FWMARK}"
        log "WARN" "firewall" "FW_TPROXY_DOWNGRADE" "TPROXY unavailable for UDP; using MARK fallback"
        backend_iptables_add_rule_checked mangle "${BOX_CHAIN_MANGLE}" -p udp -j MARK --set-xmark "${BOX_FWMARK}"
      fi
      if ! backend_iptables_ensure_policy_route; then
        return "${E_FIREWALL_APPLY}"
      fi
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
      backend_iptables_add_rule_checked mangle "${BOX_CHAIN_DNS_MANGLE}" -j RETURN
      backend_iptables_add_rule_checked nat "${BOX_CHAIN_DNS_NAT}" -j RETURN
      ;;
    redirect)
      backend_iptables_add_rule_checked nat "${BOX_CHAIN_DNS_NAT}" -p udp --dport 53 -j REDIRECT --to-ports "${BOX_DNS_PORT}"
      backend_iptables_add_rule_checked nat "${BOX_CHAIN_DNS_NAT}" -p tcp --dport 53 -j REDIRECT --to-ports "${BOX_DNS_PORT}"
      ;;
    tproxy)
      if backend_iptables_probe_tproxy \
        && iptables_try_add_if_missing_quiet mangle "${BOX_CHAIN_DNS_MANGLE}" -p udp --dport 53 -j TPROXY --on-port "${BOX_DNS_PORT}" --tproxy-mark "${BOX_FWMARK}" \
        && iptables_try_add_if_missing_quiet mangle "${BOX_CHAIN_DNS_MANGLE}" -p tcp --dport 53 -j TPROXY --on-port "${BOX_DNS_PORT}" --tproxy-mark "${BOX_FWMARK}"; then
        if ! backend_iptables_ensure_policy_route; then
          return "${E_FIREWALL_APPLY}"
        fi
      else
        iptables_delete_all mangle "${BOX_CHAIN_DNS_MANGLE}" -p udp --dport 53 -j TPROXY --on-port "${BOX_DNS_PORT}" --tproxy-mark "${BOX_FWMARK}"
        iptables_delete_all mangle "${BOX_CHAIN_DNS_MANGLE}" -p tcp --dport 53 -j TPROXY --on-port "${BOX_DNS_PORT}" --tproxy-mark "${BOX_FWMARK}"
        log "WARN" "firewall" "FW_DNS_TPROXY_DOWNGRADE" "DNS tproxy unavailable; redirecting DNS instead"
        backend_iptables_add_rule_checked nat "${BOX_CHAIN_DNS_NAT}" -p udp --dport 53 -j REDIRECT --to-ports "${BOX_DNS_PORT}"
        backend_iptables_add_rule_checked nat "${BOX_CHAIN_DNS_NAT}" -p tcp --dport 53 -j REDIRECT --to-ports "${BOX_DNS_PORT}"
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
  backend_iptables_ensure_chain_checked mangle "${BOX_CHAIN_MANGLE}"
  backend_iptables_ensure_chain_checked nat "${BOX_CHAIN_NAT}"
  backend_iptables_ensure_chain_checked mangle "${BOX_CHAIN_DNS_MANGLE}"
  backend_iptables_ensure_chain_checked nat "${BOX_CHAIN_DNS_NAT}"

  backend_iptables_add_rule_checked mangle PREROUTING -j "${BOX_CHAIN_MANGLE}"
  backend_iptables_add_rule_checked mangle OUTPUT -j "${BOX_CHAIN_MANGLE}"
  backend_iptables_add_rule_checked nat PREROUTING -j "${BOX_CHAIN_NAT}"
  backend_iptables_add_rule_checked nat OUTPUT -j "${BOX_CHAIN_NAT}"

  backend_iptables_add_rule_checked mangle "${BOX_CHAIN_MANGLE}" -j "${BOX_CHAIN_DNS_MANGLE}"
  backend_iptables_add_rule_checked nat "${BOX_CHAIN_NAT}" -j "${BOX_CHAIN_DNS_NAT}"
}

backend_iptables_apply_mode() {
  local mode="${1:?missing network mode}"

  FW_LAST_ERROR=""
  if ! backend_iptables_init; then
    FW_LAST_ERROR="${FW_LAST_ERROR:-failed to initialize iptables backend}"
    return "${E_FIREWALL_APPLY}"
  fi

  if [[ "${BOX_FIREWALL_DRY_RUN:-0}" == "1" ]]; then
    backend_iptables_dry_run "${mode}"
    return 0
  fi

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

backend_iptables_dry_run() {
  local mode="${1:?missing mode}"
  printf '# dry-run backend=iptables mode=%s dns=%s coexist=%s\n' "${mode}" "${BOX_DNS_HIJACK_MODE}" "${BOX_DNS_COEXIST_MODE}"
  printf 'iptables -t mangle -D PREROUTING -j %s\n' "${BOX_CHAIN_MANGLE}"
  printf 'iptables -t mangle -D OUTPUT -j %s\n' "${BOX_CHAIN_MANGLE}"
  printf 'iptables -t nat -D PREROUTING -j %s\n' "${BOX_CHAIN_NAT}"
  printf 'iptables -t nat -D OUTPUT -j %s\n' "${BOX_CHAIN_NAT}"
  printf 'iptables -t mangle -N %s ; iptables -t nat -N %s\n' "${BOX_CHAIN_MANGLE}" "${BOX_CHAIN_NAT}"
  printf 'iptables -t mangle -N %s ; iptables -t nat -N %s\n' "${BOX_CHAIN_DNS_MANGLE}" "${BOX_CHAIN_DNS_NAT}"
  printf 'iptables mode rules for %s and dns strategy %s\n' "${mode}" "${BOX_DNS_HIJACK_MODE}"
  printf 'ip rule add fwmark %s table %s pref %s\n' "${BOX_FWMARK}" "${BOX_ROUTE_TABLE}" "${BOX_ROUTE_PREF}"
  printf 'ip route add local default dev lo table %s\n' "${BOX_ROUTE_TABLE}"
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
  FW_CAP_IPV4="false"
  FW_CAP_IPV6="false"
  FW_DRY_RUN_SUPPORTED="true"
  FW_DNS_COEXIST_MODE_ACTIVE="${BOX_DNS_COEXIST_MODE}"
  FW_CAP_DETAILS="backend=iptables,available=false,ipv4=false,ipv6=false,tproxy=false,dry_run=true"
  FW_LAST_ERROR=""

  ipt="$(iptables_cmd || true)"
  ip_tool="$(ip_cmd || true)"

  if [[ -z "${ipt}" || -z "${ip_tool}" ]]; then
    FW_LAST_ERROR="iptables/ip command not found"
    export FW_BACKEND_AVAILABLE FW_CHAIN_MANGLE FW_CHAIN_NAT FW_CHAIN_DNS_MANGLE FW_CHAIN_DNS_NAT
    export FW_ROUTE_RULE FW_ROUTE_TABLE_INSTALLED FW_CAP_TPROXY FW_TAILSCALE_MARK_RULE FW_TAILSCALE_TABLE_PRESENT FW_TAILSCALE_BYPASS_APPLIED
    export FW_CAP_IPV4 FW_CAP_IPV6 FW_DRY_RUN_SUPPORTED FW_DNS_COEXIST_MODE_ACTIVE FW_CAP_DETAILS FW_LAST_ERROR
    return 0
  fi

  if ! "${ipt}" -t mangle -S >/dev/null 2>&1; then
    FW_LAST_ERROR="iptables inspection unavailable (need root/CAP_NET_ADMIN or kernel support)"
    export FW_BACKEND_AVAILABLE FW_CHAIN_MANGLE FW_CHAIN_NAT FW_CHAIN_DNS_MANGLE FW_CHAIN_DNS_NAT
    export FW_ROUTE_RULE FW_ROUTE_TABLE_INSTALLED FW_CAP_TPROXY FW_TAILSCALE_MARK_RULE FW_TAILSCALE_TABLE_PRESENT FW_TAILSCALE_BYPASS_APPLIED
    export FW_CAP_IPV4 FW_CAP_IPV6 FW_DRY_RUN_SUPPORTED FW_DNS_COEXIST_MODE_ACTIVE FW_CAP_DETAILS FW_LAST_ERROR
    return 0
  fi

  FW_BACKEND_AVAILABLE="true"
  FW_CAP_IPV4="true"
  if iptables_table_has_chain mangle "${BOX_CHAIN_MANGLE}"; then FW_CHAIN_MANGLE="true"; fi
  if iptables_table_has_chain nat "${BOX_CHAIN_NAT}"; then FW_CHAIN_NAT="true"; fi
  if iptables_table_has_chain mangle "${BOX_CHAIN_DNS_MANGLE}"; then FW_CHAIN_DNS_MANGLE="true"; fi
  if iptables_table_has_chain nat "${BOX_CHAIN_DNS_NAT}"; then FW_CHAIN_DNS_NAT="true"; fi

  if backend_iptables_has_policy_rule "${BOX_FWMARK}" "${BOX_ROUTE_TABLE}"; then FW_ROUTE_RULE="true"; fi
  if "${ip_tool}" route show table "${BOX_ROUTE_TABLE}" 2>/dev/null | grep -Fq "local default dev lo"; then FW_ROUTE_TABLE_INSTALLED="true"; fi
  if backend_iptables_probe_tproxy; then FW_CAP_TPROXY="true"; fi
  FW_CAP_DETAILS="backend=iptables,available=true,ipv4=true,ipv6=false,tproxy=${FW_CAP_TPROXY},dry_run=true"
  if backend_iptables_has_policy_rule "${BOX_TAILSCALE_FWMARK}" "${BOX_TAILSCALE_ROUTE_TABLE}"; then
    FW_TAILSCALE_MARK_RULE="true"
  fi
  if "${ip_tool}" route show table "${BOX_TAILSCALE_ROUTE_TABLE}" 2>/dev/null | grep -q '.'; then
    FW_TAILSCALE_TABLE_PRESENT="true"
  fi
  if iptables_rule_exists mangle "${BOX_CHAIN_MANGLE}" -i "${BOX_TAILSCALE_IFACE}" -j RETURN; then
    FW_TAILSCALE_BYPASS_APPLIED="true"
  fi

  export FW_BACKEND_AVAILABLE FW_CHAIN_MANGLE FW_CHAIN_NAT FW_CHAIN_DNS_MANGLE FW_CHAIN_DNS_NAT
  export FW_ROUTE_RULE FW_ROUTE_TABLE_INSTALLED FW_CAP_TPROXY FW_TAILSCALE_MARK_RULE FW_TAILSCALE_TABLE_PRESENT FW_TAILSCALE_BYPASS_APPLIED
  export FW_CAP_IPV4 FW_CAP_IPV6 FW_DRY_RUN_SUPPORTED FW_DNS_COEXIST_MODE_ACTIVE FW_CAP_DETAILS FW_LAST_ERROR
}
