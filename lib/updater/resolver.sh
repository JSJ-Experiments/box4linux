#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

UP_COMPONENT=""
UP_SOURCE_REF=""
UP_SOURCE_KIND=""
UP_CHECKSUM_REF=""
UP_CHECKSUM_KIND=""
UP_TARGET_PATH=""
UP_INSTALL_KIND=""
UP_INTERVAL=""
UP_REQUIRES_HANDOFF="false"

updater_component_configured() {
  local component="${1:?missing component}"
  local source_ref=""

  case "${component}" in
    kernel) source_ref="${BOX_UPDATER_KERNEL_URL:-${BOX_UPDATER_KERNEL_FILE:-}}" ;;
    subs) source_ref="${BOX_UPDATER_SUBS_URL:-${BOX_UPDATER_SUBS_FILE:-}}" ;;
    geo) source_ref="${BOX_UPDATER_GEO_URL:-${BOX_UPDATER_GEO_FILE:-}}" ;;
    dashboard) source_ref="${BOX_UPDATER_DASHBOARD_URL:-${BOX_UPDATER_DASHBOARD_FILE:-}}" ;;
    *)
      return 1
      ;;
  esac

  [[ -n "${source_ref}" ]]
}

updater_source_kind() {
  local ref="${1:-}"
  case "${ref}" in
    http://*|https://*|file://*) printf '%s\n' "url" ;;
    *) printf '%s\n' "file" ;;
  esac
}

updater_dashboard_install_kind() {
  local ref="${1:-}"
  case "${ref}" in
    *.tar|*.tar.gz|*.tgz) printf '%s\n' "archive" ;;
    *) printf '%s\n' "directory" ;;
  esac
}

updater_resolve_component() {
  local component="${1:?missing component}"

  UP_COMPONENT="${component}"
  UP_SOURCE_REF=""
  UP_SOURCE_KIND=""
  UP_CHECKSUM_REF=""
  UP_CHECKSUM_KIND=""
  UP_TARGET_PATH=""
  UP_INSTALL_KIND="file"
  UP_INTERVAL=""
  UP_REQUIRES_HANDOFF="false"

  case "${component}" in
    kernel)
      UP_SOURCE_REF="${BOX_UPDATER_KERNEL_URL:-${BOX_UPDATER_KERNEL_FILE:-}}"
      UP_CHECKSUM_REF="${BOX_UPDATER_KERNEL_CHECKSUM_FILE:-${BOX_UPDATER_KERNEL_CHECKSUM:-}}"
      UP_TARGET_PATH="${BOX_UPDATER_KERNEL_TARGET:-${BOX_CORE_BIN_DIR}/${BOX_CORE}}"
      UP_INTERVAL="${BOX_UPDATER_KERNEL_INTERVAL}"
      UP_REQUIRES_HANDOFF="true"
      ;;
    subs)
      UP_SOURCE_REF="${BOX_UPDATER_SUBS_URL:-${BOX_UPDATER_SUBS_FILE:-}}"
      UP_CHECKSUM_REF="${BOX_UPDATER_SUBS_CHECKSUM_FILE:-${BOX_UPDATER_SUBS_CHECKSUM:-}}"
      UP_TARGET_PATH="${BOX_UPDATER_SUBS_TARGET:-${BOX_CORE_CONFIG_SOURCE}}"
      UP_INTERVAL="${BOX_UPDATER_SUBS_INTERVAL}"
      UP_REQUIRES_HANDOFF="true"
      ;;
    geo)
      UP_SOURCE_REF="${BOX_UPDATER_GEO_URL:-${BOX_UPDATER_GEO_FILE:-}}"
      UP_CHECKSUM_REF="${BOX_UPDATER_GEO_CHECKSUM_FILE:-${BOX_UPDATER_GEO_CHECKSUM:-}}"
      UP_TARGET_PATH="${BOX_UPDATER_GEO_TARGET:-${BOX_UPDATER_ARTIFACT_DIR}/geo/geo.dat}"
      UP_INTERVAL="${BOX_UPDATER_GEO_INTERVAL}"
      UP_REQUIRES_HANDOFF="true"
      ;;
    dashboard)
      UP_SOURCE_REF="${BOX_UPDATER_DASHBOARD_URL:-${BOX_UPDATER_DASHBOARD_FILE:-}}"
      UP_CHECKSUM_REF="${BOX_UPDATER_DASHBOARD_CHECKSUM_FILE:-${BOX_UPDATER_DASHBOARD_CHECKSUM:-}}"
      UP_TARGET_PATH="${BOX_UPDATER_DASHBOARD_TARGET:-${BOX_UPDATER_ARTIFACT_DIR}/dashboard/current}"
      UP_INTERVAL="${BOX_UPDATER_DASHBOARD_INTERVAL}"
      UP_INSTALL_KIND="$(updater_dashboard_install_kind "${UP_SOURCE_REF}")"
      ;;
    *)
      log "ERROR" "updater" "E_UPDATE_COMPONENT" "unsupported update component: ${component}"
      return "${E_UPDATE}"
      ;;
  esac

  if [[ -z "${UP_SOURCE_REF}" ]]; then
    log "ERROR" "updater" "E_UPDATE_CONFIG" "no source configured for component=${component}"
    return "${E_UPDATE}"
  fi

  UP_SOURCE_KIND="$(updater_source_kind "${UP_SOURCE_REF}")"
  if [[ -n "${UP_CHECKSUM_REF}" ]]; then
    UP_CHECKSUM_KIND="$(updater_source_kind "${UP_CHECKSUM_REF}")"
  fi
  return 0
}
