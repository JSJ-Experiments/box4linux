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
BOX_TRACE_COMMANDS="${BOX_TRACE_COMMANDS:-0}"

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
  local escaped_message ts log_line log_file

  escaped_message="${message//\\/\\\\}"
  escaped_message="${escaped_message//\"/\\\"}"
  escaped_message="${escaped_message//$'\n'/\\n}"
  escaped_message="${escaped_message//$'\r'/\\r}"
  escaped_message="${escaped_message//$'\t'/\\t}"

  ts="$(timestamp_utc)"
  log_line="ts=${ts} level=${level} component=${component} event_id=${event_id} msg=\"${escaped_message}\""
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

trace_cmd() {
  local component="${1:-trace}"
  shift || true
  if [[ "${BOX_TRACE_COMMANDS}" == "1" ]]; then
    local cmd
    printf -v cmd '%q ' "$@"
    log "DEBUG" "${component}" "TRACE_CMD" "action=${BOX_TRACE_ACTION:-unknown} cmd=${cmd% }"
  fi
}

trace_external_command() {
  local raw="${1:-}"
  local trimmed token kind unresolved_cmd=0

  [[ -n "${raw}" ]] || return 0

  trimmed="${raw#"${raw%%[![:space:]]*}"}"
  case "${trimmed}" in
    [A-Za-z_]*=*) return 0 ;;
  esac
  while [[ -n "${trimmed}" ]]; do
    token="${trimmed%%[[:space:]]*}"
    if [[ "${token}" == *=* ]]; then
      trimmed="${trimmed#"${token}"}"
      trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
      continue
    fi
    break
  done

  token="${trimmed%%[[:space:];|&]*}"
  [[ -n "${token}" ]] || return 0
  case "${token}" in
    awk|date|mkdir)
      return 0
      ;;
  esac

  case "${token}" in
    \$*|\"\$*|\'\$*)
      unresolved_cmd=1
      ;;
  esac
  if [[ "${unresolved_cmd}" == "0" ]]; then
    kind="$(type -t -- "${token}" 2>/dev/null || true)"
    [[ "${kind}" == "file" ]] || return 0
  fi

  log "DEBUG" "${BOX_TRACE_COMPONENT:-trace}" "TRACE_CMD" \
    "action=${BOX_TRACE_ACTION:-unknown} cmd=${raw}"
}

enable_command_trace() {
  local component="${1:-trace}"
  local action="${2:-unknown}"
  if [[ "${BOX_TRACE_COMMANDS}" != "1" ]]; then
    return 0
  fi
  BOX_TRACE_COMPONENT="${component}"
  BOX_TRACE_ACTION="${action}"
  export BOX_TRACE_COMPONENT BOX_TRACE_ACTION
  if shopt -qo functrace; then
    BOX_TRACE_FUNCTRACE_RESTORE="keep"
  else
    BOX_TRACE_FUNCTRACE_RESTORE="unset"
    set -o functrace
  fi
  export BOX_TRACE_FUNCTRACE_RESTORE
  trap 'if [[ "${_BOX_TRACE_GUARD:-0}" == "0" ]]; then _BOX_TRACE_GUARD=1; trace_external_command "${BASH_COMMAND:-}"; _BOX_TRACE_GUARD=0; fi' DEBUG
}

disable_command_trace() {
  if [[ "${BOX_TRACE_COMMANDS}" != "1" ]]; then
    return 0
  fi
  trap - DEBUG
  if [[ "${BOX_TRACE_FUNCTRACE_RESTORE:-keep}" == "unset" ]]; then
    set +o functrace
  fi
  unset BOX_TRACE_COMPONENT BOX_TRACE_ACTION
  unset BOX_TRACE_FUNCTRACE_RESTORE
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
