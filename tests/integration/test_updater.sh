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
export MOCK_CURL_MAP_FILE="${TMP_DIR}/mock/curl.map"
export MOCK_CURL_PUT_LOG="${TMP_DIR}/mock/curl.put.log"
export MOCK_CURL_FLAKY_STATE_FILE="${TMP_DIR}/mock/curl.flaky"

CONFIG_FILE="${TMP_DIR}/box.toml"
INSTALLED_BIN_DIR="${TMP_DIR}/installed-bin"
PROFILE_DIR="${TMP_DIR}/profiles"
SOURCE_DIR="${TMP_DIR}/sources"
ARTIFACT_DIR="${BOX_VAR_DIR}/artifacts"
STAGING_DIR="${BOX_VAR_DIR}/staging"
ACTIVE_MOCK_DIR="${TMP_DIR}/active-mockbin"

export BOX_CONFIG_FILE="${CONFIG_FILE}"
mkdir -p "${TMP_DIR}/mock" "${BOX_RUN_DIR}" "${BOX_VAR_DIR}" "${BOX_LOG_DIR}" "${INSTALLED_BIN_DIR}" "${PROFILE_DIR}" "${SOURCE_DIR}" "${ACTIVE_MOCK_DIR}"
touch "${MOCK_IPTABLES_STATE}" "${MOCK_IP_STATE}" "${MOCK_NFT_STATE}" "${MOCK_CURL_MAP_FILE}" "${MOCK_CURL_PUT_LOG}"

for required_cmd in jq zip unzip gzip; do
  if ! command -v "${required_cmd}" >/dev/null 2>&1; then
    printf 'missing required test command: %s\n' "${required_cmd}" >&2
    exit 1
  fi
done

PATH_ORIG="${PATH}"
for helper in curl ip iptables nft sing-box; do
  ln -sf "${MOCK_DIR}/${helper}" "${ACTIVE_MOCK_DIR}/${helper}"
done

PHONE_TEMPLATE="${PROFILE_DIR}/phone-mihomo-config.yml"
cp -f "${ROOT_DIR}/etc/box/profiles/phone-mihomo-config.yml" "${PHONE_TEMPLATE}"

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

cat >"${PROFILE_DIR}/mihomo-live-api.yaml" <<'EOF_MIHOMO_API'
mode: rule
mixed-port: 7890
external-controller: 127.0.0.1:9090
secret: test-secret
rules:
  - MATCH,DIRECT
EOF_MIHOMO_API

cat >"${PROFILE_DIR}/mihomo-dashboard.yaml" <<EOF_MIHOMO_DASH
mode: rule
mixed-port: 7890
external-ui: ui/dashboard
external-ui-download-url: file://${SOURCE_DIR}/dashboard-v1.zip
rules:
  - MATCH,DIRECT
EOF_MIHOMO_DASH

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

cat >"${PROFILE_DIR}/sing-live-api.json" <<'EOF_SING_LIVE_API'
{
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9091",
      "secret": "sing-secret"
    }
  },
  "log": { "level": "info" },
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ]
}
EOF_SING_LIVE_API

cat >"${PROFILE_DIR}/sing-dashboard-generic.json" <<EOF_SING_DASH_GENERIC
{
  "log": { "level": "info" },
  "custom": {
    "external_ui": "ui/sing-dashboard",
    "external_ui_download_url": "file://${SOURCE_DIR}/dashboard-v1.zip"
  }
}
EOF_SING_DASH_GENERIC

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

mkdir -p "${SOURCE_DIR}/dashboard-zip/dist"
cat >"${SOURCE_DIR}/dashboard-zip/dist/index.html" <<'EOF_DASH_ZIP'
<!doctype html><title>dashboard-zip</title>
EOF_DASH_ZIP
(
  cd "${SOURCE_DIR}/dashboard-zip"
  zip -qr "${SOURCE_DIR}/dashboard-v1.zip" .
)

mkdir -p "${SOURCE_DIR}/sing-box-release"
cat >"${SOURCE_DIR}/sing-box-release/sing-box" <<'EOF_SING_RELEASE'
#!/usr/bin/env bash
printf 'mock-release-sing-box\n'
EOF_SING_RELEASE
chmod +x "${SOURCE_DIR}/sing-box-release/sing-box"
(
  cd "${SOURCE_DIR}"
  tar -czf "${SOURCE_DIR}/sing-box-1.0.0-linux-amd64.tar.gz" sing-box-release
)

cat >"${SOURCE_DIR}/mihomo-release-bin" <<'EOF_MIHOMO_RELEASE'
#!/usr/bin/env bash
printf 'mock-release-mihomo\n'
EOF_MIHOMO_RELEASE
chmod +x "${SOURCE_DIR}/mihomo-release-bin"
gzip -c "${SOURCE_DIR}/mihomo-release-bin" >"${SOURCE_DIR}/mihomo-linux-amd64-v1.0.0.gz"

cat >"${SOURCE_DIR}/geo-release-prerelease.dat" <<'EOF_GEO_RELEASE'
geo-release-prerelease
EOF_GEO_RELEASE

KERNEL_V1_SHA="$(sha256_of "${SOURCE_DIR}/kernel-v1")"
KERNEL_V2_SHA="$(sha256_of "${SOURCE_DIR}/kernel-v2")"
GEO_V1_SHA="$(sha256_of "${SOURCE_DIR}/geo-v1.dat")"
DASHBOARD_ZIP_SHA="$(sha256_of "${SOURCE_DIR}/dashboard-v1.zip")"
SUBS_MIHOMO_SHA="$(sha256_of "${SOURCE_DIR}/mihomo-updated.yaml")"
SUBS_SING_SHA="$(sha256_of "${SOURCE_DIR}/sing-updated.json")"
RELEASE_KERNEL_SHA="$(sha256_of "${SOURCE_DIR}/sing-box-1.0.0-linux-amd64.tar.gz")"
RELEASE_KERNEL_BIN_SHA="$(sha256_of "${SOURCE_DIR}/sing-box-release/sing-box")"
MIHOMO_RELEASE_SHA="$(sha256_of "${SOURCE_DIR}/mihomo-linux-amd64-v1.0.0.gz")"
MIHOMO_RELEASE_BIN_SHA="$(sha256_of "${SOURCE_DIR}/mihomo-release-bin")"
RELEASE_GEO_SHA="$(sha256_of "${SOURCE_DIR}/geo-release-prerelease.dat")"

cat >"${SOURCE_DIR}/sing-box-1.0.0-linux-amd64.sha256" <<EOF_RELEASE_KERNEL_SHA
${RELEASE_KERNEL_SHA}  sing-box-1.0.0-linux-amd64.tar.gz
EOF_RELEASE_KERNEL_SHA

cat >"${SOURCE_DIR}/geo-release-prerelease.sha256" <<EOF_RELEASE_GEO_SHA
${RELEASE_GEO_SHA}  geo-release-prerelease.dat
EOF_RELEASE_GEO_SHA

cat >"${SOURCE_DIR}/mihomo-linux-amd64-v1.0.0.sha256" <<EOF_RELEASE_MIHOMO_SHA
${MIHOMO_RELEASE_SHA}  mihomo-linux-amd64-v1.0.0.gz
EOF_RELEASE_MIHOMO_SHA

cat >"${SOURCE_DIR}/kernel-release-stable.json" <<EOF_KERNEL_RELEASE_JSON
{
  "tag_name": "v1.0.0",
  "prerelease": false,
  "assets": [
    {
      "name": "sing-box-1.0.0-linux-amd64.tar.gz",
      "browser_download_url": "file://${SOURCE_DIR}/sing-box-1.0.0-linux-amd64.tar.gz"
    },
    {
      "name": "sing-box-1.0.0-linux-amd64.sha256",
      "browser_download_url": "file://${SOURCE_DIR}/sing-box-1.0.0-linux-amd64.sha256"
    }
  ]
}
EOF_KERNEL_RELEASE_JSON

cat >"${SOURCE_DIR}/mihomo-release-stable.json" <<EOF_MIHOMO_RELEASE_JSON
{
  "tag_name": "v1.0.0",
  "prerelease": false,
  "assets": [
    {
      "name": "mihomo-linux-amd64-v1.0.0.gz",
      "browser_download_url": "file://${SOURCE_DIR}/mihomo-linux-amd64-v1.0.0.gz"
    },
    {
      "name": "mihomo-linux-amd64-v1.0.0.sha256",
      "browser_download_url": "file://${SOURCE_DIR}/mihomo-linux-amd64-v1.0.0.sha256"
    }
  ]
}
EOF_MIHOMO_RELEASE_JSON

cat >"${SOURCE_DIR}/geo-release-list.json" <<EOF_GEO_RELEASE_JSON
[
  {
    "tag_name": "v1.0.0",
    "prerelease": false,
    "assets": [
      {
        "name": "geo-release-stable.dat",
        "browser_download_url": "file://${SOURCE_DIR}/geo-v1.dat"
      }
    ]
  },
  {
    "tag_name": "v1.1.0-rc1",
    "prerelease": true,
    "assets": [
      {
        "name": "geo-release-prerelease.dat",
        "browser_download_url": "file://${SOURCE_DIR}/geo-release-prerelease.dat"
      },
      {
        "name": "geo-release-prerelease.sha256",
        "browser_download_url": "file://${SOURCE_DIR}/geo-release-prerelease.sha256"
      }
    ]
  }
]
EOF_GEO_RELEASE_JSON

printf '[1/19] updater status with no configured sources\n'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" ""
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"artifact_dir":"'
assert_contains "${status_json}" '"kernel":{"configured":false'
assert_contains "${status_json}" '"subs":{"configured":false'

printf '[2/19] kernel update idempotent rerun\n'
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

printf '[3/19] checksum mismatch fails safely\n'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.kernel]
file = \"${SOURCE_DIR}/kernel-v2\"
checksum = \"0000000000000000000000000000000000000000000000000000000000000000\"
target = \"${INSTALLED_BIN_DIR}/mihomo\""
must_fail update kernel >/dev/null
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"kernel":{"configured":true,"status":"error"'
assert_contains "${status_json}" '"last_error":"checksum verification failed"'
assert_file_contains "${INSTALLED_BIN_DIR}/mihomo" 'mock-kernel-v1'

printf '[4/19] fetch retry/backoff recovers flaky download\n'
printf 'https://updates.invalid/retry-geo.dat\t%s\n' "${SOURCE_DIR}/geo-v2.dat" >"${MOCK_CURL_MAP_FILE}"
export MOCK_CURL_FLAKY_URL='https://updates.invalid/retry-geo.dat'
export MOCK_CURL_FLAKY_ATTEMPTS=2
rm -f "${MOCK_CURL_FLAKY_STATE_FILE}"
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "fetch_retries = 3
fetch_retry_backoff_ms = 1

[updater.geo]
url = \"https://updates.invalid/retry-geo.dat\"
target = \"${ARTIFACT_DIR}/geo/retry.dat\""
must_run update geo >/dev/null
assert_file_contains "${ARTIFACT_DIR}/geo/retry.dat" 'geo-version-2'
assert_file_contains "${MOCK_CURL_FLAKY_STATE_FILE}" '3'
unset MOCK_CURL_FLAKY_URL MOCK_CURL_FLAKY_ATTEMPTS

printf '[5/19] download failure is reported\n'
export MOCK_CURL_FAIL_URL='https://updates.invalid/geo.dat'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.geo]
url = \"https://updates.invalid/geo.dat\"
target = \"${ARTIFACT_DIR}/geo/geo.dat\""
must_fail update geo >/dev/null
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"geo":{"configured":true,"status":"error"'
assert_contains "${status_json}" '"last_error":"download failed"'
unset MOCK_CURL_FAIL_URL

printf '[6/19] update all installs geo and dashboard payloads\n'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.kernel]
file = \"${SOURCE_DIR}/kernel-v1\"
checksum = \"${KERNEL_V1_SHA}\"
target = \"${INSTALLED_BIN_DIR}/mihomo\"

[updater.geo]
file = \"${SOURCE_DIR}/geo-v1.dat\"
checksum = \"${GEO_V1_SHA}\"
target = \"${ARTIFACT_DIR}/geo/geo.dat\"

[updater.dashboard]
file = \"${SOURCE_DIR}/dashboard-v1.zip\"
checksum = \"${DASHBOARD_ZIP_SHA}\"
target = \"${ARTIFACT_DIR}/dashboard/current\""
must_run update all >/dev/null
assert_file_contains "${ARTIFACT_DIR}/geo/geo.dat" 'geo-version-1'
assert_dir_exists "${ARTIFACT_DIR}/dashboard/current"
assert_file_contains "${ARTIFACT_DIR}/dashboard/current/index.html" 'dashboard-zip'
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"geo":{"configured":true,"status":"success"'
assert_contains "${status_json}" '"dashboard":{"configured":true,"status":"success"'
assert_contains "${status_json}" '"subs":{"configured":false,"status":"skipped"'

printf '[7/19] dashboard updater can derive target and url from core config\n'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-dashboard.yaml" ""
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"dashboard":{"configured":true'
must_run update dashboard >/dev/null
assert_file_contains "${PROFILE_DIR}/ui/dashboard/index.html" 'dashboard-zip'
status_json="$(must_run update status --json)"
assert_contains "${status_json}" "\"target_path\":\"${PROFILE_DIR}/ui/dashboard\""
rm -rf "${PROFILE_DIR}/ui/dashboard"
must_run update all >/dev/null
assert_file_contains "${PROFILE_DIR}/ui/dashboard/index.html" 'dashboard-zip'

printf '[8/19] dashboard updater falls back to ./dashboard relative to core config\n'
export MOCK_CURL_RESPONSE_FILE="${SOURCE_DIR}/dashboard-v1.zip"
rm -rf "${PROFILE_DIR}/dashboard"
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" ""
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"dashboard":{"configured":true'
must_run update all >/dev/null
assert_file_contains "${PROFILE_DIR}/dashboard/index.html" 'dashboard-zip'
unset MOCK_CURL_RESPONSE_FILE

printf '[9/19] sing-box dashboard discovery accepts generic external_ui keys\n'
write_common_config "sing-box" "${PROFILE_DIR}/sing-dashboard-generic.json" ""
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"dashboard":{"configured":true'
must_run update dashboard >/dev/null
assert_file_contains "${PROFILE_DIR}/ui/sing-dashboard/index.html" 'dashboard-zip'

printf '[10/19] mihomo phone preset generates config from sanitized template\n'
write_common_config "mihomo" "${PHONE_TEMPLATE}" "[updater.subs]
preset = \"mihomo_phone\"
target = \"${PHONE_TEMPLATE}\"
provider_names = [\"proxy1\", \"proxy3\", \"proxy4\", \"proxy5\", \"proxy6\"]
provider_urls = [\"https://subs.example/proxy1\", \"https://subs.example/proxy3\", \"https://subs.example/proxy4\", \"https://subs.example/proxy5\", \"https://subs.example/proxy6\"]"
must_run update subs >/dev/null
assert_file_contains "${PHONE_TEMPLATE}" 'https://subs.example/proxy1'
assert_file_contains "${PHONE_TEMPLATE}" 'https://subs.example/proxy6'
assert_file_contains "${PHONE_TEMPLATE}" 'https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/cn.mrs'
assert_not_contains "$(cat "${PHONE_TEMPLATE}")" '<SUBSCRIPTION_URL_PROXY1>'
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"subs":{"configured":true,"status":"success"'
assert_contains "${status_json}" '"last_handoff":"none"'

printf '[11/19] kernel release resolver selects stable archive asset\n'
write_common_config "sing-box" "${PROFILE_DIR}/sing-live.json" "[updater.kernel]
source = \"release\"
release_api_url = \"file://${SOURCE_DIR}/kernel-release-stable.json\"
release_channel = \"stable\"
asset_regex = \"sing-box-.*linux.*(amd64|x86_64).*tar.gz$\"
checksum_asset_regex = \"sha256$\"
target = \"${INSTALLED_BIN_DIR}/sing-box\""
must_run update kernel >/dev/null
assert_file_contains "${INSTALLED_BIN_DIR}/sing-box" 'mock-release-sing-box'
status_json="$(must_run update status --json)"
assert_contains "${status_json}" "\"source_ref\":\"file://${SOURCE_DIR}/sing-box-1.0.0-linux-amd64.tar.gz\""
assert_contains "${status_json}" "\"installed_sha256\":\"${RELEASE_KERNEL_BIN_SHA}\""

printf '[12/19] mihomo kernel release resolver installs gzip asset\n'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.kernel]
source = \"release\"
release_api_url = \"file://${SOURCE_DIR}/mihomo-release-stable.json\"
release_channel = \"stable\"
asset_regex = \"mihomo-.*linux.*(amd64|x86_64).*gz$\"
checksum_asset_regex = \"sha256$\"
target = \"${INSTALLED_BIN_DIR}/mihomo-release\""
must_run update kernel >/dev/null
assert_file_contains "${INSTALLED_BIN_DIR}/mihomo-release" 'mock-release-mihomo'
status_json="$(must_run update status --json)"
assert_contains "${status_json}" "\"source_ref\":\"file://${SOURCE_DIR}/mihomo-linux-amd64-v1.0.0.gz\""
assert_contains "${status_json}" "\"installed_sha256\":\"${MIHOMO_RELEASE_BIN_SHA}\""

printf '[13/19] geo release resolver selects prerelease asset\n'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.geo]
source = \"release\"
release_api_url = \"file://${SOURCE_DIR}/geo-release-list.json\"
release_channel = \"prerelease\"
asset_regex = \"geo-release-prerelease.dat$\"
checksum_asset_regex = \"geo-release-prerelease.sha256$\"
target = \"${ARTIFACT_DIR}/geo/geo-release.dat\""
must_run update geo >/dev/null
assert_file_contains "${ARTIFACT_DIR}/geo/geo-release.dat" 'geo-release-prerelease'
status_json="$(must_run update status --json)"
assert_contains "${status_json}" "\"source_ref\":\"file://${SOURCE_DIR}/geo-release-prerelease.dat\""

printf '[14/19] geo preset installs metacubex mihomo bundle\n'
cat >"${MOCK_CURL_MAP_FILE}" <<EOF_GEO_PRESET_MAP
https://github.com/MetaCubeX/meta-rules-dat/raw/release/country-lite.mmdb	${SOURCE_DIR}/geo-v1.dat
https://github.com/MetaCubeX/meta-rules-dat/raw/release/geosite.dat	${SOURCE_DIR}/geo-v2.dat
EOF_GEO_PRESET_MAP
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.geo]
preset = \"metacubex_mihomo\"
target = \"${ARTIFACT_DIR}/geo-preset\""
must_run update geo >/dev/null
assert_file_contains "${ARTIFACT_DIR}/geo-preset/Country.mmdb" 'geo-version-1'
assert_file_contains "${ARTIFACT_DIR}/geo-preset/GeoSite.dat" 'geo-version-2'
status_json="$(must_run update status --json)"
assert_contains "${status_json}" "\"target_path\":\"${ARTIFACT_DIR}/geo-preset\""
assert_contains "${status_json}" '"geo":{"configured":true,"status":"success"'

printf '[15/19] geo update does not restart running service\n'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.geo]
file = \"${SOURCE_DIR}/geo-v2.dat\"
checksum = \"$(sha256_of "${SOURCE_DIR}/geo-v2.dat")\"
target = \"${ARTIFACT_DIR}/geo/geo.dat\""
must_run service start >/dev/null
geo_pid_before="$(service_pid)"
must_run update geo >/dev/null
geo_pid_after="$(service_pid)"
assert_pid_same "${geo_pid_before}" "${geo_pid_after}"
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"geo":{"configured":true,"status":"success"'
assert_contains "${status_json}" '"last_handoff":"none"'
must_run service stop >/dev/null

printf '[16/19] inactive kernel target does not restart running service\n'
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.kernel]
file = \"${SOURCE_DIR}/kernel-v2\"
checksum = \"${KERNEL_V2_SHA}\"
target = \"${INSTALLED_BIN_DIR}/mihomo\""
must_run service start >/dev/null
kernel_pid_before="$(service_pid)"
must_run update kernel >/dev/null
kernel_pid_after="$(service_pid)"
assert_pid_same "${kernel_pid_before}" "${kernel_pid_after}"
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"kernel":{"configured":true,"status":"success"'
assert_contains "${status_json}" '"last_handoff":"none"'
must_run service stop >/dev/null

printf '[17/19] failed kernel handoff restores old binary and service\n'
cat >"${INSTALLED_BIN_DIR}/mihomo" <<'EOF_ACTIVE_GOOD'
#!/usr/bin/env bash
if [[ "${1:-}" == "-t" ]]; then
  exit 0
fi
trap 'exit 0' TERM INT
while true; do
  sleep 1
done
EOF_ACTIVE_GOOD
chmod +x "${INSTALLED_BIN_DIR}/mihomo"
cat >"${SOURCE_DIR}/kernel-bad" <<'EOF_BAD_KERNEL'
#!/usr/bin/env bash
exit 1
EOF_BAD_KERNEL
chmod +x "${SOURCE_DIR}/kernel-bad"
PATH="${ACTIVE_MOCK_DIR}:/usr/bin:/bin"
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live.yaml" "[updater.kernel]
file = \"${SOURCE_DIR}/kernel-bad\"
checksum = \"$(sha256_of "${SOURCE_DIR}/kernel-bad")\"
target = \"${INSTALLED_BIN_DIR}/mihomo\""
must_run service start >/dev/null
recovery_pid_before="$(service_pid)"
must_fail update kernel >/dev/null
recovery_pid_after="$(service_pid)"
assert_pid_changed "${recovery_pid_before}" "${recovery_pid_after}"
assert_file_contains "${INSTALLED_BIN_DIR}/mihomo" 'while true; do'
must_run service stop >/dev/null
PATH="${PATH_ORIG}"

printf '[18/19] mihomo subscription update reloads running service via controller API\n'
: >"${MOCK_CURL_PUT_LOG}"
write_common_config "mihomo" "${PROFILE_DIR}/mihomo-live-api.yaml" "[updater.subs]
file = \"${SOURCE_DIR}/mihomo-updated.yaml\"
checksum = \"${SUBS_MIHOMO_SHA}\"
target = \"${PROFILE_DIR}/mihomo-live-api.yaml\""
must_run service start >/dev/null
mihomo_pid_before="$(service_pid)"
must_run update subs >/dev/null
mihomo_pid_after="$(service_pid)"
assert_pid_same "${mihomo_pid_before}" "${mihomo_pid_after}"
assert_file_contains "${PROFILE_DIR}/mihomo-live-api.yaml" 'MATCH,REJECT'
assert_file_contains "${MOCK_CURL_PUT_LOG}" 'method=PUT url=http://127.0.0.1:9090/configs?force=true'
assert_file_contains "${MOCK_CURL_PUT_LOG}" 'header=Authorization: Bearer test-secret'
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"subs":{"configured":true,"status":"success"'
assert_contains "${status_json}" '"last_handoff":"reload"'
must_run service stop >/dev/null

printf '[19/19] sing-box subscription update reloads running service via controller API\n'
: >"${MOCK_CURL_PUT_LOG}"
write_common_config "sing-box" "${PROFILE_DIR}/sing-live-api.json" "[updater.subs]
file = \"${SOURCE_DIR}/sing-updated.json\"
checksum = \"${SUBS_SING_SHA}\"
target = \"${PROFILE_DIR}/sing-live-api.json\""
must_run service start >/dev/null
sing_pid_before="$(service_pid)"
must_run update subs >/dev/null
sing_pid_after="$(service_pid)"
assert_pid_same "${sing_pid_before}" "${sing_pid_after}"
assert_file_contains "${PROFILE_DIR}/sing-live-api.json" '"level": "warn"'
assert_file_contains "${MOCK_CURL_PUT_LOG}" 'method=PUT url=http://127.0.0.1:9091/configs?force=true'
assert_file_contains "${MOCK_CURL_PUT_LOG}" 'header=Authorization: Bearer sing-secret'
status_json="$(must_run update status --json)"
assert_contains "${status_json}" '"subs":{"configured":true,"status":"success"'
assert_contains "${status_json}" '"last_handoff":"reload"'
must_run service stop >/dev/null

printf 'PASS: updater integration checks completed\n'
