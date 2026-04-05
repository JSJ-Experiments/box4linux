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
campus_dns_mode = "auto"
campus_dns_suffixes = ["+.bit.edu.cn"]
campus_dns_probe_hosts = ["lexue.bit.edu.cn", "xk.bit.edu.cn"]
campus_dns_public_servers = [
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

# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/config.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/lib/supervisor/mutator_mihomo.sh"

printf '[1/3] multiline campus dns arrays parse from box.toml\n'
export BOX_CONFIG_FILE="${CONFIG_FILE}"
load_config >/dev/null
[[ "${BOX_CAMPUS_DNS_MODE}" == "auto" ]]
[[ "${BOX_CAMPUS_DNS_SUFFIXES[0]}" == "+.bit.edu.cn" ]]
[[ "${BOX_CAMPUS_DNS_PROBE_HOSTS[0]}" == "lexue.bit.edu.cn" ]]
[[ "${BOX_CAMPUS_DNS_PROBE_HOSTS[1]}" == "xk.bit.edu.cn" ]]
[[ "${BOX_CAMPUS_DNS_PUBLIC_SERVERS[0]}" == "https://dns.alidns.com/dns-query" ]]
[[ "${BOX_CAMPUS_DNS_PUBLIC_SERVERS[1]}" == "https://cloudflare-dns.com/dns-query" ]]
[[ "${BOX_CAMPUS_DNS_PUBLIC_SERVERS[2]}" == "https://dns.google/dns-query" ]]

printf '[2/3] campus auto mode uses live campus resolvers for bit suffix\n'
cp "${PROFILE_FILE}" "${RENDERED_FILE}"
export MOCK_DIG_PRIVATE_HOSTS="lexue.bit.edu.cn xk.bit.edu.cn"
mutator_mihomo_render_overlay "${PROFILE_FILE}" "${RENDERED_FILE}"
assert_contains "${RENDERED_FILE}" '    "+.bit.edu.cn":'
assert_contains "${RENDERED_FILE}" '      - 10.0.32.32'
assert_contains "${RENDERED_FILE}" '      - 10.0.32.33'
assert_contains "${RENDERED_FILE}" '    "+.edu.cn":'
assert_contains "${RENDERED_FILE}" '      - dhcp://system'

printf '[3/3] public auto mode falls back to configured DoH servers for bit suffix\n'
cp "${PROFILE_FILE}" "${RENDERED_FILE}"
export MOCK_DIG_PRIVATE_HOSTS=""
mutator_mihomo_render_overlay "${PROFILE_FILE}" "${RENDERED_FILE}"
assert_contains "${RENDERED_FILE}" '    "+.bit.edu.cn":'
assert_contains "${RENDERED_FILE}" '      - https://dns.alidns.com/dns-query'
assert_contains "${RENDERED_FILE}" '      - https://cloudflare-dns.com/dns-query'
assert_contains "${RENDERED_FILE}" '      - https://dns.google/dns-query'

printf 'PASS: campus dns integration checks completed\n'
