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
  local target_checksum staged_checksum

  mkdir -p "$(dirname "${target}")"
  staged_checksum="$(updater_compute_sha256 "${staged_file}" || true)"
  target_checksum="$(updater_compute_sha256 "${target}" || true)"
  if [[ -n "${staged_checksum}" && "${staged_checksum}" == "${target_checksum}" ]]; then
    UP_INSTALL_CHANGED="false"
    UP_INSTALL_CHECKSUM="${staged_checksum}"
    return 0
  fi

  updater_backup_target "${target}"
  mv -f "${staged_file}" "${target}"
  if [[ "${make_executable}" == "true" ]]; then
    chmod 0755 "${target}"
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
    *.tar.gz|*.tgz) tar -xzf "${archive}" -C "${destination}" ;;
    *.tar) tar -xf "${archive}" -C "${destination}" ;;
    *)
      log "ERROR" "updater" "E_UPDATE_ARCHIVE" "unsupported archive format: ${format_hint}"
      return "${E_UPDATE}"
      ;;
  esac
}

updater_install_directory() {
  local component="${1:?missing component}"
  local staged_dir="${2:?missing staged dir}"
  local target="${3:?missing target}"
  local source_checksum="${4:-}"
  local state_checksum="${5:-}"

  mkdir -p "$(dirname "${target}")"
  if [[ -n "${source_checksum}" && -n "${state_checksum}" && "${source_checksum}" == "${state_checksum}" && -d "${target}" ]]; then
    UP_INSTALL_CHANGED="false"
    UP_INSTALL_CHECKSUM="${source_checksum}"
    return 0
  fi

  updater_backup_target "${target}"
  rm -rf "${target}"
  mv -f "${staged_dir}" "${target}"
  UP_INSTALL_CHANGED="true"
  UP_INSTALL_CHECKSUM="${source_checksum}"
  log "INFO" "updater" "UPDATE_INSTALLED" "installed component=${component} target=${target}"
}

updater_install_nochange() {
  local checksum="${1:-}"
  UP_INSTALL_CHANGED="false"
  UP_INSTALL_CHECKSUM="${checksum}"
}
