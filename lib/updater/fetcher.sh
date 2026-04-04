#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

updater_curl_cmd() {
  if [[ -n "${BOX_CURL_CMD:-}" ]]; then
    printf '%s\n' "${BOX_CURL_CMD}"
    return 0
  fi
  command -v curl >/dev/null 2>&1 && printf '%s\n' "curl"
}

updater_fetch_ref() {
  local component="${1:?missing component}"
  local ref="${2:?missing ref}"
  local kind="${3:?missing kind}"
  local output="${4:?missing output path}"
  local curl_bin

  mkdir -p "$(dirname "${output}")"

  case "${kind}" in
    file)
      if [[ -d "${ref}" ]]; then
        cp -a "${ref}" "${output}"
      elif [[ -f "${ref}" ]]; then
        cp -f "${ref}" "${output}"
      else
        log "ERROR" "updater" "E_UPDATE_FETCH" "source file does not exist for component=${component}: ${ref}"
        return "${E_UPDATE}"
      fi
      ;;
    url)
      if [[ "${ref}" == file://* ]]; then
        updater_fetch_ref "${component}" "${ref#file://}" "file" "${output}"
        return 0
      fi
      curl_bin="$(updater_curl_cmd || true)"
      if [[ -z "${curl_bin}" ]]; then
        log "ERROR" "updater" "E_UPDATE_FETCH" "curl is required for url fetch: ${ref}"
        return "${E_UPDATE}"
      fi
      if ! "${curl_bin}" -fsSL "${ref}" -o "${output}"; then
        log "ERROR" "updater" "E_UPDATE_FETCH" "download failed for component=${component}: ${ref}"
        return "${E_UPDATE}"
      fi
      ;;
    *)
      log "ERROR" "updater" "E_UPDATE_FETCH" "unsupported source kind=${kind} for component=${component}"
      return "${E_UPDATE}"
      ;;
  esac
}
