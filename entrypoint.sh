#!/usr/bin/env bash

set -eo pipefail

set -x

# Set the default command to run if no command is specified
if [ $# -eq 0 ]; then
  # set -- /bin/bash
  set -- /usr/local/bin/repo-update
fi

# Ensure the user with PUID and PGID exists
if ! id -u "${PUID}" > /dev/null 2>&1; then
  echo "Creating a non-root user with PUID ${PUID} and PGID ${PGID} ..."
  groupadd -g "${PGID}" ${GROUP}
  # useradd -u "$PUID" -o -m "$USER"
  useradd -u "${PUID}" -g "${PGID}" -o -m "${USER}"
fi

# Ensure that the user with PUID and PGID owns all of the appropriate directories
chown -R "${PUID}":"${PGID}" "${REPO_DIR}" "${REPO_PACKAGES_DIR}" "${REPO_KEYS_DIR}"

# Run the command as the user with PUID and PGID
exec gosu "${PUID}":"${PGID}" "$@"
