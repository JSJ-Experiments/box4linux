#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

source "${BOX_LIB_DIR}/supervisor/adapter_mihomo.sh"
source "${BOX_LIB_DIR}/supervisor/adapter_sing_box.sh"
source "${BOX_LIB_DIR}/firewall/firewall.sh"

service_pid_file() {
  init_runtime_paths
  printf '%s/box.pid\n' "${BOX_RUN_DIR}"
}

service_state_file() {
  init_runtime_paths
  printf '%s/runtime.snapshot.json\n' "${BOX_RUN_DIR}"
}

rendered_config_path() {
  init_runtime_paths
  local core_dir="${BOX_RUN_DIR}/rendered/${BOX_CORE}"
  mkdir -p "${core_dir}"
  if [[ "${BOX_CORE}" == "sing-box" ]]; then
    printf '%s/config.json\n' "${core_dir}"
  else
    printf '%s/config.yaml\n' "${core_dir}"
  fi
}

render_runtime_config() {
  local rendered_path="${1:?missing rendered config path}"
  if [[ -f "${BOX_CORE_CONFIG_SOURCE}" ]]; then
    cp -f "${BOX_CORE_CONFIG_SOURCE}" "${rendered_path}"
  else
    # TODO(phase-2): deterministic core-specific config mutator.
    if [[ "${BOX_CORE}" == "sing-box" ]]; then
      printf '{ "log": { "level": "warn" } }\n' >"${rendered_path}"
    else
      printf 'mixed-port: %s\n' "${BOX_REDIR_PORT}" >"${rendered_path}"
    fi
  fi
}

resolve_core_bin() {
  case "${BOX_CORE}" in
    mihomo) adapter_mihomo_resolve_bin ;;
    sing-box) adapter_sing_box_resolve_bin ;;
    *)
      log "ERROR" "supervisor" "E_CORE_UNSUPPORTED" "unsupported core: ${BOX_CORE}"
      return "${E_CORE_START}"
      ;;
  esac
}

check_core_config() {
  local bin="${1:?missing core binary path}"
  local rendered_path="${2:?missing rendered config path}"
  local workdir="${3:?missing workdir}"

  case "${BOX_CORE}" in
    mihomo) adapter_mihomo_check_config "${bin}" "${rendered_path}" "${workdir}" ;;
    sing-box) adapter_sing_box_check_config "${bin}" "${rendered_path}" "${workdir}" ;;
    *)
      return "${E_CORE_START}"
      ;;
  esac
}

start_core_process() {
  local bin="${1:?missing core binary path}"
  local rendered_path="${2:?missing rendered config path}"
  local workdir="${3:?missing workdir}"
  local service_log="${BOX_LOG_DIR}/service.log"

  case "${BOX_CORE}" in
    mihomo) adapter_mihomo_start "${bin}" "${rendered_path}" "${workdir}" "${service_log}" ;;
    sing-box) adapter_sing_box_start "${bin}" "${rendered_path}" "${workdir}" "${service_log}" ;;
    *)
      return "${E_CORE_START}"
      ;;
  esac
}

write_runtime_snapshot() {
  local status="${1:?missing status}"
  local pid="${2:-0}"
  local state_file
  state_file="$(service_state_file)"

  cat >"${state_file}" <<EOF
{
  "timestamp": "$(timestamp_utc)",
  "status": "${status}",
  "core": "${BOX_CORE}",
  "network_mode": "${BOX_NETWORK_MODE}",
  "pid": "${pid}"
}
EOF
}

service_start_locked() {
  require_root || return 1
  load_config
  init_runtime_paths

  local pid_file existing_pid core_bin rendered_path new_pid
  pid_file="$(service_pid_file)"
  existing_pid="$(read_pid_file "${pid_file}" || true)"
  if is_pid_alive "${existing_pid}"; then
    log "INFO" "service" "SERVICE_ALREADY_RUNNING" "service already running pid=${existing_pid}"
    write_runtime_snapshot "healthy" "${existing_pid}"
    return 0
  fi

  core_bin="$(resolve_core_bin)" || {
    log "ERROR" "service" "E_CORE_BINARY" "core binary not found for ${BOX_CORE}"
    return "${E_CORE_START}"
  }

  mkdir -p "${BOX_CORE_WORKDIR}"
  rendered_path="$(rendered_config_path)"
  render_runtime_config "${rendered_path}"

  if ! check_core_config "${core_bin}" "${rendered_path}" "${BOX_CORE_WORKDIR}"; then
    log "ERROR" "service" "E_CORE_CONFIG" "core configuration check failed"
    return "${E_CORE_START}"
  fi

  new_pid="$(start_core_process "${core_bin}" "${rendered_path}" "${BOX_CORE_WORKDIR}")"
  sleep 1
  if ! is_pid_alive "${new_pid}"; then
    log "ERROR" "service" "E_CORE_START" "core process exited immediately"
    write_runtime_snapshot "failed" "0"
    return "${E_CORE_START}"
  fi

  printf '%s\n' "${new_pid}" >"${pid_file}"
  write_runtime_snapshot "starting" "${new_pid}"

  if ! firewall_enable; then
    log "ERROR" "service" "E_FIREWALL_APPLY" "firewall enable failed; stopping core"
    kill -TERM "${new_pid}" >/dev/null 2>&1 || true
    rm -f "${pid_file}"
    write_runtime_snapshot "failed" "0"
    return "${E_FIREWALL_APPLY}"
  fi

  write_runtime_snapshot "healthy" "${new_pid}"
  log "INFO" "service" "SERVICE_STARTED" "service started core=${BOX_CORE} pid=${new_pid}"
}

service_stop_locked() {
  require_root || return 1
  load_config
  init_runtime_paths

  local pid_file pid
  pid_file="$(service_pid_file)"
  pid="$(read_pid_file "${pid_file}" || true)"

  firewall_disable || true

  if is_pid_alive "${pid}"; then
    kill -TERM "${pid}" >/dev/null 2>&1 || true
    sleep 1
    if is_pid_alive "${pid}"; then
      kill -KILL "${pid}" >/dev/null 2>&1 || true
    fi
  fi

  rm -f "${pid_file}"
  write_runtime_snapshot "stopped" "0"
  log "INFO" "service" "SERVICE_STOPPED" "service stopped"
}

service_start() {
  with_lock "service" 30 service_start_locked
}

service_stop() {
  with_lock "service" 30 service_stop_locked
}

service_restart() {
  service_stop
  service_start
}

service_status() {
  load_config || true
  init_runtime_paths

  local pid_file pid status
  pid_file="$(service_pid_file)"
  pid="$(read_pid_file "${pid_file}" || true)"

  if is_pid_alive "${pid}"; then
    status="healthy"
  else
    status="stopped"
  fi

  printf 'status=%s\n' "${status}"
  printf 'core=%s\n' "${BOX_CORE}"
  printf 'pid=%s\n' "${pid:-0}"
  printf 'mode=%s\n' "${BOX_NETWORK_MODE}"
  printf 'config=%s\n' "${BOX_CONFIG_FILE:-none}"
}

supervisor_cmd() {
  local action="${1:-}"
  case "${action}" in
    start) service_start ;;
    stop) service_stop ;;
    restart) service_restart ;;
    status) service_status ;;
    *)
      printf 'usage: boxctl service <start|stop|restart|status>\n' >&2
      return 2
      ;;
  esac
}
