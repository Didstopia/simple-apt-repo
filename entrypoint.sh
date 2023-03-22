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
  echo "::notice::Setting timezone to ${TZ} ..."
  ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
  echo "${TZ}" > /etc/timezone
fi

# Ensure the user with PUID and PGID exists
if ! id -u "${PUID}" > /dev/null 2>&1; then
  echo "::notice::Creating a non-root user with PUID ${PUID} and PGID ${PGID} ..."
  groupadd -g "${PGID}" ${GROUP}
  # useradd -u "$PUID" -o -m "$USER"
  useradd -u "${PUID}" -g "${PGID}" -o -m "${USER}"
fi

# If RUNNER_WORKSPACE is set and is not empty,
# re-export GITHUB_WORKSPACE to be the same as RUNNER_WORKSPACE
if [ -n "${RUNNER_WORKSPACE}" ]; then
  echo "::notice::Detected RUNNER_WORKSPACE set to ${RUNNER_WORKSPACE}, setting GITHUB_WORKSPACE to the same value ..."
  export GITHUB_WORKSPACE="${RUNNER_WORKSPACE}"

  # Export GITHUB_WORKSPACE as an output variable
  echo "GITHUB_WORKSPACE=${GITHUB_WORKSPACE}" >> $GITHUB_OUTPUT
fi

# If GITHUB_WORKSPACE is set, then we should modify the folder environment variables
# so that they're relative to the GITHUB_WORKSPACE.
if [ -n "${GITHUB_WORKSPACE}" ]; then
  # Verify that REPO_USE_RELATIVE is set to "true", otherwise skip this step
  if [[ $REPO_USE_RELATIVE = [Tt][Rr][Uu][Ee] ]]; then
    echo "::notice::Detected GITHUB_WORKSPACE set to ${GITHUB_WORKSPACE}, adjusting repository root to be relative to the workspace path ..."
    export REPO_DIR="${GITHUB_WORKSPACE}/${REPO_DIR#/}"
    export REPO_PACKAGES_DIR="${GITHUB_WORKSPACE}/${REPO_PACKAGES_DIR#/}"
    export REPO_KEYS_DIR="${GITHUB_WORKSPACE}/${REPO_KEYS_DIR#/}"
  else
    echo "::notice::Detected GITHUB_WORKSPACE set to ${GITHUB_WORKSPACE}, but REPO_USE_RELATIVE is set to \"${REPO_USE_RELATIVE}\", skipping relative path adjustments ..."
  fi
else
  echo "::notice::GITHUB_WORKSPACE is not set, skipping relative path adjustments ..."
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
