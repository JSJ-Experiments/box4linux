#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-all}"
cd "${ROOT_DIR}"

shell_files=(
  "cmd/boxctl"
  "lib/*.sh"
  "lib/firewall/*.sh"
  "lib/supervisor/*.sh"
  "tests/integration/test_phase2.sh"
  "tests/integration/test_real_kernel.sh"
  "tests/integration/test_arch_package_smoke.sh"
  "tests/integration/test_docker_privileged.sh"
  "tests/fixtures/mockbin/ip"
  "tests/fixtures/mockbin/iptables"
  "packaging/scripts/systemd-lifecycle.sh"
  "packaging/arch/box4linux.install"
)

run_bash_syntax() {
  # shellcheck disable=SC2086
  bash -n ${shell_files[*]}
}

run_shellcheck() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    printf 'shellcheck not available; skipping\n' >&2
    return 0
  fi

  shellcheck -e SC1091,SC2034 \
    cmd/boxctl \
    lib/*.sh \
    lib/firewall/*.sh \
    lib/supervisor/*.sh \
    tests/integration/test_phase2.sh \
    tests/integration/test_real_kernel.sh \
    tests/integration/test_arch_package_smoke.sh \
    tests/integration/test_docker_privileged.sh \
    packaging/scripts/systemd-lifecycle.sh
  shellcheck -e SC1091,SC2034 -s sh packaging/arch/box4linux.install
}

case "${MODE}" in
  all)
    run_bash_syntax
    run_shellcheck
    ;;
  syntax)
    run_bash_syntax
    ;;
  shellcheck)
    run_shellcheck
    ;;
  *)
    printf 'usage: %s [all|syntax|shellcheck]\n' "$0" >&2
    exit 2
    ;;
esac
