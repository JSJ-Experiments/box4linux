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
BOX_DNS_ENHANCED_MODE=""
BOX_DNS_COEXIST_MODE=""
BOX_IPV6_ENABLED=""
BOX_CAMPUS_DNS_MODE=""
BOX_CAMPUS_DNS_SUFFIX_POLICY=""
BOX_TAILSCALE_IFACE=""
BOX_TAILNET_IPV4_CIDR=""
BOX_TAILNET_IPV6_CIDR=""
BOX_TAILSCALE_DNS_RESOLVER=""
BOX_TAILSCALE_FWMARK=""
BOX_TAILSCALE_ROUTE_TABLE=""
declare -a BOX_CAMPUS_DNS_SUFFIXES=()
declare -a BOX_CAMPUS_DNS_PROBE_HOSTS=()
declare -a BOX_CAMPUS_DNS_PUBLIC_SERVERS=()

BOX_FIREWALL_BACKEND=""
BOX_ROUTE_TABLE=""
BOX_ROUTE_PREF=""
BOX_FWMARK=""
BOX_BYPASS_PRIVATE_IP=""
BOX_BYPASS_CN_IP=""
BOX_BYPASS_CN_FILE=""

BOX_POLICY_ENABLED=""
BOX_POLICY_PROXY_MODE=""
BOX_POLICY_DEBOUNCE_SECONDS=""
BOX_POLICY_USE_MODULE_ON_WIFI_DISCONNECT=""
BOX_POLICY_DISABLE_MARKER=""
declare -a BOX_POLICY_ALLOW_IFACES=()
declare -a BOX_POLICY_IGNORE_IFACES=()
declare -a BOX_POLICY_ALLOW_SSIDS=()
declare -a BOX_POLICY_IGNORE_SSIDS=()
declare -a BOX_POLICY_ALLOW_BSSIDS=()
declare -a BOX_POLICY_IGNORE_BSSIDS=()

BOX_CORE_BIN_DIR=""
BOX_CORE_WORKDIR=""
BOX_CORE_CONFIG_SOURCE=""

BOX_UPDATER_ARTIFACT_DIR=""
BOX_UPDATER_STAGING_DIR=""
BOX_UPDATER_CHECKSUM_POLICY=""
BOX_UPDATER_FETCH_RETRIES=""
BOX_UPDATER_FETCH_RETRY_BACKOFF_MS=""
BOX_UPDATER_USE_GHPROXY=""
BOX_UPDATER_GHPROXY_URL=""
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
BOX_UPDATER_SUBS_PRESET=""
BOX_UPDATER_SUBS_CHECKSUM=""
BOX_UPDATER_SUBS_CHECKSUM_FILE=""
BOX_UPDATER_SUBS_TARGET=""
declare -a BOX_UPDATER_SUBS_PROVIDER_NAMES=()
declare -a BOX_UPDATER_SUBS_PROVIDER_URLS=()
BOX_UPDATER_GEO_URL=""
BOX_UPDATER_GEO_FILE=""
BOX_UPDATER_GEO_SOURCE=""
BOX_UPDATER_GEO_PRESET=""
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
  BOX_DNS_ENHANCED_MODE="fake-ip"
  BOX_DNS_COEXIST_MODE="preserve_tailnet"
  BOX_IPV6_ENABLED="true"
  BOX_CAMPUS_DNS_MODE="auto"
  BOX_CAMPUS_DNS_SUFFIX_POLICY="org_only"
  BOX_TAILSCALE_IFACE="tailscale0"
  BOX_TAILNET_IPV4_CIDR="100.64.0.0/10"
  BOX_TAILNET_IPV6_CIDR="fd7a:115c:a1e0::/48"
  BOX_TAILSCALE_DNS_RESOLVER="100.100.100.100"
  BOX_TAILSCALE_FWMARK="0x80000/0xff0000"
  BOX_TAILSCALE_ROUTE_TABLE="52"
  BOX_CAMPUS_DNS_SUFFIXES=("+.bit.edu.cn")
  BOX_CAMPUS_DNS_PROBE_HOSTS=("lexue.bit.edu.cn" "xk.bit.edu.cn")
  BOX_CAMPUS_DNS_PUBLIC_SERVERS=("https://dns.alidns.com/dns-query" "https://cloudflare-dns.com/dns-query" "https://dns.google/dns-query")
  BOX_FIREWALL_BACKEND="iptables"
  BOX_ROUTE_TABLE="2024"
  BOX_ROUTE_PREF="100"
  BOX_FWMARK="16777216/16777216"
  BOX_BYPASS_PRIVATE_IP="true"
  BOX_BYPASS_CN_IP="false"
  BOX_BYPASS_CN_FILE="${BOX_VAR_DIR_DEFAULT}/china_ipv4.txt"
  BOX_POLICY_ENABLED="false"
  BOX_POLICY_PROXY_MODE="core"
  BOX_POLICY_DEBOUNCE_SECONDS="3"
  BOX_POLICY_USE_MODULE_ON_WIFI_DISCONNECT="false"
  BOX_POLICY_DISABLE_MARKER="${BOX_RUN_DIR}/disable"
  BOX_POLICY_ALLOW_IFACES=()
  BOX_POLICY_IGNORE_IFACES=()
  BOX_POLICY_ALLOW_SSIDS=()
  BOX_POLICY_IGNORE_SSIDS=()
  BOX_POLICY_ALLOW_BSSIDS=()
  BOX_POLICY_IGNORE_BSSIDS=()
  BOX_CORE_BIN_DIR="/usr/local/bin"
  BOX_CORE_WORKDIR="${BOX_VAR_DIR_DEFAULT}"
  BOX_CORE_CONFIG_SOURCE="/etc/box/profiles/config.yaml"
  BOX_UPDATER_ARTIFACT_DIR="${BOX_VAR_DIR_DEFAULT}/artifacts"
  BOX_UPDATER_STAGING_DIR="${BOX_VAR_DIR_DEFAULT}/staging"
  BOX_UPDATER_CHECKSUM_POLICY="optional"
  BOX_UPDATER_FETCH_RETRIES="3"
  BOX_UPDATER_FETCH_RETRY_BACKOFF_MS="750"
  BOX_UPDATER_USE_GHPROXY="false"
  BOX_UPDATER_GHPROXY_URL="https://ghfast.top"
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
  BOX_UPDATER_SUBS_PRESET=""
  BOX_UPDATER_SUBS_CHECKSUM=""
  BOX_UPDATER_SUBS_CHECKSUM_FILE=""
  BOX_UPDATER_SUBS_TARGET=""
  BOX_UPDATER_SUBS_PROVIDER_NAMES=()
  BOX_UPDATER_SUBS_PROVIDER_URLS=()
  BOX_UPDATER_GEO_URL=""
  BOX_UPDATER_GEO_FILE=""
  BOX_UPDATER_GEO_SOURCE="auto"
  BOX_UPDATER_GEO_PRESET=""
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
    function append_value(fragment) {
      if (value == "") {
        value = fragment
      } else {
        value = value "\n" fragment
      }
    }

    BEGIN {
      section = ""
      capture = 0
      value = ""
      emitted = 0
    }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ {
      if (capture) {
        append_value($0)
      }
      next
    }
    /^[[:space:]]*\[/ {
      if (capture) {
        print value
        emitted = 1
        exit
      }
      line = $0
      gsub(/^[[:space:]]*\[/, "", line)
      gsub(/\][[:space:]]*$/, "", line)
      gsub(/[[:space:]]/, "", line)
      section = line
      next
    }
    capture {
      append_value($0)
      if ($0 ~ /\]/) {
        print value
        emitted = 1
        exit
      }
      next
    }
    section == target_section {
      line = $0
      if (line ~ "^[[:space:]]*" target_key "[[:space:]]*=") {
        sub(/^[^=]*=/, "", line)
        append_value(line)
        trimmed = line
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", trimmed)
        if (trimmed ~ /^\[/ && trimmed !~ /\]/) {
          capture = 1
          next
        }
        print value
        emitted = 1
        exit
      }
    }
    END {
      if (!emitted && capture && value != "") {
        print value
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

config_read_array() {
  local file="${1:?missing file}"
  local section="${2:?missing section}"
  local key="${3:?missing key}"
  local raw inner token
  local -a values=()

  raw="$(toml_value "${file}" "${section}" "${key}" || true)"
  if [[ -z "${raw}" ]]; then
    return 1
  fi

  raw="$(trim_space "$(strip_inline_comment "${raw}")")"
  [[ "${raw}" == \[*\] ]] || return 1
  inner="${raw#[}"
  inner="${inner%]}"
  inner="${inner//$'\n'/ }"
  inner="${inner//$'\r'/ }"

  while IFS= read -r token; do
    token="$(trim_space "${token}")"
    [[ -n "${token}" ]] || continue
    if [[ "${token}" =~ ^\"(.*)\"$ ]]; then
      values+=("${BASH_REMATCH[1]}")
    elif [[ "${token}" =~ ^\'(.*)\'$ ]]; then
      values+=("${BASH_REMATCH[1]}")
    else
      values+=("${token}")
    fi
  done < <(printf '%s\n' "${inner}" | awk '
    BEGIN { in_quote = 0; quote = ""; token = "" }
    {
      line = $0
      for (i = 1; i <= length(line); i++) {
        ch = substr(line, i, 1)
        if ((ch == "\"" || ch == "'\''")) {
          if (in_quote == 0) {
            in_quote = 1
            quote = ch
          } else if (quote == ch) {
            in_quote = 0
            quote = ""
          }
          token = token ch
          continue
        }
        if (ch == "," && in_quote == 0) {
          print token
          token = ""
          continue
        }
        token = token ch
      }
      if (in_quote == 0 && length(token) > 0) {
        print token
        token = ""
      }
    }
    END {
      if (length(token) > 0) {
        print token
      }
    }
  ')

  printf '%s\n' "${values[@]}"
}

config_read_value_first() {
  local file="${1:?missing file}"
  local section="${2:?missing section}"
  shift 2 || true
  local key value

  for key in "$@"; do
    [[ -n "${key}" ]] || continue
    value="$(config_read_value "${file}" "${section}" "${key}" || true)"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  done
  return 1
}

config_read_array_first() {
  local file="${1:?missing file}"
  local section="${2:?missing section}"
  shift 2 || true
  local key

  for key in "$@"; do
    [[ -n "${key}" ]] || continue
    if config_read_array "${file}" "${section}" "${key}" >/dev/null 2>&1; then
      config_read_array "${file}" "${section}" "${key}"
      return 0
    fi
  done
  return 1
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

validate_bool_string() {
  case "${1:-}" in
    true|false|1|0) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_org_dns_mode() {
  case "${1:-}" in
    campus) printf 'org\n' ;;
    auto|org|public) printf '%s\n' "${1}" ;;
    *) printf '%s\n' "${1:-}" ;;
  esac
}

normalize_org_dns_suffix_policy() {
  case "${1:-}" in
    ""|org|org_only) printf 'org_only\n' ;;
    best_match|link) printf 'best_match\n' ;;
    *) printf '%s\n' "${1:-}" ;;
  esac
}

box_active_default_iface() {
  local ip_cmd="${BOX_IP_CMD:-ip}"
  command -v "${ip_cmd}" >/dev/null 2>&1 || return 1
  "${ip_cmd}" route show default 2>/dev/null | awk '/^default / { for (i = 1; i <= NF; i++) if ($i == "dev" && (i + 1) <= NF) { print $(i + 1); exit } }'
}

box_active_link_dns_servers() {
  local iface="${1:-}"
  local resolvectl_cmd="${BOX_RESOLVECTL_CMD:-resolvectl}"
  [[ -n "${iface}" ]] || return 1
  command -v "${resolvectl_cmd}" >/dev/null 2>&1 || return 1
  "${resolvectl_cmd}" dns "${iface}" 2>/dev/null | awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/) {
          print $i
        }
      }
    }
  '
}

box_dns_link_ifaces() {
  local resolvectl_cmd="${BOX_RESOLVECTL_CMD:-resolvectl}"
  command -v "${resolvectl_cmd}" >/dev/null 2>&1 || return 1
  "${resolvectl_cmd}" dns 2>/dev/null | awk '
    /^Link [0-9]+ \([^)]*\):/ {
      iface = $3
      gsub(/^\(/, "", iface)
      gsub(/\):$/, "", iface)
      has_ipv4 = 0
      for (i = 4; i <= NF; i++) {
        if ($i ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/) {
          has_ipv4 = 1
          break
        }
      }
      if (iface != "" && has_ipv4) {
        print iface
      }
    }
  '
}

box_probe_host_via_dns() {
  local server="${1:-}"
  local host="${2:-}"
  local dig_cmd="${BOX_DIG_CMD:-dig}"
  [[ -n "${server}" && -n "${host}" ]] || return 1
  command -v "${dig_cmd}" >/dev/null 2>&1 || return 1
  "${dig_cmd}" +time=3 +tries=1 +short @"${server}" "${host}" A 2>/dev/null | awk 'NF { print; exit }'
}

box_is_private_ipv4() {
  local ip="${1:-}"
  [[ "${ip}" =~ ^10\. ]] && return 0
  [[ "${ip}" =~ ^192\.168\. ]] && return 0
  if [[ "${ip}" =~ ^172\.([0-9]+)\. ]]; then
    local second="${BASH_REMATCH[1]}"
    (( second >= 16 && second <= 31 )) && return 0
  fi
  return 1
}

box_org_dns_probe_count() {
  local probe_host count=0
  for probe_host in "${BOX_CAMPUS_DNS_PROBE_HOSTS[@]}"; do
    [[ -n "${probe_host}" ]] || continue
    ((count += 1))
  done
  printf '%s\n' "${count}"
}

box_org_dns_probe_score_for_iface() {
  local iface="${1:-}"
  local dns_server probe_host answer
  local -a dns_servers=()
  local score=0

  [[ -n "${iface}" ]] || {
    printf '0\n'
    return 0
  }

  mapfile -t dns_servers < <(box_active_link_dns_servers "${iface}" || true)
  if [[ "${#dns_servers[@]}" -eq 0 ]]; then
    printf '0\n'
    return 0
  fi

  for probe_host in "${BOX_CAMPUS_DNS_PROBE_HOSTS[@]}"; do
    [[ -n "${probe_host}" ]] || continue
    for dns_server in "${dns_servers[@]}"; do
      answer="$(box_probe_host_via_dns "${dns_server}" "${probe_host}" || true)"
      if [[ -n "${answer}" ]] && box_is_private_ipv4 "${answer}"; then
        ((score += 1))
        break
      fi
    done
  done

  printf '%s\n' "${score}"
}

box_detect_org_dns_iface() {
  local iface required_score score default_iface first_full_match=""
  local -a candidate_ifaces=()

  required_score="$(box_org_dns_probe_count)"
  [[ "${required_score}" -gt 0 ]] || return 1
  default_iface="$(box_active_default_iface || true)"

  mapfile -t candidate_ifaces < <(box_dns_link_ifaces || true)
  if [[ "${#candidate_ifaces[@]}" -eq 0 ]]; then
    [[ -n "${default_iface}" ]] && candidate_ifaces=("${default_iface}")
  fi

  for iface in "${candidate_ifaces[@]}"; do
    [[ -n "${iface}" ]] || continue
    score="$(box_org_dns_probe_score_for_iface "${iface}")"
    if [[ "${score}" -eq "${required_score}" ]]; then
      if [[ -z "${first_full_match}" ]]; then
        first_full_match="${iface}"
      fi
      if [[ -n "${default_iface}" && "${iface}" == "${default_iface}" ]]; then
        printf '%s\n' "${iface}"
        return 0
      fi
    fi
  done

  [[ -n "${first_full_match}" ]] || return 1
  printf '%s\n' "${first_full_match}"
}

box_best_org_dns_candidate_iface() {
  local iface best_iface="" score best_score=0 default_iface
  local -a candidate_ifaces=()
  default_iface="$(box_active_default_iface || true)"

  mapfile -t candidate_ifaces < <(box_dns_link_ifaces || true)
  if [[ "${#candidate_ifaces[@]}" -eq 0 ]]; then
    [[ -n "${default_iface}" ]] && candidate_ifaces=("${default_iface}")
  fi

  for iface in "${candidate_ifaces[@]}"; do
    [[ -n "${iface}" ]] || continue
    score="$(box_org_dns_probe_score_for_iface "${iface}")"
    if [[ "${score}" -gt "${best_score}" ]] || \
       ([[ "${score}" -eq "${best_score}" ]] && [[ -n "${default_iface}" && "${iface}" == "${default_iface}" ]] && [[ "${best_iface}" != "${default_iface}" ]]); then
      best_score="${score}"
      best_iface="${iface}"
    fi
  done

  [[ -n "${best_iface}" ]] || return 1
  printf '%s\n' "${best_iface}"
}

box_org_dns_mode_configured() {
  local mode
  if [[ "${#BOX_CAMPUS_DNS_SUFFIXES[@]}" -eq 0 ]]; then
    printf 'disabled\n'
    return 0
  fi
  mode="$(normalize_org_dns_mode "${BOX_CAMPUS_DNS_MODE}")"
  printf '%s\n' "${mode}"
}

box_detect_org_dns_mode() {
  local configured_mode detected_iface

  configured_mode="$(box_org_dns_mode_configured)"
  case "${configured_mode}" in
    disabled|org|public)
      printf '%s\n' "${configured_mode}"
      return 0
      ;;
  esac

  detected_iface="$(box_detect_org_dns_iface || true)"
  if [[ -n "${detected_iface}" ]]; then
    printf 'org\n'
  else
    printf 'public\n'
  fi
}

box_org_dns_status_iface() {
  local active_mode detected_iface
  active_mode="$(box_detect_org_dns_mode)"
  if [[ "${active_mode}" == "org" ]]; then
    detected_iface="$(box_detect_org_dns_iface || true)"
    if [[ -n "${detected_iface}" ]]; then
      printf '%s\n' "${detected_iface}"
      return 0
    fi
  fi
  box_active_default_iface || true
}

box_org_dns_status_servers() {
  local active_mode iface
  active_mode="$(box_detect_org_dns_mode)"
  case "${active_mode}" in
    disabled) return 0 ;;
    org)
      iface="$(box_org_dns_status_iface)"
      box_active_link_dns_servers "${iface}" || true
      ;;
    public)
      printf '%s\n' "${BOX_CAMPUS_DNS_PUBLIC_SERVERS[@]}"
      ;;
  esac
}

box_org_dns_status_suffixes() {
  printf '%s\n' "${BOX_CAMPUS_DNS_SUFFIXES[@]}"
}

box_org_dns_status_probe_hosts() {
  printf '%s\n' "${BOX_CAMPUS_DNS_PROBE_HOSTS[@]}"
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

  case "${BOX_DNS_ENHANCED_MODE}" in
    fake-ip|redir-host) ;;
    *)
      log "ERROR" "config" "E_CONFIG_DNS_ENHANCED_MODE" \
        "invalid dns_enhanced_mode: ${BOX_DNS_ENHANCED_MODE}"
      return "${E_CONFIG}"
      ;;
  esac

  if ! validate_bool_string "${BOX_IPV6_ENABLED}"; then
    log "ERROR" "config" "E_CONFIG_IPV6" \
      "network ipv6 must be true|false|1|0: ${BOX_IPV6_ENABLED}"
    return "${E_CONFIG}"
  fi

  case "$(normalize_org_dns_mode "${BOX_CAMPUS_DNS_MODE}")" in
    auto|org|public) ;;
    *)
      log "ERROR" "config" "E_CONFIG_ORG_DNS_MODE" \
        "network org_dns_mode must be auto|org|public (legacy campus alias accepted): ${BOX_CAMPUS_DNS_MODE}"
      return "${E_CONFIG}"
      ;;
  esac

  case "$(normalize_org_dns_suffix_policy "${BOX_CAMPUS_DNS_SUFFIX_POLICY}")" in
    org_only|best_match) ;;
    *)
      log "ERROR" "config" "E_CONFIG_ORG_DNS_SUFFIX_POLICY" \
        "network org_dns_suffix_policy must be org_only|best_match: ${BOX_CAMPUS_DNS_SUFFIX_POLICY}"
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

  if ! validate_bool_string "${BOX_BYPASS_PRIVATE_IP}"; then
    log "ERROR" "config" "E_CONFIG_BYPASS_PRIVATE" \
      "firewall bypass_private_ip must be true|false|1|0: ${BOX_BYPASS_PRIVATE_IP}"
    return "${E_CONFIG}"
  fi

  if ! validate_bool_string "${BOX_BYPASS_CN_IP}"; then
    log "ERROR" "config" "E_CONFIG_BYPASS_CN" \
      "firewall bypass_cn_ip must be true|false|1|0: ${BOX_BYPASS_CN_IP}"
    return "${E_CONFIG}"
  fi

  if [[ "${BOX_BYPASS_CN_IP}" == "true" || "${BOX_BYPASS_CN_IP}" == "1" ]]; then
    if [[ -z "${BOX_BYPASS_CN_FILE}" ]]; then
      log "ERROR" "config" "E_CONFIG_BYPASS_CN_FILE" \
        "firewall bypass_cn_file must not be empty when bypass_cn_ip is enabled"
      return "${E_CONFIG}"
    fi
  fi

  if ! validate_bool_string "${BOX_POLICY_ENABLED}"; then
    log "ERROR" "config" "E_CONFIG_POLICY_ENABLED" "policy.enabled must be true|false|1|0: ${BOX_POLICY_ENABLED}"
    return "${E_CONFIG}"
  fi

  case "${BOX_POLICY_PROXY_MODE}" in
    core|whitelist|blacklist) ;;
    *)
      log "ERROR" "config" "E_CONFIG_POLICY_MODE" "unsupported policy.proxy_mode: ${BOX_POLICY_PROXY_MODE}"
      return "${E_CONFIG}"
      ;;
  esac

  if ! validate_uint "${BOX_POLICY_DEBOUNCE_SECONDS}"; then
    log "ERROR" "config" "E_CONFIG_POLICY_DEBOUNCE" "policy.debounce_seconds must be numeric: ${BOX_POLICY_DEBOUNCE_SECONDS}"
    return "${E_CONFIG}"
  fi

  if ! validate_bool_string "${BOX_POLICY_USE_MODULE_ON_WIFI_DISCONNECT}"; then
    log "ERROR" "config" "E_CONFIG_POLICY_DISCONNECT" \
      "policy.use_module_on_wifi_disconnect must be true|false|1|0: ${BOX_POLICY_USE_MODULE_ON_WIFI_DISCONNECT}"
    return "${E_CONFIG}"
  fi

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

  if ! validate_uint "${BOX_UPDATER_FETCH_RETRIES}"; then
    log "ERROR" "config" "E_CONFIG_UPDATER_RETRIES" \
      "updater fetch_retries must be numeric: ${BOX_UPDATER_FETCH_RETRIES}"
    return "${E_CONFIG}"
  fi

  if ! validate_uint "${BOX_UPDATER_FETCH_RETRY_BACKOFF_MS}"; then
    log "ERROR" "config" "E_CONFIG_UPDATER_BACKOFF" \
      "updater fetch_retry_backoff_ms must be numeric: ${BOX_UPDATER_FETCH_RETRY_BACKOFF_MS}"
    return "${E_CONFIG}"
  fi

  if ! validate_bool_string "${BOX_UPDATER_USE_GHPROXY}"; then
    log "ERROR" "config" "E_CONFIG_UPDATER_GHPROXY" \
      "updater use_ghproxy must be true|false|1|0: ${BOX_UPDATER_USE_GHPROXY}"
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

  case "${BOX_UPDATER_SUBS_PRESET}" in
    ''|mihomo_phone) ;;
    *)
      log "ERROR" "config" "E_CONFIG_UPDATER_SUBS_PRESET" \
        "unsupported updater.subs.preset: ${BOX_UPDATER_SUBS_PRESET}"
      return "${E_CONFIG}"
      ;;
  esac

  if [[ "${BOX_UPDATER_SUBS_PRESET}" == "mihomo_phone" && "${BOX_CORE}" != "mihomo" ]]; then
    log "ERROR" "config" "E_CONFIG_UPDATER_SUBS_PRESET" \
      "updater.subs.preset=mihomo_phone requires core=mihomo"
    return "${E_CONFIG}"
  fi

  case "${BOX_UPDATER_GEO_PRESET}" in
    ''|auto|metacubex_mihomo|metacubex_sing_box|metacubex_legacy) ;;
    *)
      log "ERROR" "config" "E_CONFIG_UPDATER_GEO_PRESET" \
        "unsupported updater.geo.preset: ${BOX_UPDATER_GEO_PRESET}"
      return "${E_CONFIG}"
      ;;
  esac

  if [[ "${#BOX_UPDATER_SUBS_PROVIDER_NAMES[@]}" -gt 0 || "${#BOX_UPDATER_SUBS_PROVIDER_URLS[@]}" -gt 0 ]]; then
    if [[ "${#BOX_UPDATER_SUBS_PROVIDER_NAMES[@]}" -ne "${#BOX_UPDATER_SUBS_PROVIDER_URLS[@]}" ]]; then
      log "ERROR" "config" "E_CONFIG_UPDATER_SUBS_PROVIDERS" \
        "updater.subs provider_names and provider_urls must have equal length"
      return "${E_CONFIG}"
    fi
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
    export BOX_CORE BOX_NETWORK_MODE BOX_TPROXY_PORT BOX_REDIR_PORT BOX_DNS_PORT BOX_DNS_HIJACK_MODE BOX_DNS_ENHANCED_MODE BOX_DNS_COEXIST_MODE BOX_IPV6_ENABLED BOX_CAMPUS_DNS_MODE BOX_CAMPUS_DNS_SUFFIX_POLICY
    export BOX_TAILSCALE_IFACE BOX_TAILNET_IPV4_CIDR BOX_TAILNET_IPV6_CIDR BOX_TAILSCALE_DNS_RESOLVER BOX_TAILSCALE_FWMARK BOX_TAILSCALE_ROUTE_TABLE
    export BOX_FIREWALL_BACKEND BOX_ROUTE_TABLE BOX_ROUTE_PREF BOX_FWMARK BOX_BYPASS_PRIVATE_IP BOX_BYPASS_CN_IP BOX_BYPASS_CN_FILE
    export BOX_POLICY_ENABLED BOX_POLICY_PROXY_MODE BOX_POLICY_DEBOUNCE_SECONDS BOX_POLICY_USE_MODULE_ON_WIFI_DISCONNECT BOX_POLICY_DISABLE_MARKER
    export BOX_CORE_BIN_DIR BOX_CORE_WORKDIR BOX_CORE_CONFIG_SOURCE
    export BOX_UPDATER_ARTIFACT_DIR BOX_UPDATER_STAGING_DIR BOX_UPDATER_CHECKSUM_POLICY
    export BOX_UPDATER_FETCH_RETRIES BOX_UPDATER_FETCH_RETRY_BACKOFF_MS BOX_UPDATER_USE_GHPROXY BOX_UPDATER_GHPROXY_URL
    export BOX_UPDATER_KERNEL_INTERVAL BOX_UPDATER_SUBS_INTERVAL BOX_UPDATER_GEO_INTERVAL BOX_UPDATER_DASHBOARD_INTERVAL
    export BOX_UPDATER_KERNEL_URL BOX_UPDATER_KERNEL_FILE BOX_UPDATER_KERNEL_SOURCE BOX_UPDATER_KERNEL_RELEASE_API_URL
    export BOX_UPDATER_KERNEL_RELEASE_REPO BOX_UPDATER_KERNEL_RELEASE_CHANNEL BOX_UPDATER_KERNEL_RELEASE_TAG
    export BOX_UPDATER_KERNEL_ASSET_REGEX BOX_UPDATER_KERNEL_CHECKSUM_ASSET_REGEX BOX_UPDATER_KERNEL_RELEASE_OS BOX_UPDATER_KERNEL_RELEASE_ARCH
    export BOX_UPDATER_KERNEL_ARCHIVE_MEMBER_REGEX BOX_UPDATER_KERNEL_CHECKSUM BOX_UPDATER_KERNEL_CHECKSUM_FILE BOX_UPDATER_KERNEL_TARGET
    export BOX_UPDATER_SUBS_URL BOX_UPDATER_SUBS_FILE BOX_UPDATER_SUBS_PRESET BOX_UPDATER_SUBS_CHECKSUM BOX_UPDATER_SUBS_CHECKSUM_FILE BOX_UPDATER_SUBS_TARGET
    export BOX_UPDATER_GEO_URL BOX_UPDATER_GEO_FILE BOX_UPDATER_GEO_SOURCE BOX_UPDATER_GEO_RELEASE_API_URL
    export BOX_UPDATER_GEO_PRESET BOX_UPDATER_GEO_RELEASE_REPO BOX_UPDATER_GEO_RELEASE_CHANNEL BOX_UPDATER_GEO_RELEASE_TAG
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
  BOX_DNS_ENHANCED_MODE="$(config_read_value "${BOX_CONFIG_FILE}" "network" "dns_enhanced_mode" || printf '%s' "${BOX_DNS_ENHANCED_MODE}")"
  BOX_DNS_COEXIST_MODE="$(config_read_value "${BOX_CONFIG_FILE}" "network" "dns_coexist_mode" || printf '%s' "${BOX_DNS_COEXIST_MODE}")"
  BOX_IPV6_ENABLED="$(config_read_value "${BOX_CONFIG_FILE}" "network" "ipv6" || printf '%s' "${BOX_IPV6_ENABLED}")"
  BOX_CAMPUS_DNS_MODE="$(config_read_value_first "${BOX_CONFIG_FILE}" "network" "org_dns_mode" "campus_dns_mode" || printf '%s' "${BOX_CAMPUS_DNS_MODE}")"
  BOX_CAMPUS_DNS_SUFFIX_POLICY="$(config_read_value_first "${BOX_CONFIG_FILE}" "network" "org_dns_suffix_policy" "campus_dns_suffix_policy" || printf '%s' "${BOX_CAMPUS_DNS_SUFFIX_POLICY}")"
  BOX_TAILSCALE_IFACE="$(config_read_value "${BOX_CONFIG_FILE}" "network" "tailscale_iface" || printf '%s' "${BOX_TAILSCALE_IFACE}")"
  BOX_TAILNET_IPV4_CIDR="$(config_read_value "${BOX_CONFIG_FILE}" "network" "tailnet_ipv4_cidr" || printf '%s' "${BOX_TAILNET_IPV4_CIDR}")"
  BOX_TAILNET_IPV6_CIDR="$(config_read_value "${BOX_CONFIG_FILE}" "network" "tailnet_ipv6_cidr" || printf '%s' "${BOX_TAILNET_IPV6_CIDR}")"
  BOX_TAILSCALE_DNS_RESOLVER="$(config_read_value "${BOX_CONFIG_FILE}" "network" "tailscale_dns_resolver" || printf '%s' "${BOX_TAILSCALE_DNS_RESOLVER}")"
  BOX_TAILSCALE_FWMARK="$(config_read_value "${BOX_CONFIG_FILE}" "network" "tailscale_fwmark" || printf '%s' "${BOX_TAILSCALE_FWMARK}")"
  BOX_TAILSCALE_ROUTE_TABLE="$(config_read_value "${BOX_CONFIG_FILE}" "network" "tailscale_route_table" || printf '%s' "${BOX_TAILSCALE_ROUTE_TABLE}")"
  mapfile -t BOX_CAMPUS_DNS_SUFFIXES < <(config_read_array_first "${BOX_CONFIG_FILE}" "network" "org_dns_suffixes" "campus_dns_suffixes" || printf '%s\n' "${BOX_CAMPUS_DNS_SUFFIXES[@]}")
  mapfile -t BOX_CAMPUS_DNS_PROBE_HOSTS < <(config_read_array_first "${BOX_CONFIG_FILE}" "network" "org_dns_probe_hosts" "campus_dns_probe_hosts" || printf '%s\n' "${BOX_CAMPUS_DNS_PROBE_HOSTS[@]}")
  mapfile -t BOX_CAMPUS_DNS_PUBLIC_SERVERS < <(config_read_array_first "${BOX_CONFIG_FILE}" "network" "org_dns_public_servers" "campus_dns_public_servers" || printf '%s\n' "${BOX_CAMPUS_DNS_PUBLIC_SERVERS[@]}")
  BOX_CAMPUS_DNS_MODE="$(normalize_org_dns_mode "${BOX_CAMPUS_DNS_MODE}")"
  BOX_CAMPUS_DNS_SUFFIX_POLICY="$(normalize_org_dns_suffix_policy "${BOX_CAMPUS_DNS_SUFFIX_POLICY}")"

  BOX_FIREWALL_BACKEND="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "backend" || printf '%s' "${BOX_FIREWALL_BACKEND}")"
  BOX_ROUTE_TABLE="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "route_table" || printf '%s' "${BOX_ROUTE_TABLE}")"
  BOX_ROUTE_PREF="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "route_pref" || printf '%s' "${BOX_ROUTE_PREF}")"
  BOX_FWMARK="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "fwmark" || printf '%s' "${BOX_FWMARK}")"
  BOX_BYPASS_PRIVATE_IP="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "bypass_private_ip" || printf '%s' "${BOX_BYPASS_PRIVATE_IP}")"
  BOX_BYPASS_CN_IP="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "bypass_cn_ip" || printf '%s' "${BOX_BYPASS_CN_IP}")"
  BOX_BYPASS_CN_FILE="$(config_read_value "${BOX_CONFIG_FILE}" "firewall" "bypass_cn_file" || printf '%s' "${BOX_BYPASS_CN_FILE}")"

  BOX_POLICY_ENABLED="$(config_read_value "${BOX_CONFIG_FILE}" "policy" "enabled" || printf '%s' "${BOX_POLICY_ENABLED}")"
  BOX_POLICY_PROXY_MODE="$(config_read_value "${BOX_CONFIG_FILE}" "policy" "proxy_mode" || printf '%s' "${BOX_POLICY_PROXY_MODE}")"
  BOX_POLICY_DEBOUNCE_SECONDS="$(config_read_value "${BOX_CONFIG_FILE}" "policy" "debounce_seconds" || printf '%s' "${BOX_POLICY_DEBOUNCE_SECONDS}")"
  BOX_POLICY_USE_MODULE_ON_WIFI_DISCONNECT="$(config_read_value "${BOX_CONFIG_FILE}" "policy" "use_module_on_wifi_disconnect" || printf '%s' "${BOX_POLICY_USE_MODULE_ON_WIFI_DISCONNECT}")"
  BOX_POLICY_DISABLE_MARKER="$(config_read_value "${BOX_CONFIG_FILE}" "policy" "disable_marker" || printf '%s' "${BOX_POLICY_DISABLE_MARKER}")"
  mapfile -t BOX_POLICY_ALLOW_IFACES < <(config_read_array "${BOX_CONFIG_FILE}" "policy" "allow_ifaces" || true)
  mapfile -t BOX_POLICY_IGNORE_IFACES < <(config_read_array "${BOX_CONFIG_FILE}" "policy" "ignore_ifaces" || true)
  mapfile -t BOX_POLICY_ALLOW_SSIDS < <(config_read_array "${BOX_CONFIG_FILE}" "policy" "allow_ssids" || true)
  mapfile -t BOX_POLICY_IGNORE_SSIDS < <(config_read_array "${BOX_CONFIG_FILE}" "policy" "ignore_ssids" || true)
  mapfile -t BOX_POLICY_ALLOW_BSSIDS < <(config_read_array "${BOX_CONFIG_FILE}" "policy" "allow_bssids" || true)
  mapfile -t BOX_POLICY_IGNORE_BSSIDS < <(config_read_array "${BOX_CONFIG_FILE}" "policy" "ignore_bssids" || true)

  BOX_UPDATER_ARTIFACT_DIR="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "artifact_dir" || printf '%s' "${BOX_UPDATER_ARTIFACT_DIR}")"
  BOX_UPDATER_STAGING_DIR="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "staging_dir" || printf '%s' "${BOX_UPDATER_STAGING_DIR}")"
  BOX_UPDATER_CHECKSUM_POLICY="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "checksum_policy" || printf '%s' "${BOX_UPDATER_CHECKSUM_POLICY}")"
  BOX_UPDATER_FETCH_RETRIES="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "fetch_retries" || printf '%s' "${BOX_UPDATER_FETCH_RETRIES}")"
  BOX_UPDATER_FETCH_RETRY_BACKOFF_MS="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "fetch_retry_backoff_ms" || printf '%s' "${BOX_UPDATER_FETCH_RETRY_BACKOFF_MS}")"
  BOX_UPDATER_USE_GHPROXY="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "use_ghproxy" || printf '%s' "${BOX_UPDATER_USE_GHPROXY}")"
  BOX_UPDATER_GHPROXY_URL="$(config_read_value "${BOX_CONFIG_FILE}" "updater" "ghproxy_url" || printf '%s' "${BOX_UPDATER_GHPROXY_URL}")"
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
  BOX_UPDATER_SUBS_PRESET="$(config_read_value "${BOX_CONFIG_FILE}" "updater.subs" "preset" || printf '%s' "${BOX_UPDATER_SUBS_PRESET}")"
  BOX_UPDATER_SUBS_CHECKSUM="$(config_read_value "${BOX_CONFIG_FILE}" "updater.subs" "checksum" || printf '%s' "${BOX_UPDATER_SUBS_CHECKSUM}")"
  BOX_UPDATER_SUBS_CHECKSUM_FILE="$(config_read_value "${BOX_CONFIG_FILE}" "updater.subs" "checksum_file" || printf '%s' "${BOX_UPDATER_SUBS_CHECKSUM_FILE}")"
  BOX_UPDATER_SUBS_TARGET="$(config_read_value "${BOX_CONFIG_FILE}" "updater.subs" "target" || printf '%s' "${BOX_UPDATER_SUBS_TARGET}")"
  mapfile -t BOX_UPDATER_SUBS_PROVIDER_NAMES < <(config_read_array "${BOX_CONFIG_FILE}" "updater.subs" "provider_names" || true)
  mapfile -t BOX_UPDATER_SUBS_PROVIDER_URLS < <(config_read_array "${BOX_CONFIG_FILE}" "updater.subs" "provider_urls" || true)

  BOX_UPDATER_GEO_URL="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "url" || printf '%s' "${BOX_UPDATER_GEO_URL}")"
  BOX_UPDATER_GEO_FILE="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "file" || printf '%s' "${BOX_UPDATER_GEO_FILE}")"
  BOX_UPDATER_GEO_SOURCE="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "source" || printf '%s' "${BOX_UPDATER_GEO_SOURCE}")"
  BOX_UPDATER_GEO_PRESET="$(config_read_value "${BOX_CONFIG_FILE}" "updater.geo" "preset" || printf '%s' "${BOX_UPDATER_GEO_PRESET}")"
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
  export BOX_CORE BOX_NETWORK_MODE BOX_TPROXY_PORT BOX_REDIR_PORT BOX_DNS_PORT BOX_DNS_HIJACK_MODE BOX_DNS_ENHANCED_MODE BOX_DNS_COEXIST_MODE BOX_IPV6_ENABLED BOX_CAMPUS_DNS_MODE BOX_CAMPUS_DNS_SUFFIX_POLICY
  export BOX_TAILSCALE_IFACE BOX_TAILNET_IPV4_CIDR BOX_TAILNET_IPV6_CIDR BOX_TAILSCALE_DNS_RESOLVER BOX_TAILSCALE_FWMARK BOX_TAILSCALE_ROUTE_TABLE
  export BOX_FIREWALL_BACKEND BOX_ROUTE_TABLE BOX_ROUTE_PREF BOX_FWMARK BOX_BYPASS_PRIVATE_IP BOX_BYPASS_CN_IP BOX_BYPASS_CN_FILE
  export BOX_POLICY_ENABLED BOX_POLICY_PROXY_MODE BOX_POLICY_DEBOUNCE_SECONDS BOX_POLICY_USE_MODULE_ON_WIFI_DISCONNECT BOX_POLICY_DISABLE_MARKER
  export BOX_CORE_BIN_DIR BOX_CORE_WORKDIR BOX_CORE_CONFIG_SOURCE
  export BOX_UPDATER_ARTIFACT_DIR BOX_UPDATER_STAGING_DIR BOX_UPDATER_CHECKSUM_POLICY
  export BOX_UPDATER_FETCH_RETRIES BOX_UPDATER_FETCH_RETRY_BACKOFF_MS BOX_UPDATER_USE_GHPROXY BOX_UPDATER_GHPROXY_URL
  export BOX_UPDATER_KERNEL_INTERVAL BOX_UPDATER_SUBS_INTERVAL BOX_UPDATER_GEO_INTERVAL BOX_UPDATER_DASHBOARD_INTERVAL
  export BOX_UPDATER_KERNEL_URL BOX_UPDATER_KERNEL_FILE BOX_UPDATER_KERNEL_SOURCE BOX_UPDATER_KERNEL_RELEASE_API_URL
  export BOX_UPDATER_KERNEL_RELEASE_REPO BOX_UPDATER_KERNEL_RELEASE_CHANNEL BOX_UPDATER_KERNEL_RELEASE_TAG
  export BOX_UPDATER_KERNEL_ASSET_REGEX BOX_UPDATER_KERNEL_CHECKSUM_ASSET_REGEX BOX_UPDATER_KERNEL_RELEASE_OS BOX_UPDATER_KERNEL_RELEASE_ARCH
  export BOX_UPDATER_KERNEL_ARCHIVE_MEMBER_REGEX BOX_UPDATER_KERNEL_CHECKSUM BOX_UPDATER_KERNEL_CHECKSUM_FILE BOX_UPDATER_KERNEL_TARGET
  export BOX_UPDATER_SUBS_URL BOX_UPDATER_SUBS_FILE BOX_UPDATER_SUBS_PRESET BOX_UPDATER_SUBS_CHECKSUM BOX_UPDATER_SUBS_CHECKSUM_FILE BOX_UPDATER_SUBS_TARGET
  export BOX_UPDATER_GEO_URL BOX_UPDATER_GEO_FILE BOX_UPDATER_GEO_SOURCE BOX_UPDATER_GEO_RELEASE_API_URL
  export BOX_UPDATER_GEO_PRESET BOX_UPDATER_GEO_RELEASE_REPO BOX_UPDATER_GEO_RELEASE_CHANNEL BOX_UPDATER_GEO_RELEASE_TAG
  export BOX_UPDATER_GEO_ASSET_REGEX BOX_UPDATER_GEO_CHECKSUM_ASSET_REGEX BOX_UPDATER_GEO_RELEASE_OS BOX_UPDATER_GEO_RELEASE_ARCH
  export BOX_UPDATER_GEO_ARCHIVE_MEMBER_REGEX BOX_UPDATER_GEO_CHECKSUM BOX_UPDATER_GEO_CHECKSUM_FILE BOX_UPDATER_GEO_TARGET
  export BOX_UPDATER_DASHBOARD_URL BOX_UPDATER_DASHBOARD_FILE BOX_UPDATER_DASHBOARD_CHECKSUM BOX_UPDATER_DASHBOARD_CHECKSUM_FILE BOX_UPDATER_DASHBOARD_TARGET
}
