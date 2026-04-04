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

updater_sleep_ms() {
  local delay_ms="${1:-0}"
  local delay_s
  if [[ "${delay_ms}" == "0" ]]; then
    return 0
  fi
  delay_s="$(awk -v ms="${delay_ms}" 'BEGIN { printf "%.3f", ms / 1000 }')"
  sleep "${delay_s}"
}

updater_apply_ghproxy() {
  local ref="${1:?missing ref}"
  local base

  if ! validate_bool_string "${BOX_UPDATER_USE_GHPROXY}"; then
    printf '%s\n' "${ref}"
    return 0
  fi
  if ! [[ "${BOX_UPDATER_USE_GHPROXY}" == "true" || "${BOX_UPDATER_USE_GHPROXY}" == "1" ]]; then
    printf '%s\n' "${ref}"
    return 0
  fi
  case "${ref}" in
    https://github.com/*|https://raw.githubusercontent.com/*)
      base="${BOX_UPDATER_GHPROXY_URL%/}"
      printf '%s/%s\n' "${base}" "${ref}"
      ;;
    *)
      printf '%s\n' "${ref}"
      ;;
  esac
}

updater_fetch_ref() {
  local component="${1:?missing component}"
  local ref="${2:?missing ref}"
  local kind="${3:?missing kind}"
  local output="${4:?missing output path}"
  local curl_bin resolved_ref attempts backoff attempt

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
      resolved_ref="$(updater_apply_ghproxy "${ref}")"
      attempts=$(( BOX_UPDATER_FETCH_RETRIES + 1 ))
      backoff="${BOX_UPDATER_FETCH_RETRY_BACKOFF_MS}"
      for attempt in $(seq 1 "${attempts}"); do
        rm -rf "${output}"
        if "${curl_bin}" -fsSL "${resolved_ref}" -o "${output}" && [[ -s "${output}" ]]; then
          return 0
        fi
        if [[ "${attempt}" -lt "${attempts}" ]]; then
          log "WARN" "updater" "W_UPDATE_FETCH_RETRY" \
            "retrying download component=${component} attempt=${attempt}/${attempts} ref=${resolved_ref}"
          updater_sleep_ms "${backoff}"
          backoff=$(( backoff * 2 ))
        fi
      done
      log "ERROR" "updater" "E_UPDATE_FETCH" "download failed for component=${component}: ${resolved_ref}"
      return "${E_UPDATE}"
      ;;
    *)
      log "ERROR" "updater" "E_UPDATE_FETCH" "unsupported source kind=${kind} for component=${component}"
      return "${E_UPDATE}"
      ;;
  esac
}
