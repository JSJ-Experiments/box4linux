#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

adapter_mihomo_resolve_bin() {
  if [[ -x "${BOX_CORE_BIN_DIR}/mihomo" ]]; then
    printf '%s\n' "${BOX_CORE_BIN_DIR}/mihomo"
    return 0
  fi

  if command -v mihomo >/dev/null 2>&1; then
    command -v mihomo
    return 0
  fi

  return 1
}

adapter_mihomo_check_config() {
  local bin="${1:?missing mihomo binary path}"
  local rendered_config="${2:?missing rendered config path}"
  local workdir="${3:?missing workdir}"
  "${bin}" -t -d "${workdir}" -f "${rendered_config}" >/dev/null
}

adapter_mihomo_start() {
  local bin="${1:?missing mihomo binary path}"
  local rendered_config="${2:?missing rendered config path}"
  local workdir="${3:?missing workdir}"
  local service_log="${4:?missing service log path}"

  "${bin}" -d "${workdir}" -f "${rendered_config}" >>"${service_log}" 2>&1 &
  printf '%s\n' "$!"
}

adapter_mihomo_read_value() {
  local config_file="${1:?missing config file}"
  local key_regex="${2:?missing key regex}"
  awk -F: -v wanted="${key_regex}" '
    $0 ~ "^[[:space:]]*" wanted "[[:space:]]*:" {
      value = substr($0, index($0, ":") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "${config_file}"
}

adapter_mihomo_reload() {
  local rendered_config="${1:?missing rendered config path}"
  local workdir="${2:?missing workdir}"
  local bin="${3:?missing mihomo binary path}"
  local curl_bin controller secret url
  local -a curl_args

  controller="$(adapter_mihomo_read_value "${rendered_config}" 'external-controller|external_controller' || true)"
  secret="$(adapter_mihomo_read_value "${rendered_config}" 'secret' || true)"
  if [[ -z "${controller}" ]]; then
    log "WARN" "service" "MIHOMO_RELOAD_UNAVAILABLE" "mihomo controller is not configured; restart is required"
    return 1
  fi

  adapter_mihomo_check_config "${bin}" "${rendered_config}" "${workdir}" >/dev/null 2>&1 || true

  curl_bin="$(command -v curl || true)"
  if [[ -z "${curl_bin}" ]]; then
    log "WARN" "service" "MIHOMO_RELOAD_UNAVAILABLE" "curl is required for mihomo reload"
    return 1
  fi

  url="http://${controller}/configs?force=true"
  curl_args=("${curl_bin}" -fsS -X PUT "${url}" -H 'Content-Type: application/json')
  if [[ -n "${secret}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${secret}")
  fi
  curl_args+=(-d '{"path":"","payload":""}')

  if "${curl_args[@]}" >/dev/null; then
    log "INFO" "service" "MIHOMO_RELOADED" "mihomo API reload succeeded controller=${controller}"
    return 0
  fi

  log "WARN" "service" "MIHOMO_RELOAD_FAILED" "mihomo API reload failed controller=${controller}"
  return 1
}
