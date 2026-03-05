#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

BOX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX_REPO_ROOT="$(cd "${BOX_LIB_DIR}/.." && pwd)"

BOX_ETC_DIR_DEFAULT="/etc/box"
BOX_VAR_DIR_DEFAULT="/var/lib/box"
BOX_RUN_DIR_DEFAULT="/run/box"
BOX_LOG_DIR_DEFAULT="/var/log/box"

BOX_DEV_ROOT="${BOX_REPO_ROOT}/.box-dev"
BOX_DEV_VAR_DIR="${BOX_DEV_ROOT}/var"
BOX_DEV_RUN_DIR="${BOX_DEV_ROOT}/run"
BOX_DEV_LOG_DIR="${BOX_DEV_ROOT}/log"

BOX_VAR_DIR="${BOX_VAR_DIR:-${BOX_VAR_DIR_DEFAULT}}"
BOX_RUN_DIR="${BOX_RUN_DIR:-${BOX_RUN_DIR_DEFAULT}}"
BOX_LOG_DIR="${BOX_LOG_DIR:-${BOX_LOG_DIR_DEFAULT}}"
BOX_LOCK_DIR="${BOX_LOCK_DIR:-${BOX_RUN_DIR}/locks}"
BOX_OUTPUT_FORMAT="${BOX_OUTPUT_FORMAT:-text}"
BOX_LOG_TO_FILE="${BOX_LOG_TO_FILE:-1}"

E_CONFIG=10
E_CORE_START=20
E_FIREWALL_APPLY=30
E_POLICY=40

resolve_runtime_path() {
  local preferred="$1"
  local fallback="$2"
  local resolved="${preferred}"

  if [[ ! -d "${preferred}" ]]; then
    mkdir -p "${preferred}" 2>/dev/null || resolved="${fallback}"
  fi

  if [[ "${resolved}" == "${preferred}" && ! -w "${preferred}" ]]; then
    resolved="${fallback}"
  fi

  mkdir -p "${resolved}" 2>/dev/null || true
  printf '%s\n' "${resolved}"
}

init_runtime_paths() {
  BOX_VAR_DIR="$(resolve_runtime_path "${BOX_VAR_DIR}" "${BOX_DEV_VAR_DIR}")"
  BOX_RUN_DIR="$(resolve_runtime_path "${BOX_RUN_DIR}" "${BOX_DEV_RUN_DIR}")"
  BOX_LOG_DIR="$(resolve_runtime_path "${BOX_LOG_DIR}" "${BOX_DEV_LOG_DIR}")"
  BOX_LOCK_DIR="${BOX_RUN_DIR}/locks"
  mkdir -p "${BOX_LOCK_DIR}" "${BOX_RUN_DIR}/state" 2>/dev/null || true
  export BOX_VAR_DIR BOX_RUN_DIR BOX_LOG_DIR BOX_LOCK_DIR
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  local level="${1:-INFO}"
  local component="${2:-main}"
  local event_id="${3:-GENERIC}"
  local message="${4:-}"
  local ts log_line log_file

  ts="$(timestamp_utc)"
  log_line="ts=${ts} level=${level} component=${component} event_id=${event_id} msg=\"${message}\""
  printf '%s\n' "${log_line}" >&2
  if [[ "${BOX_LOG_TO_FILE}" == "1" ]]; then
    init_runtime_paths
    log_file="${BOX_LOG_DIR}/${component}.log"
    printf '%s\n' "${log_line}" >>"${log_file}" 2>/dev/null || true
  fi
}

require_cmd() {
  local cmd="${1:?missing command name}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log "ERROR" "common" "E_MISSING_CMD" "required command not found: ${cmd}"
    return 127
  fi
}

require_root() {
  if [[ "${BOX_UNSAFE_SKIP_ROOT_CHECK:-0}" == "1" ]]; then
    return 0
  fi
  if [[ "${EUID}" -ne 0 ]]; then
    log "ERROR" "common" "E_ROOT_REQUIRED" "this action requires root privileges"
    return 1
  fi
}

json_escape() {
  local raw="${1:-}"
  raw="${raw//\\/\\\\}"
  raw="${raw//\"/\\\"}"
  raw="${raw//$'\n'/\\n}"
  raw="${raw//$'\r'/\\r}"
  raw="${raw//$'\t'/\\t}"
  printf '%s' "${raw}"
}

json_pair() {
  local key="${1:?missing key}"
  local value="${2:-}"
  printf '"%s":"%s"' "$(json_escape "${key}")" "$(json_escape "${value}")"
}

json_num_pair() {
  local key="${1:?missing key}"
  local value="${2:-0}"
  printf '"%s":%s' "$(json_escape "${key}")" "${value}"
}

json_bool_pair() {
  local key="${1:?missing key}"
  local value="${2:-false}"
  if [[ "${value}" == "true" || "${value}" == "1" ]]; then
    printf '"%s":true' "$(json_escape "${key}")"
  else
    printf '"%s":false' "$(json_escape "${key}")"
  fi
}

lock_path_for() {
  local name="${1:?missing lock name}"
  init_runtime_paths
  printf '%s/%s.lock\n' "${BOX_LOCK_DIR}" "${name}"
}

with_lock() {
  local lock_name="${1:?missing lock name}"
  local timeout_sec="${2:?missing lock timeout}"
  shift 2
  local lock_file fd rc

  lock_file="$(lock_path_for "${lock_name}")"
  exec {fd}>"${lock_file}"
  if ! flock -w "${timeout_sec}" "${fd}"; then
    log "ERROR" "common" "E_LOCK_TIMEOUT" "lock timeout: ${lock_name}"
    exec {fd}>&-
    return 1
  fi

  "$@"
  rc=$?
  flock -u "${fd}" || true
  exec {fd}>&-
  return "${rc}"
}

try_lock() {
  local lock_name="${1:?missing lock name}"
  local timeout_sec="${2:-0}"
  local lock_file fd

  lock_file="$(lock_path_for "${lock_name}")"
  exec {fd}>"${lock_file}"
  if ! flock -w "${timeout_sec}" "${fd}"; then
    exec {fd}>&-
    return 1
  fi
  flock -u "${fd}" || true
  exec {fd}>&-
  return 0
}

is_pid_alive() {
  local pid="${1:-}"
  [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null
}

read_pid_file() {
  local pid_file="${1:?missing pid file}"
  if [[ -f "${pid_file}" ]]; then
    tr -d '[:space:]' <"${pid_file}"
  fi
}
