#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

adapter_sing_box_resolve_bin() {
  if command -v sing-box >/dev/null 2>&1; then
    command -v sing-box
    return 0
  fi

  if [[ -x "${BOX_CORE_BIN_DIR}/sing-box" ]]; then
    printf '%s\n' "${BOX_CORE_BIN_DIR}/sing-box"
    return 0
  fi

  return 1
}

adapter_sing_box_check_config() {
  local bin="${1:?missing sing-box binary path}"
  local rendered_config="${2:?missing rendered config path}"
  local workdir="${3:?missing workdir}"
  "${bin}" check -c "${rendered_config}" -D "${workdir}" >/dev/null 2>&1
}

adapter_sing_box_start() {
  local bin="${1:?missing sing-box binary path}"
  local rendered_config="${2:?missing rendered config path}"
  local workdir="${3:?missing workdir}"
  local service_log="${4:?missing service log path}"

  "${bin}" run -c "${rendered_config}" -D "${workdir}" >>"${service_log}" 2>&1 &
  printf '%s\n' "$!"
}

adapter_sing_box_reload() {
  # TODO(phase-2): call sing-box API reload endpoint when available.
  return 0
}
