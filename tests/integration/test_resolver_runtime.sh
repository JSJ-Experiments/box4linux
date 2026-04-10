#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="${1:?missing expected}"
  local actual="${2:?missing actual}"
  local context="${3:-}"
  if [[ "${expected}" != "${actual}" ]]; then
    fail "expected '${expected}', got '${actual}' (${context})"
  fi
}

assert_contains() {
  local haystack="${1:?missing haystack}"
  local needle="${2:?missing needle}"
  local context="${3:-}"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "missing '${needle}' (${context})"
  fi
}

BOX_RUN_DIR="${TMP_DIR}/run"
BOX_VAR_DIR="${TMP_DIR}/var"
BOX_LOG_DIR="${TMP_DIR}/log"
BOX_RESOLV_CONF_PATH="${TMP_DIR}/etc/resolv.conf"
BOX_NSSWITCH_CONF_PATH="${TMP_DIR}/etc/nsswitch.conf"
mkdir -p "${BOX_RUN_DIR}" "${BOX_VAR_DIR}" "${BOX_LOG_DIR}" "$(dirname "${BOX_RESOLV_CONF_PATH}")"
export BOX_RUN_DIR BOX_VAR_DIR BOX_LOG_DIR BOX_RESOLV_CONF_PATH BOX_NSSWITCH_CONF_PATH BOX_LOG_TO_FILE=0

source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/supervisor/resolver_runtime.sh"

printf '[1/2] apply/restore preserves symlinked resolv.conf and normalizes hosts order\n'
upstream_resolv="${TMP_DIR}/upstream-resolv.conf"
cat >"${upstream_resolv}" <<'EOF'
nameserver 10.0.0.10
search campus.example
options trust-ad
EOF
ln -s "${upstream_resolv}" "${BOX_RESOLV_CONF_PATH}"
cat >"${BOX_NSSWITCH_CONF_PATH}" <<'EOF'
hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns
EOF

resolver_runtime_apply

managed_resolv="$(cat "${BOX_RESOLV_CONF_PATH}")"
managed_hosts="$(cat "${BOX_NSSWITCH_CONF_PATH}")"
assert_contains "${managed_resolv}" '# Managed by box4linux while service is running.' "managed resolv marker"
assert_contains "${managed_resolv}" 'nameserver 127.0.0.1' "managed localhost resolver"
assert_contains "${managed_resolv}" 'search campus.example' "preserved search line"
assert_contains "${managed_resolv}" 'options trust-ad' "preserved options line"
assert_eq 'hosts: mymachines files myhostname dns resolve [!UNAVAIL=return]' "${managed_hosts}" "normalized hosts line"

resolver_runtime_restore

assert_eq "${upstream_resolv}" "$(readlink "${BOX_RESOLV_CONF_PATH}")" "restored resolv symlink"
assert_eq 'hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns' "$(cat "${BOX_NSSWITCH_CONF_PATH}")" "restored nsswitch"

printf '[2/2] restore skips unexpected manual resolver replacement\n'
cp -f "${upstream_resolv}" "${BOX_RESOLV_CONF_PATH}.file"
rm -f "${BOX_RESOLV_CONF_PATH}"
cp -f "${BOX_RESOLV_CONF_PATH}.file" "${BOX_RESOLV_CONF_PATH}"
resolver_runtime_apply
cat >"${BOX_RESOLV_CONF_PATH}" <<'EOF'
nameserver 9.9.9.9
EOF
resolver_runtime_restore
assert_eq 'nameserver 9.9.9.9' "$(cat "${BOX_RESOLV_CONF_PATH}")" "manual resolv override preserved"

printf 'PASS\n'
