#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOXCTL="${ROOT_DIR}/cmd/boxctl"
TMP_DIR="$(mktemp -d)"
MOCK_DIR="${ROOT_DIR}/tests/fixtures/mockbin"

cleanup() {
  local pid
  if [[ -f "${BOX_RUN_DIR}/box.pid" ]]; then
    pid="$(tr -d '[:space:]' <"${BOX_RUN_DIR}/box.pid" || true)"
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
export BOX_CURL_CMD="${MOCK_DIR}/curl"
export BOX_UNSAFE_SKIP_ROOT_CHECK=1
export BOX_CAP_TPROXY=1
export BOX_RUN_DIR="${TMP_DIR}/run"
export BOX_VAR_DIR="${TMP_DIR}/var"
export BOX_LOG_DIR="${TMP_DIR}/log"

CONFIG_FILE="${TMP_DIR}/box.toml"
INSTALLED_BIN_DIR="${TMP_DIR}/installed-bin"
PROFILE_DIR="${TMP_DIR}/profiles"
SOURCE_DIR="${TMP_DIR}/sources"
ARTIFACT_DIR="${BOX_VAR_DIR}/artifacts"
STAGING_DIR="${BOX_VAR_DIR}/staging"

export BOX_CONFIG_FILE="${CONFIG_FILE}"
mkdir -p "${TMP_DIR}/mock" "${BOX_RUN_DIR}" "${BOX_VAR_DIR}" "${BOX_LOG_DIR}" "${INSTALLED_BIN_DIR}" "${PROFILE_DIR}" "${SOURCE_DIR}"
touch "${MOCK_IPTABLES_STATE}" "${MOCK_IP_STATE}" "${MOCK_NFT_STATE}"

sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}

must_run() {
  local output
  if ! output="$(${BOXCTL} "$@" 2>&1)"; then
    printf 'FAILED: boxctl %s\n%s\n' "$*" "${output}" >&2
    exit 1
  fi
  printf '%s\n' "${output}"
}

must_fail() {
  local output
  if output="$(${BOXCTL} "$@" 2>&1)"; then
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

assert_file_contains() {
  local path="${1:?missing path}"
  local needle="${2:?missing needle}"
  if ! grep -Fq "${needle}" "${path}"; then
    printf 'ASSERT FILE CONTAINS FAILED: expected [%s] in %s\n' "${needle}" "${path}" >&2
    cat "${path}" >&2 || true
    exit 1
  fi
}

assert_dir_exists() {
  local path="${1:?missing path}"
  if [[ ! -d "${path}" ]]; then
    printf 'ASSERT DIR FAILED: missing %s\n' "${path}" >&2
    exit 1
  fi
}

assert_pid_changed() {
  local before="${1:?missing before pid}"
  local after="${2:?missing after pid}"
  if [[ -z "${before}" || -z "${after}" || "${before}" == "${after}" ]]; then
    printf 'ASSERT PID CHANGED FAILED: before=%s after=%s\n' "${before}" "${after}" >&2
    exit 1
  fi
}

assert_pid_same() {
  local before="${1:?missing before pid}"
  local after="${2:?missing after pid}"
  if [[ -z "${before}" || -z "${after}" || "${before}" != "${after}" ]]; then
    printf 'ASSERT PID SAME FAILED: before=%s after=%s\n' "${before}" "${after}" >&2
    exit 1
  fi
}

service_pid() {
  local status_json
  status_json="$(must_run service status --json)"
  printf '%s\n' "${status_json}" | sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p'
}

write_common_config() {
  local core="${1:?missing core}"
  local source="${2:?missing source}"
  local updater_block="${3:-}"
  cat >"${CONFIG_FILE}" <<EOF_CFG
[core]
selected = "${core}"
bin_dir = "${INSTALLED_BIN_DIR}"
workdir = "${BOX_VAR_DIR}"
config_source = "${source}"

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

[updater]
artifact_dir = "${ARTIFACT_DIR}"
staging_dir = "${STAGING_DIR}"
checksum_policy = "optional"
kernel_interval = "daily"
subs_interval = "hourly"
geo_interval = "daily"
dashboard_interval = "weekly"

${updater_block}
EOF_CFG
}

cat >"${SOURCE_DIR}/kernel-v1" <<'EOF_KERNEL1'
#!/usr/bin/env bash
printf 'mock-kernel-v1\n'
EOF_KERNEL1
chmod +x "${SOURCE_DIR}/kernel-v1"

cat >"${SOURCE_DIR}/kernel-v2" <<'EOF_KERNEL2'
#!/usr/bin/env bash
printf 'mock-kernel-v2\n'
EOF_KERNEL2
chmod +x "${SOURCE_DIR}/kernel-v2"

cat >"${SOURCE_DIR}/geo-v1.dat" <<'EOF_GEO1'
geo-version-1
EOF_GEO1

cat >"${SOURCE_DIR}/geo-v2.dat" <<'EOF_GEO2'
geo-version-2
EOF_GEO2

cat >"${PROFILE_DIR}/mihomo-live.yaml" <<'EOF_MIHOMO_LIVE'
mode: rule
mixed-port: 7890
rules:
  - MATCH,DIRECT
EOF_MIHOMO_LIVE

cat >"${SOURCE_DIR}/mihomo-updated.yaml" <<'EOF_MIHOMO_UPDATE'
mode: rule
mixed-port: 7891
rules:
  - MATCH,REJECT
EOF_MIHOMO_UPDATE

cat >"${PROFILE_DIR}/sing-live.json" <<'EOF_SING_LIVE'
{
  "log": { "level": "info" },
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ]
}
EOF_SING_LIVE

cat >"${SOURCE_DIR}/sing-updated.json" <<'EOF_SING_UPDATE'
{
  "log": { "level": "warn" },
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ]
}
EOF_SING_UPDATE

mkdir -p "${SOURCE_DIR}/dashboard-v1"
cat >"${SOURCE_DIR}/dashboard-v1/index.html" <<'EOF_DASH'
<!doctype html><title>dashboard-v1</title>
EOF_DASH
(
  cd "${SOURCE_DIR}/dashboard-v1"
  tar -czf "${SOURCE_DIR}/dashboard-v1.tar.gz" .
)

KERNEL_V1_SHA="$(sha256_of "${SOURCE_DIR}/kernel-v1")"
KERNEL_V2_SHA="$(sha256_of "${SOURCE_DIR}/kernel-v2")"
GEO_V1_SHA="$(sha256_of "${SOURCE_DIR}/geo-v1.dat")"
DASHBOARD_ARCHIVE_SHA="$(sha256_of "${SOURCE_DIR}/dashboard-v1.tar.gz")"
SUBS_MIHOMO_SHA="$(sha256_of "${SOURCE_DIR}/mihomo-updated.yaml")"
SUBS_SING_SHA="$(sha256_of "${SOURCE_DIR}/sing-updated.json")"

printf '[1/7] updater status with no configured sources\n'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" ""
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"artifact_dir":"'
assert_contains "${status_json}" '"kernel":{"configured":false'
assert_contains "${status_json}" '"subs":{"configured":false'

printf '[2/7] kernel update idempotent rerun\n'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.kernel]
file = \"${SOURCE_DIR}/kernel-v1\"
checksum = \"${KERNEL_V1_SHA}\"
target = \"${INSTALLED_BIN_DIR}/mihomo\""
must_run update kernel >/dev/null
assert_file_contains "${INSTALLED_BIN_DIR}/mihomo" 'mock-kernel-v1'
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"kernel":{"configured":true,"status":"success"'
assert_contains "${status_json}" '"last_handoff":"none"'
must_run update kernel >/dev/null
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"kernel":{"configured":true,"status":"unchanged"'
assert_contains "${status_json}" '"installed_sha256":"'"${KERNEL_V1_SHA}"'"'

printf '[3/7] checksum mismatch fails safely\n'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.kernel]
file = \"${SOURCE_DIR}/kernel-v2\"
checksum = \"0000000000000000000000000000000000000000000000000000000000000000\"
target = \"${INSTALLED_BIN_DIR}/mihomo\""
must_fail update kernel >/dev/null
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"kernel":{"configured":true,"status":"error"'
assert_contains "${status_json}" '"last_error":"checksum verification failed"'
assert_file_contains "${INSTALLED_BIN_DIR}/mihomo" 'mock-kernel-v1'

printf '[4/7] download failure is reported\n'
export MOCK_CURL_FAIL_URL='https://updates.invalid/geo.dat'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.geo]
url = \"https://updates.invalid/geo.dat\"
target = \"${ARTIFACT_DIR}/geo/geo.dat\""
must_fail update geo >/dev/null
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"geo":{"configured":true,"status":"error"'
assert_contains "${status_json}" '"last_error":"download failed"'
unset MOCK_CURL_FAIL_URL

printf '[5/7] update all installs geo and dashboard payloads\n'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.kernel]
file = \"${SOURCE_DIR}/kernel-v1\"
checksum = \"${KERNEL_V1_SHA}\"
target = \"${INSTALLED_BIN_DIR}/mihomo\"

[updater.geo]
file = \"${SOURCE_DIR}/geo-v1.dat\"
checksum = \"${GEO_V1_SHA}\"
target = \"${ARTIFACT_DIR}/geo/geo.dat\"

[updater.dashboard]
file = \"${SOURCE_DIR}/dashboard-v1.tar.gz\"
checksum = \"${DASHBOARD_ARCHIVE_SHA}\"
target = \"${ARTIFACT_DIR}/dashboard/current\""
must_run update all >/dev/null
assert_file_contains "${ARTIFACT_DIR}/geo/geo.dat" 'geo-version-1'
assert_dir_exists "${ARTIFACT_DIR}/dashboard/current"
assert_file_contains "${ARTIFACT_DIR}/dashboard/current/index.html" 'dashboard-v1'
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"geo":{"configured":true,"status":"success"'
assert_contains "${status_json}" '"dashboard":{"configured":true,"status":"success"'
assert_contains "${status_json}" '"subs":{"configured":false,"status":"skipped"'

printf '[6/7] mihomo subscription update restarts running service\n'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.subs]
file = \"${SOURCE_DIR}/mihomo-updated.yaml\"
checksum = \"${SUBS_MIHOMO_SHA}\"
target = \"${PROFILE_DIR}/mihomo-live.yaml\""
must_run service start >/dev/null
mihomo_pid_before="$(service_pid)"
must_run update subs >/dev/null
mihomo_pid_after="$(service_pid)"
assert_pid_changed "${mihomo_pid_before}" "${mihomo_pid_after}"
assert_file_contains "${PROFILE_DIR}/mihomo-live.yaml" 'MATCH,REJECT'
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"subs":{"configured":true,"status":"success"'
assert_contains "${status_json}" '"last_handoff":"restart"'
must_run service stop >/dev/null

printf '[7/7] sing-box subscription update falls back to restart\n'
write_common_config "sing-box" "${PROFILE_DIR}/sing-live.json" "[updater.subs]
file = \"${SOURCE_DIR}/sing-updated.json\"
checksum = \"${SUBS_SING_SHA}\"
target = \"${PROFILE_DIR}/sing-live.json\""
must_run service start >/dev/null
sing_pid_before="$(service_pid)"
must_run update subs >/dev/null
sing_pid_after="$(service_pid)"
assert_pid_changed "${sing_pid_before}" "${sing_pid_after}"
assert_file_contains "${PROFILE_DIR}/sing-live.json" '"level": "warn"'
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"subs":{"configured":true,"status":"success"'
assert_contains "${status_json}" '"last_handoff":"restart"'
must_run service stop >/dev/null

printf 'PASS: updater integration checks completed\n'
