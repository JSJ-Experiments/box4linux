#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOXCTL="${ROOT_DIR}/cmd/boxctl"
TMP_DIR="$(mktemp -d)"
MOCK_DIR="${ROOT_DIR}/tests/fixtures/mockbin"

cleanup() {
  if [[ -f "${TMP_DIR}/run/box.pid" ]]; then
    pid="$(tr -d '[:space:]' <"${TMP_DIR}/run/box.pid" || true)"
    if [[ -n "${pid:-}" ]]; then
      kill -TERM "${pid}" >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

export PATH="${MOCK_DIR}:${PATH}"
export MOCK_IPTABLES_STATE="${TMP_DIR}/mock/iptables.state"
export MOCK_IP_STATE="${TMP_DIR}/mock/ip.state"
export MOCK_NFT_STATE="${TMP_DIR}/mock/nft.state"
export BOX_IPTABLES_CMD="${MOCK_DIR}/iptables"
export BOX_IP_CMD="${MOCK_DIR}/ip"
export BOX_NFT_CMD="${MOCK_DIR}/nft"
export BOX_UNSAFE_SKIP_ROOT_CHECK=1
export BOX_CAP_TPROXY=1
export BOX_RUN_DIR="${TMP_DIR}/run"
export BOX_VAR_DIR="${TMP_DIR}/var"
export BOX_LOG_DIR="${TMP_DIR}/log"

mkdir -p "${TMP_DIR}/mock" "${TMP_DIR}/profiles" "${BOX_RUN_DIR}" "${BOX_VAR_DIR}" "${BOX_LOG_DIR}"
touch "${MOCK_IPTABLES_STATE}" "${MOCK_IP_STATE}" "${MOCK_NFT_STATE}"

MIHOMO_SOURCE="${TMP_DIR}/profiles/mihomo.yaml"
SING_SOURCE="${TMP_DIR}/profiles/sing-box.json"
CONFIG_FILE="${TMP_DIR}/box.toml"
export BOX_CONFIG_FILE="${CONFIG_FILE}"

cat >"${MIHOMO_SOURCE}" <<'EOF'
mode: rule
mixed-port: 7890
tun:
  enable: true
  auto-route: true
  auto-redirect: true
  strict-route: true
rules:
  - MATCH,DIRECT
EOF

cat >"${SING_SOURCE}" <<'EOF'
{
  "log": { "level": "info" },
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF

write_config() {
  local core="${1:?missing core}"
  local mode="${2:?missing mode}"
  local dns_mode="${3:?missing dns mode}"
  local source="${4:?missing source config path}"
  local coexist_mode="${5:-preserve_tailnet}"
  local route_pref="${6:-100}"
  local backend="${7:-iptables}"
  local firewall_extra="${8:-}"
  local dns_enhanced_mode="${9:-fake-ip}"
  local ipv6_enabled="${10:-true}"
  cat >"${CONFIG_FILE}" <<EOF
[core]
selected = "${core}"
bin_dir = "${MOCK_DIR}"
workdir = "${BOX_VAR_DIR}"
config_source = "${source}"

[network]
mode = "${mode}"
tproxy_port = 19898
redir_port = 19797
dns_port = 11053
dns_hijack_mode = "${dns_mode}"
dns_enhanced_mode = "${dns_enhanced_mode}"
dns_coexist_mode = "${coexist_mode}"
ipv6 = ${ipv6_enabled}
tailscale_iface = "tailscale0"
tailnet_ipv4_cidr = "100.64.0.0/10"
tailnet_ipv6_cidr = "fd7a:115c:a1e0::/48"
tailscale_dns_resolver = "100.100.100.100"
tailscale_fwmark = "0x80000/0xff0000"
tailscale_route_table = 52

[firewall]
backend = "${backend}"
route_table = 2024
route_pref = ${route_pref}
fwmark = "16777216/16777216"
${firewall_extra}
EOF
}

must_run() {
  local output
  if ! output="$("$BOXCTL" "$@" 2>&1)"; then
    printf 'FAILED: boxctl %s\n%s\n' "$*" "${output}" >&2
    exit 1
  fi
  printf '%s\n' "${output}"
}

must_fail() {
  local output
  if output="$("$BOXCTL" "$@" 2>&1)"; then
    printf 'UNEXPECTED SUCCESS: boxctl %s\n%s\n' "$*" "${output}" >&2
    exit 1
  fi
  printf '%s\n' "${output}"
}

assert_contains() {
  local haystack="${1:?missing haystack}"
  local needle="${2:?missing needle}"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    printf 'ASSERT CONTAINS FAILED: expected [%s] in [%s]\n' "${needle}" "${haystack}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="${1:?missing haystack}"
  local needle="${2:?missing needle}"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    printf 'ASSERT NOT CONTAINS FAILED: unexpected [%s] in [%s]\n' "${needle}" "${haystack}" >&2
    exit 1
  fi
}

assert_file_exists() {
  local path="${1:?missing path}"
  if [[ ! -f "${path}" ]]; then
    printf 'ASSERT FILE FAILED: missing %s\n' "${path}" >&2
    exit 1
  fi
}

assert_file_contains() {
  local path="${1:?missing path}"
  local needle="${2:?missing needle}"
  if ! grep -Fq "${needle}" "${path}"; then
    printf 'ASSERT FILE CONTAINS FAILED: expected [%s] in %s\n' "${needle}" "${path}" >&2
    cat "${path}" >&2 || true
    exit 1
  fi
}

assert_line_order() {
  local haystack="${1:?missing haystack}"
  local first="${2:?missing first needle}"
  local second="${3:?missing second needle}"
  local first_line second_line
  first_line="$(printf '%s\n' "${haystack}" | nl -ba | awk -v needle="${first}" 'index($0, needle) { print $1; exit }')"
  second_line="$(printf '%s\n' "${haystack}" | nl -ba | awk -v needle="${second}" 'index($0, needle) { print $1; exit }')"
  if [[ -z "${first_line}" || -z "${second_line}" || "${first_line}" -ge "${second_line}" ]]; then
    printf 'ASSERT ORDER FAILED: expected [%s] before [%s]\n' "${first}" "${second}" >&2
    printf '%s\n' "${haystack}" >&2
    exit 1
  fi
}

assert_no_duplicate_rules_iptables() {
  local dup_count
  dup_count="$(grep '^RULE|' "${MOCK_IPTABLES_STATE}" | sort | uniq -d | wc -l | tr -d '[:space:]')"
  if [[ "${dup_count}" != "0" ]]; then
    printf 'ASSERT DUPLICATE RULE FAILED: %s duplicate rules in %s\n' "${dup_count}" "${MOCK_IPTABLES_STATE}" >&2
    exit 1
  fi
}

assert_no_duplicate_rules_nft() {
  local dup_count
  dup_count="$(grep '^RULE|' "${MOCK_NFT_STATE}" | sort | uniq -d | wc -l | tr -d '[:space:]')"
  if [[ "${dup_count}" != "0" ]]; then
    printf 'ASSERT DUPLICATE NFT RULE FAILED: %s duplicate rules in %s\n' "${dup_count}" "${MOCK_NFT_STATE}" >&2
    exit 1
  fi
}

assert_no_box_artifacts() {
  if grep -q 'BOX_' "${MOCK_IPTABLES_STATE}"; then
    printf 'ASSERT CLEANUP FAILED: BOX chains/rules still present\n' >&2
    cat "${MOCK_IPTABLES_STATE}" >&2
    exit 1
  fi
  if grep -Eq 'RULE\|.*(16777216/16777216|table 2024|lookup 2024)' "${MOCK_IP_STATE}" || \
    grep -Eq 'ROUTE\|2024\|' "${MOCK_IP_STATE}"; then
    printf 'ASSERT CLEANUP FAILED: box ip rule/route artifacts still present\n' >&2
    cat "${MOCK_IP_STATE}" >&2
    exit 1
  fi
  if grep -Eq '(TABLE|CHAIN|RULE)\|(inet|ip)\|(box_mangle|box_nat)' "${MOCK_NFT_STATE}"; then
    printf 'ASSERT CLEANUP FAILED: nft BOX tables/chains/rules still present\n' >&2
    cat "${MOCK_NFT_STATE}" >&2
    exit 1
  fi
}

seed_tailscale_state() {
  cat >"${MOCK_IP_STATE}" <<'EOF'
RULE|fwmark 0x80000/0xff0000 lookup 52
ROUTE|52|local 100.100.100.100 dev lo table 52
EOF
}

assert_tailscale_state_preserved() {
  if ! grep -Fq 'RULE|fwmark 0x80000/0xff0000 lookup 52' "${MOCK_IP_STATE}"; then
    printf 'ASSERT TAILSCALE FAILED: fwmark rule missing\n' >&2
    cat "${MOCK_IP_STATE}" >&2
    exit 1
  fi
  if ! grep -Fq 'ROUTE|52|local 100.100.100.100 dev lo table 52' "${MOCK_IP_STATE}"; then
    printf 'ASSERT TAILSCALE FAILED: table 52 route missing\n' >&2
    cat "${MOCK_IP_STATE}" >&2
    exit 1
  fi
}

assert_magicdns_bypass_rules() {
  if ! grep -Fq 'RULE|mangle|BOX_DNS_MANGLE|-d 100.100.100.100 -p udp --dport 53 -j RETURN' "${MOCK_IPTABLES_STATE}"; then
    printf 'ASSERT MAGICDNS FAILED: UDP resolver bypass missing\n' >&2
    cat "${MOCK_IPTABLES_STATE}" >&2
    exit 1
  fi
  if ! grep -Fq 'RULE|mangle|BOX_DNS_MANGLE|-d 100.100.100.100 -p tcp --dport 53 -j RETURN' "${MOCK_IPTABLES_STATE}"; then
    printf 'ASSERT MAGICDNS FAILED: TCP resolver bypass missing\n' >&2
    cat "${MOCK_IPTABLES_STATE}" >&2
    exit 1
  fi
  if ! grep -Fq 'RULE|nat|BOX_DNS_NAT|-d 100.100.100.100 -p udp --dport 53 -j RETURN' "${MOCK_IPTABLES_STATE}"; then
    printf 'ASSERT MAGICDNS FAILED: NAT resolver bypass missing\n' >&2
    cat "${MOCK_IPTABLES_STATE}" >&2
    exit 1
  fi
  if ! grep -Fq 'RULE|nat|BOX_DNS_NAT|-d 100.100.100.100 -p tcp --dport 53 -j RETURN' "${MOCK_IPTABLES_STATE}"; then
    printf 'ASSERT MAGICDNS FAILED: NAT TCP resolver bypass missing\n' >&2
    cat "${MOCK_IPTABLES_STATE}" >&2
    exit 1
  fi
}

assert_tailscale_bypass_rules() {
  if ! grep -Fq 'RULE|mangle|BOX_MANGLE|-i tailscale0 -j RETURN' "${MOCK_IPTABLES_STATE}"; then
    printf 'ASSERT TAILSCALE FAILED: iface bypass missing\n' >&2
    cat "${MOCK_IPTABLES_STATE}" >&2
    exit 1
  fi
  if ! grep -Fq 'RULE|mangle|BOX_MANGLE|-m mark --mark 0x80000/0xff0000 -j RETURN' "${MOCK_IPTABLES_STATE}"; then
    printf 'ASSERT TAILSCALE FAILED: mark bypass missing\n' >&2
    cat "${MOCK_IPTABLES_STATE}" >&2
    exit 1
  fi
  if ! grep -Fq 'RULE|mangle|BOX_MANGLE|-d 100.64.0.0/10 -j RETURN' "${MOCK_IPTABLES_STATE}"; then
    printf 'ASSERT TAILSCALE FAILED: CIDR bypass missing\n' >&2
    cat "${MOCK_IPTABLES_STATE}" >&2
    exit 1
  fi
}

assert_nft_tailscale_bypass_rules() {
  if ! grep -Fq 'RULE|inet|box_mangle|box_main|iifname "tailscale0" return' "${MOCK_NFT_STATE}"; then
    printf 'ASSERT NFT TAILSCALE FAILED: iface bypass missing\n' >&2
    cat "${MOCK_NFT_STATE}" >&2
    exit 1
  fi
  if ! grep -Fq 'RULE|inet|box_mangle|box_dns|ip daddr 100.100.100.100 udp dport 53 return' "${MOCK_NFT_STATE}"; then
    printf 'ASSERT NFT MAGICDNS FAILED: resolver bypass missing\n' >&2
    cat "${MOCK_NFT_STATE}" >&2
    exit 1
  fi
}

assert_no_tailscale_bypass_rules() {
  if grep -Fq 'RULE|mangle|BOX_MANGLE|-i tailscale0 -j RETURN' "${MOCK_IPTABLES_STATE}" || \
    grep -Fq 'RULE|mangle|BOX_MANGLE|-m mark --mark 0x80000/0xff0000 -j RETURN' "${MOCK_IPTABLES_STATE}" || \
    grep -Fq 'RULE|mangle|BOX_DNS_MANGLE|-d 100.100.100.100 -p udp --dport 53 -j RETURN' "${MOCK_IPTABLES_STATE}" || \
    grep -Fq 'RULE|mangle|BOX_DNS_MANGLE|-d 100.100.100.100 -p tcp --dport 53 -j RETURN' "${MOCK_IPTABLES_STATE}" || \
    grep -Fq 'RULE|nat|BOX_DNS_NAT|-d 100.100.100.100 -p udp --dport 53 -j RETURN' "${MOCK_IPTABLES_STATE}" || \
    grep -Fq 'RULE|nat|BOX_DNS_NAT|-d 100.100.100.100 -p tcp --dport 53 -j RETURN' "${MOCK_IPTABLES_STATE}"; then
    printf 'ASSERT STRICT BOX FAILED: tailscale bypass rule unexpectedly present\n' >&2
    cat "${MOCK_IPTABLES_STATE}" >&2
    exit 1
  fi
}

assert_nft_no_tailscale_bypass_rules() {
  if grep -Fq 'RULE|inet|box_mangle|box_main|iifname "tailscale0" return' "${MOCK_NFT_STATE}" || \
    grep -Fq 'RULE|inet|box_mangle|box_dns|ip daddr 100.100.100.100 udp dport 53 return' "${MOCK_NFT_STATE}"; then
    printf 'ASSERT NFT STRICT BOX FAILED: tailscale bypass rule unexpectedly present\n' >&2
    cat "${MOCK_NFT_STATE}" >&2
    exit 1
  fi
}

assert_box_route_pref() {
  local expected_pref="${1:?missing expected pref}"
  local matching total
  matching="$(grep -Ec "^RULE\\|fwmark 16777216/16777216 (lookup|table) 2024 pref ${expected_pref}$" "${MOCK_IP_STATE}" || true)"
  total="$(grep -Ec "^RULE\\|fwmark 16777216/16777216 (lookup|table) 2024 pref " "${MOCK_IP_STATE}" || true)"
  if [[ "${matching}" != "1" || "${total}" != "1" ]]; then
    printf 'ASSERT ROUTE PREF FAILED: expected exactly one pref=%s rule; found matching=%s total=%s\n' \
      "${expected_pref}" "${matching}" "${total}" >&2
    cat "${MOCK_IP_STATE}" >&2
    exit 1
  fi
}

run_firewall_mode_case() {
  local mode="${1:?missing mode}"
  local dns_mode="${2:?missing dns mode}"
  local coexist_mode="${3:-preserve_tailnet}"
  local route_pref="${4:-100}"
  local backend="${5:-iptables}"
  local expect_box_route="false"
  write_config "mihomo" "${mode}" "${dns_mode}" "${MIHOMO_SOURCE}" "${coexist_mode}" "${route_pref}" "${backend}"
  seed_tailscale_state

  case "${mode}" in
    tproxy|mixed|enhance) expect_box_route="true" ;;
  esac
  if [[ "${dns_mode}" == "tproxy" ]]; then
    expect_box_route="true"
  fi

  must_run firewall enable >/dev/null
  must_run firewall renew >/dev/null
  must_run firewall renew >/dev/null
  if [[ "${backend}" == "iptables" ]]; then
    assert_no_duplicate_rules_iptables
  else
    assert_no_duplicate_rules_nft
  fi
  if [[ "${coexist_mode}" == "preserve_tailnet" && "${backend}" == "iptables" ]]; then
    assert_tailscale_bypass_rules
    assert_magicdns_bypass_rules
  elif [[ "${coexist_mode}" == "preserve_tailnet" && "${backend}" == "nftables" ]]; then
    assert_nft_tailscale_bypass_rules
  elif [[ "${backend}" == "iptables" ]]; then
    assert_no_tailscale_bypass_rules
  else
    assert_nft_no_tailscale_bypass_rules
  fi
  assert_tailscale_state_preserved

  status_json="$(must_run firewall status --json)"
  assert_contains "${status_json}" "\"status\":\"enabled\""
  assert_contains "${status_json}" "\"mode\":\"${mode}\""
  assert_contains "${status_json}" "\"backend\":\"${backend}\""
  assert_contains "${status_json}" "\"backend_selected\":\"${backend}\""
  assert_contains "${status_json}" "\"backend_capabilities\":"
  assert_contains "${status_json}" "\"backend_available\":true"
  assert_contains "${status_json}" "\"dns_hijack_mode\":\"${dns_mode}\""
  assert_contains "${status_json}" "\"dns_enhanced_mode\":\"fake-ip\""
  assert_contains "${status_json}" "\"dns_coexist_mode\":\"${coexist_mode}\""
  assert_contains "${status_json}" "\"dns_coexist_mode_active\":\"${coexist_mode}\""
  assert_contains "${status_json}" "\"ipv6_enabled\":true"
  if [[ "${mode}" == "tun" ]]; then
    assert_contains "${status_json}" "\"ipv6_effective_mode\":\"proxied\""
  else
    assert_contains "${status_json}" "\"ipv6_effective_mode\":\"direct\""
  fi
  assert_contains "${status_json}" "\"cap_ipv4\":true"
  assert_contains "${status_json}" "\"cap_ipv6\":false"
  assert_contains "${status_json}" "\"dry_run_supported\":true"
  assert_contains "${status_json}" "\"last_error\":\"\""
  assert_not_contains "${status_json}" "\"error\":"
  assert_contains "${status_json}" "\"tailscale_iface\":\"tailscale0\""
  assert_contains "${status_json}" "\"tailscale_mark_rule\":true"
  assert_contains "${status_json}" "\"tailscale_table_present\":true"
  if [[ "${coexist_mode}" == "preserve_tailnet" ]]; then
    assert_contains "${status_json}" "\"tailscale_bypass_applied\":true"
  else
    assert_contains "${status_json}" "\"tailscale_bypass_applied\":false"
  fi
  if [[ "${expect_box_route}" == "true" ]]; then
    assert_box_route_pref "${route_pref}"
  fi

  must_run firewall disable >/dev/null
  assert_tailscale_state_preserved
  assert_no_box_artifacts
}

printf '[1/13] firewall mode/dns apply+renew+disable idempotency (preserve_tailnet)\n'
run_firewall_mode_case "tun" "disable" "preserve_tailnet" "100" "iptables"
run_firewall_mode_case "tproxy" "tproxy" "preserve_tailnet" "100" "iptables"
run_firewall_mode_case "redirect" "redirect" "preserve_tailnet" "100" "iptables"
run_firewall_mode_case "mixed" "tproxy" "preserve_tailnet" "100" "iptables"
run_firewall_mode_case "enhance" "redirect" "preserve_tailnet" "100" "iptables"

printf '[2/13] nftables backend mode/dns apply+renew+disable idempotency (preserve_tailnet)\n'
run_firewall_mode_case "tun" "disable" "preserve_tailnet" "100" "nftables"
run_firewall_mode_case "tproxy" "tproxy" "preserve_tailnet" "100" "nftables"
run_firewall_mode_case "redirect" "redirect" "preserve_tailnet" "100" "nftables"
run_firewall_mode_case "mixed" "tproxy" "preserve_tailnet" "100" "nftables"
run_firewall_mode_case "enhance" "redirect" "preserve_tailnet" "100" "nftables"

printf '[3/13] coexist mode strict_box rule differences\n'
run_firewall_mode_case "tproxy" "tproxy" "strict_box" "100" "iptables"
run_firewall_mode_case "tproxy" "tproxy" "strict_box" "100" "nftables"

printf '[4/13] route_pref convergence across renew\n'
write_config "mihomo" "tproxy" "tproxy" "${MIHOMO_SOURCE}" "preserve_tailnet" "100" "iptables"
seed_tailscale_state
must_run firewall enable >/dev/null
assert_box_route_pref "100"
write_config "mihomo" "tproxy" "tproxy" "${MIHOMO_SOURCE}" "preserve_tailnet" "333" "iptables"
must_run firewall renew >/dev/null
assert_box_route_pref "333"
must_run firewall disable >/dev/null
assert_tailscale_state_preserved
assert_no_box_artifacts

printf '[5/13] firewall dry-run surfaces intended operations\n'
cn_bypass_file="${TMP_DIR}/china_ipv4.txt"
cat >"${cn_bypass_file}" <<'EOF_CN'
1.1.0.0/16
101.6.0.0/16
EOF_CN
write_config "mihomo" "tproxy" "tproxy" "${MIHOMO_SOURCE}" "preserve_tailnet" "100" "nftables" \
"bypass_private_ip = true
bypass_cn_ip = true
bypass_cn_file = \"${cn_bypass_file}\""
dryrun_output="$(must_run firewall dry-run)"
assert_contains "${dryrun_output}" "dry-run"
assert_contains "${dryrun_output}" "backend=nftables"
assert_contains "${dryrun_output}" "add set inet box_mangle box_private_v4"
assert_contains "${dryrun_output}" "add set inet box_mangle box_cn_v4"
assert_contains "${dryrun_output}" "add rule inet box_mangle box_main ip daddr @box_private_v4 return"
assert_contains "${dryrun_output}" "add rule inet box_mangle box_main ip daddr @box_cn_v4 return"
assert_contains "${dryrun_output}" "add rule ip box_nat box_main ip daddr @box_cn_v4 return"
assert_line_order "${dryrun_output}" "add rule inet box_mangle box_main ip daddr @box_cn_v4 return" 'add rule inet box_mangle box_main return comment "BOX_POLICY_PLACEHOLDER"'
assert_line_order "${dryrun_output}" "meta mark set 16777216" 'add rule inet box_mangle box_main return comment "BOX_POLICY_PLACEHOLDER"'

printf '[6/13] trace mode logs external commands with action context\n'
BOX_TRACE_COMMANDS=1
export BOX_TRACE_COMMANDS
trace_output="$(must_run firewall status --json)"
unset BOX_TRACE_COMMANDS
assert_contains "${trace_output}" "event_id=TRACE_CMD"
assert_contains "${trace_output}" "action=status"
assert_contains "${trace_output}" "cmd="

printf '[7/13] explicit BOX_CONFIG_FILE missing fails fast\n'
missing_cfg="${TMP_DIR}/missing-explicit-box.toml"
BOX_CONFIG_FILE="${missing_cfg}"
export BOX_CONFIG_FILE
fail_output="$(must_fail firewall status --json)"
assert_contains "${fail_output}" "explicit BOX_CONFIG_FILE does not exist"
BOX_CONFIG_FILE="${CONFIG_FILE}"
export BOX_CONFIG_FILE

printf '[8/13] status json conditional error field\n'
write_config "mihomo" "tun" "disable" "${MIHOMO_SOURCE}" "preserve_tailnet" "100" "iptables"
saved_iptables_cmd="${BOX_IPTABLES_CMD}"
BOX_IPTABLES_CMD="${TMP_DIR}/missing-iptables"
export BOX_IPTABLES_CMD
error_status_json="$(must_run firewall status --json)"
assert_contains "${error_status_json}" "\"last_error\":\"iptables inspection unavailable (need root/CAP_NET_ADMIN or kernel support)\""
assert_contains "${error_status_json}" "\"error\":\"iptables inspection unavailable (need root/CAP_NET_ADMIN or kernel support)\""
BOX_IPTABLES_CMD="${saved_iptables_cmd}"
export BOX_IPTABLES_CMD

printf '[9/13] kernel bypass rules apply in iptables backend\n'
write_config "mihomo" "mixed" "redirect" "${MIHOMO_SOURCE}" "preserve_tailnet" "100" "iptables" \
"bypass_private_ip = true
bypass_cn_ip = true
bypass_cn_file = \"${cn_bypass_file}\""
seed_tailscale_state
must_run firewall enable >/dev/null
assert_contains "$(cat "${MOCK_IPTABLES_STATE}")" 'RULE|mangle|BOX_MANGLE|-d 10.0.0.0/8 -j RETURN'
assert_contains "$(cat "${MOCK_IPTABLES_STATE}")" 'RULE|nat|BOX_NAT|-d 10.0.0.0/8 -j RETURN'
assert_contains "$(cat "${MOCK_IPTABLES_STATE}")" 'RULE|mangle|BOX_MANGLE|-d 1.1.0.0/16 -j RETURN'
assert_contains "$(cat "${MOCK_IPTABLES_STATE}")" 'RULE|nat|BOX_NAT|-d 101.6.0.0/16 -j RETURN'
status_json="$(must_run firewall status --json)"
assert_contains "${status_json}" "\"bypass_private_ip\":true"
assert_contains "${status_json}" "\"bypass_cn_ip\":true"
assert_contains "${status_json}" "\"bypass_cn_file\":\"${cn_bypass_file}\""
must_run firewall disable >/dev/null
assert_no_box_artifacts

printf '[10/13] service status side-effect free\n'
write_config "mihomo" "tun" "disable" "${MIHOMO_SOURCE}" "preserve_tailnet" "100" "iptables"
rm -rf "${BOX_RUN_DIR}/rendered"
must_run service status --json >/dev/null
if [[ -d "${BOX_RUN_DIR}/rendered" ]]; then
  printf 'ASSERT STATUS SIDE-EFFECT FAILED: rendered directory created by service status\n' >&2
  exit 1
fi

printf '[11/15] service lifecycle + mihomo overlay\n'
write_config "mihomo" "mixed" "redirect" "${MIHOMO_SOURCE}" "preserve_tailnet" "100" "iptables"
seed_tailscale_state
mihomo_checksum_before="$(sha256sum "${MIHOMO_SOURCE}" | awk '{print $1}')"
must_run service start >/dev/null
assert_tailscale_state_preserved
service_json="$(must_run service status --json)"
assert_contains "${service_json}" "\"status\":\"healthy\""
assert_contains "${service_json}" "\"core\":\"mihomo\""
assert_contains "${service_json}" "\"dns_enhanced_mode\":\"fake-ip\""
assert_contains "${service_json}" "\"ipv6_enabled\":true"
assert_contains "${service_json}" "\"ipv6_effective_mode\":\"direct\""
assert_contains "${service_json}" "/rendered/mihomo/config.yaml"
assert_file_exists "${BOX_RUN_DIR}/rendered/mihomo/config.yaml"
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" 'mixed-port: 7890'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" 'redir-port: 19797'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" 'tproxy-port: 19898'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" 'tun:'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" '  enable: false'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" '  auto-route: false'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" '  auto-redirect: false'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" '  strict-route: false'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" 'ipv6: true'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" '  ipv6: true'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" '  enhanced-mode: fake-ip'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" '  fake-ip-range6: "fc00::/18"'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" '"+.tailscale.com"'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" '"+.ts.net"'
mihomo_checksum_after="$(sha256sum "${MIHOMO_SOURCE}" | awk '{print $1}')"
if [[ "${mihomo_checksum_before}" != "${mihomo_checksum_after}" ]]; then
  printf 'ASSERT SOURCE MUTATION FAILED: mihomo source config changed\n' >&2
  exit 1
fi
must_run service restart >/dev/null
service_json="$(must_run service status --json)"
assert_contains "${service_json}" "\"status\":\"healthy\""
must_run service reload >/dev/null
service_json="$(must_run service status --json)"
assert_contains "${service_json}" "\"status\":\"healthy\""
must_run service stop >/dev/null
assert_tailscale_state_preserved
service_json="$(must_run service status --json)"
assert_contains "${service_json}" "\"status\":\"stopped\""

printf '[12/15] strict_box mihomo overlay omits tailscale fake-ip filter bypass\n'
write_config "mihomo" "mixed" "redirect" "${MIHOMO_SOURCE}" "strict_box" "100" "iptables"
must_run service start >/dev/null
assert_file_exists "${BOX_RUN_DIR}/rendered/mihomo/config.yaml"
if grep -Fq '"+.tailscale.com"' "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" || \
   grep -Fq '"+.ts.net"' "${BOX_RUN_DIR}/rendered/mihomo/config.yaml"; then
  printf 'ASSERT STRICT BOX OVERLAY FAILED: tailscale fake-ip filter bypass unexpectedly present\n' >&2
  exit 1
fi
must_run service stop >/dev/null

printf '[13/15] service lifecycle + sing-box overlay\n'
write_config "sing-box" "tproxy" "tproxy" "${SING_SOURCE}" "preserve_tailnet" "100" "iptables"
seed_tailscale_state
sing_checksum_before="$(sha256sum "${SING_SOURCE}" | awk '{print $1}')"
must_run service start >/dev/null
assert_tailscale_state_preserved
service_json="$(must_run service status --json)"
assert_contains "${service_json}" "\"core\":\"sing-box\""
assert_contains "${service_json}" "/rendered/sing-box/config.json"
assert_file_exists "${BOX_RUN_DIR}/rendered/sing-box/config.json"
sing_checksum_after="$(sha256sum "${SING_SOURCE}" | awk '{print $1}')"
if [[ "${sing_checksum_before}" != "${sing_checksum_after}" ]]; then
  printf 'ASSERT SOURCE MUTATION FAILED: sing-box source config changed\n' >&2
  exit 1
fi
must_run service stop >/dev/null
assert_tailscale_state_preserved
assert_no_box_artifacts

printf '[14/15] mihomo overlay honors ipv6 disable and redir-host\n'
write_config "mihomo" "mixed" "redirect" "${MIHOMO_SOURCE}" "preserve_tailnet" "100" "iptables" "" \
"redir-host" "false"
must_run service start >/dev/null
service_json="$(must_run service status --json)"
assert_contains "${service_json}" "\"dns_enhanced_mode\":\"redir-host\""
assert_contains "${service_json}" "\"ipv6_enabled\":false"
assert_contains "${service_json}" "\"ipv6_effective_mode\":\"disabled\""
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" 'ipv6: false'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" '  ipv6: false'
assert_file_contains "${BOX_RUN_DIR}/rendered/mihomo/config.yaml" '  enhanced-mode: redir-host'
if grep -Fq '"+.tailscale.com"' "${BOX_RUN_DIR}/rendered/mihomo/config.yaml"; then
  printf 'ASSERT REDIR-HOST OVERLAY FAILED: fake-ip filter bypass unexpectedly present\n' >&2
  exit 1
fi
must_run service stop >/dev/null

printf '[15/15] tun mode reports proxied ipv6 intent\n'
write_config "mihomo" "tun" "disable" "${MIHOMO_SOURCE}" "preserve_tailnet" "100" "iptables"
must_run service start >/dev/null
service_json="$(must_run service status --json)"
assert_contains "${service_json}" "\"ipv6_effective_mode\":\"proxied\""
must_run service stop >/dev/null

printf 'PASS: integration phase2 checks completed\n'
