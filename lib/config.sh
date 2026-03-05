#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

BOX_CONFIG_FILE=""
BOX_CONFIG_SOURCE=""

BOX_CORE="mihomo"
BOX_NETWORK_MODE="tun"
BOX_TPROXY_PORT="9898"
BOX_REDIR_PORT="9797"
BOX_DNS_HIJACK_MODE="tproxy"

BOX_FIREWALL_BACKEND="iptables"
BOX_ROUTE_TABLE="2024"
BOX_ROUTE_PREF="100"
BOX_FWMARK="16777216/16777216"

BOX_CORE_BIN_DIR="/usr/local/bin"
BOX_CORE_WORKDIR="${BOX_VAR_DIR_DEFAULT}"
BOX_CORE_CONFIG_SOURCE="/etc/box/profiles/config.yaml"

config_defaults() {
  BOX_CORE="mihomo"
  BOX_NETWORK_MODE="tun"
  BOX_TPROXY_PORT="9898"
  BOX_REDIR_PORT="9797"
  BOX_DNS_HIJACK_MODE="tproxy"
  BOX_FIREWALL_BACKEND="iptables"
  BOX_ROUTE_TABLE="2024"
  BOX_ROUTE_PREF="100"
  BOX_FWMARK="16777216/16777216"
  BOX_CORE_BIN_DIR="/usr/local/bin"
  BOX_CORE_WORKDIR="${BOX_VAR_DIR_DEFAULT}"
  BOX_CORE_CONFIG_SOURCE="/etc/box/profiles/config.yaml"
}

trim_space() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

strip_inline_comment() {
  local value="${1:-}"
  local first_char="${value:0:1}"
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
  local system_cfg="${BOX_CONFIG_FILE:-${BOX_ETC_DIR_DEFAULT}/box.toml}"
  local dev_cfg="${BOX_REPO_ROOT}/etc/box/box.toml"

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
}

load_config() {
  config_defaults

  if ! config_detect_file; then
    log "WARN" "config" "W_CONFIG_DEFAULTS" "no box.toml found; using defaults"
    validate_config
    export BOX_CONFIG_FILE BOX_CONFIG_SOURCE
    export BOX_CORE BOX_NETWORK_MODE BOX_TPROXY_PORT BOX_REDIR_PORT BOX_DNS_HIJACK_MODE
    export BOX_FIREWALL_BACKEND BOX_ROUTE_TABLE BOX_ROUTE_PREF BOX_FWMARK
    export BOX_CORE_BIN_DIR BOX_CORE_WORKDIR BOX_CORE_CONFIG_SOURCE
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
  BOX_DNS_HIJACK_MODE="$(config_read_value "${BOX_CONFIG_FILE}" "network" "dns_hijack_mode" || printf '%s' "${BOX_DNS_HIJACK_MODE}")"

  BOX_FIREWALL_BACKEND="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "backend" || printf '%s' "${BOX_FIREWALL_BACKEND}")"
  BOX_ROUTE_TABLE="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "route_table" || printf '%s' "${BOX_ROUTE_TABLE}")"
  BOX_ROUTE_PREF="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "route_pref" || printf '%s' "${BOX_ROUTE_PREF}")"
  BOX_FWMARK="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "fwmark" || printf '%s' "${BOX_FWMARK}")"

  validate_config

  export BOX_CONFIG_FILE BOX_CONFIG_SOURCE
  export BOX_CORE BOX_NETWORK_MODE BOX_TPROXY_PORT BOX_REDIR_PORT BOX_DNS_HIJACK_MODE
  export BOX_FIREWALL_BACKEND BOX_ROUTE_TABLE BOX_ROUTE_PREF BOX_FWMARK
  export BOX_CORE_BIN_DIR BOX_CORE_WORKDIR BOX_CORE_CONFIG_SOURCE
}
