#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

source "${BOX_LIB_DIR}/supervisor/adapter_mihomo.sh"
source "${BOX_LIB_DIR}/supervisor/adapter_sing_box.sh"
source "${BOX_LIB_DIR}/supervisor/mutator_mihomo.sh"
source "${BOX_LIB_DIR}/supervisor/mutator_sing_box.sh"
source "${BOX_LIB_DIR}/supervisor/resolver_runtime.sh"
source "${BOX_LIB_DIR}/firewall/firewall.sh"

service_pid_file() {
  init_runtime_paths
  printf '%s/box.pid\n' "${BOX_RUN_DIR}"
}

service_monitor_pid_file() {
  init_runtime_paths
  printf '%s/service-monitor.pid\n' "${BOX_RUN_DIR}"
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

service_monitor_ip_cmd() {
  printf '%s\n' "${BOX_IP_CMD:-ip}"
}

service_monitor_event_source() {
  local ip_tool

  if [[ -n "${BOX_SERVICE_EVENT_FILE:-}" ]]; then
    mkdir -p "$(dirname "${BOX_SERVICE_EVENT_FILE}")"
    touch "${BOX_SERVICE_EVENT_FILE}"
    tail -n 0 -F "${BOX_SERVICE_EVENT_FILE}"
    return 0
  fi

  ip_tool="$(service_monitor_ip_cmd)"
  exec "${ip_tool}" monitor link route address
}

service_monitor_enabled() {
  [[ "${BOX_CORE}" == "mihomo" ]] || return 1
  [[ "${#BOX_CAMPUS_DNS_SUFFIXES[@]}" -gt 0 ]] || return 1
  return 0
}

service_network_signature() {
  local active_mode iface dns_csv=""
  local -a dns_servers=()

  if ! service_monitor_enabled; then
    return 1
  fi

  active_mode="$(box_detect_org_dns_mode)"
  if [[ "${active_mode}" == "org" ]]; then
    iface="$(box_org_dns_status_iface || true)"
    mapfile -t dns_servers < <(box_org_dns_status_servers || true)
    if [[ "${#dns_servers[@]}" -gt 0 ]]; then
      local IFS=,
      dns_csv="${dns_servers[*]}"
    fi
    printf 'org|%s|%s\n' "${iface}" "${dns_csv}"
    return 0
  fi

  printf '%s\n' "${active_mode}"
}

service_org_dns_mode_configured() {
  box_org_dns_mode_configured
}

service_org_dns_mode_active() {
  box_detect_org_dns_mode
}

service_org_dns_iface() {
  box_org_dns_status_iface
}

service_org_dns_servers_csv() {
  local -a servers=()
  mapfile -t servers < <(box_org_dns_status_servers || true)
  join_by "," "${servers[@]}"
}

service_org_dns_suffixes_csv() {
  local -a suffixes=()
  mapfile -t suffixes < <(box_org_dns_status_suffixes || true)
  join_by "," "${suffixes[@]}"
}

service_org_dns_probe_hosts_csv() {
  local -a hosts=()
  mapfile -t hosts < <(box_org_dns_status_probe_hosts || true)
  join_by "," "${hosts[@]}"
}

service_monitor_cleanup() {
  local pid_file current_pid
  pid_file="$(service_monitor_pid_file)"
  current_pid="$(read_pid_file "${pid_file}" || true)"
  if [[ "${current_pid}" == "$$" ]]; then
    rm -f "${pid_file}"
  fi
}

service_handle_network_signature_change() {
  local previous_sig="${1:-}"
  local current_sig="${2:-}"
  local event_ts="${3:-$(timestamp_utc)}"

  if [[ "${current_sig}" == "${previous_sig}" ]]; then
    return 1
  fi

  log "INFO" "service" "SERVICE_NETWORK_CHANGE" \
    "network signature changed old=${previous_sig:-none} new=${current_sig:-none} event_ts=${event_ts}"
  "${BOXCTL_SELF_PATH}" service reload >>"${BOX_LOG_DIR}/service.log" 2>&1 || \
    log "WARN" "service" "SERVICE_NETWORK_RELOAD_FAILED" "service reload failed after network change"
  "${BOXCTL_SELF_PATH}" firewall renew >>"${BOX_LOG_DIR}/service.log" 2>&1 || \
    log "WARN" "service" "SERVICE_NETWORK_FIREWALL_RENEW_FAILED" "firewall renew failed after network change"
  return 0
}

service_monitor_loop() {
  local pid_file line pending_ts="" next_line event_pid="" previous_sig="" current_sig=""
  local debounce_sec="${BOX_SERVICE_MONITOR_DEBOUNCE_SECONDS:-2}"

  require_root || return 1
  load_config
  init_runtime_paths

  if ! service_monitor_enabled; then
    return 0
  fi

  pid_file="$(service_monitor_pid_file)"
  printf '%s\n' "$$" >"${pid_file}"
  previous_sig="$(service_network_signature || true)"

  coproc SERVICE_EVENTS { service_monitor_event_source; }
  event_pid="${SERVICE_EVENTS_PID:-}"
  trap '[[ -n "'"${event_pid}"'" ]] && kill "'"${event_pid}"'" >/dev/null 2>&1 || true; service_monitor_cleanup; exit 0' EXIT INT TERM

  while true; do
    if IFS= read -r -t 1 line <&"${SERVICE_EVENTS[0]}"; then
      pending_ts="$(timestamp_utc)"
      while IFS= read -r -t "${debounce_sec}" next_line <&"${SERVICE_EVENTS[0]}"; do
        pending_ts="$(timestamp_utc)"
      done

      current_sig="$(service_network_signature || true)"
      if service_handle_network_signature_change "${previous_sig}" "${current_sig}" "${pending_ts}"; then
        previous_sig="${current_sig}"
      fi
    fi
  done
}

service_spawn_monitor() {
  local pid_file pid

  if ! service_monitor_enabled; then
    return 0
  fi

  pid_file="$(service_monitor_pid_file)"
  pid="$(read_pid_file "${pid_file}" || true)"
  if is_pid_alive "${pid}"; then
    return 0
  fi

  pid="$(spawn_detached_process "${BOX_LOG_DIR}/service.log" "${BOXCTL_SELF_PATH}" service monitor)"
  printf '%s\n' "${pid}" >"${pid_file}"
  log "INFO" "service" "SERVICE_MONITOR_STARTED" "service monitor started pid=${pid}"
}

service_stop_monitor() {
  local pid_file pid
  pid_file="$(service_monitor_pid_file)"
  pid="$(read_pid_file "${pid_file}" || true)"
  if is_pid_alive "${pid}"; then
    kill -TERM "${pid}" >/dev/null 2>&1 || true
    sleep 1
    if is_pid_alive "${pid}"; then
      kill -KILL "${pid}" >/dev/null 2>&1 || true
    fi
  fi
  rm -f "${pid_file}"
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
      log "ERROR" "service" "E_CORE_UNSUPPORTED" "unsupported core during config check: ${BOX_CORE}"
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

discover_core_pid() {
  local rendered_path="${1:?missing rendered config path}"
  local workdir="${2:?missing workdir}"
  local discovered=""
  case "${BOX_CORE}" in
    mihomo)
      discovered="$(ps -eo pid=,args= | awk -v rendered="${rendered_path}" '
        index($0, "mihomo") > 0 && index($0, rendered) > 0 { pid=$1 }
        END { if (pid != "") print pid }
      ' | tail -n 1 || true)"
      ;;
    sing-box)
      discovered="$(ps -eo pid=,args= | awk -v rendered="${rendered_path}" '
        index($0, "sing-box") > 0 && index($0, rendered) > 0 { pid=$1 }
        END { if (pid != "") print pid }
      ' | tail -n 1 || true)"
      ;;
  esac
  printf '%s\n' "${discovered}"
}

write_runtime_snapshot() {
  local status="${1:?missing status}"
  local pid_raw="${2:-0}"
  local pid_num="0"
  local rendered_config="${3:-}"
  local state_file
  case "${pid_raw}" in
    ''|*[!0-9]*) pid_num="0" ;;
    *) pid_num="${pid_raw}" ;;
  esac
  state_file="$(service_state_file)"

  cat >"${state_file}" <<EOF
{
  "timestamp": "$(timestamp_utc)",
  "status": "${status}",
  "core": "${BOX_CORE}",
  "network_mode": "${BOX_NETWORK_MODE}",
  "dns_hijack_mode": "${BOX_DNS_HIJACK_MODE}",
  "pid": ${pid_num},
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
    resolver_runtime_apply || true
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
  discovered_pid="$(discover_core_pid "${rendered_path}" "${BOX_CORE_WORKDIR}" || true)"
  if [[ -n "${discovered_pid}" ]] && is_pid_alive "${discovered_pid}"; then
    new_pid="${discovered_pid}"
  elif ! is_pid_alive "${new_pid}"; then
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

  if ! resolver_runtime_apply; then
    log "ERROR" "service" "E_RESOLVER_APPLY" "resolver ownership apply failed; stopping core"
    firewall_disable || true
    kill -TERM "${new_pid}" >/dev/null 2>&1 || true
    rm -f "${pid_file}"
    resolver_runtime_restore || true
    write_runtime_snapshot "failed" "0" "${rendered_path}"
    return "${E_CORE_START}"
  fi

  write_runtime_snapshot "healthy" "${new_pid}" "${rendered_path}"
  service_spawn_monitor || true
  log "INFO" "service" "SERVICE_STARTED" "service started core=${BOX_CORE} pid=${new_pid} overlay=${rendered_path}"
}

service_stop_locked() {
  require_root || return 1
  load_config
  init_runtime_paths

  local pid_file pid rendered_path
  pid_file="$(service_pid_file)"
  rendered_path="$(rendered_config_path)"
  pid="$(read_pid_file "${pid_file}" || true)"
  if ! is_pid_alive "${pid}"; then
    pid="$(discover_core_pid "${rendered_path}" "${BOX_CORE_WORKDIR}" || true)"
  fi

  service_stop_monitor
  firewall_disable || true
  resolver_runtime_restore || true

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

service_restart_locked() {
  service_stop_locked
  service_start_locked
}

service_restart() {
  with_lock "service" 30 service_restart_locked
}

service_reload_locked() {
  local rc=0 rendered_path core_bin
  require_root || return 1
  load_config
  init_runtime_paths
  rendered_path="$(rendered_config_path)"
  core_bin="$(resolve_core_bin)" || return "${E_CORE_START}"
  render_runtime_config "${rendered_path}"
  if ! check_core_config "${core_bin}" "${rendered_path}" "${BOX_CORE_WORKDIR}"; then
    log "ERROR" "service" "E_CORE_CONFIG" "core configuration check failed for ${rendered_path}"
    return "${E_CORE_START}"
  fi
  case "${BOX_CORE}" in
    mihomo)
      adapter_mihomo_reload "${rendered_path}" "${BOX_CORE_WORKDIR}" "${core_bin}" >/dev/null 2>&1 || rc=$?
      ;;
    sing-box)
      adapter_sing_box_reload "${rendered_path}" "${BOX_CORE_WORKDIR}" "${core_bin}" >/dev/null 2>&1 || rc=$?
      ;;
    *)
      rc="${E_CORE_START}"
      ;;
  esac

  if [[ "${rc}" -eq 0 ]]; then
    resolver_runtime_apply || true
    log "INFO" "service" "SERVICE_RELOADED" "service reloaded core=${BOX_CORE}"
    return 0
  fi

  log "WARN" "service" "SERVICE_RELOAD_FALLBACK" "reload unsupported or failed for core=${BOX_CORE}; restarting"
  service_restart_locked
}

service_reload() {
  with_lock "service" 30 service_reload_locked
}

service_print_status_text() {
  local status="${1:?missing status}"
  local pid="${2:-0}"
  local rendered_path="${3:-}"
  local -a org_dns_servers=() org_dns_suffixes=() org_dns_probe_hosts=()
  mapfile -t org_dns_servers < <(box_org_dns_status_servers || true)
  mapfile -t org_dns_suffixes < <(box_org_dns_status_suffixes || true)
  mapfile -t org_dns_probe_hosts < <(box_org_dns_status_probe_hosts || true)
  printf 'status=%s\n' "${status}"
  printf 'core=%s\n' "${BOX_CORE}"
  printf 'pid=%s\n' "${pid:-0}"
  printf 'mode=%s\n' "${BOX_NETWORK_MODE}"
  printf 'dns_hijack_mode=%s\n' "${BOX_DNS_HIJACK_MODE}"
  printf 'dns_enhanced_mode=%s\n' "${BOX_DNS_ENHANCED_MODE}"
  printf 'ipv6_enabled=%s\n' "${BOX_IPV6_ENABLED}"
  printf 'ipv6_effective_mode=%s\n' "$(firewall_ipv6_effective_mode)"
  printf 'org_dns_mode_configured=%s\n' "$(service_org_dns_mode_configured)"
  printf 'org_dns_mode_active=%s\n' "$(service_org_dns_mode_active)"
  printf 'org_dns_iface=%s\n' "$(service_org_dns_iface)"
  printf 'org_dns_servers=%s\n' "$(join_by "," "${org_dns_servers[@]}")"
  printf 'org_dns_suffixes=%s\n' "$(join_by "," "${org_dns_suffixes[@]}")"
  printf 'org_dns_probe_hosts=%s\n' "$(join_by "," "${org_dns_probe_hosts[@]}")"
  printf 'rendered_config=%s\n' "${rendered_path}"
  printf 'config=%s\n' "${BOX_CONFIG_FILE:-none}"
}

service_print_status_json() {
  local status="${1:?missing status}"
  local pid="${2:-0}"
  local rendered_path="${3:-}"
  local -a org_dns_servers=() org_dns_suffixes=() org_dns_probe_hosts=()
  mapfile -t org_dns_servers < <(box_org_dns_status_servers || true)
  mapfile -t org_dns_suffixes < <(box_org_dns_status_suffixes || true)
  mapfile -t org_dns_probe_hosts < <(box_org_dns_status_probe_hosts || true)
  printf '{%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s}\n' \
    "$(json_pair "status" "${status}")" \
    "$(json_pair "core" "${BOX_CORE}")" \
    "$(json_num_pair "pid" "${pid:-0}")" \
    "$(json_pair "mode" "${BOX_NETWORK_MODE}")" \
    "$(json_pair "dns_hijack_mode" "${BOX_DNS_HIJACK_MODE}")" \
    "$(json_pair "dns_enhanced_mode" "${BOX_DNS_ENHANCED_MODE}")" \
    "$(json_bool_pair "ipv6_enabled" "${BOX_IPV6_ENABLED}")" \
    "$(json_pair "ipv6_effective_mode" "$(firewall_ipv6_effective_mode)")" \
    "$(json_pair "org_dns_mode_configured" "$(service_org_dns_mode_configured)")" \
    "$(json_pair "org_dns_mode_active" "$(service_org_dns_mode_active)")" \
    "$(json_pair "org_dns_iface" "$(service_org_dns_iface)")" \
    "$(json_array_pair "org_dns_servers" "${org_dns_servers[@]}")" \
    "$(json_array_pair "org_dns_suffixes" "${org_dns_suffixes[@]}")" \
    "$(json_array_pair "org_dns_probe_hosts" "${org_dns_probe_hosts[@]}")" \
    "$(json_pair "rendered_config" "${rendered_path}")" \
    "$(json_pair "config" "${BOX_CONFIG_FILE:-none}")"
}

service_status() {
  local previous_log_to_file="${BOX_LOG_TO_FILE:-1}"
  BOX_LOG_TO_FILE=0
  if ! load_config; then
    BOX_LOG_TO_FILE="${previous_log_to_file}"
    return "${E_CONFIG}"
  fi
  BOX_LOG_TO_FILE="${previous_log_to_file}"

  local pid_file pid status rendered_path
  pid_file="$(service_pid_file_readonly)"
  pid="$(read_pid_file "${pid_file}" || true)"
  rendered_path="$(rendered_config_expected_path)"
  if ! is_pid_alive "${pid}"; then
    pid="$(discover_core_pid "${rendered_path}" "${BOX_CORE_WORKDIR}" || true)"
  fi

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
    reload) service_reload ;;
    status) service_status ;;
    monitor) service_monitor_loop ;;
    *)
      printf 'usage: boxctl service <start|stop|restart|reload|status> [--json]\n' >&2
      return 2
      ;;
  esac
}
