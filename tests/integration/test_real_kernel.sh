#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOXCTL="${ROOT_DIR}/cmd/boxctl"
TMP_DIR="$(mktemp -d)"
NS="box-rt-$RANDOM-$$"

cleanup() {
  ip netns del "${NS}" >/dev/null 2>&1 || true
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

skip() {
  printf 'SKIP: %s\n' "$1"
  exit 0
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_cmd() {
  local cmd="${1:?missing cmd}"
  command -v "${cmd}" >/dev/null 2>&1 || skip "missing command: ${cmd}"
}

assert_contains_text() {
  local haystack="${1:?missing haystack}"
  local needle="${2:?missing needle}"
  local context="${3:-}"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected text not found: ${needle} (${context})"
  fi
}

assert_not_contains_text() {
  local haystack="${1:?missing haystack}"
  local needle="${2:?missing needle}"
  local context="${3:-}"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    fail "unexpected text found: ${needle} (${context})"
  fi
}

if [[ "${EUID}" -ne 0 ]]; then
  skip "requires root/CAP_NET_ADMIN"
fi

require_cmd ip

if ! ip netns add "${NS}" >/dev/null 2>&1; then
  skip "cannot create netns (CAP_SYS_ADMIN likely unavailable)"
fi
if ! ip netns exec "${NS}" ip link set lo up >/dev/null 2>&1; then
  skip "cannot configure netns loopback"
fi

BOX_RUN_DIR="${TMP_DIR}/run"
BOX_VAR_DIR="${TMP_DIR}/var"
BOX_LOG_DIR="${TMP_DIR}/log"
CONFIG_FILE="${TMP_DIR}/box.toml"
mkdir -p "${BOX_RUN_DIR}" "${BOX_VAR_DIR}" "${BOX_LOG_DIR}"

write_config() {
  local backend="${1:?missing backend}"
  local coexist_mode="${2:-preserve_tailnet}"
  local route_pref="${3:-180}"

  cat >"${CONFIG_FILE}" <<CFG
[core]
selected = "mihomo"
bin_dir = "/usr/local/bin"
workdir = "${BOX_VAR_DIR}"
config_source = "/etc/box/profiles/config.yaml"

[network]
mode = "mixed"
tproxy_port = 19898
redir_port = 19797
dns_port = 11053
dns_hijack_mode = "redirect"
dns_coexist_mode = "${coexist_mode}"
tailscale_iface = "tailscale0"
tailnet_ipv4_cidr = "100.64.0.0/10"
tailnet_ipv6_cidr = "fd7a:115c:a1e0::/48"
tailscale_dns_resolver = "100.100.100.100"
tailscale_fwmark = "0x80000/0xff0000"
tailscale_route_table = 52

[firewall]
backend = "${backend}"
route_table = 2024
route_pref = ${route_pref}
fwmark = "16777216/16777216"
CFG
}

run_boxctl() {
  ip netns exec "${NS}" env \
    PATH="${PATH}" \
    BOX_CONFIG_FILE="${CONFIG_FILE}" \
    BOX_RUN_DIR="${BOX_RUN_DIR}" \
    BOX_VAR_DIR="${BOX_VAR_DIR}" \
    BOX_LOG_DIR="${BOX_LOG_DIR}" \
    BOX_LOG_TO_FILE=0 \
    "${BOXCTL}" "$@"
}

seed_tailscale_state() {
  ip -n "${NS}" rule del pref 52 >/dev/null 2>&1 || true
  ip -n "${NS}" rule add fwmark 0x80000/0xff0000 table 52 pref 52 >/dev/null 2>&1 || true
  ip -n "${NS}" route del local 100.100.100.100 dev lo table 52 >/dev/null 2>&1 || true
  ip -n "${NS}" route add local 100.100.100.100 dev lo table 52 >/dev/null 2>&1 || true
}

assert_tailscale_invariants() {
  local rules routes
  rules="$(ip -n "${NS}" rule list 2>/dev/null || true)"
  routes="$(ip -n "${NS}" route show table 52 2>/dev/null || true)"

  if [[ ! "${rules}" =~ fwmark[[:space:]]+0x80000/0xff0000[[:space:]]+(lookup|table)[[:space:]]+52 ]]; then
    fail "tailscale fwmark/table-52 rule missing"
  fi
  assert_contains_text "${routes}" "100.100.100.100" "tailscale table 52 route"
}

assert_box_route_pref_singleton() {
  local expected_pref="${1:?missing pref}"
  local rules count
  rules="$(ip -n "${NS}" rule list 2>/dev/null || true)"
  count="$(printf '%s\n' "${rules}" | grep -Ec "fwmark[[:space:]]+16777216/16777216[[:space:]]+(lookup|table)[[:space:]]+2024[[:space:]]+pref[[:space:]]+${expected_pref}$" || true)"
  if [[ "${count}" != "1" ]]; then
    fail "expected one BOX fwmark policy rule with pref=${expected_pref}; got ${count}"
  fi
}

iptables_box_object_count() {
  local out_mangle out_nat
  out_mangle="$(ip netns exec "${NS}" iptables -t mangle -S 2>/dev/null || true)"
  out_nat="$(ip netns exec "${NS}" iptables -t nat -S 2>/dev/null || true)"
  printf '%s\n%s\n' "${out_mangle}" "${out_nat}" | grep -c 'BOX_' || true
}

nft_box_object_count() {
  local tables inet_table ip_table
  tables="$(ip netns exec "${NS}" nft list tables 2>/dev/null || true)"
  inet_table="$(ip netns exec "${NS}" nft list table inet box_mangle 2>/dev/null || true)"
  ip_table="$(ip netns exec "${NS}" nft list table ip box_nat 2>/dev/null || true)"
  {
    printf '%s\n' "${tables}"
    printf '%s\n' "${inet_table}"
    printf '%s\n' "${ip_table}"
  } | grep -Ec '(box_mangle|box_nat|box_main|box_dns)' || true
}

assert_no_box_artifacts() {
  local backend="${1:?missing backend}"
  local rules routes table
  rules="$(ip -n "${NS}" rule list 2>/dev/null || true)"
  routes="$(ip -n "${NS}" route show table 2024 2>/dev/null || true)"

  if printf '%s\n' "${rules}" | grep -Eq 'fwmark[[:space:]]+16777216/16777216[[:space:]]+(lookup|table)[[:space:]]+2024'; then
    fail "BOX fwmark policy rule leaked"
  fi
  if printf '%s\n' "${routes}" | grep -Fq 'local default dev lo'; then
    fail "BOX route table entry leaked"
  fi

  case "${backend}" in
    iptables)
      table="$(ip netns exec "${NS}" iptables -t mangle -S 2>/dev/null || true)"
      if printf '%s\n' "${table}" | grep -Fq 'BOX_'; then
        fail "iptables mangle BOX artifacts leaked"
      fi
      table="$(ip netns exec "${NS}" iptables -t nat -S 2>/dev/null || true)"
      if printf '%s\n' "${table}" | grep -Fq 'BOX_'; then
        fail "iptables nat BOX artifacts leaked"
      fi
      ;;
    nftables)
      table="$(ip netns exec "${NS}" nft list tables 2>/dev/null || true)"
      if printf '%s\n' "${table}" | grep -Eq 'table (inet box_mangle|ip box_nat)'; then
        fail "nftables BOX tables leaked"
      fi
      ;;
  esac
}

assert_preserve_tailnet_rules() {
  local backend="${1:?missing backend}"
  local out
  case "${backend}" in
    iptables)
      out="$(ip netns exec "${NS}" iptables -t mangle -S BOX_MANGLE 2>/dev/null || true)"
      assert_contains_text "${out}" "-i tailscale0 -j RETURN" "iptables tailscale bypass"
      out="$(ip netns exec "${NS}" iptables -t mangle -S BOX_DNS_MANGLE 2>/dev/null || true)"
      assert_contains_text "${out}" "100.100.100.100" "iptables magicdns bypass"
      ;;
    nftables)
      out="$(ip netns exec "${NS}" nft list chain inet box_mangle box_main 2>/dev/null || true)"
      assert_contains_text "${out}" "iifname \"tailscale0\" return" "nft tailscale bypass"
      out="$(ip netns exec "${NS}" nft list chain inet box_mangle box_dns 2>/dev/null || true)"
      assert_contains_text "${out}" "100.100.100.100" "nft magicdns bypass"
      ;;
  esac
}

assert_strict_box_rules() {
  local backend="${1:?missing backend}"
  local out
  case "${backend}" in
    iptables)
      out="$(ip netns exec "${NS}" iptables -t mangle -S BOX_MANGLE 2>/dev/null || true)"
      assert_not_contains_text "${out}" "-i tailscale0 -j RETURN" "iptables strict_box tailscale bypass"
      out="$(ip netns exec "${NS}" iptables -t mangle -S BOX_DNS_MANGLE 2>/dev/null || true)"
      assert_not_contains_text "${out}" "100.100.100.100" "iptables strict_box magicdns bypass"
      ;;
    nftables)
      out="$(ip netns exec "${NS}" nft list chain inet box_mangle box_main 2>/dev/null || true)"
      assert_not_contains_text "${out}" "iifname \"tailscale0\" return" "nft strict_box tailscale bypass"
      out="$(ip netns exec "${NS}" nft list chain inet box_mangle box_dns 2>/dev/null || true)"
      assert_not_contains_text "${out}" "100.100.100.100" "nft strict_box magicdns bypass"
      ;;
  esac
}

backend_usable() {
  local backend="${1:?missing backend}"
  case "${backend}" in
    iptables)
      command -v iptables >/dev/null 2>&1 || return 1
      ip netns exec "${NS}" iptables -t mangle -S >/dev/null 2>&1
      ;;
    nftables)
      command -v nft >/dev/null 2>&1 || return 1
      ip netns exec "${NS}" nft list tables >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

run_backend_case() {
  local backend="${1:?missing backend}"
  local count_before count_after status_json

  if ! backend_usable "${backend}"; then
    printf 'SKIP: backend=%s unavailable in this kernel/runtime\n' "${backend}"
    return 0
  fi

  printf '[backend=%s] preserve_tailnet lifecycle\n' "${backend}"
  write_config "${backend}" "preserve_tailnet" "180"
  seed_tailscale_state

  run_boxctl firewall disable >/dev/null 2>&1 || true
  run_boxctl firewall enable >/dev/null
  status_json="$(run_boxctl firewall status --json)"
  assert_contains_text "${status_json}" "\"backend\":\"${backend}\"" "status backend"
  assert_contains_text "${status_json}" "\"backend_available\":true" "status backend availability"
  assert_contains_text "${status_json}" "\"dns_coexist_mode_active\":\"preserve_tailnet\"" "status coexist active"

  if [[ "${backend}" == "iptables" ]]; then
    count_before="$(iptables_box_object_count)"
  else
    count_before="$(nft_box_object_count)"
  fi

  run_boxctl firewall renew >/dev/null
  run_boxctl firewall renew >/dev/null

  if [[ "${backend}" == "iptables" ]]; then
    count_after="$(iptables_box_object_count)"
  else
    count_after="$(nft_box_object_count)"
  fi
  if [[ "${count_before}" != "${count_after}" ]]; then
    fail "backend=${backend} object count changed across renew (${count_before} -> ${count_after})"
  fi

  assert_tailscale_invariants
  assert_box_route_pref_singleton "180"
  assert_preserve_tailnet_rules "${backend}"

  run_boxctl firewall disable >/dev/null
  assert_tailscale_invariants
  assert_no_box_artifacts "${backend}"

  printf '[backend=%s] strict_box rule-difference\n' "${backend}"
  write_config "${backend}" "strict_box" "180"
  seed_tailscale_state
  run_boxctl firewall enable >/dev/null
  status_json="$(run_boxctl firewall status --json)"
  assert_contains_text "${status_json}" "\"dns_coexist_mode_active\":\"strict_box\"" "status coexist strict_box"
  assert_contains_text "${status_json}" "\"tailscale_bypass_applied\":false" "status strict_box bypass flag"
  assert_strict_box_rules "${backend}"
  run_boxctl firewall disable >/dev/null
  assert_tailscale_invariants
  assert_no_box_artifacts "${backend}"

  printf 'PASS: backend=%s real-kernel checks\n' "${backend}"
  return 0
}

executed=0

for backend in iptables nftables; do
  if backend_usable "${backend}"; then
    executed=$((executed + 1))
  fi
  run_backend_case "${backend}"
done

if [[ "${executed}" -eq 0 ]]; then
  skip "no usable firewall backend in this environment"
fi

printf 'PASS: real-kernel firewall validation completed\n'
