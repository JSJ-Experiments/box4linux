#!/usr/bin/env bash

set -euo pipefail

PKG_PATH="${1:-}"

if [[ -z "${PKG_PATH}" ]]; then
  printf 'usage: %s <path-to-box4linux.pkg.tar.zst>\n' "$0" >&2
  exit 2
fi
if [[ ! -f "${PKG_PATH}" ]]; then
  printf 'package not found: %s\n' "${PKG_PATH}" >&2
  exit 1
fi

TMP_ROOT="$(mktemp -d)"
CONFIG_PATH="${TMP_ROOT}/etc/box/box.smoke.toml"
cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

extract_pkg() {
  local pkg="${1:?missing pkg path}"
  local dst="${2:?missing destination}"

  if command -v bsdtar >/dev/null 2>&1; then
    bsdtar -xf "${pkg}" -C "${dst}"
    return 0
  fi

  if tar --help 2>/dev/null | grep -q -- '--zstd'; then
    tar --zstd -xf "${pkg}" -C "${dst}"
    return 0
  fi

  if command -v unzstd >/dev/null 2>&1; then
    unzstd -c "${pkg}" | tar -xf - -C "${dst}"
    return 0
  fi

  printf 'no extractor available for %s (need bsdtar or tar --zstd or unzstd)\n' "${pkg}" >&2
  return 1
}

assert_file() {
  local path="${1:?missing path}"
  if [[ ! -f "${path}" ]]; then
    printf 'expected file missing: %s\n' "${path}" >&2
    exit 1
  fi
}

run_installed_boxctl() {
  BOX_LIB_DIR="${TMP_ROOT}/usr/lib/box4linux/lib" \
  BOX_CONFIG_FILE="${CONFIG_PATH}" \
  BOX_RUN_DIR="${TMP_ROOT}/run/box" \
  BOX_VAR_DIR="${TMP_ROOT}/var/lib/box" \
  BOX_LOG_DIR="${TMP_ROOT}/var/log/box" \
  BOX_LOG_TO_FILE=0 \
  "${TMP_ROOT}/usr/bin/boxctl" "$@"
}

extract_pkg "${PKG_PATH}" "${TMP_ROOT}"

assert_file "${TMP_ROOT}/usr/bin/boxctl"
assert_file "${TMP_ROOT}/usr/lib/box4linux/lib/common.sh"
assert_file "${TMP_ROOT}/usr/lib/box4linux/lib/updater/updater.sh"
assert_file "${TMP_ROOT}/etc/box/box.toml"
assert_file "${TMP_ROOT}/etc/box/profiles/phone-mihomo-config.yml"
assert_file "${TMP_ROOT}/usr/lib/systemd/system/box.service"
assert_file "${TMP_ROOT}/usr/lib/systemd/system/box-firewall.service"
assert_file "${TMP_ROOT}/usr/lib/systemd/system/box-policy.service"
assert_file "${TMP_ROOT}/usr/lib/systemd/system/box-update-all.service"
assert_file "${TMP_ROOT}/usr/lib/systemd/system/box-update-all.timer"

if ! grep -Fq 'config_source = "/etc/box/profiles/phone-mihomo-config.yml"' "${TMP_ROOT}/etc/box/box.toml"; then
  printf 'packaged default config_source did not point at shipped Mihomo profile\n' >&2
  cat "${TMP_ROOT}/etc/box/box.toml" >&2
  exit 1
fi
if ! grep -Fq 'bin_dir = "/usr/bin"' "${TMP_ROOT}/etc/box/box.toml"; then
  printf 'packaged default bin_dir was not /usr/bin\n' >&2
  cat "${TMP_ROOT}/etc/box/box.toml" >&2
  exit 1
fi
if ! grep -Fq 'preset = "auto"' "${TMP_ROOT}/etc/box/box.toml"; then
  printf 'packaged default geo preset was not auto\n' >&2
  cat "${TMP_ROOT}/etc/box/box.toml" >&2
  exit 1
fi

cat >"${CONFIG_PATH}" <<EOF_CFG
[core]
selected = "mihomo"
bin_dir = "${TMP_ROOT}/usr/bin"
workdir = "${TMP_ROOT}/var/lib/box"
config_source = "${TMP_ROOT}/etc/box/profile.yaml"

[network]
mode = "mixed"
tproxy_port = 9898
redir_port = 9797
dns_port = 1053
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
artifact_dir = "${TMP_ROOT}/var/lib/box/artifacts"
staging_dir = "${TMP_ROOT}/var/lib/box/staging"
checksum_policy = "optional"
kernel_interval = "daily"
subs_interval = "hourly"
geo_interval = "daily"
dashboard_interval = "weekly"

[updater.geo]
file = "${TMP_ROOT}/tmp/geo.dat"
target = "${TMP_ROOT}/var/lib/box/artifacts/geo/geo.dat"
EOF_CFG

mkdir -p "${TMP_ROOT}/tmp"
printf 'smoke-geo\n' >"${TMP_ROOT}/tmp/geo.dat"

service_json="$(run_installed_boxctl service status --json)"
firewall_json="$(run_installed_boxctl firewall status --json)"
policy_json="$(run_installed_boxctl policy status --json)"
update_json="$(run_installed_boxctl update status --json)"
run_installed_boxctl update geo >/dev/null
dry_run_output="$(run_installed_boxctl firewall dry-run)"

if [[ "${service_json}" != *'"status"'* ]]; then
  printf 'service status json missing status field: %s\n' "${service_json}" >&2
  exit 1
fi
if [[ "${firewall_json}" != *'"backend"'* ]]; then
  printf 'firewall status json missing backend field: %s\n' "${firewall_json}" >&2
  exit 1
fi
if [[ "${policy_json}" != *'"policy_enabled"'* ]]; then
  printf 'policy status json missing policy_enabled field: %s\n' "${policy_json}" >&2
  exit 1
fi
if [[ "${update_json}" != *'"components"'* ]]; then
  printf 'update status json missing components field: %s\n' "${update_json}" >&2
  exit 1
fi
if [[ "${dry_run_output}" != *'# dry-run backend='* ]]; then
  printf 'firewall dry-run output did not contain dry-run header\n' >&2
  printf '%s\n' "${dry_run_output}" >&2
  exit 1
fi
if [[ ! -f "${TMP_ROOT}/var/lib/box/artifacts/geo/geo.dat" ]]; then
  printf 'installed updater execution did not create geo artifact\n' >&2
  exit 1
fi
for dep in curl gzip jq unzip; do
  if ! grep -Fxq "depend = ${dep}" "${TMP_ROOT}/.PKGINFO"; then
    printf 'package metadata missing expected updater dependency: %s\n' "${dep}" >&2
    cat "${TMP_ROOT}/.PKGINFO" >&2
    exit 1
  fi
done

if command -v systemd-analyze >/dev/null 2>&1; then
  mkdir -p "${TMP_ROOT}/usr/lib/systemd/system"
  for target in sysinit.target basic.target network-online.target multi-user.target; do
    if [[ ! -f "${TMP_ROOT}/usr/lib/systemd/system/${target}" ]]; then
      cat >"${TMP_ROOT}/usr/lib/systemd/system/${target}" <<UNIT
[Unit]
Description=stub ${target} for package smoke verification
UNIT
    fi
  done

  if systemd-analyze --help 2>/dev/null | grep -q -- '--root='; then
    systemd-analyze --root="${TMP_ROOT}" verify \
      "${TMP_ROOT}/usr/lib/systemd/system/box.service" \
      "${TMP_ROOT}/usr/lib/systemd/system/box-firewall.service" \
      "${TMP_ROOT}/usr/lib/systemd/system/box-policy.service" \
      "${TMP_ROOT}/usr/lib/systemd/system/box-update-all.service" \
      "${TMP_ROOT}/usr/lib/systemd/system/box-update-all.timer" >/dev/null
  else
    systemd-analyze verify \
      "${TMP_ROOT}/usr/lib/systemd/system/box.service" \
      "${TMP_ROOT}/usr/lib/systemd/system/box-firewall.service" \
      "${TMP_ROOT}/usr/lib/systemd/system/box-policy.service" \
      "${TMP_ROOT}/usr/lib/systemd/system/box-update-all.service" \
      "${TMP_ROOT}/usr/lib/systemd/system/box-update-all.timer" >/dev/null
  fi
else
  printf 'SKIP: systemd-analyze not available\n'
fi

printf 'PASS: arch package smoke test (%s)\n' "${PKG_PATH}"
