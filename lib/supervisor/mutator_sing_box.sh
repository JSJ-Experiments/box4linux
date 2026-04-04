#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

mutator_sing_box_write_overlay_env() {
  local rendered_file="${1:?missing rendered file}"
  cat >"${rendered_file}.overlay.env" <<EOF
network_mode=${BOX_NETWORK_MODE}
dns_hijack_mode=${BOX_DNS_HIJACK_MODE}
dns_enhanced_mode=${BOX_DNS_ENHANCED_MODE}
ipv6_enabled=${BOX_IPV6_ENABLED}
tproxy_port=${BOX_TPROXY_PORT}
redir_port=${BOX_REDIR_PORT}
dns_port=${BOX_DNS_PORT}
EOF
}

mutator_sing_box_render_overlay() {
  local source_file="${1:?missing source file}"
  local rendered_file="${2:?missing rendered file}"

  if [[ -f "${source_file}" && "$(command -v jq || true)" != "" ]]; then
    jq \
      --arg mode "${BOX_NETWORK_MODE}" \
      --arg dns_mode "${BOX_DNS_HIJACK_MODE}" \
      --arg dns_enhanced_mode "${BOX_DNS_ENHANCED_MODE}" \
      --arg ipv6_enabled "${BOX_IPV6_ENABLED}" \
      --argjson tproxy_port "${BOX_TPROXY_PORT}" \
      --argjson redir_port "${BOX_REDIR_PORT}" \
      --argjson dns_port "${BOX_DNS_PORT}" \
      --arg controller "127.0.0.1:9090" \
      --arg external_ui "./dashboard" \
      --arg external_ui_download_url "https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip" \
      '
      . + {
        "experimental": ((.experimental // {}) + {
          "clash_api": ((.experimental.clash_api // {}) + {
            "external_controller": (.experimental.clash_api.external_controller // $controller),
            "external_ui": (.experimental.clash_api.external_ui // $external_ui),
            "external_ui_download_url": (.experimental.clash_api.external_ui_download_url // $external_ui_download_url)
          }),
            "box_overlay": {
              "network_mode": $mode,
              "dns_hijack_mode": $dns_mode,
              "dns_enhanced_mode": $dns_enhanced_mode,
              "ipv6_enabled": $ipv6_enabled,
              "tproxy_port": $tproxy_port,
              "redir_port": $redir_port,
            "dns_port": $dns_port
          }
        })
      }
      ' "${source_file}" >"${rendered_file}"
    mutator_sing_box_write_overlay_env "${rendered_file}"
    return 0
  fi

  if [[ -f "${source_file}" ]]; then
    cp -f "${source_file}" "${rendered_file}"
  else
    cat >"${rendered_file}" <<EOF
{
  "log": { "level": "warn" },
  "inbounds": [],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ],
  "route": { "final": "direct" }
}
EOF
  fi

  mutator_sing_box_write_overlay_env "${rendered_file}"
}
