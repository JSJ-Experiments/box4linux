#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

updater_sha256_cmd() {
  command -v sha256sum >/dev/null 2>&1 && printf '%s\n' "sha256sum"
}

updater_compute_sha256() {
  local path="${1:?missing path}"
  local sha_cmd
  sha_cmd="$(updater_sha256_cmd || true)"
  [[ -n "${sha_cmd}" ]] || return 1
  "${sha_cmd}" "${path}" 2>/dev/null | awk '{print $1}'
}

updater_compute_tree_sha256() {
  local path="${1:?missing path}"
  local sha_cmd
  sha_cmd="$(updater_sha256_cmd || true)"
  [[ -n "${sha_cmd}" ]] || return 1

  if [[ -f "${path}" ]]; then
    updater_compute_sha256 "${path}"
    return 0
  fi

  [[ -d "${path}" ]] || return 1

  (
    cd "${path}"
    find . -mindepth 1 -print | LC_ALL=C sort | while IFS= read -r entry; do
      if [[ -f "${entry}" ]]; then
        printf 'file %s %s\n' "${entry}" "$("${sha_cmd}" "${entry}" | awk '{print $1}')"
      elif [[ -d "${entry}" ]]; then
        printf 'dir %s\n' "${entry}"
      fi
    done | "${sha_cmd}" | awk '{print $1}'
  )
}

updater_parse_checksum_text() {
  local checksum_text="${1:-}"
  checksum_text="$(trim_space "${checksum_text}")"
  checksum_text="${checksum_text%% *}"
  printf '%s\n' "${checksum_text}"
}

updater_expected_checksum() {
  local ref="${1:-}"
  local kind="${2:-}"
  local value=""
  local tmp_file

  [[ -n "${ref}" ]] || return 1

  if [[ -z "${kind}" ]]; then
    if [[ "${ref}" =~ ^[0-9a-fA-F]{64}$ ]]; then
      printf '%s\n' "${ref}"
      return 0
    fi
    kind="$(updater_source_kind "${ref}")"
  fi

  if [[ "${kind}" == "file" && "${ref}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    printf '%s\n' "${ref}"
    return 0
  fi

  tmp_file="$(mktemp)"
  if ! updater_fetch_ref "checksum" "${ref}" "${kind}" "${tmp_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi
  value="$(updater_parse_checksum_text "$(head -n 1 "${tmp_file}")")"
  rm -f "${tmp_file}"
  [[ "${value}" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
  printf '%s\n' "${value}"
}

updater_verify_checksum() {
  local component="${1:?missing component}"
  local artifact_path="${2:?missing artifact path}"
  local checksum_ref="${3:-}"
  local checksum_kind="${4:-}"
  local expected actual

  case "${BOX_UPDATER_CHECKSUM_POLICY}" in
    off) return 0 ;;
  esac

  if [[ -z "${checksum_ref}" ]]; then
    if [[ "${BOX_UPDATER_CHECKSUM_POLICY}" == "required" ]]; then
      log "ERROR" "updater" "E_UPDATE_CHECKSUM" "checksum required but not configured for component=${component}"
      return "${E_UPDATE}"
    fi
    return 0
  fi

  expected="$(updater_expected_checksum "${checksum_ref}" "${checksum_kind}" || true)"
  if [[ -z "${expected}" ]]; then
    log "ERROR" "updater" "E_UPDATE_CHECKSUM" "failed to resolve checksum for component=${component}"
    return "${E_UPDATE}"
  fi

  if [[ -d "${artifact_path}" ]]; then
    actual="$(updater_compute_tree_sha256 "${artifact_path}" || true)"
  else
    actual="$(updater_compute_sha256 "${artifact_path}" || true)"
  fi
  if [[ -z "${actual}" || "${actual}" != "${expected}" ]]; then
    log "ERROR" "updater" "E_UPDATE_CHECKSUM" \
      "checksum mismatch for component=${component} expected=${expected:-unknown} actual=${actual:-unknown}"
    return "${E_UPDATE}"
  fi
}
