#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

UP_INSTALL_BACKUP=""
UP_INSTALL_CHANGED="false"
UP_INSTALL_CHECKSUM=""

updater_install_reset() {
  UP_INSTALL_BACKUP=""
  UP_INSTALL_CHANGED="false"
  UP_INSTALL_CHECKSUM=""
}

updater_restore_backup() {
  local target="${1:?missing target}"
  if [[ -n "${UP_INSTALL_BACKUP}" && -e "${UP_INSTALL_BACKUP}" ]]; then
    mkdir -p "$(dirname "${target}")"
    rm -rf "${target}"
    mv -f "${UP_INSTALL_BACKUP}" "${target}"
    UP_INSTALL_BACKUP=""
  fi
}

updater_backup_target() {
  local target="${1:?missing target}"
  if [[ -e "${target}" ]]; then
    UP_INSTALL_BACKUP="${target}.bak.$$"
    rm -rf "${UP_INSTALL_BACKUP}"
    mv -f "${target}" "${UP_INSTALL_BACKUP}"
  fi
}

updater_install_file() {
  local component="${1:?missing component}"
  local staged_file="${2:?missing staged file}"
  local target="${3:?missing target}"
  local make_executable="${4:-false}"
  local target_checksum staged_checksum temp_target

  mkdir -p "$(dirname "${target}")"
  staged_checksum="$(updater_compute_sha256 "${staged_file}" || true)"
  target_checksum="$(updater_compute_sha256 "${target}" || true)"
  if [[ -n "${staged_checksum}" && "${staged_checksum}" == "${target_checksum}" ]]; then
    UP_INSTALL_CHANGED="false"
    UP_INSTALL_CHECKSUM="${staged_checksum}"
    return 0
  fi

  temp_target="${target}.new.$$"
  rm -f "${temp_target}"
  if ! cp -f "${staged_file}" "${temp_target}"; then
    rm -f "${temp_target}"
    log "ERROR" "updater" "E_UPDATE_INSTALL" "failed to stage file install for component=${component} target=${target}"
    return "${E_UPDATE}"
  fi

  if [[ "${make_executable}" == "true" ]]; then
    chmod 0755 "${temp_target}"
  fi

  updater_backup_target "${target}"
  if ! mv -f "${temp_target}" "${target}"; then
    rm -f "${temp_target}"
    updater_restore_backup "${target}"
    log "ERROR" "updater" "E_UPDATE_INSTALL" "failed to finalize file install for component=${component} target=${target}"
    return "${E_UPDATE}"
  fi
  UP_INSTALL_CHANGED="true"
  UP_INSTALL_CHECKSUM="${staged_checksum}"
  log "INFO" "updater" "UPDATE_INSTALLED" "installed component=${component} target=${target}"
}

updater_extract_archive() {
  local archive="${1:?missing archive}"
  local destination="${2:?missing destination}"
  local format_hint="${3:-${archive}}"

  mkdir -p "${destination}"
  case "${format_hint}" in
    *.zip)
      if ! command -v unzip >/dev/null 2>&1; then
        log "ERROR" "updater" "E_UPDATE_ARCHIVE" "unzip is required for archive format: ${format_hint}"
        return "${E_UPDATE}"
      fi
      unzip -oq "${archive}" -d "${destination}" >/dev/null
      ;;
    *.tar.gz|*.tgz) tar -xzf "${archive}" -C "${destination}" ;;
    *.tar) tar -xf "${archive}" -C "${destination}" ;;
    *.tar.xz) tar -xJf "${archive}" -C "${destination}" ;;
    *)
      log "ERROR" "updater" "E_UPDATE_ARCHIVE" "unsupported archive format: ${format_hint}"
      return "${E_UPDATE}"
      ;;
  esac
}

updater_extract_gzip() {
  local archive="${1:?missing archive}"
  local destination="${2:?missing destination}"

  mkdir -p "$(dirname "${destination}")"
  if ! command -v gzip >/dev/null 2>&1; then
    log "ERROR" "updater" "E_UPDATE_ARCHIVE" "gzip is required for gzip payload extraction"
    return "${E_UPDATE}"
  fi
  if ! gzip -dc "${archive}" >"${destination}"; then
    rm -f "${destination}"
    log "ERROR" "updater" "E_UPDATE_ARCHIVE" "failed to extract gzip payload: ${archive}"
    return "${E_UPDATE}"
  fi
}

updater_install_directory() {
  local component="${1:?missing component}"
  local staged_dir="${2:?missing staged dir}"
  local target="${3:?missing target}"
  local source_checksum="${4:-}"
  local state_checksum="${5:-}"
  local temp_target

  mkdir -p "$(dirname "${target}")"
  if [[ -n "${source_checksum}" && -n "${state_checksum}" && "${source_checksum}" == "${state_checksum}" && -d "${target}" ]]; then
    UP_INSTALL_CHANGED="false"
    UP_INSTALL_CHECKSUM="${source_checksum}"
    return 0
  fi

  temp_target="${target}.new.$$"
  rm -rf "${temp_target}"
  mkdir -p "${temp_target}"
  if ! cp -a "${staged_dir}/." "${temp_target}/"; then
    rm -rf "${temp_target}"
    log "ERROR" "updater" "E_UPDATE_INSTALL" "failed to stage directory install for component=${component} target=${target}"
    return "${E_UPDATE}"
  fi

  updater_backup_target "${target}"
  rm -rf "${target}"
  if ! mv -f "${temp_target}" "${target}"; then
    rm -rf "${temp_target}"
    updater_restore_backup "${target}"
    log "ERROR" "updater" "E_UPDATE_INSTALL" "failed to finalize directory install for component=${component} target=${target}"
    return "${E_UPDATE}"
  fi
  UP_INSTALL_CHANGED="true"
  UP_INSTALL_CHECKSUM="${source_checksum}"
  log "INFO" "updater" "UPDATE_INSTALLED" "installed component=${component} target=${target}"
}

updater_install_nochange() {
  local checksum="${1:-}"
  UP_INSTALL_CHANGED="false"
  UP_INSTALL_CHECKSUM="${checksum}"
}
