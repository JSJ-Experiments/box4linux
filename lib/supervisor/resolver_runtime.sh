#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

resolver_resolv_conf_path() {
  printf '%s\n' "${BOX_RESOLV_CONF_PATH:-/etc/resolv.conf}"
}

resolver_nsswitch_conf_path() {
  printf '%s\n' "${BOX_NSSWITCH_CONF_PATH:-/etc/nsswitch.conf}"
}

resolver_resolv_state_file() {
  init_runtime_paths
  printf '%s/state/resolv.conf.state\n' "${BOX_RUN_DIR}"
}

resolver_resolv_backup_file() {
  init_runtime_paths
  printf '%s/state/resolv.conf.backup\n' "${BOX_RUN_DIR}"
}

resolver_nsswitch_state_file() {
  init_runtime_paths
  printf '%s/state/nsswitch.conf.state\n' "${BOX_RUN_DIR}"
}

resolver_nsswitch_backup_file() {
  init_runtime_paths
  printf '%s/state/nsswitch.conf.backup\n' "${BOX_RUN_DIR}"
}

resolver_resolv_conf_is_managed() {
  local path
  path="$(resolver_resolv_conf_path)"
  [[ -f "${path}" ]] || return 1
  grep -Fqx '# Managed by box4linux while service is running.' "${path}" 2>/dev/null
}

resolver_capture_first_line() {
  local path="${1:?missing path}"
  local prefix="${2:?missing prefix}"
  awk -v pfx="${prefix}" '$1 == pfx { print; exit }' "${path}" 2>/dev/null || true
}

resolver_backup_resolv_conf() {
  local path state_file backup_file
  path="$(resolver_resolv_conf_path)"
  state_file="$(resolver_resolv_state_file)"
  backup_file="$(resolver_resolv_backup_file)"

  if [[ -f "${state_file}" ]]; then
    return 0
  fi

  if [[ -L "${path}" ]]; then
    printf 'kind=symlink\ntarget=%s\n' "$(readlink "${path}")" >"${state_file}"
    return 0
  fi

  if [[ -f "${path}" ]]; then
    cp -f "${path}" "${backup_file}"
    printf 'kind=file\nbackup=%s\n' "${backup_file}" >"${state_file}"
    return 0
  fi

  printf 'kind=absent\n' >"${state_file}"
}

resolver_write_managed_resolv_conf() {
  local path tmp_file search_line options_line
  path="$(resolver_resolv_conf_path)"
  tmp_file="$(mktemp)"
  search_line="$(resolver_capture_first_line "${path}" "search" || true)"
  options_line="$(resolver_capture_first_line "${path}" "options" || true)"

  cat >"${tmp_file}" <<EOF
# Managed by box4linux while service is running.
nameserver 127.0.0.1
EOF
  if [[ -n "${search_line}" ]]; then
    printf '%s\n' "${search_line}" >>"${tmp_file}"
  fi
  if [[ -n "${options_line}" ]]; then
    printf '%s\n' "${options_line}" >>"${tmp_file}"
  fi

  mkdir -p "$(dirname "${path}")"
  rm -f "${path}"
  install -m 0644 "${tmp_file}" "${path}"
  rm -f "${tmp_file}"
}

resolver_restore_resolv_conf() {
  local path state_file backup_file kind target current_managed
  path="$(resolver_resolv_conf_path)"
  state_file="$(resolver_resolv_state_file)"
  backup_file="$(resolver_resolv_backup_file)"

  [[ -f "${state_file}" ]] || return 0

  kind="$(awk -F= '$1=="kind" { print $2; exit }' "${state_file}")"
  target="$(awk -F= '$1=="target" { print substr($0, index($0, "=")+1); exit }' "${state_file}")"
  current_managed="false"
  if resolver_resolv_conf_is_managed; then
    current_managed="true"
  fi

  if [[ "${current_managed}" != "true" && -e "${path}" ]]; then
    log "WARN" "service" "RESOLV_CONF_RESTORE_SKIPPED" \
      "resolver restore skipped because ${path} is no longer managed by box4linux"
    rm -f "${state_file}" "${backup_file}"
    return 0
  fi

  case "${kind}" in
    symlink)
      rm -f "${path}"
      ln -s "${target}" "${path}"
      ;;
    file)
      install -m 0644 "${backup_file}" "${path}"
      ;;
    absent)
      rm -f "${path}"
      ;;
  esac

  rm -f "${state_file}" "${backup_file}"
}

resolver_split_hosts_modules() {
  local line="${1:-}"
  local hosts_body="${line#hosts:}"
  local -a words=() modules=()
  local word current=""

  read -r -a words <<<"${hosts_body}"
  for word in "${words[@]}"; do
    if [[ -z "${current}" ]]; then
      current="${word}"
      continue
    fi
    if [[ "${word}" == \[* ]]; then
      current+=" ${word}"
    else
      modules+=("${current}")
      current="${word}"
    fi
  done
  if [[ -n "${current}" ]]; then
    modules+=("${current}")
  fi

  printf '%s\n' "${modules[@]}"
}

resolver_normalize_hosts_line() {
  local line="${1:-}"
  local -a modules=() normalized=()
  local item dns_item="" resolve_item=""

  mapfile -t modules < <(resolver_split_hosts_modules "${line}")
  for item in "${modules[@]}"; do
    case "${item}" in
      dns*) dns_item="${item}" ;;
      resolve*) resolve_item="${item}" ;;
    esac
  done

  if [[ -z "${dns_item}" || -z "${resolve_item}" ]]; then
    printf '%s\n' "${line}"
    return 0
  fi

  for item in "${modules[@]}"; do
    case "${item}" in
      dns*|resolve*) ;;
      *)
        normalized+=("${item}")
        ;;
    esac
  done

  normalized+=("${dns_item}" "${resolve_item}")

  printf 'hosts: %s\n' "$(join_by " " "${normalized[@]}")"
}

resolver_backup_nsswitch() {
  local path state_file backup_file
  path="$(resolver_nsswitch_conf_path)"
  state_file="$(resolver_nsswitch_state_file)"
  backup_file="$(resolver_nsswitch_backup_file)"

  if [[ -f "${state_file}" || ! -f "${path}" ]]; then
    return 0
  fi

  cp -f "${path}" "${backup_file}"
  printf 'backup=%s\n' "${backup_file}" >"${state_file}"
}

resolver_apply_nsswitch() {
  local path tmp_file current_line normalized_line
  path="$(resolver_nsswitch_conf_path)"
  [[ -f "${path}" ]] || return 0

  current_line="$(awk '/^hosts:/ { print; exit }' "${path}" 2>/dev/null || true)"
  [[ -n "${current_line}" ]] || return 0

  normalized_line="$(resolver_normalize_hosts_line "${current_line}")"
  if [[ "${normalized_line}" == "${current_line}" ]]; then
    return 0
  fi

  resolver_backup_nsswitch
  tmp_file="$(mktemp)"
  awk -v replacement="${normalized_line}" '
    BEGIN { replaced = 0 }
    /^hosts:/ && replaced == 0 {
      print replacement
      replaced = 1
      next
    }
    { print }
  ' "${path}" >"${tmp_file}"
  install -m 0644 "${tmp_file}" "${path}"
  rm -f "${tmp_file}"
}

resolver_restore_nsswitch() {
  local path state_file backup_file
  path="$(resolver_nsswitch_conf_path)"
  state_file="$(resolver_nsswitch_state_file)"
  backup_file="$(resolver_nsswitch_backup_file)"

  [[ -f "${state_file}" && -f "${backup_file}" ]] || return 0
  install -m 0644 "${backup_file}" "${path}"
  rm -f "${state_file}" "${backup_file}"
}

resolver_runtime_apply() {
  resolver_backup_resolv_conf
  resolver_write_managed_resolv_conf
  resolver_apply_nsswitch
}

resolver_runtime_restore() {
  resolver_restore_nsswitch || true
  resolver_restore_resolv_conf || true
}
