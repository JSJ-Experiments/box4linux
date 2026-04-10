#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
MOCK_DIR="${TMP_DIR}/mockbin"
PROFILE_FILE="${TMP_DIR}/profiles/mihomo.yml"
RENDERED_FILE="${TMP_DIR}/rendered.yml"
CONFIG_FILE="${TMP_DIR}/box.toml"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${MOCK_DIR}" "${TMP_DIR}/run" "${TMP_DIR}/var" "${TMP_DIR}/log" "${TMP_DIR}/profiles"
cp "${ROOT_DIR}/tests/fixtures/mockbin/ip" "${MOCK_DIR}/ip"
cp "${ROOT_DIR}/tests/fixtures/mockbin/resolvectl" "${MOCK_DIR}/resolvectl"
cp "${ROOT_DIR}/tests/fixtures/mockbin/dig" "${MOCK_DIR}/dig"
chmod +x "${MOCK_DIR}/ip" "${MOCK_DIR}/resolvectl" "${MOCK_DIR}/dig"

cat >"${CONFIG_FILE}" <<'EOF'
[network]
org_dns_mode = "auto"
org_dns_suffix_policy = "org_only"
org_dns_suffixes = ["+.bit.edu.cn"]
org_dns_probe_hosts = ["lexue.bit.edu.cn", "xk.bit.edu.cn"]
org_dns_public_servers = [
  "https://dns.alidns.com/dns-query",
  "https://cloudflare-dns.com/dns-query",
  "https://dns.google/dns-query",
]
EOF

cat >"${PROFILE_FILE}" <<'EOF'
dns:
  enable: true
  enhanced-mode: fake-ip
  fake-ip-filter:
    - "+.edu.cn"
    - "+.bit.edu.cn"
  nameserver-policy:
    "+.bit.edu.cn":
      - dhcp://system
      - system
    "+.edu.cn":
      - dhcp://system
      - system
    "rule-set:cn_domain":
      - https://dns.alidns.com/dns-query
EOF

assert_contains() {
  local file="${1:?missing file}"
  local pattern="${2:?missing pattern}"
  if ! grep -Fq "${pattern}" "${file}"; then
    printf 'ASSERT CONTAINS FAILED: %s not found in %s\n' "${pattern}" "${file}" >&2
    cat "${file}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="${1:?missing file}"
  local pattern="${2:?missing pattern}"
  if grep -Fq "${pattern}" "${file}"; then
    printf 'ASSERT NOT CONTAINS FAILED: %s unexpectedly found in %s\n' "${pattern}" "${file}" >&2
    cat "${file}" >&2
    exit 1
  fi
}

wait_for_contains() {
  local file="${1:?missing file}"
  local pattern="${2:?missing pattern}"
  local attempts="${3:-30}"
  local i

  for ((i = 0; i < attempts; i++)); do
    if [[ -f "${file}" ]] && grep -Fq "${pattern}" "${file}"; then
      return 0
    fi
    sleep 0.1
  done

  printf 'ASSERT WAIT FAILED: %s not found in %s\n' "${pattern}" "${file}" >&2
  [[ -f "${file}" ]] && cat "${file}" >&2
  exit 1
}

export BOX_IP_CMD="${MOCK_DIR}/ip"
export BOX_RESOLVECTL_CMD="${MOCK_DIR}/resolvectl"
export BOX_DIG_CMD="${MOCK_DIR}/dig"
export BOX_RUN_DIR="${TMP_DIR}/run"
export BOX_VAR_DIR="${TMP_DIR}/var"
export BOX_LOG_DIR="${TMP_DIR}/log"
export MOCK_IP_STATE="${TMP_DIR}/ip.state"
export MOCK_IP_DEFAULT_ROUTE_LINE="default via 10.0.32.1 dev wlan0 proto dhcp src 10.0.32.100 metric 100"
export MOCK_RESOLVECTL_DEFAULT_IFACE="wlan0"
export MOCK_RESOLVECTL_DEFAULT_DNS="10.0.32.32 10.0.32.33"
export BOX_CAMPUS_DNS_MODE="auto"
export BOX_CAMPUS_DNS_SUFFIX_POLICY="org_only"
export BOX_CAMPUS_DNS_SUFFIXES=("+.bit.edu.cn")
export BOX_CAMPUS_DNS_PROBE_HOSTS=("lexue.bit.edu.cn" "xk.bit.edu.cn")
export BOX_CAMPUS_DNS_PUBLIC_SERVERS=("https://dns.alidns.com/dns-query" "https://cloudflare-dns.com/dns-query" "https://dns.google/dns-query")
export BOX_NETWORK_MODE="mixed"
export BOX_DNS_HIJACK_MODE="redirect"
export BOX_DNS_ENHANCED_MODE="fake-ip"
export BOX_DNS_COEXIST_MODE="preserve_tailnet"
export BOX_IPV6_ENABLED="false"
export BOX_DNS_PORT="1053"
export BOX_REDIR_PORT="9797"
export BOX_TPROXY_PORT="9898"
export BOX_UNSAFE_SKIP_ROOT_CHECK="1"

# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/config.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/supervisor/mutator_mihomo.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/supervisor/adapter_mihomo.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/supervisor/adapter_sing_box.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/supervisor/mutator_sing_box.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/firewall/firewall.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/supervisor/supervisor.sh"

printf '[1/8] multiline org dns arrays parse from box.toml\n'
export BOX_CONFIG_FILE="${CONFIG_FILE}"
load_config >/dev/null
[[ "${BOX_CAMPUS_DNS_MODE}" == "auto" ]]
[[ "${BOX_CAMPUS_DNS_SUFFIX_POLICY}" == "org_only" ]]
[[ "${BOX_CAMPUS_DNS_SUFFIXES[0]}" == "+.bit.edu.cn" ]]
[[ "${BOX_CAMPUS_DNS_PROBE_HOSTS[0]}" == "lexue.bit.edu.cn" ]]
[[ "${BOX_CAMPUS_DNS_PROBE_HOSTS[1]}" == "xk.bit.edu.cn" ]]
[[ "${BOX_CAMPUS_DNS_PUBLIC_SERVERS[0]}" == "https://dns.alidns.com/dns-query" ]]
[[ "${BOX_CAMPUS_DNS_PUBLIC_SERVERS[1]}" == "https://cloudflare-dns.com/dns-query" ]]
[[ "${BOX_CAMPUS_DNS_PUBLIC_SERVERS[2]}" == "https://dns.google/dns-query" ]]

printf '[2/8] org auto mode uses live org resolvers for org suffixes\n'
cp "${PROFILE_FILE}" "${RENDERED_FILE}"
export MOCK_DIG_PRIVATE_HOSTS="lexue.bit.edu.cn xk.bit.edu.cn"
unset MOCK_DIG_RESPONSES_FILE
unset MOCK_RESOLVECTL_DNS_MAP_FILE
mutator_mihomo_render_overlay "${PROFILE_FILE}" "${RENDERED_FILE}"
assert_contains "${RENDERED_FILE}" '    "+.bit.edu.cn":'
assert_contains "${RENDERED_FILE}" '      - 10.0.32.32'
assert_contains "${RENDERED_FILE}" '      - 10.0.32.33'
assert_contains "${RENDERED_FILE}" '    "+.edu.cn":'
assert_contains "${RENDERED_FILE}" '      - 10.0.32.32'
assert_contains "${RENDERED_FILE}" '      - 10.0.32.33'

printf '[3/8] public auto mode removes org suffix policies\n'
cp "${PROFILE_FILE}" "${RENDERED_FILE}"
export MOCK_DIG_PRIVATE_HOSTS=""
mutator_mihomo_render_overlay "${PROFILE_FILE}" "${RENDERED_FILE}"
assert_not_contains "${RENDERED_FILE}" '    "+.bit.edu.cn":'
assert_not_contains "${RENDERED_FILE}" '    "+.edu.cn":'
assert_contains "${RENDERED_FILE}" '    "rule-set:cn_domain":'

printf '[4/8] partial auto probe match stays public\n'
cp "${PROFILE_FILE}" "${RENDERED_FILE}"
RESPONSES_FILE="${TMP_DIR}/dig-responses.txt"
cat >"${RESPONSES_FILE}" <<'EOF'
lexue.bit.edu.cn 10.0.9.95
xk.bit.edu.cn 211.68.9.205
EOF
export MOCK_DIG_RESPONSES_FILE="${RESPONSES_FILE}"
mutator_mihomo_render_overlay "${PROFILE_FILE}" "${RENDERED_FILE}"
assert_not_contains "${RENDERED_FILE}" '    "+.bit.edu.cn":'
assert_not_contains "${RENDERED_FILE}" '    "+.edu.cn":'

printf '[5/8] best_match keeps configured org suffix opt-in\n'
cp "${PROFILE_FILE}" "${RENDERED_FILE}"
export BOX_CAMPUS_DNS_SUFFIX_POLICY="best_match"
mutator_mihomo_render_overlay "${PROFILE_FILE}" "${RENDERED_FILE}"
assert_contains "${RENDERED_FILE}" '    "+.bit.edu.cn":'
assert_contains "${RENDERED_FILE}" '      - 10.0.32.32'
assert_contains "${RENDERED_FILE}" '      - 10.0.32.33'
assert_not_contains "${RENDERED_FILE}" '    "+.edu.cn":'
export BOX_CAMPUS_DNS_SUFFIX_POLICY="org_only"

printf '[6/9] org detection ignores non-org default route when wifi carries campus dns\n'
cp "${PROFILE_FILE}" "${RENDERED_FILE}"
MULTI_DNS_FILE="${TMP_DIR}/resolvectl-dns-map.txt"
cat >"${MULTI_DNS_FILE}" <<'EOF'
enp2s0 10.0.0.10 10.0.0.9
wlan0 10.0.32.32 10.0.32.33
EOF
cat >"${RESPONSES_FILE}" <<'EOF'
10.0.0.10 lexue.bit.edu.cn 211.68.9.205
10.0.0.9 lexue.bit.edu.cn 211.68.9.205
10.0.0.10 xk.bit.edu.cn 211.68.9.205
10.0.0.9 xk.bit.edu.cn 211.68.9.205
10.0.32.32 lexue.bit.edu.cn 10.0.9.95
10.0.32.33 lexue.bit.edu.cn 10.0.9.95
10.0.32.32 xk.bit.edu.cn 10.0.8.88
10.0.32.33 xk.bit.edu.cn 10.0.8.88
EOF
export MOCK_IP_DEFAULT_ROUTE_LINE="default via 10.0.0.1 dev enp2s0 proto dhcp src 10.0.0.2 metric 100"
export MOCK_RESOLVECTL_DEFAULT_IFACE="enp2s0"
export MOCK_RESOLVECTL_DEFAULT_DNS="10.0.0.10 10.0.0.9"
export MOCK_RESOLVECTL_DNS_MAP_FILE="${MULTI_DNS_FILE}"
[[ "$(box_detect_org_dns_mode)" == "org" ]]
[[ "$(box_org_dns_status_iface)" == "wlan0" ]]
mutator_mihomo_render_overlay "${PROFILE_FILE}" "${RENDERED_FILE}"
assert_contains "${RENDERED_FILE}" '    "+.bit.edu.cn":'
assert_contains "${RENDERED_FILE}" '      - 10.0.32.32'
assert_contains "${RENDERED_FILE}" '      - 10.0.32.33'
assert_contains "${RENDERED_FILE}" '    "+.edu.cn":'

printf '[7/9] org detection prefers default route when multiple links qualify\n'
cp "${PROFILE_FILE}" "${RENDERED_FILE}"
cat >"${RESPONSES_FILE}" <<'EOF'
10.0.0.10 lexue.bit.edu.cn 10.0.9.95
10.0.0.9 lexue.bit.edu.cn 10.0.9.95
10.0.0.10 xk.bit.edu.cn 10.0.2.21
10.0.0.9 xk.bit.edu.cn 10.0.2.21
10.0.32.32 lexue.bit.edu.cn 10.0.9.95
10.0.32.33 lexue.bit.edu.cn 10.0.9.95
10.0.32.32 xk.bit.edu.cn 10.0.8.88
10.0.32.33 xk.bit.edu.cn 10.0.8.88
EOF
[[ "$(box_detect_org_dns_mode)" == "org" ]]
[[ "$(box_org_dns_status_iface)" == "enp2s0" ]]
mutator_mihomo_render_overlay "${PROFILE_FILE}" "${RENDERED_FILE}"
assert_contains "${RENDERED_FILE}" '    "+.bit.edu.cn":'
assert_contains "${RENDERED_FILE}" '      - 10.0.0.10'
assert_contains "${RENDERED_FILE}" '      - 10.0.0.9'
assert_contains "${RENDERED_FILE}" '    "+.edu.cn":'

printf '[8/9] status surfaces org dns detection fields\n'
unset MOCK_RESOLVECTL_DNS_MAP_FILE
export MOCK_IP_DEFAULT_ROUTE_LINE="default via 10.0.32.1 dev wlan0 proto dhcp src 10.0.32.100 metric 100"
export MOCK_RESOLVECTL_DEFAULT_IFACE="wlan0"
export MOCK_RESOLVECTL_DEFAULT_DNS="10.0.32.32 10.0.32.33"
cat >"${RESPONSES_FILE}" <<'EOF'
lexue.bit.edu.cn 211.68.9.205
xk.bit.edu.cn 211.68.9.205
EOF
export MOCK_DIG_RESPONSES_FILE="${RESPONSES_FILE}"

export BOX_OUTPUT_FORMAT="json"
SERVICE_STATUS_JSON="${TMP_DIR}/service-status.json"
FIREWALL_STATUS_JSON="${TMP_DIR}/firewall-status.json"
service_status >"${SERVICE_STATUS_JSON}"
firewall_status >"${FIREWALL_STATUS_JSON}"
assert_contains "${SERVICE_STATUS_JSON}" '"org_dns_mode_configured":"auto"'
assert_contains "${SERVICE_STATUS_JSON}" '"org_dns_mode_active":"public"'
assert_contains "${SERVICE_STATUS_JSON}" '"org_dns_iface":"wlan0"'
assert_contains "${SERVICE_STATUS_JSON}" '"org_dns_servers":["https://dns.alidns.com/dns-query","https://cloudflare-dns.com/dns-query","https://dns.google/dns-query"]'
assert_contains "${SERVICE_STATUS_JSON}" '"org_dns_suffixes":["+.bit.edu.cn"]'
assert_contains "${SERVICE_STATUS_JSON}" '"org_dns_probe_hosts":["lexue.bit.edu.cn","xk.bit.edu.cn"]'
assert_contains "${FIREWALL_STATUS_JSON}" '"org_dns_mode_active":"public"'
assert_contains "${FIREWALL_STATUS_JSON}" '"org_dns_iface":"wlan0"'
unset MOCK_DIG_RESPONSES_FILE

printf '[9/9] service network signature change triggers reload and renew\n'
COMMAND_LOG="${TMP_DIR}/boxctl.commands"
MOCK_BOXCTL="${TMP_DIR}/mock-boxctl.sh"

cat >"${MOCK_BOXCTL}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${COMMAND_LOG}"
EOF
chmod +x "${MOCK_BOXCTL}"

export BOXCTL_SELF_PATH="${MOCK_BOXCTL}"
service_handle_network_signature_change \
  "org|wlan0|10.0.32.32,10.0.32.33" \
  "public" \
  "2026-04-05T06:00:00Z"
wait_for_contains "${COMMAND_LOG}" "service reload"
wait_for_contains "${COMMAND_LOG}" "firewall renew"

printf 'PASS: campus dns integration checks completed\n'
