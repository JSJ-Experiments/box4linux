#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOXCTL="${ROOT_DIR}/cmd/boxctl"
TMP_DIR="$(mktemp -d)"
MOCK_DIR="${ROOT_DIR}/tests/fixtures/mockbin"

cleanup() {
  local pid
  if [[ -f "${BOX_RUN_DIR}/policy.pid" ]]; then
    pid="$(tr -d '[:space:]' <"${BOX_RUN_DIR}/policy.pid" || true)"
    [[ -n "${pid:-}" ]] && kill -TERM "${pid}" >/dev/null 2>&1 || true
  fi
  if [[ -f "${BOX_RUN_DIR}/box.pid" ]]; then
    pid="$(tr -d '[:space:]' <"${BOX_RUN_DIR}/box.pid" || true)"
    [[ -n "${pid:-}" ]] && kill -TERM "${pid}" >/dev/null 2>&1 || true
  fi
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

export PATH="${MOCK_DIR}:${PATH}"
export MOCK_IPTABLES_STATE="${TMP_DIR}/mock/iptables.state"
export MOCK_IP_STATE="${TMP_DIR}/mock/ip.state"
export MOCK_NFT_STATE="${TMP_DIR}/mock/nft.state"
export MOCK_IP_LINKS_FILE="${TMP_DIR}/mock/ip.links"
export MOCK_IP_ADDRS_FILE="${TMP_DIR}/mock/ip.addrs"
export MOCK_IP_MONITOR_FILE="${TMP_DIR}/mock/ip.monitor"
export MOCK_NMCLI_WIFI_FILE="${TMP_DIR}/mock/nmcli.wifi"
export MOCK_NMCLI_DEV_FILE="${TMP_DIR}/mock/nmcli.dev"
export BOX_IPTABLES_CMD="${MOCK_DIR}/iptables"
export BOX_IP_CMD="${MOCK_DIR}/ip"
export BOX_NFT_CMD="${MOCK_DIR}/nft"
export BOX_NMCLI_CMD="${MOCK_DIR}/nmcli"
export BOX_IW_CMD="${MOCK_DIR}/iw"
export BOX_UNSAFE_SKIP_ROOT_CHECK=1
export BOX_CAP_TPROXY=1
export BOX_RUN_DIR="${TMP_DIR}/run"
export BOX_VAR_DIR="${TMP_DIR}/var"
export BOX_LOG_DIR="${TMP_DIR}/log"
export BOX_CONFIG_FILE="${TMP_DIR}/box.toml"

PROFILE_DIR="${TMP_DIR}/profiles"
mkdir -p "${TMP_DIR}/mock" "${PROFILE_DIR}" "${BOX_RUN_DIR}" "${BOX_VAR_DIR}" "${BOX_LOG_DIR}"
touch "${MOCK_IPTABLES_STATE}" "${MOCK_IP_STATE}" "${MOCK_NFT_STATE}" "${MOCK_IP_MONITOR_FILE}"

cat >"${PROFILE_DIR}/mihomo.yaml" <<'EOF_MIHOMO'
mode: rule
mixed-port: 7890
rules:
  - MATCH,DIRECT
EOF_MIHOMO

must_run() {
  local output
  if ! output="$("${BOXCTL}" "$@" 2>&1)"; then
    printf 'FAILED: boxctl %s\n%s\n' "$*" "${output}" >&2
    exit 1
  fi
  printf '%s\n' "${output}"
}

must_fail() {
  local output
  if output="$("${BOXCTL}" "$@" 2>&1)"; then
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

force_reset_runtime() {
  local pid
  if [[ -f "${BOX_RUN_DIR}/policy.pid" ]]; then
    pid="$(tr -d '[:space:]' <"${BOX_RUN_DIR}/policy.pid" || true)"
    [[ -n "${pid:-}" ]] && kill -TERM "${pid}" >/dev/null 2>&1 || true
  fi
  if [[ -f "${BOX_RUN_DIR}/box.pid" ]]; then
    pid="$(tr -d '[:space:]' <"${BOX_RUN_DIR}/box.pid" || true)"
    [[ -n "${pid:-}" ]] && kill -TERM "${pid}" >/dev/null 2>&1 || true
  fi
  sleep 1
  rm -rf "${BOX_RUN_DIR}" "${BOX_VAR_DIR}" "${BOX_LOG_DIR}"
  mkdir -p "${BOX_RUN_DIR}" "${BOX_VAR_DIR}" "${BOX_LOG_DIR}"
  : >"${MOCK_IP_MONITOR_FILE}"
}

wait_for_contains() {
  local command=("${@:1:$#-1}")
  local needle="${!#}"
  local attempt output
  for attempt in $(seq 1 50); do
    output="$("${command[@]}" 2>&1 || true)"
    if [[ "${output}" == *"${needle}"* ]]; then
      printf '%s\n' "${output}"
      return 0
    fi
    sleep 0.2
  done
  printf 'WAIT FAILED: missing [%s]\nLast output:\n%s\n' "${needle}" "${output:-}" >&2
  exit 1
}

service_status_json() {
  must_run service status --json
}

policy_status_json() {
  must_run policy status --json
}

write_policy_config() {
  local policy_block="${1:-enabled = true
proxy_mode = \"core\"
debounce_seconds = 1
use_module_on_wifi_disconnect = false
disable_marker = \"${BOX_RUN_DIR}/disable\"
allow_ifaces = []
ignore_ifaces = []
allow_ssids = []
ignore_ssids = []
allow_bssids = []
ignore_bssids = []}"
  cat >"${BOX_CONFIG_FILE}" <<EOF_CFG
[core]
selected = "mihomo"
bin_dir = "${MOCK_DIR}"
workdir = "${BOX_VAR_DIR}"
config_source = "${PROFILE_DIR}/mihomo.yaml"

[network]
mode = "mixed"
tproxy_port = 19898
redir_port = 19797
dns_port = 11053
dns_hijack_mode = "redirect"
dns_coexist_mode = "preserve_tailnet"
tailscale_iface = "tailscale0"
tailnet_ipv4_cidr = "100.64.0.0/10"
tailnet_ipv6_cidr = "fd7a:115c:a1e0::/48"
tailscale_dns_resolver = "100.100.100.100"
tailscale_fwmark = "0x80000/0xff0000"
tailscale_route_table = 52

[firewall]
backend = "iptables"
route_table = 2024
route_pref = 100
fwmark = "16777216/16777216"

[policy]
${policy_block}
EOF_CFG
}

write_active_ethernet() {
  cat >"${MOCK_IP_LINKS_FILE}" <<'EOF_LINK'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP mode DEFAULT group default qlen 1000
EOF_LINK
  cat >"${MOCK_IP_ADDRS_FILE}" <<'EOF_ADDR'
2: eth0    inet 192.168.1.10/24 brd 192.168.1.255 scope global eth0
EOF_ADDR
  : >"${MOCK_NMCLI_WIFI_FILE}"
}

write_active_wifi() {
  cat >"${MOCK_IP_LINKS_FILE}" <<'EOF_LINK'
3: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP mode DEFAULT group default qlen 1000
EOF_LINK
  cat >"${MOCK_IP_ADDRS_FILE}" <<'EOF_ADDR'
3: wlan0    inet 10.0.0.20/24 brd 10.0.0.255 scope global wlan0
EOF_ADDR
  cat >"${MOCK_NMCLI_WIFI_FILE}" <<'EOF_WIFI'
yes:TrustedWiFi:AA:BB:CC:DD:EE:FF
EOF_WIFI
}

write_wifi_without_identity() {
  cat >"${MOCK_IP_LINKS_FILE}" <<'EOF_LINK'
3: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP mode DEFAULT group default qlen 1000
EOF_LINK
  cat >"${MOCK_IP_ADDRS_FILE}" <<'EOF_ADDR'
3: wlan0    inet 10.0.0.20/24 brd 10.0.0.255 scope global wlan0
EOF_ADDR
  : >"${MOCK_NMCLI_WIFI_FILE}"
}

write_no_network() {
  : >"${MOCK_IP_LINKS_FILE}"
  : >"${MOCK_IP_ADDRS_FILE}"
  : >"${MOCK_NMCLI_WIFI_FILE}"
}

printf '[1/8] policy evaluate starts service in core mode with active network\n'
write_active_ethernet
write_policy_config ""
must_run policy evaluate >/dev/null
status_json="$(service_status_json)"
assert_contains "${status_json}" '"status":"healthy"'
policy_json="$(policy_status_json)"
assert_contains "${policy_json}" '"desired_state":"enabled"'
assert_contains "${policy_json}" '"applied_state":"started"'

printf '[2/8] whitelist policy disables service when there is no match\n'
must_run service stop >/dev/null
wait_for_contains "${BOXCTL}" service status --json '"status":"stopped"' >/dev/null
write_active_ethernet
write_policy_config 'enabled = true
proxy_mode = "whitelist"
debounce_seconds = 1
use_module_on_wifi_disconnect = false
disable_marker = "'"${BOX_RUN_DIR}"'/disable"
allow_ifaces = ["wlan+"]'
must_run policy evaluate >/dev/null
status_json="$(service_status_json)"
assert_contains "${status_json}" '"status":"stopped"'
policy_json="$(policy_status_json)"
assert_contains "${policy_json}" '"desired_state":"disabled"'
assert_contains "${policy_json}" '"last_reason":"no whitelist match"'

printf '[3/8] whitelist policy enables service from SSID match\n'
write_active_wifi
write_policy_config 'enabled = true
proxy_mode = "whitelist"
debounce_seconds = 1
use_module_on_wifi_disconnect = false
disable_marker = "'"${BOX_RUN_DIR}"'/disable"
allow_ifaces = []
allow_ssids = ["TrustedWiFi"]'
must_run policy evaluate >/dev/null
status_json="$(service_status_json)"
assert_contains "${status_json}" '"status":"healthy"'
policy_json="$(policy_status_json)"
assert_contains "${policy_json}" '"ssid":"TrustedWiFi"'
assert_contains "${policy_json}" '"desired_state":"enabled"'

printf '[4/8] disable marker forces disabled state\n'
touch "${BOX_RUN_DIR}/disable"
must_run policy evaluate >/dev/null
status_json="$(service_status_json)"
assert_contains "${status_json}" '"status":"stopped"'
policy_json="$(policy_status_json)"
assert_contains "${policy_json}" '"disable_marker_present":true'
assert_contains "${policy_json}" '"desired_state":"disabled"'
rm -f "${BOX_RUN_DIR}/disable"

printf '[5/8] wifi identity fallback uses disconnect policy on unknown wlan context\n'
force_reset_runtime
write_wifi_without_identity
write_policy_config 'enabled = true
proxy_mode = "whitelist"
debounce_seconds = 1
use_module_on_wifi_disconnect = true
disable_marker = "'"${BOX_RUN_DIR}"'/disable"
allow_ifaces = []
allow_ssids = ["TrustedWiFi"]'
must_run policy evaluate >/dev/null
policy_json="$(policy_status_json)"
assert_contains "${policy_json}" '"desired_state":"enabled"'
assert_contains "${policy_json}" '"last_reason":"wifi identity unavailable; using disconnect fallback"'

printf '[6/8] policy watcher enable/disable manages lifecycle and status\n'
write_active_ethernet
write_policy_config ""
must_run policy enable >/dev/null
policy_json="$(wait_for_contains "${BOXCTL}" policy status --json '"watcher_running":true')"
assert_contains "${policy_json}" '"policy_enabled":true'
must_run policy disable >/dev/null
policy_json="$(wait_for_contains "${BOXCTL}" policy status --json '"watcher_running":false')"
assert_contains "${policy_json}" '"watcher_running":false'

printf '[7/8] disable marker changes trigger watcher reevaluation\n'
force_reset_runtime
write_active_ethernet
write_policy_config ""
must_run service start >/dev/null
must_run policy enable >/dev/null
touch "${BOX_RUN_DIR}/disable"
policy_json="$(wait_for_contains "${BOXCTL}" policy status --json '"last_reason":"disable marker present"')"
assert_contains "${policy_json}" '"desired_state":"disabled"'
status_json="$(service_status_json)"
assert_contains "${status_json}" '"status":"stopped"'
rm -f "${BOX_RUN_DIR}/disable"
policy_json="$(wait_for_contains "${BOXCTL}" policy status --json '"desired_state":"enabled"')"
status_json="$(wait_for_contains "${BOXCTL}" service status --json '"status":"healthy"')"
must_run policy disable >/dev/null

printf '[8/8] address event triggers firewall refresh and blacklist transition stops service\n'
force_reset_runtime
write_active_ethernet
write_policy_config 'enabled = true
proxy_mode = "blacklist"
debounce_seconds = 1
use_module_on_wifi_disconnect = false
disable_marker = "'"${BOX_RUN_DIR}"'/disable"
allow_ifaces = []
ignore_ifaces = ["wlan+"]'
must_run service start >/dev/null
status_json="$(wait_for_contains "${BOXCTL}" service status --json '"status":"healthy"')"
must_run policy enable >/dev/null
printf 'Deleted 2: eth0    inet 192.168.1.10/24 scope global eth0\n' >>"${MOCK_IP_MONITOR_FILE}"
policy_json="$(wait_for_contains "${BOXCTL}" policy status --json '"last_refresh_ts":"20')"
assert_contains "${policy_json}" '"watcher_running":true'
write_active_wifi
printf '3: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP>\n' >>"${MOCK_IP_MONITOR_FILE}"
policy_json="$(wait_for_contains "${BOXCTL}" policy status --json '"last_reason":"blacklist match"')"
assert_contains "${policy_json}" '"desired_state":"disabled"'
status_json="$(service_status_json)"
assert_contains "${status_json}" '"status":"stopped"'
must_run policy disable >/dev/null

printf 'PASS: policy integration checks completed\n'
