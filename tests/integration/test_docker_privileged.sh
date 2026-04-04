#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${BOX_DOCKER_ENV_FILE:-${ROOT_DIR}/.box-test-subscription.env}"
IMAGE="${BOX_DOCKER_IMAGE:-archlinux:base-devel}"
CONTAINER_NAME="box4linux-test-$RANDOM-$$"
PHASE2_CMD="${BOX_DOCKER_PHASE2_CMD:-./tests/integration/test_phase2.sh}"
REAL_CMD="${BOX_DOCKER_REAL_CMD:-./tests/integration/test_real_kernel.sh}"
RUN_PACKAGE_BUILD="${BOX_DOCKER_RUN_PACKAGE_BUILD:-0}"

cleanup() {
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

require_cmd() {
  local cmd="${1:?missing command}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    printf 'missing command: %s\n' "${cmd}" >&2
    exit 1
  fi
}

log() {
  printf '[docker-test] %s\n' "$1"
}

require_cmd docker

docker_env_args=()
if [[ -f "${ENV_FILE}" ]]; then
  docker_env_args+=(--env-file "${ENV_FILE}")
  log "using env file ${ENV_FILE}"
else
  log "no env file found at ${ENV_FILE}; continuing without subscription env"
fi

container_cmd=$'set -euo pipefail\n'
container_cmd+=$'pacman -Syu --noconfirm --needed bash coreutils gawk grep iproute2 iptables nftables procps-ng sed tar >/dev/null\n'
container_cmd+=$'cd /work\n'
container_cmd+=$'printf "[container] kernel=%s\\n" "$(uname -r)"\n'
container_cmd+=$'if [[ -n "${BOX_TEST_SUBSCRIPTION_URL:-}" ]]; then printf "[container] subscription env present\\n"; else printf "[container] subscription env absent\\n"; fi\n'
container_cmd+=$'bash -lc "${BOX_DOCKER_PHASE2_CMD}"\n'
container_cmd+=$'bash -lc "${BOX_DOCKER_REAL_CMD}"\n'
container_cmd+=$'if [[ "${BOX_DOCKER_RUN_PACKAGE_BUILD:-0}" == "1" ]]; then cd packaging/arch && makepkg --noconfirm -f; fi\n'

log "starting privileged container ${CONTAINER_NAME} from ${IMAGE}"
docker run --rm --name "${CONTAINER_NAME}" \
  --privileged \
  --network host \
  -e BOX_DOCKER_RUN_PACKAGE_BUILD="${RUN_PACKAGE_BUILD}" \
  -e BOX_DOCKER_PHASE2_CMD="${PHASE2_CMD}" \
  -e BOX_DOCKER_REAL_CMD="${REAL_CMD}" \
  "${docker_env_args[@]}" \
  -v "${ROOT_DIR}:/work" \
  -w /work \
  "${IMAGE}" \
  bash -lc "${container_cmd}"
