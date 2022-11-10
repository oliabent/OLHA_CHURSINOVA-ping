#!/bin/bash

########################################################################################################################
# Comments out feature flagged resources from k8s-configs kustomization.yaml files.
#
# Arguments
#   $1 -> The directory containing k8s-configs.
########################################################################################################################
feature_flags() {
  # TODO: NEED TO FIX TO MAKE THIS CONSISTENT for CDE
  #cd "${1}/k8s-configs"
  pushd "${1}" > /dev/null 2>&1

  local pgo_enabled=false

  # PGO can be used by multiple features. If any of them are enabled, we need to enable PGO.
  if [[ ${PF_PROVISIONING_ENABLED} == "true" ]]; then
    pgo_enabled=true
  fi

  # Map with the feature flag environment variable & the term to search to find the kustomization files
  flag_map="${RADIUS_PROXY_ENABLED}:ff-radius-proxy ${PF_PROVISIONING_ENABLED}:ff-provisioning ${pgo_enabled}:ff-pgo"

  for flag in $flag_map ; do
    enabled="${flag%%:*}"
    search_term="${flag##*:}"
    log "feature-flags.sh: ${search_term} is set to ${enabled}"

    # If the feature flag is disabled, comment the search term lines out of the kustomization files
    if [[ ${enabled} != "true" ]]; then
      # TODO: probably need to restrict to git repo items only?
      for kust_file in $(grep -rl "${search_term}" * | grep "kustomization.yaml"); do
        log "feature-flags.sh: Commenting out ${search_term} in ${kust_file}"
        sed -i.bak \
            -e "/${search_term}/ s|^#*|#|g" \
            "${kust_file}"
        rm -f "${kust_file}".bak
      done
    fi
  done
  popd > /dev/null 2>&1
}