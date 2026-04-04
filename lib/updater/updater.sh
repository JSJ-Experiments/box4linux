#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

source "${BOX_LIB_DIR}/updater/resolver.sh"
source "${BOX_LIB_DIR}/updater/fetcher.sh"
source "${BOX_LIB_DIR}/updater/verifier.sh"
source "${BOX_LIB_DIR}/updater/installer.sh"

updater_state_root() {
  init_runtime_paths
  local path="${BOX_VAR_DIR}/state/update"
  mkdir -p "${path}"
  printf '%s\n' "${path}"
}

updater_snapshot_file() {
  init_runtime_paths
  mkdir -p "${BOX_VAR_DIR}/state"
  printf '%s/state/update-state.json\n' "${BOX_VAR_DIR}"
}

updater_state_file() {
  local component="${1:?missing component}"
  printf '%s/%s.state\n' "$(updater_state_root)" "${component}"
}

updater_read_state_value() {
  local component="${1:?missing component}"
  local key="${2:?missing key}"
  local file
  file="$(updater_state_file "${component}")"
  [[ -f "${file}" ]] || return 1
  awk -F= -v wanted="${key}" '$1==wanted {print substr($0, index($0, "=")+1); exit}' "${file}"
}

updater_write_state_component() {
  local component="${1:?missing component}"
  local status="${2:?missing status}"
  local error_message="${3:-}"
  local source_ref="${4:-}"
  local target_path="${5:-}"
  local checksum="${6:-}"
  local handoff="${7:-none}"
  local attempt_ts success_ts file

  file="$(updater_state_file "${component}")"
  attempt_ts="$(timestamp_utc)"
  success_ts="$(updater_read_state_value "${component}" "last_success_ts" || true)"
  if [[ "${status}" == "success" || "${status}" == "unchanged" ]]; then
    success_ts="${attempt_ts}"
  fi

  cat >"${file}" <<EOF
component=${component}
last_status=${status}
last_error=${error_message}
last_attempt_ts=${attempt_ts}
last_success_ts=${success_ts}
source_ref=${source_ref}
target_path=${target_path}
installed_sha256=${checksum}
last_handoff=${handoff}
interval=$(updater_interval_for "${component}")
configured=$(updater_component_configured "${component}" && printf 'true' || printf 'false')
EOF
  updater_write_snapshot
}

updater_write_snapshot() {
  local snapshot_file component state_json configured configured_json status error_msg attempt success source target checksum handoff interval
  local components_json=()

  snapshot_file="$(updater_snapshot_file)"
  for component in kernel subs geo dashboard; do
    configured="false"
    if updater_component_configured "${component}"; then
      configured="true"
    fi
    status="$(updater_read_state_value "${component}" "last_status" || printf 'never')"
    error_msg="$(updater_read_state_value "${component}" "last_error" || true)"
    attempt="$(updater_read_state_value "${component}" "last_attempt_ts" || true)"
    success="$(updater_read_state_value "${component}" "last_success_ts" || true)"
    source="$(updater_read_state_value "${component}" "source_ref" || true)"
    target="$(updater_read_state_value "${component}" "target_path" || true)"
    checksum="$(updater_read_state_value "${component}" "installed_sha256" || true)"
    handoff="$(updater_read_state_value "${component}" "last_handoff" || printf 'none')"
    interval="$(updater_interval_for "${component}")"

    configured_json="$(json_bool_pair "configured" "${configured}")"
    state_json="{${configured_json},$(json_pair "status" "${status}"),$(json_pair "last_error" "${error_msg}"),$(json_pair "last_attempt_ts" "${attempt}"),$(json_pair "last_success_ts" "${success}"),$(json_pair "source_ref" "${source}"),$(json_pair "target_path" "${target}"),$(json_pair "installed_sha256" "${checksum}"),$(json_pair "last_handoff" "${handoff}"),$(json_pair "interval" "${interval}")}"
    components_json+=("\"${component}\":${state_json}")
  done

  {
    printf '{%s,%s,%s,%s,%s,%s}\n' \
      "$(json_pair "timestamp" "$(timestamp_utc)")" \
      "$(json_pair "artifact_dir" "${BOX_UPDATER_ARTIFACT_DIR}")" \
      "$(json_pair "staging_dir" "${BOX_UPDATER_STAGING_DIR}")" \
      "$(json_pair "checksum_policy" "${BOX_UPDATER_CHECKSUM_POLICY}")" \
      "$(json_pair "core" "${BOX_CORE}")" \
      "\"components\":{$(IFS=,; printf '%s' "${components_json[*]}")}"
  } >"${snapshot_file}"
}

updater_interval_for() {
  local component="${1:?missing component}"
  case "${component}" in
    kernel) printf '%s\n' "${BOX_UPDATER_KERNEL_INTERVAL}" ;;
    subs) printf '%s\n' "${BOX_UPDATER_SUBS_INTERVAL}" ;;
    geo) printf '%s\n' "${BOX_UPDATER_GEO_INTERVAL}" ;;
    dashboard) printf '%s\n' "${BOX_UPDATER_DASHBOARD_INTERVAL}" ;;
    *) printf '%s\n' "" ;;
  esac
}

updater_service_running() {
  local pid
  pid="$(read_pid_file "$(service_pid_file_readonly)" || true)"
  is_pid_alive "${pid}"
}

updater_handoff_runtime() {
  local component="${1:?missing component}"

  if [[ "${component}" == "dashboard" ]]; then
    printf '%s\n' "none"
    return 0
  fi

  if ! updater_service_running; then
    printf '%s\n' "none"
    return 0
  fi

  case "${component}" in
    subs)
      case "${BOX_CORE}" in
        sing-box)
          if adapter_sing_box_reload; then
            printf '%s\n' "reload"
            return 0
          fi
          ;;
        mihomo)
          adapter_mihomo_reload >/dev/null 2>&1 || true
          ;;
      esac
      ;;
  esac

  if service_restart; then
    printf '%s\n' "restart"
    return 0
  fi

  log "ERROR" "updater" "E_UPDATE_HANDOFF" "runtime handoff failed for component=${component}"
  return "${E_UPDATE}"
}

updater_validate_staged_component() {
  local component="${1:?missing component}"
  local staged_path="${2:?missing staged path}"
  local core_bin rendered_tmp

  case "${component}" in
    kernel)
      if [[ ! -s "${staged_path}" ]]; then
        log "ERROR" "updater" "E_UPDATE_VALIDATE" "kernel artifact is empty: ${staged_path}"
        return "${E_UPDATE}"
      fi
      chmod 0755 "${staged_path}"
      ;;
    subs)
      core_bin="$(resolve_core_bin || true)"
      if [[ -z "${core_bin}" ]]; then
        log "ERROR" "updater" "E_UPDATE_VALIDATE" "cannot validate subscriptions: core binary not found"
        return "${E_UPDATE}"
      fi
      rendered_tmp="$(mktemp)"
      if [[ "${BOX_CORE}" == "mihomo" ]]; then
        rendered_tmp="${rendered_tmp}.yaml"
        mutator_mihomo_render_overlay "${staged_path}" "${rendered_tmp}"
      else
        rendered_tmp="${rendered_tmp}.json"
        mutator_sing_box_render_overlay "${staged_path}" "${rendered_tmp}"
      fi
      if ! check_core_config "${core_bin}" "${rendered_tmp}" "${BOX_CORE_WORKDIR}"; then
        rm -f "${rendered_tmp}" "${rendered_tmp}.overlay.env"
        log "ERROR" "updater" "E_UPDATE_VALIDATE" "subscription payload failed core validation"
        return "${E_UPDATE}"
      fi
      rm -f "${rendered_tmp}" "${rendered_tmp}.overlay.env"
      ;;
    geo)
      if [[ ! -s "${staged_path}" ]]; then
        log "ERROR" "updater" "E_UPDATE_VALIDATE" "geo artifact is empty: ${staged_path}"
        return "${E_UPDATE}"
      fi
      ;;
    dashboard)
      if [[ ! -d "${staged_path}" ]]; then
        log "ERROR" "updater" "E_UPDATE_VALIDATE" "dashboard payload is not a directory: ${staged_path}"
        return "${E_UPDATE}"
      fi
      ;;
  esac
}

updater_stage_dir() {
  init_runtime_paths
  mkdir -p "${BOX_UPDATER_STAGING_DIR}"
  printf '%s/%s\n' "${BOX_UPDATER_STAGING_DIR}" "$1"
}

updater_cleanup_paths() {
  local path
  for path in "$@"; do
    [[ -n "${path}" ]] || continue
    rm -rf "${path}" 2>/dev/null || true
  done
}

updater_component_checksum() {
  local install_kind="${1:?missing install kind}"
  local path="${2:?missing path}"
  case "${install_kind}" in
    file|archive) updater_compute_sha256 "${path}" ;;
    directory) updater_compute_tree_sha256 "${path}" ;;
    *) return 1 ;;
  esac
}

updater_apply_component() {
  local component="${1:?missing component}"
  local source_basename fetch_output dashboard_unpack_dir source_checksum previous_checksum target_checksum handoff result_status
  local validate_path="" install_path=""

  if ! updater_resolve_component "${component}"; then
    updater_write_state_component "${component}" "error" "component not configured" "" "" "" "none"
    return "${E_UPDATE}"
  fi

  updater_install_reset
  source_basename="$(basename "${UP_SOURCE_REF}")"
  fetch_output="$(updater_stage_dir "${component}.${source_basename}.download")"
  rm -rf "${fetch_output}"

  if ! updater_fetch_ref "${component}" "${UP_SOURCE_REF}" "${UP_SOURCE_KIND}" "${fetch_output}"; then
    updater_write_state_component "${component}" "error" "download failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
    return "${E_UPDATE}"
  fi

  if ! updater_verify_checksum "${component}" "${fetch_output}" "${UP_CHECKSUM_REF}" "${UP_CHECKSUM_KIND}"; then
    updater_write_state_component "${component}" "error" "checksum verification failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
    updater_cleanup_paths "${fetch_output}"
    return "${E_UPDATE}"
  fi

  case "${UP_INSTALL_KIND}" in
    file)
      validate_path="${fetch_output}"
      install_path="${fetch_output}"
      ;;
    archive)
      dashboard_unpack_dir="$(updater_stage_dir "${component}.unpack.$$")"
      updater_cleanup_paths "${dashboard_unpack_dir}"
      if ! updater_extract_archive "${fetch_output}" "${dashboard_unpack_dir}" "${UP_SOURCE_REF}"; then
        updater_write_state_component "${component}" "error" "archive extraction failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
        updater_cleanup_paths "${fetch_output}" "${dashboard_unpack_dir}"
        return "${E_UPDATE}"
      fi
      validate_path="${dashboard_unpack_dir}"
      install_path="${dashboard_unpack_dir}"
      ;;
    directory)
      validate_path="${fetch_output}"
      install_path="${fetch_output}"
      ;;
    *)
      updater_write_state_component "${component}" "error" "unsupported install kind" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
      updater_cleanup_paths "${fetch_output}"
      return "${E_UPDATE}"
      ;;
  esac

  if ! updater_validate_staged_component "${component}" "${validate_path}"; then
    updater_write_state_component "${component}" "error" "validation failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
    updater_cleanup_paths "${fetch_output}" "${dashboard_unpack_dir}"
    return "${E_UPDATE}"
  fi

  source_checksum="$(updater_component_checksum "${UP_INSTALL_KIND}" "${install_path}" || true)"
  previous_checksum="$(updater_read_state_value "${component}" "installed_sha256" || true)"
  if [[ -n "${source_checksum}" && -n "${previous_checksum}" && "${source_checksum}" == "${previous_checksum}" ]]; then
    target_checksum="$(updater_component_checksum "$([[ "${UP_INSTALL_KIND}" == "archive" || "${UP_INSTALL_KIND}" == "directory" ]] && printf 'directory' || printf 'file')" "${UP_TARGET_PATH}" || true)"
    if [[ -n "${target_checksum}" && "${target_checksum}" == "${source_checksum}" ]]; then
      updater_install_nochange "${source_checksum}"
    fi
  fi

  case "${UP_INSTALL_KIND}" in
    file)
      if [[ "${UP_INSTALL_CHANGED}" != "false" || -z "${UP_INSTALL_CHECKSUM}" ]]; then
        if ! updater_install_file "${component}" "${fetch_output}" "${UP_TARGET_PATH}" "$([[ "${component}" == "kernel" ]] && printf 'true' || printf 'false')"; then
          updater_write_state_component "${component}" "error" "install failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
          updater_cleanup_paths "${fetch_output}"
          return "${E_UPDATE}"
        fi
      fi
      updater_cleanup_paths "${fetch_output}"
      ;;
    archive)
      if [[ "${UP_INSTALL_CHANGED}" != "false" || -z "${UP_INSTALL_CHECKSUM}" ]]; then
        if ! updater_install_directory "${component}" "${dashboard_unpack_dir}" "${UP_TARGET_PATH}" "${source_checksum}" "${previous_checksum}"; then
          updater_write_state_component "${component}" "error" "install failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
          updater_cleanup_paths "${fetch_output}" "${dashboard_unpack_dir}"
          return "${E_UPDATE}"
        fi
      fi
      updater_cleanup_paths "${fetch_output}" "${dashboard_unpack_dir}"
      ;;
    directory)
      if [[ "${UP_INSTALL_CHANGED}" != "false" || -z "${UP_INSTALL_CHECKSUM}" ]]; then
        if ! updater_install_directory "${component}" "${fetch_output}" "${UP_TARGET_PATH}" "${source_checksum}" "${previous_checksum}"; then
          updater_write_state_component "${component}" "error" "install failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
          updater_cleanup_paths "${fetch_output}"
          return "${E_UPDATE}"
        fi
      fi
      updater_cleanup_paths "${fetch_output}"
      ;;
  esac

  if [[ "${UP_INSTALL_CHANGED}" == "true" && "${UP_REQUIRES_HANDOFF}" == "true" ]]; then
    if ! handoff="$(updater_handoff_runtime "${component}")"; then
      updater_restore_backup "${UP_TARGET_PATH}"
      updater_write_state_component "${component}" "error" "runtime handoff failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "${UP_INSTALL_CHECKSUM}" "failed"
      return "${E_UPDATE}"
    fi
  else
    handoff="none"
  fi

  result_status="success"
  if [[ "${UP_INSTALL_CHANGED}" != "true" ]]; then
    result_status="unchanged"
  fi
  updater_write_state_component "${component}" "${result_status}" "" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "${UP_INSTALL_CHECKSUM}" "${handoff}"
  return 0
}

updater_status_json() {
  local snapshot
  snapshot="$(updater_snapshot_file)"
  if [[ -f "${snapshot}" ]]; then
    cat "${snapshot}"
    return 0
  fi
  updater_write_snapshot
  cat "${snapshot}"
}

updater_status_text() {
  local component configured status last_error target interval
  printf 'artifact_dir=%s\n' "${BOX_UPDATER_ARTIFACT_DIR}"
  printf 'staging_dir=%s\n' "${BOX_UPDATER_STAGING_DIR}"
  printf 'checksum_policy=%s\n' "${BOX_UPDATER_CHECKSUM_POLICY}"
  for component in kernel subs geo dashboard; do
    configured="false"
    if updater_component_configured "${component}"; then
      configured="true"
    fi
    status="$(updater_read_state_value "${component}" "last_status" || printf 'never')"
    last_error="$(updater_read_state_value "${component}" "last_error" || true)"
    target="$(updater_read_state_value "${component}" "target_path" || true)"
    interval="$(updater_interval_for "${component}")"
    printf '[%s]\n' "${component}"
    printf 'configured=%s\n' "${configured}"
    printf 'interval=%s\n' "${interval}"
    printf 'status=%s\n' "${status}"
    printf 'target=%s\n' "${target}"
    printf 'last_error=%s\n' "${last_error}"
  done
}

updater_status() {
  load_config
  if [[ "${BOX_OUTPUT_FORMAT}" == "json" ]]; then
    updater_status_json
  else
    updater_status_text
  fi
}

updater_run_locked() {
  local component="${1:?missing component}"
  load_config
  init_runtime_paths
  mkdir -p "${BOX_UPDATER_ARTIFACT_DIR}" "${BOX_UPDATER_STAGING_DIR}" "${BOX_VAR_DIR}/state"

  case "${component}" in
    kernel|subs|geo|dashboard)
      updater_apply_component "${component}"
      ;;
    all)
      local current rc=0 any_configured=0
      for current in kernel subs geo dashboard; do
        if updater_component_configured "${current}"; then
          any_configured=1
          updater_apply_component "${current}" || rc=$?
        else
          updater_write_state_component "${current}" "skipped" "component not configured" "" "" "" "none"
        fi
      done
      if [[ "${any_configured}" != "1" ]]; then
        log "ERROR" "updater" "E_UPDATE_CONFIG" "no updater components configured"
        return "${E_UPDATE}"
      fi
      return "${rc}"
      ;;
    *)
      log "ERROR" "updater" "E_UPDATE_COMPONENT" "unsupported update action=${component}"
      return 2
      ;;
  esac
}

updater_run() {
  local component="${1:?missing component}"
  with_lock "update" 120 updater_run_locked "${component}"
}

updater_cmd() {
  local action="${1:-}"
  case "${action}" in
    kernel|subs|geo|dashboard|all) updater_run "${action}" ;;
    status) updater_status ;;
    *)
      printf 'usage: boxctl update <kernel|subs|geo|dashboard|all|status> [--json]\n' >&2
      return 2
      ;;
  esac
}
