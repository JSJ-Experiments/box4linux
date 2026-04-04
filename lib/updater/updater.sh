#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

source "${BOX_LIB_DIR}/updater/presets.sh"
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
  local active_bin rendered_path core_bin=""

  if [[ "${component}" == "dashboard" || "${component}" == "geo" ]]; then
    printf '%s\n' "none"
    return 0
  fi

  if ! updater_service_running; then
    printf '%s\n' "none"
    return 0
  fi

  case "${component}" in
    kernel)
      active_bin="$(resolve_core_bin || true)"
      if [[ -z "${active_bin}" || "${active_bin}" != "${UP_TARGET_PATH}" ]]; then
        printf '%s\n' "none"
        return 0
      fi
      ;;
    subs)
      rendered_path="$(rendered_config_expected_path)"
      core_bin="$(resolve_core_bin || true)"
      case "${BOX_CORE}" in
        sing-box)
          if [[ -n "${core_bin}" ]] && adapter_sing_box_reload "${rendered_path}" "${BOX_CORE_WORKDIR}" "${core_bin}"; then
            printf '%s\n' "reload"
            return 0
          fi
          ;;
        mihomo)
          if [[ -n "${core_bin}" ]] && adapter_mihomo_reload "${rendered_path}" "${BOX_CORE_WORKDIR}" "${core_bin}" >/dev/null 2>&1; then
            printf '%s\n' "reload"
            return 0
          fi
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

updater_recover_runtime_after_restore() {
  local component="${1:?missing component}"

  case "${component}" in
    dashboard|geo)
      return 0
      ;;
    kernel)
      if ! updater_service_running; then
        if ! service_restart; then
          return "${E_UPDATE}"
        fi
      else
        if ! service_restart; then
          return "${E_UPDATE}"
        fi
      fi
      ;;
    subs)
      if ! service_restart; then
        return "${E_UPDATE}"
      fi
      ;;
  esac
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
      if [[ -d "${staged_path}" ]]; then
        if ! find "${staged_path}" -type f -print -quit | grep -q .; then
          log "ERROR" "updater" "E_UPDATE_VALIDATE" "geo preset bundle is empty: ${staged_path}"
          return "${E_UPDATE}"
        fi
      elif [[ ! -s "${staged_path}" ]]; then
        log "ERROR" "updater" "E_UPDATE_VALIDATE" "geo artifact is empty: ${staged_path}"
        return "${E_UPDATE}"
      fi
      ;;
    dashboard)
      if [[ ! -d "${staged_path}" ]]; then
        log "ERROR" "updater" "E_UPDATE_VALIDATE" "dashboard payload is not a directory: ${staged_path}"
        return "${E_UPDATE}"
      fi
      if ! find "${staged_path}" -mindepth 1 -print -quit | grep -q .; then
        log "ERROR" "updater" "E_UPDATE_VALIDATE" "dashboard payload is empty: ${staged_path}"
        return "${E_UPDATE}"
      fi
      if [[ ! -f "${staged_path}/index.html" ]]; then
        log "ERROR" "updater" "E_UPDATE_VALIDATE" "dashboard payload missing index.html: ${staged_path}"
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
    file|archive-file|gzip-file) updater_compute_sha256 "${path}" ;;
    directory|archive-dir) updater_compute_tree_sha256 "${path}" ;;
    *) return 1 ;;
  esac
}

updater_find_archive_member() {
  local component="${1:?missing component}"
  local unpack_dir="${2:?missing unpack dir}"
  local member_regex="${3:-}"
  local candidate relative_path

  while IFS= read -r candidate; do
    relative_path="${candidate#"${unpack_dir}"/}"
    if [[ -z "${member_regex}" || "${relative_path}" =~ ${member_regex} ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done < <(find "${unpack_dir}" -type f | LC_ALL=C sort)

  log "ERROR" "updater" "E_UPDATE_ARCHIVE_MEMBER" \
    "no archive member matched for component=${component} regex=${member_regex:-<any>}"
  return "${E_UPDATE}"
}

updater_dashboard_payload_root() {
  local unpack_dir="${1:?missing unpack dir}"
  local index_file candidate best_dir=""
  local top_entries=()

  while IFS= read -r index_file; do
    candidate="$(dirname "${index_file}")"
    if [[ -z "${best_dir}" || "${#candidate}" -gt "${#best_dir}" ]]; then
      best_dir="${candidate}"
    fi
  done < <(find "${unpack_dir}" -type f -name 'index.html' | LC_ALL=C sort)

  if [[ -n "${best_dir}" ]]; then
    printf '%s\n' "${best_dir}"
    return 0
  fi

  mapfile -t top_entries < <(find "${unpack_dir}" -mindepth 1 -maxdepth 1 | LC_ALL=C sort)
  if [[ "${#top_entries[@]}" == "1" && -d "${top_entries[0]}" ]]; then
    printf '%s\n' "${top_entries[0]}"
    return 0
  fi

  printf '%s\n' "${unpack_dir}"
}

updater_generate_preset_subs() {
  local output_path="${1:?missing output path}"
  local template_path=""

  case "${UP_PRESET_NAME}" in
    mihomo_phone)
      if [[ -f "${UP_TARGET_PATH}" ]]; then
        template_path="${UP_TARGET_PATH}"
      else
        template_path="$(updater_subs_default_template || true)"
      fi
      if [[ -z "${template_path}" ]]; then
        log "ERROR" "updater" "E_UPDATE_PRESET" "no mihomo phone template available"
        return "${E_UPDATE}"
      fi
      updater_subs_render_mihomo_phone "${template_path}" "${output_path}"
      ;;
    *)
      log "ERROR" "updater" "E_UPDATE_PRESET" "unsupported subs preset: ${UP_PRESET_NAME}"
      return "${E_UPDATE}"
      ;;
  esac
}

updater_geo_bundle_current_checksum() {
  local manifest_file="${1:?missing manifest file}"
  local snapshot_dir snapshot_target snapshot_name

  snapshot_dir="$(mktemp -d)"
  while IFS=$'\t' read -r snapshot_name _ snapshot_target; do
    [[ -n "${snapshot_name}" && -n "${snapshot_target}" ]] || continue
    if [[ ! -f "${snapshot_target}" ]]; then
      rm -rf "${snapshot_dir}"
      return 1
    fi
    cp -f "${snapshot_target}" "${snapshot_dir}/${snapshot_name}"
  done <"${manifest_file}"

  updater_compute_tree_sha256 "${snapshot_dir}"
  rm -rf "${snapshot_dir}"
}

updater_fetch_geo_bundle() {
  local bundle_dir="${1:?missing bundle dir}"
  local manifest_file="${2:?missing manifest file}"
  local name ref target

  : >"${manifest_file}"
  while IFS=$'\t' read -r name ref target; do
    [[ -n "${name}" && -n "${ref}" && -n "${target}" ]] || continue
    if ! updater_fetch_ref "geo:${name}" "${ref}" "$(updater_source_kind "${ref}")" "${bundle_dir}/${name}"; then
      log "ERROR" "updater" "E_UPDATE_FETCH" "failed geo preset fetch asset=${name}"
      return "${E_UPDATE}"
    fi
    printf '%s\t%s\t%s\n' "${name}" "${ref}" "${target}" >>"${manifest_file}"
  done < <(updater_geo_emit_manifest "${UP_PRESET_NAME}" "${UP_TARGET_ROOT}")
}

updater_install_geo_bundle() {
  local bundle_dir="${1:?missing bundle dir}"
  local manifest_file="${2:?missing manifest file}"
  local source_checksum="${3:-}"
  local previous_checksum="${4:-}"
  local current_checksum="" any_changed=0 name source_ref target_path

  if [[ -n "${source_checksum}" && -n "${previous_checksum}" && "${source_checksum}" == "${previous_checksum}" ]]; then
    current_checksum="$(updater_geo_bundle_current_checksum "${manifest_file}" || true)"
    if [[ -n "${current_checksum}" && "${current_checksum}" == "${source_checksum}" ]]; then
      updater_install_nochange "${source_checksum}"
      return 0
    fi
  fi

  while IFS=$'\t' read -r name source_ref target_path; do
    [[ -n "${name}" && -n "${target_path}" ]] || continue
    if ! updater_install_file "geo" "${bundle_dir}/${name}" "${target_path}" "false"; then
      updater_restore_all_backups
      return "${E_UPDATE}"
    fi
    if [[ "${UP_INSTALL_CHANGED}" == "true" ]]; then
      any_changed=1
    fi
  done <"${manifest_file}"

  if [[ "${any_changed}" == "1" ]]; then
    UP_INSTALL_CHANGED="true"
  else
    UP_INSTALL_CHANGED="false"
  fi
  UP_INSTALL_CHECKSUM="${source_checksum}"
}

updater_apply_component() {
  local component="${1:?missing component}"
  local source_basename fetch_output unpack_dir="" install_source="" source_checksum previous_checksum target_checksum handoff result_status
  local validate_path="" install_path="" target_install_kind="" manifest_file=""

  if ! updater_resolve_component "${component}"; then
    updater_write_state_component "${component}" "error" "component not configured" "" "" "" "none"
    return "${E_UPDATE}"
  fi

  updater_install_reset
  source_basename="${UP_SOURCE_NAME:-$(basename "${UP_SOURCE_REF}")}"
  fetch_output="$(updater_stage_dir "${component}.${source_basename}.download")"
  rm -rf "${fetch_output}"
  manifest_file="${fetch_output}.manifest"

  case "${UP_SOURCE_KIND}" in
    preset-subs)
      if ! updater_generate_preset_subs "${fetch_output}"; then
        updater_write_state_component "${component}" "error" "preset generation failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
        return "${E_UPDATE}"
      fi
      ;;
    preset-geo)
      rm -rf "${fetch_output}"
      mkdir -p "${fetch_output}"
      if ! updater_fetch_geo_bundle "${fetch_output}" "${manifest_file}"; then
        updater_write_state_component "${component}" "error" "download failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
        updater_cleanup_paths "${fetch_output}" "${manifest_file}"
        return "${E_UPDATE}"
      fi
      ;;
    *)
      if ! updater_fetch_ref "${component}" "${UP_SOURCE_REF}" "${UP_SOURCE_KIND}" "${fetch_output}"; then
        updater_write_state_component "${component}" "error" "download failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
        return "${E_UPDATE}"
      fi

      if ! updater_verify_checksum "${component}" "${fetch_output}" "${UP_CHECKSUM_REF}" "${UP_CHECKSUM_KIND}"; then
        updater_write_state_component "${component}" "error" "checksum verification failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
        updater_cleanup_paths "${fetch_output}"
        return "${E_UPDATE}"
      fi
      ;;
  esac

  case "${UP_INSTALL_KIND}" in
    file)
      validate_path="${fetch_output}"
      install_path="${fetch_output}"
      ;;
    gzip-file)
      install_source="$(updater_stage_dir "${component}.extract.$$")"
      updater_cleanup_paths "${install_source}"
      if ! updater_extract_gzip "${fetch_output}" "${install_source}"; then
        updater_write_state_component "${component}" "error" "gzip extraction failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
        updater_cleanup_paths "${fetch_output}" "${install_source}"
        return "${E_UPDATE}"
      fi
      validate_path="${install_source}"
      install_path="${install_source}"
      ;;
    archive-file|archive-dir)
      unpack_dir="$(updater_stage_dir "${component}.unpack.$$")"
      updater_cleanup_paths "${unpack_dir}"
      if ! updater_extract_archive "${fetch_output}" "${unpack_dir}" "${UP_SOURCE_NAME:-${UP_SOURCE_REF}}"; then
        updater_write_state_component "${component}" "error" "archive extraction failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
        updater_cleanup_paths "${fetch_output}" "${unpack_dir}"
        return "${E_UPDATE}"
      fi
      if [[ "${UP_INSTALL_KIND}" == "archive-file" ]]; then
        install_source="$(updater_find_archive_member "${component}" "${unpack_dir}" "${UP_ARCHIVE_MEMBER_REGEX}")" || {
          updater_write_state_component "${component}" "error" "archive member not found" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
          updater_cleanup_paths "${fetch_output}" "${unpack_dir}"
          return "${E_UPDATE}"
        }
        validate_path="${install_source}"
        install_path="${install_source}"
      else
        install_source="$(updater_dashboard_payload_root "${unpack_dir}")"
        validate_path="${install_source}"
        install_path="${install_source}"
      fi
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
    updater_cleanup_paths "${fetch_output}" "${unpack_dir}" "${manifest_file}"
    return "${E_UPDATE}"
  fi

  source_checksum="$(updater_component_checksum "${UP_INSTALL_KIND}" "${install_path}" || true)"
  previous_checksum="$(updater_read_state_value "${component}" "installed_sha256" || true)"
  if [[ -n "${source_checksum}" && -n "${previous_checksum}" && "${source_checksum}" == "${previous_checksum}" ]]; then
    if [[ "${UP_INSTALL_KIND}" == "archive-dir" || "${UP_INSTALL_KIND}" == "directory" ]]; then
      target_install_kind="directory"
    else
      target_install_kind="file"
    fi
    target_checksum="$(updater_component_checksum "${target_install_kind}" "${UP_TARGET_PATH}" || true)"
    if [[ -n "${target_checksum}" && "${target_checksum}" == "${source_checksum}" ]]; then
      updater_install_nochange "${source_checksum}"
    fi
  fi

  case "${UP_INSTALL_KIND}" in
    file|archive-file|gzip-file)
      if [[ "${UP_INSTALL_CHANGED}" != "false" || -z "${UP_INSTALL_CHECKSUM}" ]]; then
        if ! updater_install_file "${component}" "${install_path}" "${UP_TARGET_PATH}" "$([[ "${component}" == "kernel" ]] && printf 'true' || printf 'false')"; then
          updater_write_state_component "${component}" "error" "install failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
          updater_cleanup_paths "${fetch_output}" "${unpack_dir}" "${manifest_file}"
          return "${E_UPDATE}"
        fi
      fi
      updater_cleanup_paths "${fetch_output}" "${unpack_dir}" "${manifest_file}"
      ;;
    archive-dir)
      if [[ "${UP_INSTALL_CHANGED}" != "false" || -z "${UP_INSTALL_CHECKSUM}" ]]; then
        if ! updater_install_directory "${component}" "${install_path}" "${UP_TARGET_PATH}" "${source_checksum}" "${previous_checksum}"; then
          updater_write_state_component "${component}" "error" "install failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
          updater_cleanup_paths "${fetch_output}" "${unpack_dir}" "${manifest_file}"
          return "${E_UPDATE}"
        fi
      fi
      updater_cleanup_paths "${fetch_output}" "${unpack_dir}" "${manifest_file}"
      ;;
    directory)
      if [[ "${UP_SOURCE_KIND}" == "preset-geo" ]]; then
        if ! updater_install_geo_bundle "${fetch_output}" "${manifest_file}" "${source_checksum}" "${previous_checksum}"; then
          updater_write_state_component "${component}" "error" "install failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
          updater_cleanup_paths "${fetch_output}" "${manifest_file}"
          return "${E_UPDATE}"
        fi
      else
        if [[ "${UP_INSTALL_CHANGED}" != "false" || -z "${UP_INSTALL_CHECKSUM}" ]]; then
          if ! updater_install_directory "${component}" "${fetch_output}" "${UP_TARGET_PATH}" "${source_checksum}" "${previous_checksum}"; then
            updater_write_state_component "${component}" "error" "install failed" "${UP_SOURCE_REF}" "${UP_TARGET_PATH}" "" "none"
            updater_cleanup_paths "${fetch_output}" "${manifest_file}"
            return "${E_UPDATE}"
          fi
        fi
      fi
      updater_cleanup_paths "${fetch_output}" "${manifest_file}"
      ;;
  esac

  if [[ "${UP_INSTALL_CHANGED}" == "true" && "${UP_REQUIRES_HANDOFF}" == "true" ]]; then
    if ! handoff="$(updater_handoff_runtime "${component}")"; then
      updater_restore_all_backups
      updater_recover_runtime_after_restore "${component}" || true
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
  updater_discard_backups
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
