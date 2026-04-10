#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

BOX_NFT_TABLE_INET="box_mangle"
BOX_NFT_TABLE_IP="box_nat"
BOX_MIHOMO_FAKEIP_V4_CIDR="198.18.0.0/16"

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

nft_fwmark_normalize() {
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

nft_fwmark_equal() {
  local left="${1:?missing left fwmark}"
  local right="${2:?missing right fwmark}"
  local left_norm right_norm

  left_norm="$(nft_fwmark_normalize "${left}" 2>/dev/null || true)"
  right_norm="$(nft_fwmark_normalize "${right}" 2>/dev/null || true)"
  [[ -n "${left_norm}" && -n "${right_norm}" && "${left_norm}" == "${right_norm}" ]]
}

backend_nft_rule_line_fwmark() {
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

backend_nft_rule_line_table() {
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

backend_nft_probe_tproxy() {
  if [[ "${BOX_NFT_FORCE_NO_TPROXY:-0}" == "1" ]]; then
    return 1
  fi
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
  local line_mark line_table
  line_mark="$(backend_nft_rule_line_fwmark "${line}" 2>/dev/null || true)"
  line_table="$(backend_nft_rule_line_table "${line}" 2>/dev/null || true)"
  [[ -n "${line_mark}" && "${line_table}" == "${BOX_ROUTE_TABLE}" ]] || return 1
  nft_fwmark_equal "${line_mark}" "${BOX_FWMARK}"
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
        "${ip_tool}" rule del pref "${pref}" >/dev/null 2>&1 || true
      else
        "${ip_tool}" rule del fwmark "${BOX_FWMARK}" table "${BOX_ROUTE_TABLE}" >/dev/null 2>&1 || true
      fi
    fi
  done < <("${ip_tool}" rule list 2>/dev/null || true)
}

backend_nft_ensure_policy_route() {
  local ip_tool
  ip_tool="$(nft_ip_cmd)"
  backend_nft_prune_box_policy_rules

  "${ip_tool}" rule add fwmark "${BOX_FWMARK}" table "${BOX_ROUTE_TABLE}" pref "${BOX_ROUTE_PREF}" >/dev/null 2>&1 || true
  if ! "${ip_tool}" route show table "${BOX_ROUTE_TABLE}" 2>/dev/null | grep -Fq "local default dev lo"; then
    "${ip_tool}" route add local default dev lo table "${BOX_ROUTE_TABLE}" >/dev/null 2>&1 || true
  fi
}

backend_nft_cleanup() {
  local nft ip_tool
  nft="$(nft_cmd || true)"
  ip_tool="$(nft_ip_cmd || true)"

  if [[ -n "${nft}" ]]; then
    "${nft}" delete table inet "${BOX_NFT_TABLE_INET}" >/dev/null 2>&1 || true
    "${nft}" delete table ip "${BOX_NFT_TABLE_IP}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${ip_tool}" ]]; then
    backend_nft_prune_box_policy_rules
    while "${ip_tool}" route show table "${BOX_ROUTE_TABLE}" 2>/dev/null | grep -Fq "local default dev lo"; do
      "${ip_tool}" route del local default dev lo table "${BOX_ROUTE_TABLE}" >/dev/null 2>&1 || break
    done
  fi
}

backend_nft_ruleset_debug_path() {
  init_runtime_paths
  printf '%s/state/nft-last-ruleset.nft\n' "${BOX_RUN_DIR}"
}

backend_nft_stderr_debug_path() {
  init_runtime_paths
  printf '%s/state/nft-last-error.log\n' "${BOX_RUN_DIR}"
}

backend_nft_record_failure_artifacts() {
  local ruleset="${1:-}"
  local stderr_file="${2:-}"
  local ruleset_path error_path

  ruleset_path="$(backend_nft_ruleset_debug_path)"
  error_path="$(backend_nft_stderr_debug_path)"

  printf '%s\n' "${ruleset}" >"${ruleset_path}"
  if [[ -n "${stderr_file}" && -f "${stderr_file}" ]]; then
    cp -f "${stderr_file}" "${error_path}" 2>/dev/null || true
  else
    : >"${error_path}"
  fi

  log "ERROR" "firewall" "E_NFT_RULESET_DUMP" \
    "nft failure artifacts written ruleset=${ruleset_path} stderr=${error_path}"
}

backend_nft_format_cidrs() {
  local first=1 cidr
  while IFS= read -r cidr; do
    [[ -n "${cidr}" ]] || continue
    if [[ "${first}" == "1" ]]; then
      printf '%s' "${cidr}"
      first=0
    else
      printf ', %s' "${cidr}"
    fi
  done
}

backend_nft_build_bypass_sets() {
  local private_elements="" cn_elements=""

  if firewall_bool_enabled "${BOX_BYPASS_PRIVATE_IP:-false}"; then
    private_elements="$(firewall_private_ipv4_cidrs | backend_nft_format_cidrs)"
    if [[ -n "${private_elements}" ]]; then
      cat <<EOF
add set inet ${BOX_NFT_TABLE_INET} box_private_v4 { type ipv4_addr; flags interval; elements = { ${private_elements} } }
add set ip ${BOX_NFT_TABLE_IP} box_private_v4 { type ipv4_addr; flags interval; elements = { ${private_elements} } }
EOF
    fi
  fi

  if firewall_bool_enabled "${BOX_BYPASS_CN_IP:-false}"; then
    if ! cn_elements="$(firewall_load_cn_ipv4_cidrs | backend_nft_format_cidrs)"; then
      return "${E_FIREWALL_APPLY}"
    fi
    if [[ -z "${cn_elements}" ]]; then
      FW_LAST_ERROR="CN bypass CIDR list is empty: ${BOX_BYPASS_CN_FILE}"
      return "${E_FIREWALL_APPLY}"
    fi
    cat <<EOF
add set inet ${BOX_NFT_TABLE_INET} box_cn_v4 { type ipv4_addr; flags interval; elements = { ${cn_elements} } }
add set ip ${BOX_NFT_TABLE_IP} box_cn_v4 { type ipv4_addr; flags interval; elements = { ${cn_elements} } }
EOF
  fi
}

backend_nft_build_bypass_rules() {
  if firewall_bool_enabled "${BOX_BYPASS_PRIVATE_IP:-false}"; then
    cat <<EOF
add rule inet ${BOX_NFT_TABLE_INET} box_main ip daddr @box_private_v4 return
add rule ip ${BOX_NFT_TABLE_IP} box_main ip daddr @box_private_v4 return
EOF
  fi

  if firewall_bool_enabled "${BOX_BYPASS_CN_IP:-false}"; then
    cat <<EOF
add rule inet ${BOX_NFT_TABLE_INET} box_main ip daddr @box_cn_v4 return
add rule ip ${BOX_NFT_TABLE_IP} box_main ip daddr @box_cn_v4 return
EOF
  fi
}

backend_nft_build_org_dns_bypass_rules() {
  local dns_server
  local -a dns_servers=()

  mapfile -t dns_servers < <(firewall_org_dns_bypass_servers || true)
  [[ "${#dns_servers[@]}" -gt 0 ]] || return 0

  for dns_server in "${dns_servers[@]}"; do
    [[ "${dns_server}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || continue
    cat <<EOF
add rule inet ${BOX_NFT_TABLE_INET} box_dns ip daddr ${dns_server} udp dport 53 return
add rule inet ${BOX_NFT_TABLE_INET} box_dns ip daddr ${dns_server} tcp dport 53 return
add rule ip ${BOX_NFT_TABLE_IP} box_dns ip daddr ${dns_server} udp dport 53 return
add rule ip ${BOX_NFT_TABLE_IP} box_dns ip daddr ${dns_server} tcp dport 53 return
EOF
  done
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
$(if [[ "${BOX_DNS_ENHANCED_MODE}" == "fake-ip" ]]; then printf 'add rule inet %s output meta skuid 0 ip daddr %s jump box_main\n' "${BOX_NFT_TABLE_INET}" "${BOX_MIHOMO_FAKEIP_V4_CIDR}"; fi)
add rule inet ${BOX_NFT_TABLE_INET} output meta skuid 0 jump box_dns
add rule inet ${BOX_NFT_TABLE_INET} output meta skuid 0 return
add rule inet ${BOX_NFT_TABLE_INET} output jump box_main
add rule inet ${BOX_NFT_TABLE_INET} box_main jump box_dns
add rule inet ${BOX_NFT_TABLE_INET} box_main iifname "lo" return
add rule inet ${BOX_NFT_TABLE_INET} box_main ip daddr 127.0.0.0/8 return
add table ip ${BOX_NFT_TABLE_IP}
add chain ip ${BOX_NFT_TABLE_IP} prerouting { type nat hook prerouting priority dstnat; policy accept; }
add chain ip ${BOX_NFT_TABLE_IP} output { type nat hook output priority -100; policy accept; }
add chain ip ${BOX_NFT_TABLE_IP} box_main
add chain ip ${BOX_NFT_TABLE_IP} box_dns
add rule ip ${BOX_NFT_TABLE_IP} prerouting jump box_main
$(if [[ "${BOX_DNS_ENHANCED_MODE}" == "fake-ip" ]]; then printf 'add rule ip %s output meta skuid 0 ip daddr %s jump box_main\n' "${BOX_NFT_TABLE_IP}" "${BOX_MIHOMO_FAKEIP_V4_CIDR}"; fi)
add rule ip ${BOX_NFT_TABLE_IP} output meta skuid 0 jump box_dns
add rule ip ${BOX_NFT_TABLE_IP} output meta skuid 0 return
add rule ip ${BOX_NFT_TABLE_IP} output jump box_main
add rule ip ${BOX_NFT_TABLE_IP} box_main jump box_dns
add rule ip ${BOX_NFT_TABLE_IP} box_main iifname "lo" return
add rule ip ${BOX_NFT_TABLE_IP} box_main ip daddr 127.0.0.0/8 return
EOF

  backend_nft_build_bypass_sets || return "${E_FIREWALL_APPLY}"
  backend_nft_build_bypass_rules || return "${E_FIREWALL_APPLY}"
  backend_nft_build_org_dns_bypass_rules || return "${E_FIREWALL_APPLY}"

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
      printf 'add rule ip %s box_main meta l4proto tcp redirect to :%s\n' "${BOX_NFT_TABLE_IP}" "${BOX_REDIR_PORT}"
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
      printf 'add rule ip %s box_main meta l4proto tcp redirect to :%s\n' "${BOX_NFT_TABLE_IP}" "${BOX_REDIR_PORT}"
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

  printf 'add rule inet %s box_main return comment "BOX_POLICY_PLACEHOLDER"\n' "${BOX_NFT_TABLE_INET}"

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
  local nft ruleset stderr_file

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
  stderr_file="$(mktemp)"
  if ! printf '%s\n' "${ruleset}" | "${nft}" -f - >/dev/null 2>"${stderr_file}"; then
    # Some kernels expose nft userspace tproxy tokens but fail loading tproxy expressions.
    # Retry once with explicit non-tproxy fallback before failing apply.
    if backend_nft_probe_tproxy; then
      log "WARN" "firewall" "FW_TPROXY_DOWNGRADE" "nft apply with tproxy failed; retrying without tproxy expressions"
      backend_nft_cleanup || true
      BOX_NFT_FORCE_NO_TPROXY=1
      ruleset="$(backend_nft_build_ruleset "${mode}")" || {
        unset BOX_NFT_FORCE_NO_TPROXY
        rm -f "${stderr_file}"
        FW_LAST_ERROR="failed to build nft fallback ruleset"
        return "${E_FIREWALL_APPLY}"
      }
      if ! printf '%s\n' "${ruleset}" | "${nft}" -f - >/dev/null 2>"${stderr_file}"; then
        unset BOX_NFT_FORCE_NO_TPROXY
        backend_nft_record_failure_artifacts "${ruleset}" "${stderr_file}"
        rm -f "${stderr_file}"
        FW_LAST_ERROR="nft apply failed"
        backend_nft_cleanup || true
        return "${E_FIREWALL_APPLY}"
      fi
      unset BOX_NFT_FORCE_NO_TPROXY
    else
      backend_nft_record_failure_artifacts "${ruleset}" "${stderr_file}"
      rm -f "${stderr_file}"
      FW_LAST_ERROR="nft apply failed"
      backend_nft_cleanup || true
      return "${E_FIREWALL_APPLY}"
    fi
  fi
  rm -f "${stderr_file}"

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
  FW_CAP_IPV4="false"
  FW_CAP_IPV6="false"
  FW_DRY_RUN_SUPPORTED="true"
  FW_DNS_COEXIST_MODE_ACTIVE="${BOX_DNS_COEXIST_MODE}"
  FW_CAP_DETAILS="backend=nftables,available=false,ipv4=false,ipv6=false,tproxy=false,dry_run=true"
  FW_LAST_ERROR=""

  nft="$(nft_cmd || true)"
  ip_tool="$(nft_ip_cmd || true)"
  if [[ -z "${nft}" || -z "${ip_tool}" ]]; then
    FW_LAST_ERROR="nft/ip command not found"
    return 0
  fi

  if ! "${nft}" list tables >/dev/null 2>&1; then
    FW_LAST_ERROR="nftables inspection unavailable (need root/CAP_NET_ADMIN or kernel support)"
    return 0
  fi

  FW_BACKEND_AVAILABLE="true"
  FW_CAP_IPV4="true"
  if "${nft}" list table inet "${BOX_NFT_TABLE_INET}" >/dev/null 2>&1; then
    FW_CHAIN_MANGLE="true"
    FW_CHAIN_DNS_MANGLE="true"
  fi
  if "${nft}" list table ip "${BOX_NFT_TABLE_IP}" >/dev/null 2>&1; then
    FW_CHAIN_NAT="true"
    FW_CHAIN_DNS_NAT="true"
  fi
  if backend_nft_probe_tproxy; then FW_CAP_TPROXY="true"; fi
  FW_CAP_DETAILS="backend=nftables,available=true,ipv4=true,ipv6=false,tproxy=${FW_CAP_TPROXY},dry_run=true"
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
