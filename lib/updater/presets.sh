#!/usr/bin/env bash

# shellcheck shell=bash

set -euo pipefail

updater_system_or_repo_path() {
  local relative_path="${1:?missing relative path}"
  local system_path="${BOX_ETC_DIR_DEFAULT}/${relative_path}"
  local repo_path="${BOX_REPO_ROOT}/etc/${relative_path}"

  if [[ -f "${system_path}" ]]; then
    printf '%s\n' "${system_path}"
    return 0
  fi
  if [[ -f "${repo_path}" ]]; then
    printf '%s\n' "${repo_path}"
    return 0
  fi
  return 1
}

updater_subs_default_provider_names() {
  printf '%s\n' proxy1 proxy3 proxy4 proxy5 proxy6
}

updater_subs_default_template() {
  updater_system_or_repo_path "box/profiles/phone-mihomo-config.yml"
}

updater_subs_render_mihomo_phone() {
  local template_file="${1:?missing template file}"
  local output_file="${2:?missing output file}"
  local unresolved=0
  local -a provider_names=()
  local -a provider_urls=()
  local idx

  if [[ ! -f "${template_file}" ]]; then
    log "ERROR" "updater" "E_UPDATE_PRESET" \
      "mihomo phone preset template missing: ${template_file}"
    return "${E_UPDATE}"
  fi

  cp -f "${template_file}" "${output_file}"

  if [[ "${#BOX_UPDATER_SUBS_PROVIDER_URLS[@]}" -gt 0 ]]; then
    provider_urls=("${BOX_UPDATER_SUBS_PROVIDER_URLS[@]}")
    if [[ "${#BOX_UPDATER_SUBS_PROVIDER_NAMES[@]}" -gt 0 ]]; then
      provider_names=("${BOX_UPDATER_SUBS_PROVIDER_NAMES[@]}")
    else
      mapfile -t provider_names < <(updater_subs_default_provider_names)
      if [[ "${#provider_urls[@]}" -ne "${#provider_names[@]}" ]]; then
        log "ERROR" "updater" "E_UPDATE_PRESET" \
          "mihomo phone preset needs provider_names when provider_urls length differs from defaults"
        return "${E_UPDATE}"
      fi
    fi

    local names_csv urls_csv tmp_output
    names_csv="$(IFS=$'\037'; printf '%s' "${provider_names[*]}")"
    urls_csv="$(IFS=$'\037'; printf '%s' "${provider_urls[*]}")"
    tmp_output="${output_file}.tmp"

    if ! awk -v names="${names_csv}" -v urls="${urls_csv}" '
      BEGIN {
        split(names, name_arr, "\037")
        split(urls, url_arr, "\037")
        for (i = 1; i in name_arr; i++) {
          map[name_arr[i]] = url_arr[i]
          seen[name_arr[i]] = 0
        }
      }
      {
        line = $0
        if (match(line, /^[[:space:]]*([A-Za-z0-9_-]+):[[:space:]]*$/, m)) {
          current = m[1]
        }
        if (current in map && line ~ /^[[:space:]]*url:[[:space:]]*"/) {
          sub(/url:[[:space:]]*".*"/, "url: \"" map[current] "\"", line)
          seen[current] = 1
          current = ""
        }
        print line
      }
      END {
        missing = 0
        for (name in map) {
          if (seen[name] == 0) {
            printf("missing provider in template: %s\n", name) > "/dev/stderr"
            missing = 1
          }
        }
        exit missing
      }
    ' "${output_file}" >"${tmp_output}"; then
      rm -f "${tmp_output}"
      log "ERROR" "updater" "E_UPDATE_PRESET" "failed to apply mihomo phone provider mapping"
      return "${E_UPDATE}"
    fi
    mv -f "${tmp_output}" "${output_file}"
  fi

  if grep -Eq '<SUBSCRIPTION_URL_[A-Z0-9_]+>' "${output_file}"; then
    unresolved=1
  fi
  if [[ "${unresolved}" == "1" ]]; then
    log "ERROR" "updater" "E_UPDATE_PRESET" \
      "mihomo phone preset still contains unresolved subscription placeholders"
    return "${E_UPDATE}"
  fi
}

updater_geo_default_preset() {
  case "${BOX_CORE}" in
    mihomo) printf '%s\n' "metacubex_mihomo" ;;
    sing-box) printf '%s\n' "metacubex_sing_box" ;;
    *) printf '%s\n' "metacubex_legacy" ;;
  esac
}

updater_geo_manifest_target_root() {
  if [[ -n "${BOX_UPDATER_GEO_TARGET:-}" ]]; then
    printf '%s\n' "${BOX_UPDATER_GEO_TARGET}"
  else
    printf '%s\n' "${BOX_CORE_WORKDIR}"
  fi
}

updater_geo_emit_manifest() {
  local preset="${1:?missing preset}"
  local target_root="${2:?missing target root}"
  case "${preset}" in
    metacubex_mihomo)
      printf 'Country.mmdb\thttps://github.com/MetaCubeX/meta-rules-dat/raw/release/country-lite.mmdb\t%s/Country.mmdb\n' "${target_root}"
      printf 'GeoSite.dat\thttps://github.com/MetaCubeX/meta-rules-dat/raw/release/geosite.dat\t%s/GeoSite.dat\n' "${target_root}"
      ;;
    metacubex_sing_box)
      printf 'geoip.db\thttps://github.com/MetaCubeX/meta-rules-dat/raw/release/geoip-lite.db\t%s/geoip.db\n' "${target_root}"
      printf 'geosite.db\thttps://github.com/MetaCubeX/meta-rules-dat/raw/release/geosite.db\t%s/geosite.db\n' "${target_root}"
      ;;
    metacubex_legacy)
      printf 'geoip.dat\thttps://github.com/MetaCubeX/meta-rules-dat/raw/release/geoip-lite.dat\t%s/geoip.dat\n' "${target_root}"
      printf 'geosite.dat\thttps://github.com/MetaCubeX/meta-rules-dat/raw/release/geosite.dat\t%s/geosite.dat\n' "${target_root}"
      ;;
    *)
      log "ERROR" "updater" "E_UPDATE_PRESET" "unsupported geo preset: ${preset}"
      return "${E_UPDATE}"
      ;;
  esac
}
