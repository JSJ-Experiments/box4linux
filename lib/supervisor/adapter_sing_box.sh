#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

adapter_sing_box_resolve_bin() {
  if [[ -x "${BOX_CORE_BIN_DIR}/sing-box" ]]; then
    printf '%s\n' "${BOX_CORE_BIN_DIR}/sing-box"
    return 0
  fi

  if command -v sing-box >/dev/null 2>&1; then
    command -v sing-box
    return 0
  fi

  return 1
}

adapter_sing_box_check_config() {
  local bin="${1:?missing sing-box binary path}"
  local rendered_config="${2:?missing rendered config path}"
  local workdir="${3:?missing workdir}"
  "${bin}" check -c "${rendered_config}" -D "${workdir}" >/dev/null
}

adapter_sing_box_start() {
  local bin="${1:?missing sing-box binary path}"
  local rendered_config="${2:?missing rendered config path}"
  local workdir="${3:?missing workdir}"
  local service_log="${4:?missing service log path}"

  spawn_detached_process "${service_log}" "${bin}" run -c "${rendered_config}" -D "${workdir}"
}

adapter_sing_box_reload() {
  local rendered_config="${1:?missing rendered config path}"
  local workdir="${2:?missing workdir}"
  local bin="${3:?missing sing-box binary path}"
  local curl_bin controller secret url jq_bin
  local -a curl_args

  jq_bin="$(command -v jq || true)"
  if [[ -z "${jq_bin}" ]]; then
    log "WARN" "service" "SING_BOX_RELOAD_UNAVAILABLE" "jq is required for sing-box reload"
    return 1
  fi

  controller="$("${jq_bin}" -r '.experimental.clash_api.external_controller // (.. | objects | .external_controller? // empty)' "${rendered_config}" 2>/dev/null | head -n 1)"
  secret="$("${jq_bin}" -r '.experimental.clash_api.secret // (.. | objects | .secret? // empty)' "${rendered_config}" 2>/dev/null | head -n 1)"
  if [[ -z "${controller}" || "${controller}" == "null" ]]; then
    log "WARN" "service" "SING_BOX_RELOAD_UNAVAILABLE" "sing-box controller is not configured; restart is required"
    return 1
  fi

  adapter_sing_box_check_config "${bin}" "${rendered_config}" "${workdir}" >/dev/null 2>&1 || true

  curl_bin="$(command -v curl || true)"
  if [[ -z "${curl_bin}" ]]; then
    log "WARN" "service" "SING_BOX_RELOAD_UNAVAILABLE" "curl is required for sing-box reload"
    return 1
  fi

  url="http://${controller}/configs?force=true"
  curl_args=("${curl_bin}" -fsS -X PUT "${url}" -H 'Content-Type: application/json')
  if [[ -n "${secret}" && "${secret}" != "null" ]]; then
    curl_args+=(-H "Authorization: Bearer ${secret}")
  fi
  curl_args+=(-d '{"path":"","payload":""}')

  if "${curl_args[@]}" >/dev/null; then
    log "INFO" "service" "SING_BOX_RELOADED" "sing-box API reload succeeded controller=${controller}"
    return 0
  fi

  log "WARN" "service" "SING_BOX_RELOAD_FAILED" "sing-box API reload failed controller=${controller}"
  return 1
}
