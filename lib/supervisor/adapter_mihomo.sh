#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

adapter_mihomo_resolve_bin() {
  if command -v mihomo >/dev/null 2>&1; then
    command -v mihomo
    return 0
  fi

  if [[ -x "${BOX_CORE_BIN_DIR}/mihomo" ]]; then
    printf '%s\n' "${BOX_CORE_BIN_DIR}/mihomo"
    return 0
  fi

  return 1
}

adapter_mihomo_check_config() {
  local bin="${1:?missing mihomo binary path}"
  local rendered_config="${2:?missing rendered config path}"
  local workdir="${3:?missing workdir}"
  "${bin}" -t -d "${workdir}" -f "${rendered_config}" >/dev/null 2>&1
}

adapter_mihomo_start() {
  local bin="${1:?missing mihomo binary path}"
  local rendered_config="${2:?missing rendered config path}"
  local workdir="${3:?missing workdir}"
  local service_log="${4:?missing service log path}"

  "${bin}" -d "${workdir}" -f "${rendered_config}" >>"${service_log}" 2>&1 &
  printf '%s\n' "$!"
}

adapter_mihomo_reload() {
  # TODO(phase-2): call mihomo external-controller reload endpoint.
  return 0
}
