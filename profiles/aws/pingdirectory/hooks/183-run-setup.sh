#!/usr/bin/env sh

${VERBOSE} && set -x

. "${HOOKS_DIR}/pingcommon.lib.sh"
. "${HOOKS_DIR}/utils.lib.sh"

test -f "${HOOKS_DIR}/pingdata.lib.sh" && . "${HOOKS_DIR}/pingdata.lib.sh"

export encryptionOption=$(getEncryptionOption)
export jvmOptions=$(getJvmOptions)

ORIG_UNBOUNDID_JAVA_ARGS="${UNBOUNDID_JAVA_ARGS}"
HEAP_SIZE_INT=$(echo "${MAX_HEAP_SIZE}" | grep 'g$' | cut -d'g' -f1)

if test ! -z "${HEAP_SIZE_INT}" && test "${HEAP_SIZE_INT}" -ge 4; then
  NEW_HEAP_SIZE=$((HEAP_SIZE_INT - 2))g
  echo "setup: changing manage-profile heap size to ${NEW_HEAP_SIZE}"
  export UNBOUNDID_JAVA_ARGS="-client -Xmx${NEW_HEAP_SIZE} -Xms${NEW_HEAP_SIZE}"
fi

if is_multi_cluster; then
  SHORT_HOST_NAME=$(hostname)
  ORDINAL=${SHORT_HOST_NAME##*-}
  export PD_LDAP_PORT="636${ORDINAL}"
else
  export PD_PUBLIC_HOSTNAME=$(hostname -f)
  export PD_LDAP_PORT="${LDAPS_PORT}"
fi

echo "setup: using public host:port of ${PD_PUBLIC_HOSTNAME}:${PD_LDAP_PORT}"
SERVER_HOST_FILE="${SERVER_ROOT_DIR}"/config/server.host

echo "setup: adding PD_PUBLIC_HOSTNAME ${PD_PUBLIC_HOSTNAME} to ${SERVER_HOST_FILE} before setup"
echo "hostname=${PD_PUBLIC_HOSTNAME}" > "${SERVER_HOST_FILE}"

echo "setup: contents of ${SERVER_HOST_FILE} before setup"
cat "${SERVER_HOST_FILE}"

"${SERVER_ROOT_DIR}"/bin/manage-profile setup \
    --profile "${PD_PROFILE}" \
    --useEnvironmentVariables \
    --tempProfileDirectory /tmp \
    --doNotStart \
    --rejectFile /tmp/rejects.ldif

MANAGE_PROFILE_STATUS=${?}
echo "setup: manage-profile setup status: ${MANAGE_PROFILE_STATUS}"

echo "setup: contents of ${SERVER_HOST_FILE} after setup"
cat "${SERVER_HOST_FILE}"

# Re-add the hostname in case manage-profile setup loses it.
echo "setup: adding PD_PUBLIC_HOSTNAME ${PD_PUBLIC_HOSTNAME} to ${SERVER_HOST_FILE} after setup"
echo "hostname=${PD_PUBLIC_HOSTNAME}" > "${SERVER_HOST_FILE}"

echo "setup: contents of ${SERVER_HOST_FILE} after restore post-setup"
cat "${SERVER_HOST_FILE}"

export UNBOUNDID_JAVA_ARGS="${ORIG_UNBOUNDID_JAVA_ARGS}"

if test "${MANAGE_PROFILE_STATUS}" -ne 0; then
  echo "setup: contents of manage-profile.log file:"
  cat "${SERVER_ROOT_DIR}/logs/tools/manage-profile.log"

  test -f /tmp/rejects.ldif && cat /tmp/rejects.ldif

  echo "setup: server install failed"
  exit 183
fi

echo "setup: server install complete"
exit 0