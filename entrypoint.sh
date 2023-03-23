#!/usr/bin/env bash

set -eo pipefail

# set -x

# Set the default command to run if no command is specified
if [ $# -eq 0 ]; then
  # set -- /bin/bash
  set -- /usr/local/bin/repo-update
fi

# Set the timezone from the TZ environment variable
if [ -n "${TZ}" ]; then
  echo "::debug::Setting timezone to ${TZ} ..."
  ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
  echo "${TZ}" > /etc/timezone
fi

# Ensure the user with PUID and PGID exists
if ! id -u "${PUID}" > /dev/null 2>&1; then
  echo "::debug::Creating a non-root user with PUID ${PUID} and PGID ${PGID} ..."
  groupadd -g "${PGID}" ${GROUP}
  useradd -u "${PUID}" -g "${PGID}" -o -m "${USER}"
fi

# Print out both GITHUB_WORKSPACE and RUNNER_WORKSPACE if they are set and not empty
if [ -n "${GITHUB_WORKSPACE}" ]; then
  echo "::debug::GITHUB_WORKSPACE is set to ${GITHUB_WORKSPACE}"
fi
if [ -n "${RUNNER_WORKSPACE}" ]; then
  echo "::debug::RUNNER_WORKSPACE is set to ${RUNNER_WORKSPACE}"
fi

# If GITHUB_WORKSPACE is set and WORKSPACE_PATH is not set, then set WORKSPACE_PATH to GITHUB_WORKSPACE
if [ -n "${GITHUB_WORKSPACE}" ]; then
  # If WORKSPACE_PATH is not set, then set it to GITHUB_WORKSPACE
  if [ -z "${WORKSPACE_PATH}" ]; then
    echo "::debug::GitHub workspace is set to ${GITHUB_WORKSPACE}, setting workspace path to match this ..."

    # Override the workspace path with the GitHub workspace path
    export WORKSPACE_PATH="${GITHUB_WORKSPACE}"
  fi

  # Ensure that the WORKSPACE_PATH exists
  mkdir -p "${WORKSPACE_PATH}"

  # Export the WORKSPACE_PATH as an output variable
  echo "workspace-path=${WORKSPACE_PATH}" >> $GITHUB_OUTPUT
fi

# If WORKSPACE_PATH is set, then we should modify the folder environment variables
# so that they're relative to the WORKSPACE_PATH.
if [ -n "${WORKSPACE_PATH}" ]; then
  echo "::notice::Detected workspace path as ${WORKSPACE_PATH}, adjusting repository root to be relative to the workspace path ..."
  export REPO_DIR="${WORKSPACE_PATH}/${REPO_DIR#/}"
  export REPO_PACKAGES_DIR="${WORKSPACE_PATH}/${REPO_PACKAGES_DIR#/}"
  export REPO_KEYS_DIR="${WORKSPACE_PATH}/${REPO_KEYS_DIR#/}"
else
  echo "::debug::WORKSPACE_PATH is not set, skipping relative path adjustments ..."
fi

echo
echo "::notice::Starting with the following configuration:"
echo "::notice::  Root Path: ${REPO_DIR}"
echo "::notice::  Packages Path: ${REPO_PACKAGES_DIR}"
echo "::notice::  Keys Path: ${REPO_KEYS_DIR}"
echo

# Ensure that the required directories exist
mkdir -p "${REPO_DIR}" "${REPO_PACKAGES_DIR}" "${REPO_KEYS_DIR}"

# Ensure that the user with PUID and PGID owns all of the appropriate directories
chown -R "${PUID}":"${PGID}" "${REPO_DIR}" "${REPO_PACKAGES_DIR}" "${REPO_KEYS_DIR}"

# Run the command as the user with PUID and PGID
exec gosu "${PUID}":"${PGID}" "$@"
