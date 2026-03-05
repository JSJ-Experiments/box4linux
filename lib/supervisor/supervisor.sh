#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

source "${BOX_LIB_DIR}/supervisor/adapter_mihomo.sh"
source "${BOX_LIB_DIR}/supervisor/adapter_sing_box.sh"
source "${BOX_LIB_DIR}/supervisor/mutator_mihomo.sh"
source "${BOX_LIB_DIR}/supervisor/mutator_sing_box.sh"
source "${BOX_LIB_DIR}/firewall/firewall.sh"

service_pid_file() {
  init_runtime_paths
  printf '%s/box.pid\n' "${BOX_RUN_DIR}"
}

service_state_file() {
  init_runtime_paths
  printf '%s/runtime.snapshot.json\n' "${BOX_RUN_DIR}"
}

rendered_config_dir() {
  init_runtime_paths
  local core_dir="${BOX_RUN_DIR}/rendered/${BOX_CORE}"
  mkdir -p "${core_dir}"
  printf '%s\n' "${core_dir}"
}

rendered_config_path() {
  local core_dir
  core_dir="$(rendered_config_dir)"
  if [[ "${BOX_CORE}" == "sing-box" ]]; then
    printf '%s/config.json\n' "${core_dir}"
  else
    printf '%s/config.yaml\n' "${core_dir}"
  fi
}

runtime_run_dir_readonly() {
  if [[ -d "${BOX_RUN_DIR}" ]]; then
    printf '%s\n' "${BOX_RUN_DIR}"
  elif [[ -d "${BOX_DEV_RUN_DIR}" ]]; then
    printf '%s\n' "${BOX_DEV_RUN_DIR}"
  else
    printf '%s\n' "${BOX_RUN_DIR}"
  fi
}

service_pid_file_readonly() {
  local run_dir
  run_dir="$(runtime_run_dir_readonly)"
  printf '%s/box.pid\n' "${run_dir}"
}

rendered_config_expected_path() {
  local run_dir core_dir
  run_dir="$(runtime_run_dir_readonly)"
  core_dir="${run_dir}/rendered/${BOX_CORE}"
  if [[ "${BOX_CORE}" == "sing-box" ]]; then
    printf '%s/config.json\n' "${core_dir}"
  else
    printf '%s/config.yaml\n' "${core_dir}"
  fi
}

render_runtime_config() {
  local rendered_path="${1:?missing rendered config path}"
  case "${BOX_CORE}" in
    mihomo) mutator_mihomo_render_overlay "${BOX_CORE_CONFIG_SOURCE}" "${rendered_path}" ;;
    sing-box) mutator_sing_box_render_overlay "${BOX_CORE_CONFIG_SOURCE}" "${rendered_path}" ;;
    *)
      log "ERROR" "service" "E_CORE_UNSUPPORTED" "no mutator for core=${BOX_CORE}"
      return "${E_CORE_START}"
      ;;
  esac
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
  local rendered_config="${3:-}"
  local state_file
  state_file="$(service_state_file)"

  cat >"${state_file}" <<EOF
{
  "timestamp": "$(timestamp_utc)",
  "status": "${status}",
  "core": "${BOX_CORE}",
  "network_mode": "${BOX_NETWORK_MODE}",
  "dns_hijack_mode": "${BOX_DNS_HIJACK_MODE}",
  "pid": "${pid}",
  "rendered_config": "$(json_escape "${rendered_config}")",
  "config_source": "$(json_escape "${BOX_CONFIG_FILE:-}")"
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
    rendered_path="$(rendered_config_path)"
    log "INFO" "service" "SERVICE_ALREADY_RUNNING" "service already running pid=${existing_pid}"
    write_runtime_snapshot "healthy" "${existing_pid}" "${rendered_path}"
    return 0
  fi

  core_bin="$(resolve_core_bin)" || {
    log "ERROR" "service" "E_CORE_BINARY" "core binary not found for ${BOX_CORE}"
    write_runtime_snapshot "failed" "0" ""
    return "${E_CORE_START}"
  }

  mkdir -p "${BOX_CORE_WORKDIR}"
  rendered_path="$(rendered_config_path)"
  render_runtime_config "${rendered_path}"

  if ! check_core_config "${core_bin}" "${rendered_path}" "${BOX_CORE_WORKDIR}"; then
    log "ERROR" "service" "E_CORE_CONFIG" "core configuration check failed for ${rendered_path}"
    write_runtime_snapshot "failed" "0" "${rendered_path}"
    return "${E_CORE_START}"
  fi

  new_pid="$(start_core_process "${core_bin}" "${rendered_path}" "${BOX_CORE_WORKDIR}")"
  sleep 1
  if ! is_pid_alive "${new_pid}"; then
    log "ERROR" "service" "E_CORE_START" "core process exited immediately"
    write_runtime_snapshot "failed" "0" "${rendered_path}"
    return "${E_CORE_START}"
  fi

  printf '%s\n' "${new_pid}" >"${pid_file}"
  write_runtime_snapshot "starting" "${new_pid}" "${rendered_path}"

  if ! firewall_enable; then
    log "ERROR" "service" "E_FIREWALL_APPLY" "firewall enable failed; stopping core"
    kill -TERM "${new_pid}" >/dev/null 2>&1 || true
    rm -f "${pid_file}"
    write_runtime_snapshot "failed" "0" "${rendered_path}"
    return "${E_FIREWALL_APPLY}"
  fi

  write_runtime_snapshot "healthy" "${new_pid}" "${rendered_path}"
  log "INFO" "service" "SERVICE_STARTED" "service started core=${BOX_CORE} pid=${new_pid} overlay=${rendered_path}"
}

service_stop_locked() {
  require_root || return 1
  load_config
  init_runtime_paths

  local pid_file pid rendered_path
  pid_file="$(service_pid_file)"
  pid="$(read_pid_file "${pid_file}" || true)"
  rendered_path="$(rendered_config_path)"

  firewall_disable || true

  if is_pid_alive "${pid}"; then
    kill -TERM "${pid}" >/dev/null 2>&1 || true
    sleep 1
    if is_pid_alive "${pid}"; then
      kill -KILL "${pid}" >/dev/null 2>&1 || true
    fi
  fi

  rm -f "${pid_file}"
  write_runtime_snapshot "stopped" "0" "${rendered_path}"
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

service_print_status_text() {
  local status="${1:?missing status}"
  local pid="${2:-0}"
  local rendered_path="${3:-}"
  printf 'status=%s\n' "${status}"
  printf 'core=%s\n' "${BOX_CORE}"
  printf 'pid=%s\n' "${pid:-0}"
  printf 'mode=%s\n' "${BOX_NETWORK_MODE}"
  printf 'dns_hijack_mode=%s\n' "${BOX_DNS_HIJACK_MODE}"
  printf 'rendered_config=%s\n' "${rendered_path}"
  printf 'config=%s\n' "${BOX_CONFIG_FILE:-none}"
}

service_print_status_json() {
  local status="${1:?missing status}"
  local pid="${2:-0}"
  local rendered_path="${3:-}"
  printf '{%s,%s,%s,%s,%s,%s,%s}\n' \
    "$(json_pair "status" "${status}")" \
    "$(json_pair "core" "${BOX_CORE}")" \
    "$(json_num_pair "pid" "${pid:-0}")" \
    "$(json_pair "mode" "${BOX_NETWORK_MODE}")" \
    "$(json_pair "dns_hijack_mode" "${BOX_DNS_HIJACK_MODE}")" \
    "$(json_pair "rendered_config" "${rendered_path}")" \
    "$(json_pair "config" "${BOX_CONFIG_FILE:-none}")"
}

service_status() {
  local previous_log_to_file="${BOX_LOG_TO_FILE:-1}"
  BOX_LOG_TO_FILE=0
  load_config || true
  BOX_LOG_TO_FILE="${previous_log_to_file}"

  local pid_file pid status rendered_path
  pid_file="$(service_pid_file_readonly)"
  pid="$(read_pid_file "${pid_file}" || true)"
  rendered_path="$(rendered_config_expected_path)"

  if is_pid_alive "${pid}"; then
    status="healthy"
  else
    status="stopped"
    pid="0"
  fi

  if [[ "${BOX_OUTPUT_FORMAT}" == "json" ]]; then
    service_print_status_json "${status}" "${pid}" "${rendered_path}"
  else
    service_print_status_text "${status}" "${pid}" "${rendered_path}"
  fi
}

supervisor_cmd() {
  local action="${1:-}"
  case "${action}" in
    start) service_start ;;
    stop) service_stop ;;
    restart) service_restart ;;
    status) service_status ;;
    *)
      printf 'usage: boxctl service <start|stop|restart|status> [--json]\n' >&2
      return 2
      ;;
  esac
}
