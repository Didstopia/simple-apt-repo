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
  # useradd -u "$PUID" -o -m "$USER"
  useradd -u "${PUID}" -g "${PGID}" -o -m "${USER}"
fi

# Print out both GITHUB_WORKSPACE and RUNNER_WORKSPACE if they are set and not empty
if [ -n "${GITHUB_WORKSPACE}" ]; then
  echo "::debug::GITHUB_WORKSPACE is set to ${GITHUB_WORKSPACE}"
fi
if [ -n "${RUNNER_WORKSPACE}" ]; then
  echo "::debug::RUNNER_WORKSPACE is set to ${RUNNER_WORKSPACE}"
fi

# HACK: Fix the GITHUB_WORKSPACE path inside containers being wrong (points to /github/workspace instead of /home/runner/work/<repo>/<repo>)
if [ -n "${GITHUB_WORKSPACE}" ]; then
  # If GITHUB_WORKSPACE is set to /github/workspace, then we need to fix it by setting it to RUNNER_WORKSPACE/<repo>
  if [[ "${GITHUB_WORKSPACE}" = "/github/workspace" ]]; then
    # Get the repository name from the GITHUB_REPOSITORY environment variable, which is in the format of <owner>/<repo>
    REPO_NAME=$(echo "${GITHUB_REPOSITORY}" | cut -d'/' -f2)
    export WORKSPACE_PATH="${RUNNER_WORKSPACE}/${REPO_NAME}"
    echo "::warning::Detected GITHUB_WORKSPACE set to ${GITHUB_WORKSPACE}, overriding and setting it to ${WORKSPACE_PATH} instead ..."
    export GITHUB_WORKSPACE="/home/runner/work/${GITHUB_REPOSITORY}"
  fi
fi

# Always export the WORKSPACE_PATH as an output variable
echo "workspace-path=${WORKSPACE_PATH}" >> $GITHUB_OUTPUT

# If WORKSPACE_PATH is set, then we should modify the folder environment variables
# so that they're relative to the WORKSPACE_PATH.
if [ -n "${WORKSPACE_PATH}" ]; then
  # Verify that REPO_USE_RELATIVE is set to "true", otherwise skip this step
  # if [[ $REPO_USE_RELATIVE = [Tt][Rr][Uu][Ee] ]]; then
  echo "::notice::Detected workspace path as ${WORKSPACE_PATH}, adjusting repository root to be relative to the workspace path ..."
  export REPO_DIR="${WORKSPACE_PATH}/${REPO_DIR#/}"
  export REPO_PACKAGES_DIR="${WORKSPACE_PATH}/${REPO_PACKAGES_DIR#/}"
  export REPO_KEYS_DIR="${WORKSPACE_PATH}/${REPO_KEYS_DIR#/}"
  # else
  #   echo "::notice::Detected WORKSPACE_PATH set to ${WORKSPACE_PATH}, but REPO_USE_RELATIVE is set to \"${REPO_USE_RELATIVE}\", skipping relative path adjustments ..."
  # fi
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
