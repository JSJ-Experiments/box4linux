#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

BOX_NFT_TABLE_INET="box_mangle"
BOX_NFT_TABLE_IP="box_nat"

nft_cmd() {
  if [[ -n "${BOX_NFT_CMD:-}" ]]; then
    printf '%s\n' "${BOX_NFT_CMD}"
    return 0
  fi
  command -v nft >/dev/null 2>&1 && printf '%s\n' "nft"
}

nft_ip_cmd() {
  if [[ -n "${BOX_IP_CMD:-}" ]]; then
    printf '%s\n' "${BOX_IP_CMD}"
    return 0
  fi
  command -v ip >/dev/null 2>&1 && printf '%s\n' "ip"
}

nft_mark_value() {
  local mark="${1:?missing mark}"
  printf '%s\n' "${mark%%/*}"
}

nft_mark_mask() {
  local mark="${1:?missing mark}"
  if [[ "${mark}" == */* ]]; then
    printf '%s\n' "${mark##*/}"
  else
    printf '%s\n' "0xffffffff"
  fi
}

backend_nft_probe_tproxy() {
  if [[ -n "${BOX_CAP_TPROXY:-}" ]]; then
    [[ "${BOX_CAP_TPROXY}" == "1" || "${BOX_CAP_TPROXY}" == "true" ]] && return 0
    return 1
  fi
  local nft
  nft="$(nft_cmd || true)"
  [[ -n "${nft}" ]] || return 1
  "${nft}" describe tproxy >/dev/null 2>&1
}

backend_nft_init() {
  local nft ip_tool
  nft="$(nft_cmd || true)"
  ip_tool="$(nft_ip_cmd || true)"
  if [[ -z "${nft}" || -z "${ip_tool}" ]]; then
    FW_LAST_ERROR="nft/ip command not found"
    log "ERROR" "firewall" "E_FW_PREREQ" "${FW_LAST_ERROR}"
    return "${E_FIREWALL_APPLY}"
  fi
  return 0
}

backend_nft_rule_line_matches_box() {
  local line="${1:-}"
  [[ "${line}" == *"fwmark ${BOX_FWMARK}"* ]] && \
    ([[ "${line}" == *" lookup ${BOX_ROUTE_TABLE}"* ]] || [[ "${line}" == *" table ${BOX_ROUTE_TABLE}"* ]])
}

backend_nft_rule_line_pref() {
  local line="${1:-}"
  if [[ "${line}" =~ (^|[[:space:]])pref[[:space:]]+([0-9]+)($|[[:space:]]) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

backend_nft_prune_box_policy_rules() {
  local ip_tool line pref
  ip_tool="$(nft_ip_cmd || true)"
  [[ -n "${ip_tool}" ]] || return 0

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    if backend_nft_rule_line_matches_box "${line}"; then
      pref="$(backend_nft_rule_line_pref "${line}" 2>/dev/null || true)"
      if [[ -n "${pref}" ]]; then
        trace_cmd "firewall" "${ip_tool}" rule del pref "${pref}"
        "${ip_tool}" rule del pref "${pref}" >/dev/null 2>&1 || true
      else
        trace_cmd "firewall" "${ip_tool}" rule del fwmark "${BOX_FWMARK}" table "${BOX_ROUTE_TABLE}"
        "${ip_tool}" rule del fwmark "${BOX_FWMARK}" table "${BOX_ROUTE_TABLE}" >/dev/null 2>&1 || true
      fi
    fi
  done < <("${ip_tool}" rule list 2>/dev/null || true)
}

backend_nft_ensure_policy_route() {
  local ip_tool
  ip_tool="$(nft_ip_cmd)"
  backend_nft_prune_box_policy_rules

  trace_cmd "firewall" "${ip_tool}" rule add fwmark "${BOX_FWMARK}" table "${BOX_ROUTE_TABLE}" pref "${BOX_ROUTE_PREF}"
  "${ip_tool}" rule add fwmark "${BOX_FWMARK}" table "${BOX_ROUTE_TABLE}" pref "${BOX_ROUTE_PREF}" >/dev/null 2>&1 || true
  if ! "${ip_tool}" route show table "${BOX_ROUTE_TABLE}" 2>/dev/null | grep -Fq "local default dev lo"; then
    trace_cmd "firewall" "${ip_tool}" route add local default dev lo table "${BOX_ROUTE_TABLE}"
    "${ip_tool}" route add local default dev lo table "${BOX_ROUTE_TABLE}" >/dev/null 2>&1 || true
  fi
}

backend_nft_cleanup() {
  local nft ip_tool
  nft="$(nft_cmd || true)"
  ip_tool="$(nft_ip_cmd || true)"

  if [[ -n "${nft}" ]]; then
    trace_cmd "firewall" "${nft}" delete table inet "${BOX_NFT_TABLE_INET}"
    "${nft}" delete table inet "${BOX_NFT_TABLE_INET}" >/dev/null 2>&1 || true
    trace_cmd "firewall" "${nft}" delete table ip "${BOX_NFT_TABLE_IP}"
    "${nft}" delete table ip "${BOX_NFT_TABLE_IP}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${ip_tool}" ]]; then
    backend_nft_prune_box_policy_rules
    while "${ip_tool}" route show table "${BOX_ROUTE_TABLE}" 2>/dev/null | grep -Fq "local default dev lo"; do
      trace_cmd "firewall" "${ip_tool}" route del local default dev lo table "${BOX_ROUTE_TABLE}"
      "${ip_tool}" route del local default dev lo table "${BOX_ROUTE_TABLE}" >/dev/null 2>&1 || break
    done
  fi
}

backend_nft_build_ruleset() {
  local mode="${1:?missing mode}"
  local mark_value tailscale_mark tailscale_mask
  mark_value="$(nft_mark_value "${BOX_FWMARK}")"
  tailscale_mark="$(nft_mark_value "${BOX_TAILSCALE_FWMARK}")"
  tailscale_mask="$(nft_mark_mask "${BOX_TAILSCALE_FWMARK}")"

  cat <<EOF
add table inet ${BOX_NFT_TABLE_INET}
add chain inet ${BOX_NFT_TABLE_INET} prerouting { type filter hook prerouting priority mangle; policy accept; }
add chain inet ${BOX_NFT_TABLE_INET} output { type route hook output priority mangle; policy accept; }
add chain inet ${BOX_NFT_TABLE_INET} box_main
add chain inet ${BOX_NFT_TABLE_INET} box_dns
add rule inet ${BOX_NFT_TABLE_INET} prerouting jump box_main
add rule inet ${BOX_NFT_TABLE_INET} output jump box_main
add rule inet ${BOX_NFT_TABLE_INET} box_main jump box_dns
add rule inet ${BOX_NFT_TABLE_INET} box_main iifname "lo" return
add rule inet ${BOX_NFT_TABLE_INET} box_main ip daddr 127.0.0.0/8 return
add rule inet ${BOX_NFT_TABLE_INET} box_main comment "BOX_POLICY_PLACEHOLDER" return
add table ip ${BOX_NFT_TABLE_IP}
add chain ip ${BOX_NFT_TABLE_IP} prerouting { type nat hook prerouting priority dstnat; policy accept; }
add chain ip ${BOX_NFT_TABLE_IP} output { type nat hook output priority -100; policy accept; }
add chain ip ${BOX_NFT_TABLE_IP} box_main
add chain ip ${BOX_NFT_TABLE_IP} box_dns
add rule ip ${BOX_NFT_TABLE_IP} prerouting jump box_main
add rule ip ${BOX_NFT_TABLE_IP} output jump box_main
add rule ip ${BOX_NFT_TABLE_IP} box_main jump box_dns
add rule ip ${BOX_NFT_TABLE_IP} box_main iifname "lo" return
add rule ip ${BOX_NFT_TABLE_IP} box_main ip daddr 127.0.0.0/8 return
EOF

  if [[ "${BOX_DNS_COEXIST_MODE}" == "preserve_tailnet" ]]; then
    cat <<EOF
add rule inet ${BOX_NFT_TABLE_INET} box_main iifname "${BOX_TAILSCALE_IFACE}" return
add rule inet ${BOX_NFT_TABLE_INET} box_main oifname "${BOX_TAILSCALE_IFACE}" return
add rule ip ${BOX_NFT_TABLE_IP} box_main iifname "${BOX_TAILSCALE_IFACE}" return
add rule ip ${BOX_NFT_TABLE_IP} box_main oifname "${BOX_TAILSCALE_IFACE}" return
add rule inet ${BOX_NFT_TABLE_INET} box_main ip daddr ${BOX_TAILNET_IPV4_CIDR} return
add rule ip ${BOX_NFT_TABLE_IP} box_main ip daddr ${BOX_TAILNET_IPV4_CIDR} return
add rule inet ${BOX_NFT_TABLE_INET} box_main meta mark & ${tailscale_mask} == ${tailscale_mark} return
add rule inet ${BOX_NFT_TABLE_INET} box_dns ip daddr ${BOX_TAILSCALE_DNS_RESOLVER} udp dport 53 return
add rule inet ${BOX_NFT_TABLE_INET} box_dns ip daddr ${BOX_TAILSCALE_DNS_RESOLVER} tcp dport 53 return
add rule ip ${BOX_NFT_TABLE_IP} box_dns ip daddr ${BOX_TAILSCALE_DNS_RESOLVER} udp dport 53 return
add rule ip ${BOX_NFT_TABLE_IP} box_dns ip daddr ${BOX_TAILSCALE_DNS_RESOLVER} tcp dport 53 return
EOF
  fi

  case "${mode}" in
    tun)
      printf 'add rule inet %s box_main return\n' "${BOX_NFT_TABLE_INET}"
      ;;
    redirect)
      printf 'add rule ip %s box_main tcp redirect to :%s\n' "${BOX_NFT_TABLE_IP}" "${BOX_REDIR_PORT}"
      ;;
    tproxy)
      if backend_nft_probe_tproxy; then
        printf 'add rule inet %s box_main meta l4proto tcp tproxy to :%s meta mark set %s\n' "${BOX_NFT_TABLE_INET}" "${BOX_TPROXY_PORT}" "${mark_value}"
        printf 'add rule inet %s box_main meta l4proto udp tproxy to :%s meta mark set %s\n' "${BOX_NFT_TABLE_INET}" "${BOX_TPROXY_PORT}" "${mark_value}"
      else
        printf 'add rule inet %s box_main meta l4proto tcp meta mark set %s\n' "${BOX_NFT_TABLE_INET}" "${mark_value}"
        printf 'add rule inet %s box_main meta l4proto udp meta mark set %s\n' "${BOX_NFT_TABLE_INET}" "${mark_value}"
      fi
      ;;
    mixed|enhance)
      printf 'add rule ip %s box_main tcp redirect to :%s\n' "${BOX_NFT_TABLE_IP}" "${BOX_REDIR_PORT}"
      if backend_nft_probe_tproxy; then
        printf 'add rule inet %s box_main meta l4proto udp tproxy to :%s meta mark set %s\n' "${BOX_NFT_TABLE_INET}" "${BOX_TPROXY_PORT}" "${mark_value}"
      else
        printf 'add rule inet %s box_main meta l4proto udp meta mark set %s\n' "${BOX_NFT_TABLE_INET}" "${mark_value}"
      fi
      ;;
    *)
      return "${E_FIREWALL_APPLY}"
      ;;
  esac

  case "${BOX_DNS_HIJACK_MODE}" in
    disable)
      printf 'add rule inet %s box_dns return\n' "${BOX_NFT_TABLE_INET}"
      printf 'add rule ip %s box_dns return\n' "${BOX_NFT_TABLE_IP}"
      ;;
    redirect)
      printf 'add rule ip %s box_dns udp dport 53 redirect to :%s\n' "${BOX_NFT_TABLE_IP}" "${BOX_DNS_PORT}"
      printf 'add rule ip %s box_dns tcp dport 53 redirect to :%s\n' "${BOX_NFT_TABLE_IP}" "${BOX_DNS_PORT}"
      ;;
    tproxy)
      if backend_nft_probe_tproxy; then
        printf 'add rule inet %s box_dns udp dport 53 tproxy to :%s meta mark set %s\n' "${BOX_NFT_TABLE_INET}" "${BOX_DNS_PORT}" "${mark_value}"
        printf 'add rule inet %s box_dns tcp dport 53 tproxy to :%s meta mark set %s\n' "${BOX_NFT_TABLE_INET}" "${BOX_DNS_PORT}" "${mark_value}"
      else
        printf 'add rule ip %s box_dns udp dport 53 redirect to :%s\n' "${BOX_NFT_TABLE_IP}" "${BOX_DNS_PORT}"
        printf 'add rule ip %s box_dns tcp dport 53 redirect to :%s\n' "${BOX_NFT_TABLE_IP}" "${BOX_DNS_PORT}"
      fi
      ;;
    *)
      return "${E_FIREWALL_APPLY}"
      ;;
  esac
}

backend_nft_dry_run() {
  local mode="${1:?missing mode}"
  printf '# dry-run backend=nftables mode=%s dns=%s coexist=%s\n' "${mode}" "${BOX_DNS_HIJACK_MODE}" "${BOX_DNS_COEXIST_MODE}"
  printf 'delete table inet %s\n' "${BOX_NFT_TABLE_INET}"
  printf 'delete table ip %s\n' "${BOX_NFT_TABLE_IP}"
  backend_nft_build_ruleset "${mode}"
  printf 'ip rule add fwmark %s table %s pref %s\n' "${BOX_FWMARK}" "${BOX_ROUTE_TABLE}" "${BOX_ROUTE_PREF}"
  printf 'ip route add local default dev lo table %s\n' "${BOX_ROUTE_TABLE}"
}

backend_nft_apply_mode() {
  local mode="${1:?missing mode}"
  local nft ruleset

  backend_nft_init
  FW_LAST_ERROR=""
  FW_TAILSCALE_BYPASS_APPLIED="false"

  if [[ "${BOX_FIREWALL_DRY_RUN:-0}" == "1" ]]; then
    backend_nft_dry_run "${mode}"
    return 0
  fi

  backend_nft_cleanup
  ruleset="$(backend_nft_build_ruleset "${mode}")" || {
    FW_LAST_ERROR="failed to build nft ruleset"
    return "${E_FIREWALL_APPLY}"
  }

  nft="$(nft_cmd)"
  trace_cmd "firewall" "${nft}" -f -
  if ! printf '%s\n' "${ruleset}" | "${nft}" -f - >/dev/null 2>&1; then
    FW_LAST_ERROR="nft apply failed"
    backend_nft_cleanup || true
    return "${E_FIREWALL_APPLY}"
  fi

  case "${mode}" in
    tproxy|mixed|enhance) backend_nft_ensure_policy_route ;;
  esac
  if [[ "${BOX_DNS_HIJACK_MODE}" == "tproxy" ]]; then
    backend_nft_ensure_policy_route
  fi

  if [[ "${BOX_DNS_COEXIST_MODE}" == "preserve_tailnet" ]]; then
    FW_TAILSCALE_BYPASS_APPLIED="true"
  fi
  return 0
}

backend_nft_collect_status() {
  local nft ip_tool
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
  FW_CAP_DETAILS="backend=nftables,available=false"
  FW_LAST_ERROR=""

  nft="$(nft_cmd || true)"
  ip_tool="$(nft_ip_cmd || true)"
  if [[ -z "${nft}" || -z "${ip_tool}" ]]; then
    FW_LAST_ERROR="nft/ip command not found"
    return 0
  fi

  FW_BACKEND_AVAILABLE="true"
  if "${nft}" list table inet "${BOX_NFT_TABLE_INET}" >/dev/null 2>&1; then
    FW_CHAIN_MANGLE="true"
    FW_CHAIN_DNS_MANGLE="true"
  fi
  if "${nft}" list table ip "${BOX_NFT_TABLE_IP}" >/dev/null 2>&1; then
    FW_CHAIN_NAT="true"
    FW_CHAIN_DNS_NAT="true"
  fi
  if backend_nft_probe_tproxy; then FW_CAP_TPROXY="true"; fi
  FW_CAP_DETAILS="backend=nftables,available=true,tproxy=${FW_CAP_TPROXY}"
  if "${ip_tool}" rule list 2>/dev/null | grep -Eq "fwmark[[:space:]]+${BOX_FWMARK}[[:space:]]+(lookup|table)[[:space:]]+${BOX_ROUTE_TABLE}"; then FW_ROUTE_RULE="true"; fi
  if "${ip_tool}" route show table "${BOX_ROUTE_TABLE}" 2>/dev/null | grep -Fq "local default dev lo"; then FW_ROUTE_TABLE_INSTALLED="true"; fi
  if "${ip_tool}" rule list 2>/dev/null | grep -Eq "fwmark[[:space:]]+${BOX_TAILSCALE_FWMARK}[[:space:]]+(lookup|table)[[:space:]]+${BOX_TAILSCALE_ROUTE_TABLE}"; then
    FW_TAILSCALE_MARK_RULE="true"
  fi
  if "${ip_tool}" route show table "${BOX_TAILSCALE_ROUTE_TABLE}" 2>/dev/null | grep -q '.'; then
    FW_TAILSCALE_TABLE_PRESENT="true"
  fi
  if "${nft}" list chain inet "${BOX_NFT_TABLE_INET}" box_main 2>/dev/null | grep -Fq "iifname \"${BOX_TAILSCALE_IFACE}\" return"; then
    FW_TAILSCALE_BYPASS_APPLIED="true"
  fi
}
