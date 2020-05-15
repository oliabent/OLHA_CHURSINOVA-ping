#!/bin/bash

##################################################################
# Common variables
##################################################################

test ! -z ${VERBOSE} && set -x

export REGION="${AWS_DEFAULT_REGION}"
export CLUSTER_NAME="${EKS_CLUSTER_NAME_EKS1_14}"
export CLUSTER_NAME_LC=$(echo ${CLUSTER_NAME} | tr '[:upper:]' '[:lower:]')

export CONFIG_PARENT_DIR=aws
export CONFIG_REPO_BRANCH=${CI_COMMIT_REF_NAME}

export ARTIFACT_REPO_URL=s3://${CLUSTER_NAME}-artifacts-bucket
export PING_ARTIFACT_REPO_URL=https://ping-artifacts.s3-us-west-2.amazonaws.com
export LOG_ARCHIVE_URL=s3://${CLUSTER_NAME}-logs-bucket
export BACKUP_URL=s3://${CLUSTER_NAME}-backup-bucket

export NAMESPACE=ping-cloud-${CI_COMMIT_REF_SLUG}
export AWS_PROFILE=csg

[[ ${CI_COMMIT_REF_SLUG} != master ]] && export ENVIRONMENT=-${CI_COMMIT_REF_SLUG}

FQDN=${ENVIRONMENT}.${TENANT_DOMAIN}

# Common
LOGS_CONSOLE=https://logs-${CLUSTER_NAME_LC}.${TENANT_DOMAIN}

# Pingdirectory
PINGDIRECTORY_CONSOLE=https://pingdataconsole${FQDN}/console
PINGDIRECTORY_ADMIN=pingdirectory-admin${FQDN}

# Pingfederate
# admin services:
PINGFEDERATE_CONSOLE=https://pingfederate-admin${FQDN}/pingfederate/app
PINGFEDERATE_API=https://pingfederate-admin${FQDN}/pingfederate/app/pf-admin-api/api-docs

# runtime services:
PINGFEDERATE_AUTH_ENDPOINT=https://pingfederate${FQDN}
PINGFEDERATE_OAUTH_PLAYGROUND=https://pingfederate${FQDN}/OAuthPlayground

# Pingaccess
# admin services:
PINGACCESS_CONSOLE=https://pingaccess-admin${FQDN}
PINGACCESS_API=https://pingaccess-admin${FQDN}/pa-admin-api/v3/api-docs

# runtime services:
PINGACCESS_RUNTIME=https://pingaccess${FQDN}
PINGACCESS_AGENT=https://pingaccess-agent${FQDN}

# Source some utility methods.
. ${CI_PROJECT_DIR}/utils.sh

########################################################################################################################
# Configures kubectl to be able to talk to the Kubernetes API server based on the following environment variables:
#
#   - KUBE_CA_PEM_EKS1_14
#   - KUBE_URL_EKS1_14
#   - EKS_CLUSTER_NAME_EKS1_14
#   - AWS_ACCOUNT_ROLE_ARN
#
# If the environment variables are not present, then the function will exit with a non-zero return code.
########################################################################################################################
configure_kube() {
  if test -n "${SKIP_CONFIGURE_KUBE}"; then
    log "Skipping KUBE configuration"
    return
  fi

  check_env_vars "KUBE_CA_PEM_EKS1_14" "KUBE_URL_EKS1_14" "EKS_CLUSTER_NAME_EKS1_14" "AWS_ACCOUNT_ROLE_ARN"
  HAS_REQUIRED_VARS=${?}

  if test ${HAS_REQUIRED_VARS} -ne 0; then
    exit 1
  fi

  log "Configuring KUBE"
  echo "${KUBE_CA_PEM_EKS1_14}" > "$(pwd)/kube.ca.pem"

  kubectl config set-cluster "${EKS_CLUSTER_NAME_EKS1_14}" \
    --server="${KUBE_URL_EKS1_14}" \
    --certificate-authority="$(pwd)/kube.ca.pem"

  kubectl config set-credentials aws \
    --exec-command aws-iam-authenticator \
    --exec-api-version client.authentication.k8s.io/v1alpha1 \
    --exec-arg=token \
    --exec-arg=-i --exec-arg="${EKS_CLUSTER_NAME_EKS1_14}" \
    --exec-arg=-r --exec-arg="${AWS_ACCOUNT_ROLE_ARN}"

  kubectl config set-context "${EKS_CLUSTER_NAME_EKS1_14}" \
    --cluster="${EKS_CLUSTER_NAME_EKS1_14}" \
    --user=aws

  kubectl config use-context "${EKS_CLUSTER_NAME_EKS1_14}"
}

########################################################################################################################
# Configures the aws CLI to be able to talk to the AWS API server based on the following environment variables:
#
#   - AWS_ACCESS_KEY_ID
#   - AWS_SECRET_ACCESS_KEY
#   - AWS_DEFAULT_REGION
#   - AWS_ACCOUNT_ROLE_ARN
#
# If the environment variables are not present, then the function will exit with a non-zero return code. The AWS config
# and credentials file will be set up with a profile of ${AWS_PROFILE} environment variable defined in the common.sh
# file.
########################################################################################################################
configure_aws() {
  if test -n "${SKIP_CONFIGURE_AWS}"; then
    log "Skipping AWS CLI configuration"
    return
  fi

  check_env_vars "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_DEFAULT_REGION" "AWS_ACCOUNT_ROLE_ARN"
  HAS_REQUIRED_VARS=${?}

  if test ${HAS_REQUIRED_VARS} -ne 0; then
    exit 1
  fi

  log "Configuring AWS CLI"
  mkdir -p ~/.aws

  cat > ~/.aws/config <<EOF
  [default]
  output = json

  [profile ${AWS_PROFILE}]
  output = json
  region = ${AWS_DEFAULT_REGION}
  source_profile = default
  role_arn = ${AWS_ACCOUNT_ROLE_ARN}
EOF

  cat > ~/.aws/credentials <<EOF
  [default]
  aws_access_key_id = ${AWS_ACCESS_KEY_ID}
  aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}

  [${AWS_PROFILE}]
  role_arn = ${AWS_ACCOUNT_ROLE_ARN}
EOF
}

########################################################################################################################
# Wait for the expected count of a resource until the specified timeout.
#
# Arguments
#   ${1} -> The expected count of the resource.
#   ${2} -> The command to get the actual count of the resource. The execution of the command is expected to return
#           a number.
#   ${3} -> Wait timeout in seconds. Default is 2 minutes.
########################################################################################################################
wait_for_expected_resource_count() {
  EXPECTED=${1}
  COMMAND=${2}
  TIMEOUT_SECONDS=${3:-120}

  TIME_WAITED_SECONDS=0
  SLEEP_SECONDS=5

  while true; do
    ACTUAL=$(eval "${COMMAND}")
    if test ! -z "${ACTUAL}" && test "${ACTUAL}" -eq "${EXPECTED}"; then
      break
    fi

    eval "${COMMAND}"
    sleep "${SLEEP_SECONDS}"

    TIME_WAITED_SECONDS=$((TIME_WAITED_SECONDS + SLEEP_SECONDS))
    if test "${TIME_WAITED_SECONDS}" -ge "${TIMEOUT_SECONDS}"; then
      echo "Expected count ${EXPECTED} but found ${ACTUAL} after ${TIMEOUT_SECONDS} seconds"
      return 1
    fi
  done

  return 0
}
