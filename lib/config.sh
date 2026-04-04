#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

BOX_CONFIG_FILE="${BOX_CONFIG_FILE:-}"
BOX_CONFIG_SOURCE="${BOX_CONFIG_SOURCE:-}"

# Runtime config values; initialized via config_defaults().
BOX_CORE=""
BOX_NETWORK_MODE=""
BOX_TPROXY_PORT=""
BOX_REDIR_PORT=""
BOX_DNS_PORT=""
BOX_DNS_HIJACK_MODE=""
BOX_DNS_COEXIST_MODE=""
BOX_TAILSCALE_IFACE=""
BOX_TAILNET_IPV4_CIDR=""
BOX_TAILNET_IPV6_CIDR=""
BOX_TAILSCALE_DNS_RESOLVER=""
BOX_TAILSCALE_FWMARK=""
BOX_TAILSCALE_ROUTE_TABLE=""

BOX_FIREWALL_BACKEND=""
BOX_ROUTE_TABLE=""
BOX_ROUTE_PREF=""
BOX_FWMARK=""

BOX_CORE_BIN_DIR=""
BOX_CORE_WORKDIR=""
BOX_CORE_CONFIG_SOURCE=""

BOX_UPDATER_ARTIFACT_DIR=""
BOX_UPDATER_STAGING_DIR=""
BOX_UPDATER_CHECKSUM_POLICY=""
BOX_UPDATER_KERNEL_INTERVAL=""
BOX_UPDATER_SUBS_INTERVAL=""
BOX_UPDATER_GEO_INTERVAL=""
BOX_UPDATER_DASHBOARD_INTERVAL=""
BOX_UPDATER_KERNEL_URL=""
BOX_UPDATER_KERNEL_FILE=""
BOX_UPDATER_KERNEL_SOURCE=""
BOX_UPDATER_KERNEL_RELEASE_API_URL=""
BOX_UPDATER_KERNEL_RELEASE_REPO=""
BOX_UPDATER_KERNEL_RELEASE_CHANNEL=""
BOX_UPDATER_KERNEL_RELEASE_TAG=""
BOX_UPDATER_KERNEL_ASSET_REGEX=""
BOX_UPDATER_KERNEL_CHECKSUM_ASSET_REGEX=""
BOX_UPDATER_KERNEL_RELEASE_OS=""
BOX_UPDATER_KERNEL_RELEASE_ARCH=""
BOX_UPDATER_KERNEL_ARCHIVE_MEMBER_REGEX=""
BOX_UPDATER_KERNEL_CHECKSUM=""
BOX_UPDATER_KERNEL_CHECKSUM_FILE=""
BOX_UPDATER_KERNEL_TARGET=""
BOX_UPDATER_SUBS_URL=""
BOX_UPDATER_SUBS_FILE=""
BOX_UPDATER_SUBS_CHECKSUM=""
BOX_UPDATER_SUBS_CHECKSUM_FILE=""
BOX_UPDATER_SUBS_TARGET=""
BOX_UPDATER_GEO_URL=""
BOX_UPDATER_GEO_FILE=""
BOX_UPDATER_GEO_SOURCE=""
BOX_UPDATER_GEO_RELEASE_API_URL=""
BOX_UPDATER_GEO_RELEASE_REPO=""
BOX_UPDATER_GEO_RELEASE_CHANNEL=""
BOX_UPDATER_GEO_RELEASE_TAG=""
BOX_UPDATER_GEO_ASSET_REGEX=""
BOX_UPDATER_GEO_CHECKSUM_ASSET_REGEX=""
BOX_UPDATER_GEO_RELEASE_OS=""
BOX_UPDATER_GEO_RELEASE_ARCH=""
BOX_UPDATER_GEO_ARCHIVE_MEMBER_REGEX=""
BOX_UPDATER_GEO_CHECKSUM=""
BOX_UPDATER_GEO_CHECKSUM_FILE=""
BOX_UPDATER_GEO_TARGET=""
BOX_UPDATER_DASHBOARD_URL=""
BOX_UPDATER_DASHBOARD_FILE=""
BOX_UPDATER_DASHBOARD_CHECKSUM=""
BOX_UPDATER_DASHBOARD_CHECKSUM_FILE=""
BOX_UPDATER_DASHBOARD_TARGET=""

config_defaults() {
  BOX_CORE="mihomo"
  BOX_NETWORK_MODE="tun"
  BOX_TPROXY_PORT="9898"
  BOX_REDIR_PORT="9797"
  BOX_DNS_PORT="1053"
  BOX_DNS_HIJACK_MODE="tproxy"
  BOX_DNS_COEXIST_MODE="preserve_tailnet"
  BOX_TAILSCALE_IFACE="tailscale0"
  BOX_TAILNET_IPV4_CIDR="100.64.0.0/10"
  BOX_TAILNET_IPV6_CIDR="fd7a:115c:a1e0::/48"
  BOX_TAILSCALE_DNS_RESOLVER="100.100.100.100"
  BOX_TAILSCALE_FWMARK="0x80000/0xff0000"
  BOX_TAILSCALE_ROUTE_TABLE="52"
  BOX_FIREWALL_BACKEND="iptables"
  BOX_ROUTE_TABLE="2024"
  BOX_ROUTE_PREF="100"
  BOX_FWMARK="16777216/16777216"
  BOX_CORE_BIN_DIR="/usr/local/bin"
  BOX_CORE_WORKDIR="${BOX_VAR_DIR_DEFAULT}"
  BOX_CORE_CONFIG_SOURCE="/etc/box/profiles/config.yaml"
  BOX_UPDATER_ARTIFACT_DIR="${BOX_VAR_DIR_DEFAULT}/artifacts"
  BOX_UPDATER_STAGING_DIR="${BOX_VAR_DIR_DEFAULT}/staging"
  BOX_UPDATER_CHECKSUM_POLICY="optional"
  BOX_UPDATER_KERNEL_INTERVAL="daily"
  BOX_UPDATER_SUBS_INTERVAL="hourly"
  BOX_UPDATER_GEO_INTERVAL="daily"
  BOX_UPDATER_DASHBOARD_INTERVAL="weekly"
  BOX_UPDATER_KERNEL_URL=""
  BOX_UPDATER_KERNEL_FILE=""
  BOX_UPDATER_KERNEL_SOURCE="auto"
  BOX_UPDATER_KERNEL_RELEASE_API_URL=""
  BOX_UPDATER_KERNEL_RELEASE_REPO=""
  BOX_UPDATER_KERNEL_RELEASE_CHANNEL="stable"
  BOX_UPDATER_KERNEL_RELEASE_TAG=""
  BOX_UPDATER_KERNEL_ASSET_REGEX=""
  BOX_UPDATER_KERNEL_CHECKSUM_ASSET_REGEX=""
  BOX_UPDATER_KERNEL_RELEASE_OS="linux"
  BOX_UPDATER_KERNEL_RELEASE_ARCH=""
  BOX_UPDATER_KERNEL_ARCHIVE_MEMBER_REGEX=""
  BOX_UPDATER_KERNEL_CHECKSUM=""
  BOX_UPDATER_KERNEL_CHECKSUM_FILE=""
  BOX_UPDATER_KERNEL_TARGET=""
  BOX_UPDATER_SUBS_URL=""
  BOX_UPDATER_SUBS_FILE=""
  BOX_UPDATER_SUBS_CHECKSUM=""
  BOX_UPDATER_SUBS_CHECKSUM_FILE=""
  BOX_UPDATER_SUBS_TARGET=""
  BOX_UPDATER_GEO_URL=""
  BOX_UPDATER_GEO_FILE=""
  BOX_UPDATER_GEO_SOURCE="auto"
  BOX_UPDATER_GEO_RELEASE_API_URL=""
  BOX_UPDATER_GEO_RELEASE_REPO=""
  BOX_UPDATER_GEO_RELEASE_CHANNEL="stable"
  BOX_UPDATER_GEO_RELEASE_TAG=""
  BOX_UPDATER_GEO_ASSET_REGEX=""
  BOX_UPDATER_GEO_CHECKSUM_ASSET_REGEX=""
  BOX_UPDATER_GEO_RELEASE_OS="linux"
  BOX_UPDATER_GEO_RELEASE_ARCH=""
  BOX_UPDATER_GEO_ARCHIVE_MEMBER_REGEX=""
  BOX_UPDATER_GEO_CHECKSUM=""
  BOX_UPDATER_GEO_CHECKSUM_FILE=""
  BOX_UPDATER_GEO_TARGET=""
  BOX_UPDATER_DASHBOARD_URL=""
  BOX_UPDATER_DASHBOARD_FILE=""
  BOX_UPDATER_DASHBOARD_CHECKSUM=""
  BOX_UPDATER_DASHBOARD_CHECKSUM_FILE=""
  BOX_UPDATER_DASHBOARD_TARGET=""
}

# Keep sourced-state deterministic even before load_config is called.
config_defaults

trim_space() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

strip_inline_comment() {
  local value="${1:-}"
  local trimmed first_char
  trimmed="${value#"${value%%[![:space:]]*}"}"
  first_char="${trimmed:0:1}"
  if [[ "${first_char}" == "\"" || "${first_char}" == "'" ]]; then
    printf '%s' "${value}"
    return
  fi
  value="${value%%#*}"
  printf '%s' "${value}"
}

toml_value() {
  local file="${1:?missing toml file}"
  local section="${2:?missing section}"
  local key="${3:?missing key}"
  awk -v target_section="${section}" -v target_key="${key}" '
    BEGIN { section = "" }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*\[/ {
      line = $0
      gsub(/^[[:space:]]*\[/, "", line)
      gsub(/\][[:space:]]*$/, "", line)
      gsub(/[[:space:]]/, "", line)
      section = line
      next
    }
    section == target_section {
      line = $0
      if (line ~ "^[[:space:]]*" target_key "[[:space:]]*=") {
        sub(/^[^=]*=/, "", line)
        print line
        exit
      }
    }
  ' "${file}"
}

normalize_toml_scalar() {
  local value
  value="$(trim_space "$(strip_inline_comment "${1:-}")")"
  if [[ "${value}" =~ ^\"(.*)\"$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "${value}" =~ ^\'(.*)\'$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return
  fi
  printf '%s' "${value}"
}

config_read_value() {
  local file="${1:?missing file}"
  local section="${2:?missing section}"
  local key="${3:?missing key}"
  local raw
  raw="$(toml_value "${file}" "${section}" "${key}" || true)"
  if [[ -z "${raw}" ]]; then
    return 1
  fi
  normalize_toml_scalar "${raw}"
}

config_detect_file() {
  local explicit_cfg="${BOX_CONFIG_FILE:-}"
  local system_cfg="${BOX_ETC_DIR_DEFAULT}/box.toml"
  local dev_cfg="${BOX_REPO_ROOT}/etc/box/box.toml"

  if [[ -n "${explicit_cfg}" ]]; then
    if [[ -f "${explicit_cfg}" ]]; then
      BOX_CONFIG_FILE="${explicit_cfg}"
      BOX_CONFIG_SOURCE="explicit"
      return 0
    fi
    BOX_CONFIG_SOURCE="explicit-missing"
    log "ERROR" "config" "E_CONFIG_FILE" "explicit BOX_CONFIG_FILE does not exist: ${explicit_cfg}"
    return "${E_CONFIG}"
  fi

  if [[ -f "${system_cfg}" ]]; then
    BOX_CONFIG_FILE="${system_cfg}"
    BOX_CONFIG_SOURCE="system"
    return 0
  fi

  if [[ -f "${dev_cfg}" ]]; then
    BOX_CONFIG_FILE="${dev_cfg}"
    BOX_CONFIG_SOURCE="dev-fallback"
    return 0
  fi

  BOX_CONFIG_FILE=""
  BOX_CONFIG_SOURCE="defaults-only"
  return 1
}

validate_port() {
  local value="${1:-}"
  [[ "${value}" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 65535 ))
}

validate_uint() {
  local value="${1:-}"
  [[ "${value}" =~ ^[0-9]+$ ]]
}

validate_config() {
  case "${BOX_CORE}" in
    mihomo|sing-box) ;;
    *)
      log "ERROR" "config" "E_CONFIG_CORE" "unsupported core: ${BOX_CORE}"
      return "${E_CONFIG}"
      ;;
  esac

  case "${BOX_NETWORK_MODE}" in
    tun|tproxy|redirect|mixed|enhance) ;;
    *)
      log "ERROR" "config" "E_CONFIG_MODE" "invalid network mode: ${BOX_NETWORK_MODE}"
      return "${E_CONFIG}"
      ;;
  esac

  if ! validate_port "${BOX_TPROXY_PORT}"; then
    log "ERROR" "config" "E_CONFIG_PORT" "invalid tproxy port: ${BOX_TPROXY_PORT}"
    return "${E_CONFIG}"
  fi
  if ! validate_port "${BOX_REDIR_PORT}"; then
    log "ERROR" "config" "E_CONFIG_PORT" "invalid redirect port: ${BOX_REDIR_PORT}"
    return "${E_CONFIG}"
  fi
  if ! validate_port "${BOX_DNS_PORT}"; then
    log "ERROR" "config" "E_CONFIG_PORT" "invalid dns port: ${BOX_DNS_PORT}"
    return "${E_CONFIG}"
  fi

  case "${BOX_DNS_HIJACK_MODE}" in
    tproxy|redirect|disable) ;;
    *)
      log "ERROR" "config" "E_CONFIG_DNS_MODE" "invalid dns_hijack_mode: ${BOX_DNS_HIJACK_MODE}"
      return "${E_CONFIG}"
      ;;
  esac

  case "${BOX_DNS_COEXIST_MODE}" in
    preserve_tailnet|strict_box) ;;
    *)
      log "ERROR" "config" "E_CONFIG_DNS_COEXIST" "invalid dns_coexist_mode: ${BOX_DNS_COEXIST_MODE}"
      return "${E_CONFIG}"
      ;;
  esac

  if ! validate_uint "${BOX_ROUTE_TABLE}"; then
    log "ERROR" "config" "E_CONFIG_ROUTE_TABLE" "route_table must be numeric: ${BOX_ROUTE_TABLE}"
    return "${E_CONFIG}"
  fi
  if ! validate_uint "${BOX_TAILSCALE_ROUTE_TABLE}"; then
    log "ERROR" "config" "E_CONFIG_TAILSCALE_ROUTE_TABLE" \
      "tailscale_route_table must be numeric: ${BOX_TAILSCALE_ROUTE_TABLE}"
    return "${E_CONFIG}"
  fi
  if ! validate_uint "${BOX_ROUTE_PREF}"; then
    log "ERROR" "config" "E_CONFIG_ROUTE_PREF" "route_pref must be numeric: ${BOX_ROUTE_PREF}"
    return "${E_CONFIG}"
  fi

  if [[ "${BOX_ROUTE_TABLE}" == "${BOX_TAILSCALE_ROUTE_TABLE}" ]]; then
    log "ERROR" "config" "E_CONFIG_ROUTE_TABLE" \
      "box route_table (${BOX_ROUTE_TABLE}) must differ from tailscale_route_table (${BOX_TAILSCALE_ROUTE_TABLE})"
    return "${E_CONFIG}"
  fi

  if [[ "${BOX_FWMARK}" == "${BOX_TAILSCALE_FWMARK}" ]]; then
    log "ERROR" "config" "E_CONFIG_FWMARK" \
      "box fwmark (${BOX_FWMARK}) must differ from tailscale_fwmark (${BOX_TAILSCALE_FWMARK})"
    return "${E_CONFIG}"
  fi

  if [[ -z "${BOX_TAILSCALE_IFACE}" || -z "${BOX_TAILNET_IPV4_CIDR}" || -z "${BOX_TAILSCALE_DNS_RESOLVER}" ]]; then
    log "ERROR" "config" "E_CONFIG_TAILSCALE" "tailscale coexist fields must not be empty"
    return "${E_CONFIG}"
  fi

  case "${BOX_FIREWALL_BACKEND}" in
    iptables|nftables) ;;
    *)
      log "ERROR" "config" "E_CONFIG_FW_BACKEND" "unsupported firewall backend: ${BOX_FIREWALL_BACKEND}"
      return "${E_CONFIG}"
      ;;
  esac

  case "${BOX_UPDATER_CHECKSUM_POLICY}" in
    off|optional|required) ;;
    *)
      log "ERROR" "config" "E_CONFIG_UPDATER_CHECKSUM" \
        "unsupported updater checksum_policy: ${BOX_UPDATER_CHECKSUM_POLICY}"
      return "${E_CONFIG}"
      ;;
  esac

  if [[ -z "${BOX_UPDATER_ARTIFACT_DIR}" || -z "${BOX_UPDATER_STAGING_DIR}" ]]; then
    log "ERROR" "config" "E_CONFIG_UPDATER_DIR" "updater artifact_dir and staging_dir must not be empty"
    return "${E_CONFIG}"
  fi

  case "${BOX_UPDATER_KERNEL_SOURCE}" in
    auto|file|url|release) ;;
    *)
      log "ERROR" "config" "E_CONFIG_UPDATER_KERNEL_SOURCE" \
        "unsupported updater.kernel.source: ${BOX_UPDATER_KERNEL_SOURCE}"
      return "${E_CONFIG}"
      ;;
  esac

  case "${BOX_UPDATER_GEO_SOURCE}" in
    auto|file|url|release) ;;
    *)
      log "ERROR" "config" "E_CONFIG_UPDATER_GEO_SOURCE" \
        "unsupported updater.geo.source: ${BOX_UPDATER_GEO_SOURCE}"
      return "${E_CONFIG}"
      ;;
  esac

  case "${BOX_UPDATER_KERNEL_RELEASE_CHANNEL}" in
    stable|prerelease|any) ;;
    *)
      log "ERROR" "config" "E_CONFIG_UPDATER_KERNEL_CHANNEL" \
        "unsupported updater.kernel.release_channel: ${BOX_UPDATER_KERNEL_RELEASE_CHANNEL}"
      return "${E_CONFIG}"
      ;;
  esac

  case "${BOX_UPDATER_GEO_RELEASE_CHANNEL}" in
    stable|prerelease|any) ;;
    *)
      log "ERROR" "config" "E_CONFIG_UPDATER_GEO_CHANNEL" \
        "unsupported updater.geo.release_channel: ${BOX_UPDATER_GEO_RELEASE_CHANNEL}"
      return "${E_CONFIG}"
      ;;
  esac

  if [[ "${BOX_UPDATER_GEO_SOURCE}" == "release" &&
    -z "${BOX_UPDATER_GEO_RELEASE_REPO}" &&
    -z "${BOX_UPDATER_GEO_RELEASE_API_URL}" ]]; then
    log "ERROR" "config" "E_CONFIG_UPDATER_GEO_RELEASE" \
      "updater.geo release source requires release_repo or release_api_url"
    return "${E_CONFIG}"
  fi
}

load_config() {
  config_defaults

  if ! config_detect_file; then
    if [[ "${BOX_CONFIG_SOURCE}" == "explicit-missing" ]]; then
      return "${E_CONFIG}"
    fi
    log "WARN" "config" "W_CONFIG_DEFAULTS" "no box.toml found; using defaults"
    validate_config
    export BOX_CONFIG_FILE BOX_CONFIG_SOURCE
    export BOX_CORE BOX_NETWORK_MODE BOX_TPROXY_PORT BOX_REDIR_PORT BOX_DNS_PORT BOX_DNS_HIJACK_MODE BOX_DNS_COEXIST_MODE
    export BOX_TAILSCALE_IFACE BOX_TAILNET_IPV4_CIDR BOX_TAILNET_IPV6_CIDR BOX_TAILSCALE_DNS_RESOLVER BOX_TAILSCALE_FWMARK BOX_TAILSCALE_ROUTE_TABLE
    export BOX_FIREWALL_BACKEND BOX_ROUTE_TABLE BOX_ROUTE_PREF BOX_FWMARK
    export BOX_CORE_BIN_DIR BOX_CORE_WORKDIR BOX_CORE_CONFIG_SOURCE
    export BOX_UPDATER_ARTIFACT_DIR BOX_UPDATER_STAGING_DIR BOX_UPDATER_CHECKSUM_POLICY
    export BOX_UPDATER_KERNEL_INTERVAL BOX_UPDATER_SUBS_INTERVAL BOX_UPDATER_GEO_INTERVAL BOX_UPDATER_DASHBOARD_INTERVAL
    export BOX_UPDATER_KERNEL_URL BOX_UPDATER_KERNEL_FILE BOX_UPDATER_KERNEL_SOURCE BOX_UPDATER_KERNEL_RELEASE_API_URL
    export BOX_UPDATER_KERNEL_RELEASE_REPO BOX_UPDATER_KERNEL_RELEASE_CHANNEL BOX_UPDATER_KERNEL_RELEASE_TAG
    export BOX_UPDATER_KERNEL_ASSET_REGEX BOX_UPDATER_KERNEL_CHECKSUM_ASSET_REGEX BOX_UPDATER_KERNEL_RELEASE_OS BOX_UPDATER_KERNEL_RELEASE_ARCH
    export BOX_UPDATER_KERNEL_ARCHIVE_MEMBER_REGEX BOX_UPDATER_KERNEL_CHECKSUM BOX_UPDATER_KERNEL_CHECKSUM_FILE BOX_UPDATER_KERNEL_TARGET
    export BOX_UPDATER_SUBS_URL BOX_UPDATER_SUBS_FILE BOX_UPDATER_SUBS_CHECKSUM BOX_UPDATER_SUBS_CHECKSUM_FILE BOX_UPDATER_SUBS_TARGET
    export BOX_UPDATER_GEO_URL BOX_UPDATER_GEO_FILE BOX_UPDATER_GEO_SOURCE BOX_UPDATER_GEO_RELEASE_API_URL
    export BOX_UPDATER_GEO_RELEASE_REPO BOX_UPDATER_GEO_RELEASE_CHANNEL BOX_UPDATER_GEO_RELEASE_TAG
    export BOX_UPDATER_GEO_ASSET_REGEX BOX_UPDATER_GEO_CHECKSUM_ASSET_REGEX BOX_UPDATER_GEO_RELEASE_OS BOX_UPDATER_GEO_RELEASE_ARCH
    export BOX_UPDATER_GEO_ARCHIVE_MEMBER_REGEX BOX_UPDATER_GEO_CHECKSUM BOX_UPDATER_GEO_CHECKSUM_FILE BOX_UPDATER_GEO_TARGET
    export BOX_UPDATER_DASHBOARD_URL BOX_UPDATER_DASHBOARD_FILE BOX_UPDATER_DASHBOARD_CHECKSUM BOX_UPDATER_DASHBOARD_CHECKSUM_FILE BOX_UPDATER_DASHBOARD_TARGET
    return 0
  fi

  log "INFO" "config" "CONFIG_SOURCE" "loaded ${BOX_CONFIG_SOURCE} config from ${BOX_CONFIG_FILE}"

  BOX_CORE="$(config_read_value "${BOX_CONFIG_FILE}" "core" "selected" || printf '%s' "${BOX_CORE}")"
  BOX_CORE_BIN_DIR="$(config_read_value "${BOX_CONFIG_FILE}" "core" "bin_dir" || printf '%s' "${BOX_CORE_BIN_DIR}")"
  BOX_CORE_WORKDIR="$(config_read_value "${BOX_CONFIG_FILE}" "core" "workdir" || printf '%s' "${BOX_CORE_WORKDIR}")"
  BOX_CORE_CONFIG_SOURCE="$(config_read_value "${BOX_CONFIG_FILE}" "core" "config_source" || printf '%s' "${BOX_CORE_CONFIG_SOURCE}")"

  BOX_NETWORK_MODE="$(config_read_value "${BOX_CONFIG_FILE}" "network" "mode" || printf '%s' "${BOX_NETWORK_MODE}")"
  BOX_TPROXY_PORT="$(config_read_value "${BOX_CONFIG_FILE}" "network" "tproxy_port" || printf '%s' "${BOX_TPROXY_PORT}")"
  BOX_REDIR_PORT="$(config_read_value "${BOX_CONFIG_FILE}" "network" "redir_port" || printf '%s' "${BOX_REDIR_PORT}")"
  BOX_DNS_PORT="$(config_read_value "${BOX_CONFIG_FILE}" "network" "dns_port" || printf '%s' "${BOX_DNS_PORT}")"
  BOX_DNS_HIJACK_MODE="$(config_read_value "${BOX_CONFIG_FILE}" "network" "dns_hijack_mode" || printf '%s' "${BOX_DNS_HIJACK_MODE}")"
  BOX_DNS_COEXIST_MODE="$(config_read_value "${BOX_CONFIG_FILE}" "network" "dns_coexist_mode" || printf '%s' "${BOX_DNS_COEXIST_MODE}")"
  BOX_TAILSCALE_IFACE="$(config_read_value "${BOX_CONFIG_FILE}" "network" "tailscale_iface" || printf '%s' "${BOX_TAILSCALE_IFACE}")"
  BOX_TAILNET_IPV4_CIDR="$(config_read_value "${BOX_CONFIG_FILE}" "network" "tailnet_ipv4_cidr" || printf '%s' "${BOX_TAILNET_IPV4_CIDR}")"
  BOX_TAILNET_IPV6_CIDR="$(config_read_value "${BOX_CONFIG_FILE}" "network" "tailnet_ipv6_cidr" || printf '%s' "${BOX_TAILNET_IPV6_CIDR}")"
  BOX_TAILSCALE_DNS_RESOLVER="$(config_read_value "${BOX_CONFIG_FILE}" "network" "tailscale_dns_resolver" || printf '%s' "${BOX_TAILSCALE_DNS_RESOLVER}")"
  BOX_TAILSCALE_FWMARK="$(config_read_value "${BOX_CONFIG_FILE}" "network" "tailscale_fwmark" || printf '%s' "${BOX_TAILSCALE_FWMARK}")"
  BOX_TAILSCALE_ROUTE_TABLE="$(config_read_value "${BOX_CONFIG_FILE}" "network" "tailscale_route_table" || printf '%s' "${BOX_TAILSCALE_ROUTE_TABLE}")"

  BOX_FIREWALL_BACKEND="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "backend" || printf '%s' "${BOX_FIREWALL_BACKEND}")"
  BOX_ROUTE_TABLE="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "route_table" || printf '%s' "${BOX_ROUTE_TABLE}")"
  BOX_ROUTE_PREF="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "route_pref" || printf '%s' "${BOX_ROUTE_PREF}")"
  BOX_FWMARK="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "fwmark" || printf '%s' "${BOX_FWMARK}")"

  BOX_UPDATER_ARTIFACT_DIR="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "artifact_dir" || printf '%s' "${BOX_UPDATER_ARTIFACT_DIR}")"
  BOX_UPDATER_STAGING_DIR="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "staging_dir" || printf '%s' "${BOX_UPDATER_STAGING_DIR}")"
  BOX_UPDATER_CHECKSUM_POLICY="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "checksum_policy" || printf '%s' "${BOX_UPDATER_CHECKSUM_POLICY}")"
  BOX_UPDATER_KERNEL_INTERVAL="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "kernel_interval" || printf '%s' "${BOX_UPDATER_KERNEL_INTERVAL}")"
  BOX_UPDATER_SUBS_INTERVAL="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "subs_interval" || printf '%s' "${BOX_UPDATER_SUBS_INTERVAL}")"
  BOX_UPDATER_GEO_INTERVAL="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "geo_interval" || printf '%s' "${BOX_UPDATER_GEO_INTERVAL}")"
  BOX_UPDATER_DASHBOARD_INTERVAL="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "dashboard_interval" || printf '%s' "${BOX_UPDATER_DASHBOARD_INTERVAL}")"

  BOX_UPDATER_KERNEL_URL="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "url" || printf '%s' "${BOX_UPDATER_KERNEL_URL}")"
  BOX_UPDATER_KERNEL_FILE="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "file" || printf '%s' "${BOX_UPDATER_KERNEL_FILE}")"
  BOX_UPDATER_KERNEL_SOURCE="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "source" || printf '%s' "${BOX_UPDATER_KERNEL_SOURCE}")"
  BOX_UPDATER_KERNEL_RELEASE_API_URL="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "release_api_url" || printf '%s' "${BOX_UPDATER_KERNEL_RELEASE_API_URL}")"
  BOX_UPDATER_KERNEL_RELEASE_REPO="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "release_repo" || printf '%s' "${BOX_UPDATER_KERNEL_RELEASE_REPO}")"
  BOX_UPDATER_KERNEL_RELEASE_CHANNEL="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "release_channel" || printf '%s' "${BOX_UPDATER_KERNEL_RELEASE_CHANNEL}")"
  BOX_UPDATER_KERNEL_RELEASE_TAG="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "release_tag" || printf '%s' "${BOX_UPDATER_KERNEL_RELEASE_TAG}")"
  BOX_UPDATER_KERNEL_ASSET_REGEX="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "asset_regex" || printf '%s' "${BOX_UPDATER_KERNEL_ASSET_REGEX}")"
  BOX_UPDATER_KERNEL_CHECKSUM_ASSET_REGEX="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "checksum_asset_regex" || printf '%s' "${BOX_UPDATER_KERNEL_CHECKSUM_ASSET_REGEX}")"
  BOX_UPDATER_KERNEL_RELEASE_OS="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "release_os" || printf '%s' "${BOX_UPDATER_KERNEL_RELEASE_OS}")"
  BOX_UPDATER_KERNEL_RELEASE_ARCH="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "release_arch" || printf '%s' "${BOX_UPDATER_KERNEL_RELEASE_ARCH}")"
  BOX_UPDATER_KERNEL_ARCHIVE_MEMBER_REGEX="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "archive_member_regex" || printf '%s' "${BOX_UPDATER_KERNEL_ARCHIVE_MEMBER_REGEX}")"
  BOX_UPDATER_KERNEL_CHECKSUM="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "checksum" || printf '%s' "${BOX_UPDATER_KERNEL_CHECKSUM}")"
  BOX_UPDATER_KERNEL_CHECKSUM_FILE="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "checksum_file" || printf '%s' "${BOX_UPDATER_KERNEL_CHECKSUM_FILE}")"
  BOX_UPDATER_KERNEL_TARGET="$(config_read_value "${BOX_CONFIG_FILE}" "updater.kernel" "target" || printf '%s' "${BOX_UPDATER_KERNEL_TARGET}")"

  BOX_UPDATER_SUBS_URL="$(config_read_value "${BOX_CONFIG_FILE}" "updater.subs" "url" || printf '%s' "${BOX_UPDATER_SUBS_URL}")"
  BOX_UPDATER_SUBS_FILE="$(config_read_value "${BOX_CONFIG_FILE}" "updater.subs" "file" || printf '%s' "${BOX_UPDATER_SUBS_FILE}")"
  BOX_UPDATER_SUBS_CHECKSUM="$(config_read_value "${BOX_CONFIG_FILE}" "updater.subs" "checksum" || printf '%s' "${BOX_UPDATER_SUBS_CHECKSUM}")"
  BOX_UPDATER_SUBS_CHECKSUM_FILE="$(config_read_value "${BOX_CONFIG_FILE}" "updater.subs" "checksum_file" || printf '%s' "${BOX_UPDATER_SUBS_CHECKSUM_FILE}")"
  BOX_UPDATER_SUBS_TARGET="$(config_read_value "${BOX_CONFIG_FILE}" "updater.subs" "target" || printf '%s' "${BOX_UPDATER_SUBS_TARGET}")"

  BOX_UPDATER_GEO_URL="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "url" || printf '%s' "${BOX_UPDATER_GEO_URL}")"
  BOX_UPDATER_GEO_FILE="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "file" || printf '%s' "${BOX_UPDATER_GEO_FILE}")"
  BOX_UPDATER_GEO_SOURCE="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "source" || printf '%s' "${BOX_UPDATER_GEO_SOURCE}")"
  BOX_UPDATER_GEO_RELEASE_API_URL="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "release_api_url" || printf '%s' "${BOX_UPDATER_GEO_RELEASE_API_URL}")"
  BOX_UPDATER_GEO_RELEASE_REPO="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "release_repo" || printf '%s' "${BOX_UPDATER_GEO_RELEASE_REPO}")"
  BOX_UPDATER_GEO_RELEASE_CHANNEL="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "release_channel" || printf '%s' "${BOX_UPDATER_GEO_RELEASE_CHANNEL}")"
  BOX_UPDATER_GEO_RELEASE_TAG="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "release_tag" || printf '%s' "${BOX_UPDATER_GEO_RELEASE_TAG}")"
  BOX_UPDATER_GEO_ASSET_REGEX="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "asset_regex" || printf '%s' "${BOX_UPDATER_GEO_ASSET_REGEX}")"
  BOX_UPDATER_GEO_CHECKSUM_ASSET_REGEX="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "checksum_asset_regex" || printf '%s' "${BOX_UPDATER_GEO_CHECKSUM_ASSET_REGEX}")"
  BOX_UPDATER_GEO_RELEASE_OS="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "release_os" || printf '%s' "${BOX_UPDATER_GEO_RELEASE_OS}")"
  BOX_UPDATER_GEO_RELEASE_ARCH="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "release_arch" || printf '%s' "${BOX_UPDATER_GEO_RELEASE_ARCH}")"
  BOX_UPDATER_GEO_ARCHIVE_MEMBER_REGEX="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "archive_member_regex" || printf '%s' "${BOX_UPDATER_GEO_ARCHIVE_MEMBER_REGEX}")"
  BOX_UPDATER_GEO_CHECKSUM="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "checksum" || printf '%s' "${BOX_UPDATER_GEO_CHECKSUM}")"
  BOX_UPDATER_GEO_CHECKSUM_FILE="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "checksum_file" || printf '%s' "${BOX_UPDATER_GEO_CHECKSUM_FILE}")"
  BOX_UPDATER_GEO_TARGET="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "target" || printf '%s' "${BOX_UPDATER_GEO_TARGET}")"

  BOX_UPDATER_DASHBOARD_URL="$(config_read_value "${BOX_CONFIG_FILE}" "updater.dashboard" "url" || printf '%s' "${BOX_UPDATER_DASHBOARD_URL}")"
  BOX_UPDATER_DASHBOARD_FILE="$(config_read_value "${BOX_CONFIG_FILE}" "updater.dashboard" "file" || printf '%s' "${BOX_UPDATER_DASHBOARD_FILE}")"
  BOX_UPDATER_DASHBOARD_CHECKSUM="$(config_read_value "${BOX_CONFIG_FILE}" "updater.dashboard" "checksum" || printf '%s' "${BOX_UPDATER_DASHBOARD_CHECKSUM}")"
  BOX_UPDATER_DASHBOARD_CHECKSUM_FILE="$(config_read_value "${BOX_CONFIG_FILE}" "updater.dashboard" "checksum_file" || printf '%s' "${BOX_UPDATER_DASHBOARD_CHECKSUM_FILE}")"
  BOX_UPDATER_DASHBOARD_TARGET="$(config_read_value "${BOX_CONFIG_FILE}" "updater.dashboard" "target" || printf '%s' "${BOX_UPDATER_DASHBOARD_TARGET}")"

  validate_config

  # validate_config constrains BOX_CORE and BOX_CONFIG_FILE/BOX_CONFIG_SOURCE inputs.
  # For sing-box, if the config source remains the default YAML profile path, rewrite
  # it to the JSON profile path before export; sing-box expects JSON at runtime.
  if [[ "${BOX_CORE}" == "sing-box" && "${BOX_CORE_CONFIG_SOURCE}" == "/etc/box/profiles/config.yaml" ]]; then
    BOX_CORE_CONFIG_SOURCE="/etc/box/profiles/config.json"
  fi

  export BOX_CONFIG_FILE BOX_CONFIG_SOURCE
  export BOX_CORE BOX_NETWORK_MODE BOX_TPROXY_PORT BOX_REDIR_PORT BOX_DNS_PORT BOX_DNS_HIJACK_MODE BOX_DNS_COEXIST_MODE
  export BOX_TAILSCALE_IFACE BOX_TAILNET_IPV4_CIDR BOX_TAILNET_IPV6_CIDR BOX_TAILSCALE_DNS_RESOLVER BOX_TAILSCALE_FWMARK BOX_TAILSCALE_ROUTE_TABLE
  export BOX_FIREWALL_BACKEND BOX_ROUTE_TABLE BOX_ROUTE_PREF BOX_FWMARK
  export BOX_CORE_BIN_DIR BOX_CORE_WORKDIR BOX_CORE_CONFIG_SOURCE
  export BOX_UPDATER_ARTIFACT_DIR BOX_UPDATER_STAGING_DIR BOX_UPDATER_CHECKSUM_POLICY
  export BOX_UPDATER_KERNEL_INTERVAL BOX_UPDATER_SUBS_INTERVAL BOX_UPDATER_GEO_INTERVAL BOX_UPDATER_DASHBOARD_INTERVAL
  export BOX_UPDATER_KERNEL_URL BOX_UPDATER_KERNEL_FILE BOX_UPDATER_KERNEL_SOURCE BOX_UPDATER_KERNEL_RELEASE_API_URL
  export BOX_UPDATER_KERNEL_RELEASE_REPO BOX_UPDATER_KERNEL_RELEASE_CHANNEL BOX_UPDATER_KERNEL_RELEASE_TAG
  export BOX_UPDATER_KERNEL_ASSET_REGEX BOX_UPDATER_KERNEL_CHECKSUM_ASSET_REGEX BOX_UPDATER_KERNEL_RELEASE_OS BOX_UPDATER_KERNEL_RELEASE_ARCH
  export BOX_UPDATER_KERNEL_ARCHIVE_MEMBER_REGEX BOX_UPDATER_KERNEL_CHECKSUM BOX_UPDATER_KERNEL_CHECKSUM_FILE BOX_UPDATER_KERNEL_TARGET
  export BOX_UPDATER_SUBS_URL BOX_UPDATER_SUBS_FILE BOX_UPDATER_SUBS_CHECKSUM BOX_UPDATER_SUBS_CHECKSUM_FILE BOX_UPDATER_SUBS_TARGET
  export BOX_UPDATER_GEO_URL BOX_UPDATER_GEO_FILE BOX_UPDATER_GEO_SOURCE BOX_UPDATER_GEO_RELEASE_API_URL
  export BOX_UPDATER_GEO_RELEASE_REPO BOX_UPDATER_GEO_RELEASE_CHANNEL BOX_UPDATER_GEO_RELEASE_TAG
  export BOX_UPDATER_GEO_ASSET_REGEX BOX_UPDATER_GEO_CHECKSUM_ASSET_REGEX BOX_UPDATER_GEO_RELEASE_OS BOX_UPDATER_GEO_RELEASE_ARCH
  export BOX_UPDATER_GEO_ARCHIVE_MEMBER_REGEX BOX_UPDATER_GEO_CHECKSUM BOX_UPDATER_GEO_CHECKSUM_FILE BOX_UPDATER_GEO_TARGET
  export BOX_UPDATER_DASHBOARD_URL BOX_UPDATER_DASHBOARD_FILE BOX_UPDATER_DASHBOARD_CHECKSUM BOX_UPDATER_DASHBOARD_CHECKSUM_FILE BOX_UPDATER_DASHBOARD_TARGET
}
