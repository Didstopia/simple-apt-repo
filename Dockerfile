# syntax=docker/dockerfile:1

# The base image to use
FROM debian:bullseye

# The maintainer of this Dockerfile
LABEL maintainer="Didstopia <support@didstopia.com>"

# Set the default environment variables
ENV WORKSPACE_PATH=""
ENV REPO_DIR="/repo" \
    REPO_PACKAGES_DIR="/packages" \
    REPO_KEYS_DIR="/keys"
ENV REPO_ORIGIN="Example Repository" \
    REPO_LABEL="Example Repository" \
    REPO_VERSION="1.0" \
    REPO_DESCRIPTION="This is an example repository."
ENV REPO_KEY_TYPE="RSA" \
    REPO_KEY_LENGTH="4096" \
    REPO_KEY_EXPIRE="0" \
    REPO_KEY_NAME="Example Key" \
    REPO_KEY_EMAIL="example@example.com" \
    REPO_KEY_COMMENT="This is an example key." \
    REPO_KEY_PASSPHRASE="" \
    REPO_KEY_PUBLIC="" \
    REPO_KEY_PRIVATE="" \
    REPO_KEY_PUBLIC_PATH="${REPO_KEYS_DIR}/public.key" \
    REPO_KEY_PRIVATE_PATH="${REPO_KEYS_DIR}/private.key"

# Install the necessary tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      apt-transport-https \
      ca-certificates \
      curl \
      dpkg-dev \
      gpg \
      gpg-agent

# Create the necessary directories
RUN mkdir -p "${REPO_DIR}" "${REPO_PACKAGES_DIR}" "${REPO_KEYS_DIR}"

# Copy the entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

## FIXME: Once the verification script is fixed, uncomment it below!
# Copy the other scripts
COPY update.sh /usr/local/bin/repo-update
COPY verify.sh /usr/local/bin/repo-verify
RUN echo "#!/usr/bin/env bash" > /usr/local/bin/repo-all && \
    echo "#set -eo pipefail" >> /usr/local/bin/repo-all && \
    echo "repo-update" >> /usr/local/bin/repo-all && \
    echo "#repo-verify" >> /usr/local/bin/repo-all
RUN chmod a+x /usr/local/bin/repo-*

# Setup gosu for running as a non-root user
RUN set -eux; \
    apt-get update; \
    apt-get install -y gosu; \
    rm -rf /var/lib/apt/lists/*; \
    gosu nobody true

# Set default timezone
ENV TZ=UTC

# Set the default non-root user id and group id
ENV PUID=1000
ENV PGID=1000
ENV USER=docker
ENV GROUP=docker

# Set default permissions
RUN chown -R "${PUID}":"${PGID}" "${REPO_DIR}" "${REPO_PACKAGES_DIR}" "${REPO_KEYS_DIR}"

# Set the default working directory
WORKDIR /repo

# Set the volumes
VOLUME [ "${REPO_DIR}}", "${REPO_PACKAGES_DIR}", "${REPO_KEYS_DIR}" ]

# Set the entrypoint
ENTRYPOINT [ "/entrypoint.sh" ]

# Set the default command
CMD [ "repo-all" ]
