#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

bool_literal() {
  case "${1:-}" in
    true|1) printf 'true\n' ;;
    *) printf 'false\n' ;;
  esac
}

yaml_set_scalar() {
  local file="${1:?missing file}"
  local key="${2:?missing key}"
  local value="${3:?missing value}"

  if grep -Eq "^${key}:" "${file}"; then
    sed -i -E "s|^${key}:.*$|${key}: ${value}|" "${file}"
  else
    printf '%s: %s\n' "${key}" "${value}" >>"${file}"
  fi
}

yaml_set_scalar_if_missing() {
  local file="${1:?missing file}"
  local key="${2:?missing key}"
  local value="${3:?missing value}"

  if ! grep -Eq "^${key}:" "${file}"; then
    printf '%s: %s\n' "${key}" "${value}" >>"${file}"
  fi
}

yaml_set_section_scalar() {
  local file="${1:?missing file}"
  local section="${2:?missing section}"
  local key="${3:?missing key}"
  local value="${4:?missing value}"
  local tmp_file
  tmp_file="$(mktemp)"

  awk -v section="${section}" -v key="${key}" -v value="${value}" '
    function print_key() {
      print "  " key ": " value
    }

    BEGIN {
      section_seen = 0
      in_section = 0
      key_seen = 0
    }

    {
      line = $0

      if (line ~ ("^" section ":[[:space:]]*$")) {
        if (in_section && !key_seen) {
          print_key()
          key_seen = 1
        }
        section_seen = 1
        in_section = 1
        key_seen = 0
        print line
        next
      }

      if (in_section && line ~ /^[^[:space:]#][^:]*:[[:space:]]*$/) {
        if (!key_seen) {
          print_key()
          key_seen = 1
        }
        in_section = 0
      }

      if (in_section && line ~ ("^  " key ":[[:space:]]*")) {
        print_key()
        key_seen = 1
        next
      }

      print line
    }

    END {
      if (in_section && !key_seen) {
        print_key()
      } else if (!section_seen) {
        print section ":"
        print_key()
      }
    }
  ' "${file}" >"${tmp_file}"

  mv "${tmp_file}" "${file}"
}

yaml_mihomo_ensure_dns_fake_ip_filter_item() {
  local file="${1:?missing file}"
  local item="${2:?missing item}"
  local tmp_file
  tmp_file="$(mktemp)"

  awk -v item="${item}" '
    function print_item() {
      print "    - \"" item "\""
    }

    function normalized_list_value(line, value) {
      value = line
      sub(/^[[:space:]]*-[[:space:]]*/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      gsub(/^'\''/, "", value)
      gsub(/'\''$/, "", value)
      return value
    }

    BEGIN {
      saw_dns = 0
      in_dns = 0
      in_filter = 0
      have_item = 0
      inserted = 0
    }

    {
      line = $0

      if (line ~ /^dns:[[:space:]]*$/) {
        saw_dns = 1
        in_dns = 1
        in_filter = 0
        print line
        next
      }

      if (in_dns && line ~ /^[^[:space:]#][^:]*:[[:space:]]*$/) {
        if (!have_item && !inserted) {
          if (!in_filter) {
            print "  fake-ip-filter:"
          }
          print_item()
          inserted = 1
        }
        in_dns = 0
        in_filter = 0
      }

      if (in_dns && line ~ /^  fake-ip-filter:[[:space:]]*$/) {
        in_filter = 1
        print line
        next
      }

      if (in_dns && in_filter) {
        if (line ~ /^    -[[:space:]]*/) {
          if (normalized_list_value(line) == item) {
            have_item = 1
          }
          print line
          next
        }

        if (!have_item && !inserted) {
          print_item()
          inserted = 1
        }
        in_filter = 0
      }

      print line
    }

    END {
      if (in_dns && in_filter && !have_item && !inserted) {
        print_item()
        inserted = 1
      } else if (in_dns && !have_item && !inserted) {
        print "  fake-ip-filter:"
        print_item()
        inserted = 1
      } else if (!saw_dns) {
        print "dns:"
        print "  fake-ip-filter:"
        print_item()
      }
    }
  ' "${file}" >"${tmp_file}"

  mv "${tmp_file}" "${file}"
}

yaml_mihomo_set_dns_policy_servers() {
  local file="${1:?missing file}"
  local key="${2:?missing key}"
  local anchor_key="${3:-}"
  shift 3 || true
  local tmp_file
  tmp_file="$(mktemp)"

  awk -v key="${key}" -v anchor_key="${anchor_key}" -v servers="$*" '
    function print_block() {
      local_count = split(servers, entries, " ")
      print "    \"" key "\":"
      for (i = 1; i <= local_count; i++) {
        if (entries[i] != "") {
          print "      - " entries[i]
        }
      }
    }

    BEGIN {
      in_policy = 0
      replaced = 0
      skipping = 0
      saw_policy = 0
    }

    {
      line = $0

      if (line ~ /^  nameserver-policy:[[:space:]]*$/) {
        saw_policy = 1
        in_policy = 1
        print line
        next
      }

      if (in_policy && line ~ /^  [^[:space:]][^:]*:[[:space:]]*$/) {
        if (!replaced) {
          print_block()
          replaced = 1
        }
        in_policy = 0
      }

      if (in_policy && line == ("    \"" key "\":")) {
        if (!replaced) {
          print_block()
          replaced = 1
        }
        skipping = 1
        next
      }

      if (in_policy && !replaced && anchor_key != "" && line == ("    \"" anchor_key "\":")) {
        print_block()
        replaced = 1
      }

      if (in_policy && skipping) {
        if (line ~ /^      - /) {
          next
        }
        skipping = 0
      }

      print line
    }

    END {
      if (in_policy && !replaced) {
        print_block()
      } else if (!saw_policy) {
        print "dns:"
        print "  nameserver-policy:"
        print_block()
      }
    }
  ' "${file}" >"${tmp_file}"

  mv "${tmp_file}" "${file}"
}

is_private_ipv4() {
  local ip="${1:-}"
  [[ "${ip}" =~ ^10\. ]] && return 0
  [[ "${ip}" =~ ^192\.168\. ]] && return 0
  if [[ "${ip}" =~ ^172\.([0-9]+)\. ]]; then
    local second="${BASH_REMATCH[1]}"
    (( second >= 16 && second <= 31 )) && return 0
  fi
  return 1
}

mihomo_active_default_iface() {
  local ip_cmd="${BOX_IP_CMD:-ip}"
  command -v "${ip_cmd}" >/dev/null 2>&1 || return 1
  "${ip_cmd}" route show default 2>/dev/null | awk '/^default / { for (i = 1; i <= NF; i++) if ($i == "dev" && (i + 1) <= NF) { print $(i + 1); exit } }'
}

mihomo_active_link_dns_servers() {
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

mihomo_probe_host_via_dns() {
  local server="${1:-}"
  local host="${2:-}"
  local dig_cmd="${BOX_DIG_CMD:-dig}"
  [[ -n "${server}" && -n "${host}" ]] || return 1
  command -v "${dig_cmd}" >/dev/null 2>&1 || return 1
  "${dig_cmd}" +time=3 +tries=1 +short @"${server}" "${host}" A 2>/dev/null | awk 'NF { print; exit }'
}

mihomo_detect_campus_dns_mode() {
  local iface dns_server probe_host answer

  case "${BOX_CAMPUS_DNS_MODE}" in
    campus|public)
      printf '%s\n' "${BOX_CAMPUS_DNS_MODE}"
      return 0
      ;;
  esac

  iface="$(mihomo_active_default_iface || true)"
  mapfile -t dns_servers < <(mihomo_active_link_dns_servers "${iface}" || true)
  if [[ "${#dns_servers[@]}" -eq 0 ]]; then
    printf 'public\n'
    return 0
  fi

  for probe_host in "${BOX_CAMPUS_DNS_PROBE_HOSTS[@]}"; do
    [[ -n "${probe_host}" ]] || continue
    for dns_server in "${dns_servers[@]}"; do
      answer="$(mihomo_probe_host_via_dns "${dns_server}" "${probe_host}" || true)"
      if [[ -n "${answer}" ]] && is_private_ipv4 "${answer}"; then
        printf 'campus\n'
        return 0
      fi
    done
  done

  printf 'public\n'
}

mutator_mihomo_apply_campus_dns_policy() {
  local rendered_file="${1:?missing rendered file}"
  local active_mode iface
  active_mode="$(mihomo_detect_campus_dns_mode)"

  if [[ "${#BOX_CAMPUS_DNS_SUFFIXES[@]}" -eq 0 ]]; then
    return 0
  fi

  if [[ "${active_mode}" == "campus" ]]; then
    iface="$(mihomo_active_default_iface || true)"
    mapfile -t dns_servers < <(mihomo_active_link_dns_servers "${iface}" || true)
    [[ "${#dns_servers[@]}" -gt 0 ]] || return 0
    local suffix
    for suffix in "${BOX_CAMPUS_DNS_SUFFIXES[@]}"; do
      [[ -n "${suffix}" ]] || continue
      yaml_mihomo_set_dns_policy_servers "${rendered_file}" "${suffix}" "+.edu.cn" "${dns_servers[@]}"
    done
  else
    local suffix
    for suffix in "${BOX_CAMPUS_DNS_SUFFIXES[@]}"; do
      [[ -n "${suffix}" ]] || continue
      yaml_mihomo_set_dns_policy_servers "${rendered_file}" "${suffix}" "+.edu.cn" "${BOX_CAMPUS_DNS_PUBLIC_SERVERS[@]}"
    done
  fi
}

mutator_mihomo_render_overlay() {
  local source_file="${1:?missing source file}"
  local rendered_file="${2:?missing rendered file}"

  if [[ -f "${source_file}" ]]; then
    cp -f "${source_file}" "${rendered_file}"
  else
    cat >"${rendered_file}" <<EOF
# generated by boxctl
mode: rule
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
EOF
  fi

  yaml_set_scalar_if_missing "${rendered_file}" "mixed-port" "7890"
  yaml_set_scalar "${rendered_file}" "redir-port" "${BOX_REDIR_PORT}"
  yaml_set_scalar "${rendered_file}" "tproxy-port" "${BOX_TPROXY_PORT}"
  yaml_set_scalar "${rendered_file}" "allow-lan" "true"
  yaml_set_scalar "${rendered_file}" "ipv6" "$(bool_literal "${BOX_IPV6_ENABLED}")"
  yaml_set_scalar_if_missing "${rendered_file}" "external-controller" "\"127.0.0.1:9090\""
  yaml_set_scalar_if_missing "${rendered_file}" "external-ui" "\"./dashboard\""
  yaml_set_scalar_if_missing "${rendered_file}" "external-ui-url" "\"https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip\""
  yaml_set_section_scalar "${rendered_file}" "dns" "ipv6" "$(bool_literal "${BOX_IPV6_ENABLED}")"
  yaml_set_section_scalar "${rendered_file}" "dns" "enhanced-mode" "${BOX_DNS_ENHANCED_MODE}"
  if [[ "${BOX_DNS_ENHANCED_MODE}" == "fake-ip" && "$(bool_literal "${BOX_IPV6_ENABLED}")" == "true" ]]; then
    yaml_set_section_scalar "${rendered_file}" "dns" "fake-ip-range6" "\"fc00::/18\""
  fi

  if [[ "${BOX_NETWORK_MODE}" == "tun" ]]; then
    yaml_set_section_scalar "${rendered_file}" "tun" "enable" "true"
    yaml_set_section_scalar "${rendered_file}" "tun" "auto-route" "true"
    yaml_set_section_scalar "${rendered_file}" "tun" "auto-redirect" "true"
    yaml_set_section_scalar "${rendered_file}" "tun" "strict-route" "true"
  else
    yaml_set_section_scalar "${rendered_file}" "tun" "enable" "false"
    yaml_set_section_scalar "${rendered_file}" "tun" "auto-route" "false"
    yaml_set_section_scalar "${rendered_file}" "tun" "auto-redirect" "false"
    yaml_set_section_scalar "${rendered_file}" "tun" "strict-route" "false"
  fi

  if [[ "${BOX_DNS_COEXIST_MODE}" == "preserve_tailnet" && "${BOX_DNS_ENHANCED_MODE}" == "fake-ip" ]]; then
    yaml_mihomo_ensure_dns_fake_ip_filter_item "${rendered_file}" "+.tailscale.com"
    yaml_mihomo_ensure_dns_fake_ip_filter_item "${rendered_file}" "+.ts.net"
  fi

  mutator_mihomo_apply_campus_dns_policy "${rendered_file}"

  {
    printf '# box overlay (runtime only)\n'
    printf '# network_mode=%s\n' "${BOX_NETWORK_MODE}"
    printf '# dns_hijack_mode=%s dns_enhanced_mode=%s dns_port=%s\n' "${BOX_DNS_HIJACK_MODE}" "${BOX_DNS_ENHANCED_MODE}" "${BOX_DNS_PORT}"
    printf '# ipv6_enabled=%s\n' "$(bool_literal "${BOX_IPV6_ENABLED}")"
  } >>"${rendered_file}"
}
