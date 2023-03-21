# syntax=docker/dockerfile:1

# This Dockerfile is used to build an image which can both create and update
# an apt repository. It is based on the official Debian Bullseye image, and adds
# the necessary tools to create and update the repository.
# 
# It has the following features:
# - Automatically create a new apt repository if it doesn't already exist in the
#   /repo directory, including the necessary directories and files, as well as
#   the Release and InRelease files, and the Packages/Packages.gz file
# - Update an apt repository based on the contents of the /packages directory
# - Automatically generates a GPG/PGP key pair, if they don't already exist,
#   or if the user hasn't provided them as environment variables
# - Automatically signs the Release file with the GPG/PGP key pair,
#   creating the InRelease file
# - Exposing the public key as part of the repository, so that clients can
#   verify the authenticity of the repository and its packages easily
# - Verifying packages in /packages using for example `dpkg-deb --info`,
#   to verify that all required files are present, and that the package
#   is not corrupt, and that it has all the metadata necessary, including a
#   Description field
# - Allowing the user to customize the entire process, by providing environment
#   variables to the container, which will be used to set the paths used by
#   the entrypoint script and the volumes, as well as the GPG/PGP key pair
#   used to sign the repository, and anything else that would be useful
# - Allows hosting packages for multiple different linux distributions,
#   and multiple different architectures, by using environment variables
#
# dists\
#       |--jessie/
#       |--bullseye\
#                   |Changelog
#                   |Release
#                   |InRelease
#                   |Release.gpg
#                   |--main\
#                           |--amd64\
#                           |--arm64\
#                   |--contrib\
#                   |--non-free\
# pool\
#      |--this is where the .deb files for all releases live
#
# The following environment variables are available:
# - REPO_DIR: The directory where the repository will be created or updated, eg. "/repo"
# - REPO_PACKAGES_DIR: The directory where the packages are located, eg. "/packages"
# - REPO_KEYS_DIR: The directory where the GPG/PGP keys are located, eg. "/keys"
#
# - REPO_CODENAME: The codename of the repository, e.g. "bullseye"
# - REPO_COMPONENTS: The components of the repository, e.g. "main,contrib,non-free"
# - REPO_ARCHITECTURES: The architectures of the repository, e.g. "amd64,arm64,i386"
#
# - REPO_ORIGIN: The origin of the repository, e.g. "My Repository"
# - REPO_LABEL: The label of the repository, e.g. "My Repository"
# - REPO_VERSION: The version of the repository, e.g. "1.0"
# - REPO_DESCRIPTION: The description of the repository, e.g. "My Repository Description"
#
# - REPO_KEY_TYPE: The type of key to use, e.g. "RSA" or "DSA"
# - REPO_KEY_LENGTH: The length of the key to use, e.g. 4096
# - REPO_KEY_EXPIRE: The expiration date of the key, e.g. "0" for never
# - REPO_KEY_NAME: The name of the key, e.g. "My Key"
# - REPO_KEY_EMAIL: The email address of the key, e.g. "foo@bar.com"
# - REPO_KEY_COMMENT: The comment of the key, e.g. "My Key Comment"
# - REPO_KEY_PASSPHRASE: The passphrase of the key, e.g. "My Key Passphrase"
# - REPO_KEY_PUBLIC: The public key to use, e.g. "-----BEGIN PGP PUBLIC KEY BLOCK-----..."
# - REPO_KEY_PRIVATE: The private key to use, e.g. "-----BEGIN PGP PRIVATE KEY BLOCK-----..."

# The base image to use
FROM debian:bullseye

# The maintainer of this Dockerfile
LABEL maintainer="Didstopia <support@didstopia.com>"

# Set the default environment variables
ENV REPO_DIR="/repo" \
    REPO_PACKAGES_DIR="/packages" \
    REPO_KEYS_DIR="/keys"
ENV REPO_CODENAME="bullseye" \
    REPO_COMPONENTS="main,contrib,non-free" \
    REPO_ARCHITECTURES="amd64,arm64,i386"
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

# Copy the other scripts
COPY update.sh /usr/local/bin/repo-update
RUN chmod a+x /usr/local/bin/repo-update

# Setup gosu for running as a non-root user
RUN set -eux; \
    apt-get update; \
    apt-get install -y gosu; \
    rm -rf /var/lib/apt/lists/*; \
    gosu nobody true

# Set the default non-root user id and group id
ENV PUID 1000
ENV PGID 1000
ENV USER docker
ENV GROUP docker

# Set default permissions
RUN chown -R "${PUID}":"${PGID}" "${REPO_DIR}" "${REPO_PACKAGES_DIR}" "${REPO_KEYS_DIR}"

# Set the default working directory
WORKDIR /repo

# Set the volumes
VOLUME [ "${REPO_DIR}}", "${REPO_PACKAGES_DIR}", "${REPO_KEYS_DIR}" ]

# Set the entrypoint
ENTRYPOINT [ "/entrypoint.sh" ]

# Set the default command
CMD [ "repo-update" ]
