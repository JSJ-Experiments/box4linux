#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

source "${BOX_LIB_DIR}/policy/context.sh"
source "${BOX_LIB_DIR}/policy/engine.sh"

policy_pid_file() {
  init_runtime_paths
  printf '%s/policy.pid\n' "${BOX_RUN_DIR}"
}

policy_state_file() {
  init_runtime_paths
  printf '%s/policy.state\n' "${BOX_RUN_DIR}"
}

policy_refresh_pid_file() {
  init_runtime_paths
  printf '%s/policy-refresh.pid\n' "${BOX_RUN_DIR}"
}

policy_state_readonly_file() {
  local run_dir
  if [[ -d "${BOX_RUN_DIR}" ]]; then
    run_dir="${BOX_RUN_DIR}"
  elif [[ -d "${BOX_DEV_RUN_DIR}" ]]; then
    run_dir="${BOX_DEV_RUN_DIR}"
  else
    run_dir="${BOX_RUN_DIR}"
  fi
  printf '%s/policy.state\n' "${run_dir}"
}

policy_join_csv() {
  local IFS=,
  printf '%s' "$*"
}

policy_json_array() {
  local first=1 item
  printf '['
  for item in "$@"; do
    [[ -n "${item}" ]] || continue
    if [[ "${first}" == "0" ]]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$(json_escape "${item}")"
  done
  printf ']'
}

policy_active_ifaces_json() {
  local raw item
  local -a items=()

  raw="$(policy_snapshot_get "active_ifaces" "")"
  if [[ -z "${raw}" ]]; then
    printf '[]'
    return 0
  fi

  IFS=',' read -r -a items <<<"${raw}"
  for item in "${items[@]}"; do
    [[ -n "${item}" ]] || continue
    policy_json_array "${items[@]}"
    return 0
  done

  printf '[]'
}

policy_write_state() {
  local status="${1:?missing status}"
  local last_event="${2:-}"
  local last_event_ts="${3:-}"
  local last_refresh_ts="${4:-}"
  local state_file state_dir tmp_file

  state_file="$(policy_state_file)"
  state_dir="$(dirname "${state_file}")"
  tmp_file="$(mktemp "${state_dir}/policy.state.tmp.XXXXXX")"
  cat >"${tmp_file}" <<EOF
status=${status}
policy_enabled=${BOX_POLICY_ENABLED}
desired_state=${POLICY_DESIRED_STATE}
applied_state=${POLICY_APPLIED_STATE}
proxy_mode=${BOX_POLICY_PROXY_MODE}
debounce_seconds=${BOX_POLICY_DEBOUNCE_SECONDS}
watcher_pid=$$
watcher_running=true
active_ifaces=$(policy_join_csv "${POLICY_CTX_IFACES[@]}")
wifi_connected=${POLICY_CTX_WIFI_CONNECTED}
ssid=${POLICY_CTX_SSID}
bssid=${POLICY_CTX_BSSID}
disable_marker_present=$(if policy_disable_marker_present; then printf 'true'; else printf 'false'; fi)
last_reason=${POLICY_REASON}
last_error=${POLICY_LAST_ERROR}
last_event=${last_event}
last_event_ts=${last_event_ts}
last_refresh_ts=${last_refresh_ts}
timestamp=$(timestamp_utc)
EOF
  mv -f "${tmp_file}" "${state_file}"
}

policy_clear_state() {
  local state_file
  state_file="$(policy_state_file)"
  rm -f "${state_file}"
}

policy_read_state_value() {
  local key="${1:?missing key}"
  local state_file
  state_file="$(policy_state_readonly_file)"
  [[ -f "${state_file}" ]] || return 1
  awk -F= -v wanted="${key}" '$1==wanted {print substr($0, index($0, "=")+1); exit}' "${state_file}"
}

policy_snapshot_load() {
  local state_file line key value

  declare -gA POLICY_STATUS_SNAPSHOT=()
  state_file="$(policy_state_readonly_file)"
  [[ -f "${state_file}" ]] || return 0

  while IFS= read -r line; do
    [[ "${line}" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    POLICY_STATUS_SNAPSHOT["${key}"]="${value}"
  done <"${state_file}"
}

policy_snapshot_get() {
  local key="${1:?missing key}"
  local default_value="${2:-}"

  if [[ -v "POLICY_STATUS_SNAPSHOT[${key}]" ]]; then
    printf '%s' "${POLICY_STATUS_SNAPSHOT["${key}"]}"
  else
    printf '%s' "${default_value}"
  fi
}

policy_event_source() {
  local ip_tool

  if [[ -n "${BOX_POLICY_EVENT_FILE:-}" ]]; then
    mkdir -p "$(dirname "${BOX_POLICY_EVENT_FILE}")"
    touch "${BOX_POLICY_EVENT_FILE}"
    tail -n 0 -F "${BOX_POLICY_EVENT_FILE}"
    return 0
  fi

  ip_tool="$(policy_ip_cmd)"
  exec "${ip_tool}" monitor link route address
}

policy_monitor_cleanup() {
  local pid_file current_pid refresh_pid_file refresh_pid
  pid_file="$(policy_pid_file)"
  current_pid="$(read_pid_file "${pid_file}" || true)"
  if [[ "${current_pid}" == "$$" ]]; then
    rm -f "${pid_file}"
  fi
  refresh_pid_file="$(policy_refresh_pid_file)"
  refresh_pid="$(read_pid_file "${refresh_pid_file}" || true)"
  if [[ -n "${refresh_pid}" ]] && ! is_pid_alive "${refresh_pid}"; then
    rm -f "${refresh_pid_file}"
  fi
}

policy_spawn_firewall_refresh() {
  local pid_file pid

  pid_file="$(policy_refresh_pid_file)"
  pid="$(read_pid_file "${pid_file}" || true)"
  if is_pid_alive "${pid}"; then
    return 0
  fi

  (
    trap 'rm -f "'"${pid_file}"'"' EXIT
    "${BOXCTL_SELF_PATH}" firewall renew >>"${BOX_LOG_DIR}/policy.log" 2>&1
  ) &
  printf '%s\n' "$!" >"${pid_file}"
}

policy_apply_cycle() {
  local event_label="${1:-manual}"
  local event_ts="${2:-$(timestamp_utc)}"
  local refresh_requested="${3:-false}"
  local refresh_ts=""

  POLICY_LAST_ERROR=""
  if ! policy_evaluate_desired_state; then
    POLICY_LAST_ERROR="policy evaluation failed"
    policy_write_state "error" "${event_label}" "${event_ts}" ""
    return "${E_POLICY}"
  fi

  if ! policy_apply_desired_state "${POLICY_DESIRED_STATE}"; then
    policy_write_state "error" "${event_label}" "${event_ts}" ""
    return "${E_POLICY}"
  fi

  if policy_bool_true "${refresh_requested}" && [[ "${POLICY_DESIRED_STATE}" == "enabled" ]]; then
    if ! policy_refresh_firewall_if_running; then
      POLICY_LAST_ERROR="firewall refresh failed after address event"
      policy_write_state "error" "${event_label}" "${event_ts}" ""
      return "${E_POLICY}"
    fi
    refresh_ts="$(timestamp_utc)"
  fi

  policy_write_state "${POLICY_DESIRED_STATE}" "${event_label}" "${event_ts}" "${refresh_ts}"
  log "INFO" "policy" "POLICY_APPLIED" \
    "desired=${POLICY_DESIRED_STATE} applied=${POLICY_APPLIED_STATE} reason=${POLICY_REASON} event=${event_label}"
}

policy_monitor_loop() {
  local pid_file line pending_event="" pending_ts="" refresh_requested="false" next_line
  local marker_state previous_marker_state event_pid=""

  require_root || return 1
  load_config
  init_runtime_paths

  pid_file="$(policy_pid_file)"
  printf '%s\n' "$$" >"${pid_file}"
  previous_marker_state="$(if policy_disable_marker_present; then printf 'present'; else printf 'absent'; fi)"
  coproc POLICY_EVENTS { policy_event_source; }
  event_pid="${POLICY_EVENTS_PID:-}"
  trap '[[ -n "'"${event_pid}"'" ]] && kill "'"${event_pid}"'" >/dev/null 2>&1 || true; policy_monitor_cleanup; exit 0' EXIT INT TERM

  policy_apply_cycle "startup" "$(timestamp_utc)" "false"

  while true; do
    marker_state="$(if policy_disable_marker_present; then printf 'present'; else printf 'absent'; fi)"
    if [[ "${marker_state}" != "${previous_marker_state}" ]]; then
      previous_marker_state="${marker_state}"
      policy_apply_cycle "disable-marker" "$(timestamp_utc)" "false"
      continue
    fi

    if IFS= read -r -t 1 line <&"${POLICY_EVENTS[0]}"; then
      pending_event="${line}"
      pending_ts="$(timestamp_utc)"
      case "${line}" in
        *inet*|*address*|*Deleted*) refresh_requested="true" ;;
      esac

      while IFS= read -r -t "${BOX_POLICY_DEBOUNCE_SECONDS}" next_line <&"${POLICY_EVENTS[0]}"; do
        pending_event="${next_line}"
        pending_ts="$(timestamp_utc)"
        case "${next_line}" in
          *inet*|*address*|*Deleted*) refresh_requested="true" ;;
        esac
        marker_state="$(if policy_disable_marker_present; then printf 'present'; else printf 'absent'; fi)"
        if [[ "${marker_state}" != "${previous_marker_state}" ]]; then
          previous_marker_state="${marker_state}"
          pending_event="disable-marker"
          pending_ts="$(timestamp_utc)"
          refresh_requested="false"
          break
        fi
      done

      policy_apply_cycle "${pending_event:-event}" "${pending_ts}" "${refresh_requested}"
      refresh_requested="false"
      continue
    fi
  done
}

policy_enable() {
  require_root || return 1
  load_config
  init_runtime_paths

  local pid_file pid attempt
  pid_file="$(policy_pid_file)"
  pid="$(read_pid_file "${pid_file}" || true)"
  if is_pid_alive "${pid}"; then
    log "INFO" "policy" "POLICY_ALREADY_RUNNING" "policy watcher already running pid=${pid}"
    return 0
  fi

  rm -f "${pid_file}"
  nohup "${BOXCTL_SELF_PATH}" policy monitor >>"${BOX_LOG_DIR}/policy.log" 2>&1 &
  disown || true

  for attempt in $(seq 1 15); do
    sleep 0.2
    pid="$(read_pid_file "${pid_file}" || true)"
    if is_pid_alive "${pid}"; then
      log "INFO" "policy" "POLICY_STARTED" "policy watcher started pid=${pid}"
      return 0
    fi
  done

  if ! is_pid_alive "${pid:-}"; then
    log "ERROR" "policy" "E_POLICY" "failed to start policy watcher"
    return "${E_POLICY}"
  fi
}

policy_disable() {
  require_root || return 1
  load_config
  init_runtime_paths

  local pid_file pid
  pid_file="$(policy_pid_file)"
  pid="$(read_pid_file "${pid_file}" || true)"
  if is_pid_alive "${pid}"; then
    kill -TERM "${pid}" >/dev/null 2>&1 || true
    sleep 1
    if is_pid_alive "${pid}"; then
      kill -KILL "${pid}" >/dev/null 2>&1 || true
    fi
  fi
  rm -f "${pid_file}"
  policy_clear_state
  log "INFO" "policy" "POLICY_STOPPED" "policy watcher stopped"
}

policy_evaluate() {
  require_root || return 1
  load_config
  init_runtime_paths
  policy_apply_cycle "manual-evaluate" "$(timestamp_utc)" "false"
}

policy_status_text() {
  load_config
  local pid_file pid watcher_running
  policy_snapshot_load

  pid_file="$(policy_pid_file)"
  pid="$(read_pid_file "${pid_file}" || true)"
  watcher_running="false"
  if is_pid_alive "${pid}"; then
    watcher_running="true"
  else
    pid="0"
  fi

  printf 'status=%s\n' "$(policy_snapshot_get "status" "inactive")"
  printf 'policy_enabled=%s\n' "${BOX_POLICY_ENABLED}"
  printf 'watcher_running=%s\n' "${watcher_running}"
  printf 'pid=%s\n' "${pid}"
  printf 'desired_state=%s\n' "$(policy_snapshot_get "desired_state" "disabled")"
  printf 'applied_state=%s\n' "$(policy_snapshot_get "applied_state" "unchanged")"
  printf 'proxy_mode=%s\n' "${BOX_POLICY_PROXY_MODE}"
  printf 'debounce_seconds=%s\n' "${BOX_POLICY_DEBOUNCE_SECONDS}"
  printf 'active_ifaces=%s\n' "$(policy_snapshot_get "active_ifaces" "")"
  printf 'wifi_connected=%s\n' "$(policy_snapshot_get "wifi_connected" "false")"
  printf 'ssid=%s\n' "$(policy_snapshot_get "ssid" "")"
  printf 'bssid=%s\n' "$(policy_snapshot_get "bssid" "")"
  printf 'disable_marker_present=%s\n' "$(policy_snapshot_get "disable_marker_present" "false")"
  printf 'last_reason=%s\n' "$(policy_snapshot_get "last_reason" "")"
  printf 'last_error=%s\n' "$(policy_snapshot_get "last_error" "")"
  printf 'last_event=%s\n' "$(policy_snapshot_get "last_event" "")"
  printf 'last_event_ts=%s\n' "$(policy_snapshot_get "last_event_ts" "")"
  printf 'last_refresh_ts=%s\n' "$(policy_snapshot_get "last_refresh_ts" "")"
}

policy_status_json() {
  load_config
  local pid_file pid watcher_running
  policy_snapshot_load

  pid_file="$(policy_pid_file)"
  pid="$(read_pid_file "${pid_file}" || true)"
  watcher_running="false"
  if is_pid_alive "${pid}"; then
    watcher_running="true"
  else
    pid="0"
  fi

  printf '{%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s}\n' \
    "$(json_pair "status" "$(policy_snapshot_get "status" "inactive")")" \
    "$(json_bool_pair "policy_enabled" "${BOX_POLICY_ENABLED}")" \
    "$(json_bool_pair "watcher_running" "${watcher_running}")" \
    "$(json_num_pair "pid" "${pid}")" \
    "$(json_pair "desired_state" "$(policy_snapshot_get "desired_state" "disabled")")" \
    "$(json_pair "applied_state" "$(policy_snapshot_get "applied_state" "unchanged")")" \
    "$(json_pair "proxy_mode" "${BOX_POLICY_PROXY_MODE}")" \
    "$(json_num_pair "debounce_seconds" "${BOX_POLICY_DEBOUNCE_SECONDS}")" \
    "\"active_ifaces\":$(policy_active_ifaces_json)" \
    "$(json_bool_pair "wifi_connected" "$(policy_snapshot_get "wifi_connected" "false")")" \
    "$(json_pair "ssid" "$(policy_snapshot_get "ssid" "")")" \
    "$(json_pair "bssid" "$(policy_snapshot_get "bssid" "")")" \
    "$(json_bool_pair "disable_marker_present" "$(policy_snapshot_get "disable_marker_present" "false")")" \
    "$(json_pair "last_reason" "$(policy_snapshot_get "last_reason" "")")" \
    "$(json_pair "last_error" "$(policy_snapshot_get "last_error" "")")" \
    "$(json_pair "last_event" "$(policy_snapshot_get "last_event" "")")" \
    "$(json_pair "last_event_ts" "$(policy_snapshot_get "last_event_ts" "")")" \
    "$(json_pair "last_refresh_ts" "$(policy_snapshot_get "last_refresh_ts" "")")"
}

policy_status() {
  if [[ "${BOX_OUTPUT_FORMAT}" == "json" ]]; then
    policy_status_json
  else
    policy_status_text
  fi
}

policy_cmd() {
  local action="${1:-}"
  case "${action}" in
    evaluate) policy_evaluate ;;
    enable) policy_enable ;;
    disable) policy_disable ;;
    status) policy_status ;;
    monitor) policy_monitor_loop ;;
    *)
      printf 'usage: boxctl policy <evaluate|enable|disable|status> [--json]\n' >&2
      return 2
      ;;
  esac
}
