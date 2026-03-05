#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

mutator_sing_box_render_overlay() {
  local source_file="${1:?missing source file}"
  local rendered_file="${2:?missing rendered file}"

  if [[ -f "${source_file}" && "$(command -v jq || true)" != "" ]]; then
    jq \
      --arg mode "${BOX_NETWORK_MODE}" \
      --arg dns_mode "${BOX_DNS_HIJACK_MODE}" \
      --argjson tproxy_port "${BOX_TPROXY_PORT}" \
      --argjson redir_port "${BOX_REDIR_PORT}" \
      --argjson dns_port "${BOX_DNS_PORT}" \
      '
      . + {
        "experimental": ((.experimental // {}) + {
          "box_overlay": {
            "network_mode": $mode,
            "dns_hijack_mode": $dns_mode,
            "tproxy_port": $tproxy_port,
            "redir_port": $redir_port,
            "dns_port": $dns_port
          }
        })
      }
      ' "${source_file}" >"${rendered_file}"
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

  cat >"${rendered_file}.overlay.env" <<EOF
network_mode=${BOX_NETWORK_MODE}
dns_hijack_mode=${BOX_DNS_HIJACK_MODE}
tproxy_port=${BOX_TPROXY_PORT}
redir_port=${BOX_REDIR_PORT}
dns_port=${BOX_DNS_PORT}
EOF
}
