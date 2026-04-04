#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

UP_COMPONENT=""
UP_SOURCE_REF=""
UP_SOURCE_NAME=""
UP_SOURCE_KIND=""
UP_CHECKSUM_REF=""
UP_CHECKSUM_NAME=""
UP_CHECKSUM_KIND=""
UP_TARGET_PATH=""
UP_INSTALL_KIND=""
UP_INTERVAL=""
UP_REQUIRES_HANDOFF="false"
UP_ARCHIVE_MEMBER_REGEX=""
UP_PRESET_NAME=""
UP_TARGET_ROOT=""

updater_component_configured() {
  local component="${1:?missing component}"
  local source_mode source_ref="" release_repo="" release_api_url="" dashboard_target="" preset=""

  case "${component}" in
    kernel)
      source_mode="${BOX_UPDATER_KERNEL_SOURCE}"
      source_ref="${BOX_UPDATER_KERNEL_URL:-${BOX_UPDATER_KERNEL_FILE:-}}"
      release_repo="${BOX_UPDATER_KERNEL_RELEASE_REPO}"
      release_api_url="${BOX_UPDATER_KERNEL_RELEASE_API_URL}"
      ;;
    subs)
      source_mode="auto"
      source_ref="${BOX_UPDATER_SUBS_URL:-${BOX_UPDATER_SUBS_FILE:-}}"
      preset="${BOX_UPDATER_SUBS_PRESET}"
      ;;
    geo)
      source_mode="${BOX_UPDATER_GEO_SOURCE}"
      source_ref="${BOX_UPDATER_GEO_URL:-${BOX_UPDATER_GEO_FILE:-}}"
      release_repo="${BOX_UPDATER_GEO_RELEASE_REPO}"
      release_api_url="${BOX_UPDATER_GEO_RELEASE_API_URL}"
      preset="${BOX_UPDATER_GEO_PRESET}"
      ;;
    dashboard)
      source_mode="auto"
      source_ref="${BOX_UPDATER_DASHBOARD_URL:-${BOX_UPDATER_DASHBOARD_FILE:-}}"
      dashboard_target="${BOX_UPDATER_DASHBOARD_TARGET:-$(updater_dashboard_resolve_from_core_config target || true)}"
      ;;
    *)
      return 1
      ;;
  esac

  case "${source_mode}" in
    release)
      [[ -n "${release_repo}" || -n "${release_api_url}" ]]
      ;;
    auto)
      [[ -n "${source_ref}" || -n "${release_repo}" || -n "${release_api_url}" || -n "${dashboard_target}" || -n "${preset}" ]]
      ;;
    *)
      [[ -n "${source_ref}" ]]
      ;;
  esac
}

updater_source_kind() {
  local ref="${1:-}"
  case "${ref}" in
    http://*|https://*|file://*) printf '%s\n' "url" ;;
    *) printf '%s\n' "file" ;;
  esac
}

updater_install_kind_for_name() {
  local component="${1:?missing component}"
  local name="${2:-}"
  case "${component}:${name}" in
    dashboard:*.zip|dashboard:*.tar|dashboard:*.tar.gz|dashboard:*.tgz|dashboard:*.tar.xz) printf '%s\n' "archive-dir" ;;
    dashboard:*) printf '%s\n' "directory" ;;
    kernel:*.tar|kernel:*.tar.gz|kernel:*.tgz|kernel:*.tar.xz) printf '%s\n' "archive-file" ;;
    kernel:*.gz) printf '%s\n' "gzip-file" ;;
    geo:*.tar|geo:*.tar.gz|geo:*.tgz|geo:*.tar.xz) printf '%s\n' "archive-file" ;;
    *) printf '%s\n' "file" ;;
  esac
}

updater_jq_cmd() {
  command -v jq >/dev/null 2>&1 && printf '%s\n' "jq"
}

updater_release_os() {
  local override="${1:-}"
  local uname_s
  if [[ -n "${override}" ]]; then
    printf '%s\n' "${override}"
    return 0
  fi
  uname_s="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "${uname_s}" in
    linux) printf '%s\n' "linux" ;;
    darwin) printf '%s\n' "darwin" ;;
    *) printf '%s\n' "${uname_s}" ;;
  esac
}

updater_release_arch() {
  local override="${1:-}"
  local uname_m
  if [[ -n "${override}" ]]; then
    printf '%s\n' "${override}"
    return 0
  fi
  uname_m="$(uname -m)"
  case "${uname_m}" in
    x86_64|amd64) printf '%s\n' "amd64" ;;
    aarch64|arm64) printf '%s\n' "arm64" ;;
    i386|i686) printf '%s\n' "386" ;;
    armv7l|armv7|armhf) printf '%s\n' "armv7" ;;
    armv6l|armv6) printf '%s\n' "armv6" ;;
    *) printf '%s\n' "${uname_m}" ;;
  esac
}

updater_release_arch_regex() {
  local arch="${1:-}"
  case "${arch}" in
    amd64) printf '%s\n' '(amd64|x86_64)' ;;
    arm64) printf '%s\n' '(arm64|aarch64)' ;;
    386) printf '%s\n' '(386|i386|i686|x86)' ;;
    armv7) printf '%s\n' '(armv7|armv7l|armhf)' ;;
    armv6) printf '%s\n' '(armv6|armv6l)' ;;
    *) printf '%s\n' "${arch}" ;;
  esac
}

updater_release_default_repo() {
  local component="${1:?missing component}"
  case "${component}:${BOX_CORE}" in
    kernel:mihomo) printf '%s\n' "MetaCubeX/mihomo" ;;
    kernel:sing-box) printf '%s\n' "SagerNet/sing-box" ;;
    *) printf '%s\n' "" ;;
  esac
}

updater_release_default_asset_regex() {
  local component="${1:?missing component}"
  local os_name="${2:-}"
  local arch_name="${3:-}"
  local arch_regex
  arch_regex="$(updater_release_arch_regex "${arch_name}")"
  case "${component}" in
    kernel)
      case "${BOX_CORE}" in
        mihomo) printf '%s\n' "^mihomo-${os_name}-${arch_regex}.*\\.(gz|tgz|tar\\.gz)$" ;;
        sing-box) printf '%s\n' "^sing-box-.*-${os_name}-${arch_regex}\\.tar\\.gz$" ;;
        *) printf '%s\n' "${BOX_CORE}.*${os_name}.*${arch_regex}" ;;
      esac
      ;;
    geo)
      printf '%s\n' "$(basename "${BOX_UPDATER_GEO_TARGET:-geo.dat}")"
      ;;
    *)
      printf '%s\n' ''
      ;;
  esac
}

updater_release_default_checksum_regex() {
  printf '%s\n' '(sha256|checksums?)'
}

updater_release_default_archive_member_regex() {
  local component="${1:?missing component}"
  case "${component}" in
    kernel) printf '%s\n' "(^|/)${BOX_CORE}$" ;;
    geo) printf '%s\n' "(^|/)[^/]+\\.(dat|db|mmdb)$" ;;
    *) printf '%s\n' '' ;;
  esac
}

updater_dashboard_default_url() {
  printf '%s\n' "https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip"
}

updater_dashboard_normalize_target() {
  local raw_target="${1:-}"
  local base_dir="${2:-}"
  if [[ -z "${raw_target}" ]]; then
    return 1
  fi
  case "${raw_target}" in
    /*) printf '%s\n' "${raw_target}" ;;
    *) printf '%s\n' "${base_dir}/${raw_target}" ;;
  esac
}

updater_dashboard_default_target() {
  local config_file="${BOX_CORE_CONFIG_SOURCE}"
  local config_dir

  [[ -f "${config_file}" ]] || return 1
  config_dir="$(cd "$(dirname "${config_file}")" && pwd)"
  printf '%s\n' "${config_dir}/dashboard"
}

updater_dashboard_read_mihomo_value() {
  local config_file="${1:?missing config file}"
  local key_regex="${2:?missing key regex}"
  awk -F: -v wanted="${key_regex}" '
    $0 ~ "^[[:space:]]*" wanted "[[:space:]]*:" {
      value = substr($0, index($0, ":") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "${config_file}"
}

updater_dashboard_read_sing_box_value() {
  local config_file="${1:?missing config file}"
  local jq_expr="${2:?missing jq expression}"
  local jq_bin
  jq_bin="$(updater_jq_cmd || true)"
  [[ -n "${jq_bin}" ]] || return 1
  "${jq_bin}" -r "${jq_expr} // empty" "${config_file}"
}

updater_dashboard_resolve_from_core_config() {
  local field="${1:?missing field}"
  local config_file="${BOX_CORE_CONFIG_SOURCE}"
  local config_dir result=""

  [[ -f "${config_file}" ]] || return 1
  config_dir="$(cd "$(dirname "${config_file}")" && pwd)"

  case "${BOX_CORE}:${field}" in
    mihomo:target)
      result="$(updater_dashboard_read_mihomo_value "${config_file}" 'external-ui' || true)"
      ;;
    mihomo:url)
      result="$(updater_dashboard_read_mihomo_value "${config_file}" 'external-ui-download-url|external_ui_download_url|external-ui-url|external_ui_url' || true)"
      ;;
    sing-box:target)
      result="$(updater_dashboard_read_sing_box_value "${config_file}" '.experimental.clash_api.external_ui // (.. | objects | .external_ui? // empty)' || true)"
      ;;
    sing-box:url)
      result="$(updater_dashboard_read_sing_box_value "${config_file}" '.experimental.clash_api.external_ui_download_url // (.. | objects | .external_ui_download_url? // empty)' || true)"
      ;;
  esac

  if [[ "${field}" == "target" ]]; then
    if [[ -n "${result}" ]]; then
      updater_dashboard_normalize_target "${result}" "${config_dir}"
      return 0
    fi
    updater_dashboard_default_target
    return 0
  fi

  [[ -n "${result}" ]] || return 1
  printf '%s\n' "${result}"
}

updater_release_metadata_ref() {
  local repo="${1:-}"
  local channel="${2:-stable}"
  local tag="${3:-}"
  local api_url="${4:-}"

  if [[ -n "${api_url}" ]]; then
    printf '%s\n' "${api_url}"
    return 0
  fi

  if [[ -z "${repo}" ]]; then
    return 1
  fi

  if [[ -n "${tag}" ]]; then
    printf 'https://api.github.com/repos/%s/releases/tags/%s\n' "${repo}" "${tag}"
    return 0
  fi

  case "${channel}" in
    stable) printf 'https://api.github.com/repos/%s/releases/latest\n' "${repo}" ;;
    prerelease|any) printf 'https://api.github.com/repos/%s/releases\n' "${repo}" ;;
    *) return 1 ;;
  esac
}

updater_release_pick_filter() {
  local channel="${1:-stable}"
  case "${channel}" in
    stable) printf '%s\n' '.prerelease != true' ;;
    prerelease) printf '%s\n' '.prerelease == true' ;;
    any) printf '%s\n' 'true' ;;
    *) return 1 ;;
  esac
}

updater_release_select_asset() {
  local metadata_file="${1:?missing metadata file}"
  local channel="${2:?missing channel}"
  local tag="${3:-}"
  local asset_regex="${4:?missing asset regex}"
  local jq_bin filter tag_filter

  jq_bin="$(updater_jq_cmd || true)"
  if [[ -z "${jq_bin}" ]]; then
    log "ERROR" "updater" "E_UPDATE_RESOLVE" "jq is required for release metadata resolution"
    return "${E_UPDATE}"
  fi

  filter="$(updater_release_pick_filter "${channel}")"
  tag_filter='true'
  if [[ -n "${tag}" ]]; then
    filter='true'
    tag_filter=".tag_name == \"${tag}\""
  fi

  "${jq_bin}" -r \
    --arg regex "${asset_regex}" \
    "
    def selected_release:
      if type == \"array\" then
        ([ .[] | select(${filter}) | select(${tag_filter}) ][0])
      else
        .
      end;
    selected_release
    | .assets[]?
    | select(.name | test(\$regex; \"i\"))
    | [.name, .browser_download_url]
    | @tsv
    " "${metadata_file}" | head -n 1
}

updater_resolve_release() {
  local component="${1:?missing component}"
  local repo="${2:-}"
  local channel="${3:-stable}"
  local tag="${4:-}"
  local api_url="${5:-}"
  local asset_regex="${6:-}"
  local checksum_asset_regex="${7:-}"
  local metadata_ref metadata_kind metadata_file selected_asset selected_checksum

  metadata_ref="$(updater_release_metadata_ref "${repo}" "${channel}" "${tag}" "${api_url}" || true)"
  if [[ -z "${metadata_ref}" ]]; then
    log "ERROR" "updater" "E_UPDATE_RESOLVE" "unable to build release metadata source for component=${component}"
    return "${E_UPDATE}"
  fi
  metadata_kind="$(updater_source_kind "${metadata_ref}")"
  metadata_file="$(mktemp)"
  if ! updater_fetch_ref "${component}-metadata" "${metadata_ref}" "${metadata_kind}" "${metadata_file}"; then
    rm -f "${metadata_file}"
    log "ERROR" "updater" "E_UPDATE_RESOLVE" "failed to fetch release metadata for component=${component}"
    return "${E_UPDATE}"
  fi

  selected_asset="$(updater_release_select_asset "${metadata_file}" "${channel}" "${tag}" "${asset_regex}" || true)"
  if [[ -z "${selected_asset}" ]]; then
    rm -f "${metadata_file}"
    log "ERROR" "updater" "E_UPDATE_RESOLVE" "no matching release asset for component=${component} regex=${asset_regex}"
    return "${E_UPDATE}"
  fi

  UP_SOURCE_NAME="${selected_asset%%$'\t'*}"
  UP_SOURCE_REF="${selected_asset#*$'\t'}"
  UP_SOURCE_KIND="$(updater_source_kind "${UP_SOURCE_REF}")"

  if [[ -n "${checksum_asset_regex}" && -z "${UP_CHECKSUM_REF}" ]]; then
    selected_checksum="$(updater_release_select_asset "${metadata_file}" "${channel}" "${tag}" "${checksum_asset_regex}" || true)"
    if [[ -n "${selected_checksum}" ]]; then
      UP_CHECKSUM_NAME="${selected_checksum%%$'\t'*}"
      UP_CHECKSUM_REF="${selected_checksum#*$'\t'}"
      UP_CHECKSUM_KIND="$(updater_source_kind "${UP_CHECKSUM_REF}")"
    fi
  fi

  rm -f "${metadata_file}"
}

updater_resolve_component() {
  local component="${1:?missing component}"
  local source_mode="auto" source_ref="" source_name="" checksum_ref="" checksum_name=""
  local release_repo="" release_channel="stable" release_tag="" release_api_url="" asset_regex="" checksum_asset_regex=""
  local release_os="linux" release_arch="" archive_member_regex=""
  local preset_name="" target_root=""

  UP_COMPONENT="${component}"
  UP_SOURCE_REF=""
  UP_SOURCE_NAME=""
  UP_SOURCE_KIND=""
  UP_CHECKSUM_REF=""
  UP_CHECKSUM_NAME=""
  UP_CHECKSUM_KIND=""
  UP_TARGET_PATH=""
  UP_INSTALL_KIND="file"
  UP_INTERVAL=""
  UP_REQUIRES_HANDOFF="false"
  UP_ARCHIVE_MEMBER_REGEX=""
  UP_PRESET_NAME=""
  UP_TARGET_ROOT=""

  case "${component}" in
    kernel)
      source_mode="${BOX_UPDATER_KERNEL_SOURCE}"
      source_ref="${BOX_UPDATER_KERNEL_URL:-${BOX_UPDATER_KERNEL_FILE:-}}"
      checksum_ref="${BOX_UPDATER_KERNEL_CHECKSUM_FILE:-${BOX_UPDATER_KERNEL_CHECKSUM:-}}"
      UP_TARGET_PATH="${BOX_UPDATER_KERNEL_TARGET:-${BOX_CORE_BIN_DIR}/${BOX_CORE}}"
      UP_INTERVAL="${BOX_UPDATER_KERNEL_INTERVAL}"
      UP_REQUIRES_HANDOFF="true"
      release_repo="${BOX_UPDATER_KERNEL_RELEASE_REPO}"
      release_channel="${BOX_UPDATER_KERNEL_RELEASE_CHANNEL}"
      release_tag="${BOX_UPDATER_KERNEL_RELEASE_TAG}"
      release_api_url="${BOX_UPDATER_KERNEL_RELEASE_API_URL}"
      release_os="$(updater_release_os "${BOX_UPDATER_KERNEL_RELEASE_OS}")"
      release_arch="$(updater_release_arch "${BOX_UPDATER_KERNEL_RELEASE_ARCH}")"
      asset_regex="${BOX_UPDATER_KERNEL_ASSET_REGEX:-$(updater_release_default_asset_regex kernel "${release_os}" "${release_arch}")}"
      checksum_asset_regex="${BOX_UPDATER_KERNEL_CHECKSUM_ASSET_REGEX:-$(updater_release_default_checksum_regex)}"
      archive_member_regex="${BOX_UPDATER_KERNEL_ARCHIVE_MEMBER_REGEX:-$(updater_release_default_archive_member_regex kernel)}"
      ;;
    subs)
      source_ref="${BOX_UPDATER_SUBS_URL:-${BOX_UPDATER_SUBS_FILE:-}}"
      checksum_ref="${BOX_UPDATER_SUBS_CHECKSUM_FILE:-${BOX_UPDATER_SUBS_CHECKSUM:-}}"
      UP_TARGET_PATH="${BOX_UPDATER_SUBS_TARGET:-${BOX_CORE_CONFIG_SOURCE}}"
      UP_INTERVAL="${BOX_UPDATER_SUBS_INTERVAL}"
      UP_REQUIRES_HANDOFF="true"
      preset_name="${BOX_UPDATER_SUBS_PRESET}"
      ;;
    geo)
      source_mode="${BOX_UPDATER_GEO_SOURCE}"
      source_ref="${BOX_UPDATER_GEO_URL:-${BOX_UPDATER_GEO_FILE:-}}"
      checksum_ref="${BOX_UPDATER_GEO_CHECKSUM_FILE:-${BOX_UPDATER_GEO_CHECKSUM:-}}"
      UP_TARGET_PATH="${BOX_UPDATER_GEO_TARGET:-${BOX_UPDATER_ARTIFACT_DIR}/geo/geo.dat}"
      UP_INTERVAL="${BOX_UPDATER_GEO_INTERVAL}"
      UP_REQUIRES_HANDOFF="false"
      preset_name="${BOX_UPDATER_GEO_PRESET}"
      release_repo="${BOX_UPDATER_GEO_RELEASE_REPO}"
      release_channel="${BOX_UPDATER_GEO_RELEASE_CHANNEL}"
      release_tag="${BOX_UPDATER_GEO_RELEASE_TAG}"
      release_api_url="${BOX_UPDATER_GEO_RELEASE_API_URL}"
      release_os="$(updater_release_os "${BOX_UPDATER_GEO_RELEASE_OS}")"
      release_arch="$(updater_release_arch "${BOX_UPDATER_GEO_RELEASE_ARCH}")"
      asset_regex="${BOX_UPDATER_GEO_ASSET_REGEX:-$(updater_release_default_asset_regex geo "${release_os}" "${release_arch}")}"
      checksum_asset_regex="${BOX_UPDATER_GEO_CHECKSUM_ASSET_REGEX}"
      archive_member_regex="${BOX_UPDATER_GEO_ARCHIVE_MEMBER_REGEX:-$(updater_release_default_archive_member_regex geo)}"
      ;;
    dashboard)
      source_ref="${BOX_UPDATER_DASHBOARD_URL:-${BOX_UPDATER_DASHBOARD_FILE:-}}"
      checksum_ref="${BOX_UPDATER_DASHBOARD_CHECKSUM_FILE:-${BOX_UPDATER_DASHBOARD_CHECKSUM:-}}"
      UP_TARGET_PATH="${BOX_UPDATER_DASHBOARD_TARGET:-$(updater_dashboard_resolve_from_core_config target || printf '%s' "${BOX_UPDATER_ARTIFACT_DIR}/dashboard/current")}"
      UP_INTERVAL="${BOX_UPDATER_DASHBOARD_INTERVAL}"
      if [[ -z "${source_ref}" ]]; then
        source_ref="$(updater_dashboard_resolve_from_core_config url || true)"
      fi
      if [[ -z "${source_ref}" ]]; then
        source_ref="$(updater_dashboard_default_url)"
      fi
      ;;
    *)
      log "ERROR" "updater" "E_UPDATE_COMPONENT" "unsupported update component: ${component}"
      return "${E_UPDATE}"
      ;;
  esac

  case "${source_mode}" in
    auto)
      if [[ -n "${source_ref}" || -n "${preset_name}" ]]; then
        :
      elif [[ -n "${release_repo}" || -n "${release_api_url}" ]]; then
        source_mode="release"
      fi
      ;;
  esac

  if [[ "${preset_name}" == "auto" ]]; then
    preset_name="$(updater_geo_default_preset)"
  fi

  if [[ -n "${preset_name}" ]]; then
    case "${component}" in
      subs)
        UP_PRESET_NAME="${preset_name}"
        UP_SOURCE_REF="preset:${preset_name}"
        UP_SOURCE_NAME="${preset_name}.yaml"
        UP_SOURCE_KIND="preset-subs"
        UP_INSTALL_KIND="file"
        return 0
        ;;
      geo)
        target_root="$(updater_geo_manifest_target_root)"
        UP_PRESET_NAME="${preset_name}"
        UP_TARGET_ROOT="${target_root}"
        UP_TARGET_PATH="${target_root}"
        UP_SOURCE_REF="preset:${preset_name}"
        UP_SOURCE_NAME="${preset_name}.bundle"
        UP_SOURCE_KIND="preset-geo"
        UP_INSTALL_KIND="directory"
        return 0
        ;;
    esac
  fi

  if [[ "${source_mode}" == "release" ]]; then
    if [[ -z "${release_repo}" ]]; then
      release_repo="$(updater_release_default_repo "${component}")"
    fi
    UP_CHECKSUM_REF="${checksum_ref}"
    if [[ -n "${UP_CHECKSUM_REF}" ]]; then
      UP_CHECKSUM_KIND="$(updater_source_kind "${UP_CHECKSUM_REF}")"
      checksum_name="$(basename "${UP_CHECKSUM_REF}")"
      UP_CHECKSUM_NAME="${checksum_name}"
    fi
    if ! updater_resolve_release "${component}" "${release_repo}" "${release_channel}" "${release_tag}" "${release_api_url}" "${asset_regex}" "${checksum_asset_regex}"; then
      return "${E_UPDATE}"
    fi
  else
    if [[ -z "${source_ref}" ]]; then
      log "ERROR" "updater" "E_UPDATE_CONFIG" "no source configured for component=${component}"
      return "${E_UPDATE}"
    fi
    source_name="$(basename "${source_ref}")"
    UP_SOURCE_REF="${source_ref}"
    UP_SOURCE_NAME="${source_name}"
    UP_SOURCE_KIND="$(updater_source_kind "${UP_SOURCE_REF}")"
    if [[ -n "${checksum_ref}" ]]; then
      checksum_name="$(basename "${checksum_ref}")"
      UP_CHECKSUM_REF="${checksum_ref}"
      UP_CHECKSUM_NAME="${checksum_name}"
      UP_CHECKSUM_KIND="$(updater_source_kind "${UP_CHECKSUM_REF}")"
    fi
  fi

  UP_INSTALL_KIND="$(updater_install_kind_for_name "${component}" "${UP_SOURCE_NAME:-$(basename "${UP_SOURCE_REF}")}")"
  UP_ARCHIVE_MEMBER_REGEX="${archive_member_regex}"
  return 0
}
