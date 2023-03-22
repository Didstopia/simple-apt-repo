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
  echo "Setting timezone to ${TZ} ..."
  ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
  echo "${TZ}" > /etc/timezone
fi

# Ensure the user with PUID and PGID exists
if ! id -u "${PUID}" > /dev/null 2>&1; then
  echo "Creating a non-root user with PUID ${PUID} and PGID ${PGID} ..."
  groupadd -g "${PGID}" ${GROUP}
  # useradd -u "$PUID" -o -m "$USER"
  useradd -u "${PUID}" -g "${PGID}" -o -m "${USER}"
fi

# If GITHUB_WORKSPACE is set, then we should modify the folder environment variables
# so that they're relative to the GITHUB_WORKSPACE.
if [ -n "${GITHUB_WORKSPACE}" ]; then
  # Verify that REPO_USE_RELATIVE is set to "true", otherwise skip this step
  if [ "${REPO_USE_RELATIVE}" == "true" ]; then
    echo "Detected GITHUB_WORKSPACE set to ${GITHUB_WORKSPACE}, adjusting repository root to be relative to the workspace path ..."
    export REPO_DIR="${GITHUB_WORKSPACE}/${REPO_DIR}"
    export REPO_PACKAGES_DIR="${GITHUB_WORKSPACE}/${REPO_PACKAGES_DIR}"
    export REPO_KEYS_DIR="${GITHUB_WORKSPACE}/${REPO_KEYS_DIR}"
  else
    echo "Detected GITHUB_WORKSPACE set to ${GITHUB_WORKSPACE}, but REPO_USE_RELATIVE is not set to \"true\", skipping relative path adjustments ..."
  fi
else
  echo "GITHUB_WORKSPACE is not set, skipping relative path adjustments ..."
fi

# Ensure that the user with PUID and PGID owns all of the appropriate directories
chown -R "${PUID}":"${PGID}" "${REPO_DIR}" "${REPO_PACKAGES_DIR}" "${REPO_KEYS_DIR}"

# Run the command as the user with PUID and PGID
exec gosu "${PUID}":"${PGID}" "$@"
