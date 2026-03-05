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
  BOX_CONFIG_FILE="${TMP_ROOT}/etc/box/box.toml" \
  BOX_RUN_DIR="${TMP_ROOT}/run/box" \
  BOX_VAR_DIR="${TMP_ROOT}/var/lib/box" \
  BOX_LOG_DIR="${TMP_ROOT}/var/log/box" \
  BOX_LOG_TO_FILE=0 \
  "${TMP_ROOT}/usr/bin/boxctl" "$@"
}

extract_pkg "${PKG_PATH}" "${TMP_ROOT}"

assert_file "${TMP_ROOT}/usr/bin/boxctl"
assert_file "${TMP_ROOT}/usr/lib/box4linux/lib/common.sh"
assert_file "${TMP_ROOT}/etc/box/box.toml"
assert_file "${TMP_ROOT}/usr/lib/systemd/system/box.service"
assert_file "${TMP_ROOT}/usr/lib/systemd/system/box-firewall.service"

service_json="$(run_installed_boxctl service status --json)"
firewall_json="$(run_installed_boxctl firewall status --json)"
dry_run_output="$(run_installed_boxctl firewall dry-run)"

if [[ "${service_json}" != *'"status"'* ]]; then
  printf 'service status json missing status field: %s\n' "${service_json}" >&2
  exit 1
fi
if [[ "${firewall_json}" != *'"backend"'* ]]; then
  printf 'firewall status json missing backend field: %s\n' "${firewall_json}" >&2
  exit 1
fi
if [[ "${dry_run_output}" != *'# dry-run backend='* ]]; then
  printf 'firewall dry-run output did not contain dry-run header\n' >&2
  printf '%s\n' "${dry_run_output}" >&2
  exit 1
fi

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
      "${TMP_ROOT}/usr/lib/systemd/system/box-firewall.service" >/dev/null
  else
    systemd-analyze verify \
      "${TMP_ROOT}/usr/lib/systemd/system/box.service" \
      "${TMP_ROOT}/usr/lib/systemd/system/box-firewall.service" >/dev/null
  fi
else
  printf 'SKIP: systemd-analyze not available\n'
fi

printf 'PASS: arch package smoke test (%s)\n' "${PKG_PATH}"
