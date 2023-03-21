#!/usr/bin/env bash

# This script is part of a Dockerfile that is used to build an image which can both create and update
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
# - REPO_KEY_TYPE: The type of key to use, e.g. "RSA" or "DSA"
# - REPO_KEY_LENGTH: The length of the key to use, e.g. 4096
# - REPO_KEY_EXPIRE: The expiration date of the key, e.g. "0" for never
# - REPO_KEY_NAME: The name of the key, e.g. "My Key"
# - REPO_KEY_EMAIL: The email address of the key, e.g. "foo@bar.com"
# - REPO_KEY_COMMENT: The comment of the key, e.g. "My Key Comment"
# - REPO_KEY_PASSPHRASE: The passphrase of the key, e.g. "My Key Passphrase"
# - REPO_KEY_PUBLIC: The public key to use, e.g. "-----BEGIN PGP PUBLIC KEY BLOCK-----..."
# - REPO_KEY_PRIVATE: The private key to use, e.g. "-----BEGIN PGP PRIVATE KEY BLOCK-----..."

set -eo pipefail

# set -x

# Fix GPG issues when running without a TTY/non-interactively
rm -fr ~/.gnupg
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg
# export GPG_TTY=$(tty)
# mkdir -p ~/.gnupg
# touch ~/.gnupg/gpg.conf
# echo "use-agent" >> ~/.gnupg/gpg.conf
# echo "pinentry-mode loopback" >> ~/.gnupg/gpg.conf
# touch ~/.gnupg/gpg-agent.conf
# echo "allow-loopback-pinentry" >> ~/.gnupg/gpg-agent.conf

# Function for printing out information about the current user
function printUser() {
  echo
  echo "Who am I? I am $(whoami)."
  echo "- My username is $(id -un)."
  echo "- My group is $(id -gn)."
  echo "- My user ID is $(id -u)."
  echo "- My group ID is $(id -g)."
  echo
}

# Function for generating  a GPG key pair,
# if one doesn't already exist in the /keys directory,
# and if the user hasn't provided one as environment variables
function createKeys() {
  echo "Checking for existing signing keys ..."

  # Return early if the keys already exist under $REPO_KEYS_DIR
  if [[ -f "${REPO_KEYS_DIR}/public.key" ]] && [[ -f "${REPO_KEYS_DIR}/private.key" ]]; then
    echo "Existing key files detected, skipping key generation ..."
  
    # Load the GPG keys
    echo "Loading existing GPG keys ..."
    gpg --quiet --batch --import "${REPO_KEYS_DIR}/private.key"

    return
  fi

  # Return early if the user has already provided keys under the
  # $REPO_KEY_PUBLIC and $REPO_KEY_PRIVATE environment variables
  if [[ -n "${REPO_KEY_PUBLIC}" ]] && [[ -n "${REPO_KEY_PRIVATE}" ]]; then
    echo "Detected keys as environment variables, skipping key generation ..."

    echo "${REPO_KEY_PUBLIC}" > "${REPO_KEYS_DIR}/public.key"
    echo "${REPO_KEY_PRIVATE}" > "${REPO_KEYS_DIR}/private.key"

    # Load the GPG keys
    echo "Loading existing GPG keys ..."
    gpg --quiet --batch --import "${REPO_KEYS_DIR}/private.key"

    return
  fi

  # Show an error if a required environment variable is missing,
  # such as the key type, length, name, or email
  if [[ -z "${REPO_KEY_TYPE}" ]] || [[ -z "${REPO_KEY_LENGTH}" ]] || [[ -z "${REPO_KEY_NAME}" ]] || [[ -z "${REPO_KEY_EMAIL}" ]]; then
    echo "Error: missing required environment variables for key generation, unable to continue"
    exit 1
  fi

  echo "Generating signing keys ..."

  # Generate a new  PGP key pair, skipping environment variables
  # that are empty or unset.
  # See here for more information:
  # https://www.gnupg.org/documentation/manuals/gnupg/Unattended-GPG-key-generation.html
  # gpg --no-tty --batch --gen-key <<EOF
  gpg --quiet --batch --gen-key <<EOF
%echo Generating keys ...
Key-Type: ${REPO_KEY_TYPE}
Key-Length: ${REPO_KEY_LENGTH}
Name-Real: ${REPO_KEY_NAME}
Name-Email: ${REPO_KEY_EMAIL}
Expire-Date: ${REPO_KEY_EXPIRE}
$(if [[ -n "${REPO_KEY_COMMENT}" ]]; then echo "Name-Comment: ${REPO_KEY_COMMENT}"; fi)
$(if [[ -n "${REPO_KEY_PASSPHRASE}" ]]; then echo "Passphrase: ${REPO_KEY_PASSPHRASE}"; else echo "%no-ask-passphrase"; echo "%no-protection"; fi)
%commit
%echo Successfully generated keys
EOF

  # Export the public key to the keys directory
  echo "Exporting public key ..."
  gpg --quiet --armor --export "${REPO_KEY_EMAIL}" > "${REPO_KEYS_DIR}/public.key"

  # Export the private key to the keys directory
  echo "Exporting private key ..."
  gpg --quiet --armor --export-secret-keys "${REPO_KEY_EMAIL}" > "${REPO_KEYS_DIR}/private.key"

  ## FIXME: Is the format of the filename correct? Is it even a GPG key, or is it actually a PGP key?!
  # Copy the public key to the root of the repository
  echo "Copying public key to repository root ..."
  cp "${REPO_KEYS_DIR}/public.key" "${REPO_DIR}/gpg-pubkey.asc"

  # Convert the repo root public key from PGP to GPG
  echo "Converting public key to GPG format ..."
  

  echo "Successfully generated signing keys"
}

# Function for updating the packages in the apt repository
function updatePackages() {
  # Shorthand variables for the repo paths etc.
  ROOT="${REPO_DIR}"
  CODENAME="${REPO_CODENAME}"
  COMPONENTS="${REPO_COMPONENTS}"
  ARCHITECTURES="${REPO_ARCHITECTURES}"

  echo "Updating packages ..."

  # Recursively loop through all .deb files in the $REPO_PACKAGES_DIR,
  # using eg. `dpkg-deb --info` to get information about the package,
  # so we can figure out which codename, component and architecture
  # the package belongs to, then copy it to the correct directory.
  
  # Loop through all .deb files in the $REPO_PACKAGES_DIR
  for DEB in $(find "${REPO_PACKAGES_DIR}" -name "*.deb"); do
    # Get the package basename
    DEB_BASENAME=$(basename "${DEB}")
    echo "Adding package ${DEB_BASENAME} ..."

    # Get the package information
    DEB_INFO=$(dpkg-deb --info "${DEB}")
    # echo "DEB_INFO: ${DEB_INFO}"

    # Get the package architecture
    DEB_ARCHITECTURE=$(echo "${DEB_INFO}" | grep Architecture | awk '{print $2}')

    # Get the package component
    DEB_COMPONENT=$(echo "${DEB_INFO}" | grep Section | awk '{print $2}')

    # Get the package codename
    DEB_CODENAME=$(echo "${DEB_INFO}" | grep Maintainer | awk '{print $2}' | cut -d' ' -f2)

    # Get the package name
    DEB_NAME=$(echo "${DEB_INFO}" | grep Package | awk '{print $2}')

    # Get the package version
    DEB_VERSION=$(echo "${DEB_INFO}" | grep Version | awk '{print $2}')

    # Get the package filename
    DEB_FILENAME="${DEB_NAME}_${DEB_VERSION}_${DEB_ARCHITECTURE}.deb"

    # Get the package destination directory
    DEB_DESTINATION="${ROOT}/pool/${DEB_CODENAME}/${DEB_COMPONENT}/${DEB_ARCHITECTURE}"

    # Create the package destination directory if it doesn't exist
    mkdir -p "${DEB_DESTINATION}"

    # Create the appropriate repo component directories if they don't exist
    mkdir -p "${ROOT}/dists/${DEB_CODENAME}/${DEB_COMPONENT}/${DEB_ARCHITECTURE}"

    # Copy the package to the destination directory
    cp -f "${DEB}" "${DEB_DESTINATION}/${DEB_FILENAME}"

    ## TODO: Ideally we wouldn't do this every time, right?
    ##       Couldn't we instead loop through all the pool directories,
    ##       then the codename and component directories, then run this once for those?

    # Get the current pool based on the codename, component and architecture
    POOL="${ROOT}/pool/${DEB_CODENAME}/${DEB_COMPONENT}"

    # Get the current Packages file based on the codename, component and architecture
    PACKAGES_FILE="${ROOT}/dists/${DEB_CODENAME}/${DEB_COMPONENT}/${DEB_ARCHITECTURE}/Packages"

    # Update the Changelog file
    cat << EOF > "${ROOT}/dists/${DEB_CODENAME}/Changelog"
$(date -R) - ${REPO_KEY_EMAIL}
EOF

    # Update the Packages and Packages.gz files
    dpkg-scanpackages --arch "${ARCHITECTURE}" "${POOL}" > "${PACKAGES_FILE}" 2> /dev/null
    cat "${PACKAGES_FILE}" | gzip -9 > "${PACKAGES_FILE}.gz"
  done

  # This function will loop through the "pool" directory, looking for .deb files,
  # and it will create a Packages file and a Packages.gz file, which will be used by
  # apt to get information about the packages in the repository, and to download
  # the packages themselves.

  # # Get the repo components by splitting the $REPO_COMPONENTS string by comma
  # IFS=',' read -ra COMPONENTS_ARRAY <<< "${COMPONENTS}"

  # # Loop through the repo components
  # for COMPONENT in "${COMPONENTS_ARRAY[@]}"; do
  #   # Get the repo architectures by splitting the $REPO_ARCHITECTURES string by comma
  #   IFS=',' read -ra ARCHITECTURES_ARRAY <<< "${ARCHITECTURES}"

  #   # Loop through the repo architectures
  #   for ARCHITECTURE in "${ARCHITECTURES_ARRAY[@]}"; do
  #     # Get the current pool based on the codename, component and architecture
  #     POOL="${ROOT}/pool/${CODENAME}/${COMPONENT}"

  #     # Get the current Packages file based on the codename, component and architecture
  #     PACKAGES_FILE="${ROOT}/dists/${CODENAME}/${COMPONENT}/${ARCHITECTURE}/Packages"

  #     # Update the Packages and Packages.gz files
  #     dpkg-scanpackages --arch "${ARCHITECTURE}" "${POOL}" > "${PACKAGES_FILE}"
  #     cat "${PACKAGES_FILE}" | gzip -9 > "${PACKAGES_FILE}.gz"
  #   done
  # done

  echo "Successfully updated packages"
}

# # Function for updating the apt repository,
# # including creating a new one if one doesn't already exist
# function createRepo() {
#   # Shorthand variables for the repo paths etc.
#   ROOT="${REPO_DIR}"
#   CODENAME="${REPO_CODENAME}"
#   COMPONENTS="${REPO_COMPONENTS}"
#   ARCHITECTURES="${REPO_ARCHITECTURES}"

#   echo "Creating repository ..."

#   # Ensure that the core repo directories exist
#   mkdir -p "${ROOT}" "${ROOT}/dists" "${ROOT}/pool"

#   # Ensure that the repo codename directory exists
#   mkdir -p "${ROOT}/dists/${CODENAME}"

#   # Get the repo components by splitting the $REPO_COMPONENTS string by comma
#   IFS=',' read -ra COMPONENTS_ARRAY <<< "${COMPONENTS}"

#   # Loop through the repo components
#   for COMPONENT in "${COMPONENTS_ARRAY[@]}"; do
#     # Ensure that each component directory exists
#     mkdir -p "$ROOT/dists/${CODENAME}/${COMPONENT}" "${ROOT}/pool/${CODENAME}/${COMPONENT}"

#     # Get the repo architectures by splitting the $REPO_ARCHITECTURES string by comma
#     IFS=',' read -ra ARCHITECTURES_ARRAY <<< "${ARCHITECTURES}"

#     # Loop through the repo architectures
#     for ARCHITECTURE in "${ARCHITECTURES_ARRAY[@]}"; do
#       # Ensure that each architecture directory exists
#       mkdir -p "$ROOT/dists/${CODENAME}/${COMPONENT}/${ARCHITECTURE}"
#     done
#   done

#   # - Ensure that the repo architectures directories exist, eg. $REPO_DIR/dists/$REPO_CODENAME/$REPO_COMPONENTS/$REPO_ARCHITECTURES (split $REPO_ARCHITECTURES string by comma)
#   # - Ensure that the repo codename directory has the "Changelog", "Release", "InRelease" and "Release.gpg" files
#   # - Ensure that the repo pool directory has the "Packages" and "Packages.gz" files (these should be auto-generated and updated eg. when .deb files change)

#   echo "Successfully created repository"

# }

# Function for generating Release file hashes as a string
function generateHashString() {
  # Shorthand variables for the repo paths etc.
  local ROOT="${REPO_DIR}"

  local HASH_NAME="${1}"
  local HASH_CMD="${2}"
  local CODENAME="${3}"
  echo "${HASH_NAME}:"
  for f in $(find "${ROOT}/dists/${CODENAME}" -type f); do
    if [[ "$f" == *"Release"* ]]; then
      continue
    fi
    echo " $(${HASH_CMD} ${f}  | cut -d" " -f1) $(wc -c $f | cut -d" " -f1) $(echo $f | cut -c$((${#ROOT}+${#CODENAME}+1))-)"
  done
}

# Function for generating the Release file as a string
function generateReleaseString() {

  ## FIXME: Change the values of the Release file to match the values of the environment variables!

  local CODENAME="${1}"

  # Split $REPO_ARCHITECTURES string by commas and transform it into a space separated string
  # ARCHITECTURES=$(echo "${REPO_ARCHITECTURES}" | sed 's/,/ /g')
  local ARCHITECTURES="${2}"

  # Split $REPO_COMPONENTS string by commas and transform it into a space separated string
  # COMPONENTS=$(echo "${REPO_COMPONENTS}" | sed 's/,/ /g')
  local COMPONENTS="${3}"

  # Generate the Release file contents
  # and print them as part of the console output.
  cat << EOF
Origin: ${REPO_ORIGIN}
Label: ${REPO_LABEL}
Codename: ${CODENAME}
Version: ${REPO_VERSION}
Architectures: ${ARCHITECTURES}
Components: ${COMPONENTS}
Description: ${REPO_DESCRIPTION}
Date: $(date -Ru)
EOF

  # Generate and print the file hashes.
  generateHashString "MD5Sum" "md5sum" "${CODENAME}"
  generateHashString "SHA1" "sha1sum" "${CODENAME}"
  generateHashString "SHA256" "sha256sum" "${CODENAME}"
}

# Function for creating a codename specific Release file,
# as well as signing it with the PGP keys
function createRelease() {
  # Shorthand variables for the repo paths etc.
  local ROOT="${REPO_DIR}"
  
  # Get all the codenames
  local CODENAMES=$(getCodenames)

  # Loop through the codenames, architectures and components
  # and store the results in the $CODENAMES, $ARCHITECTURES and $COMPONENTS variables
  

  # Loop through the codenames
  for CODENAME in ${CODENAMES}; do
    # Get the architectures
    local ARCHITECTURES=$(getArchitectures "${CODENAME}")

    # Get all the components for every architecture,
    # combined into a single array, with no duplicates
    local COMPONENTS=$(getComponents "${CODENAME}" "${ARCHITECTURES}")

    # # Get the components
    # COMPONENTS=$(getComponents "${CODENAME}" "${ARCHITECTURE}")

    # Create the Release file
    echo "Creating Release file for ${CODENAME} ..."
    rm -f "${ROOT}/dists/${CODENAME}/Release"
    generateReleaseString "${CODENAME}" "${ARCHITECTURES}" "${COMPONENTS}" > "${ROOT}/dists/${CODENAME}/Release"

    # Sign the Release file
    echo "Creating signed Release.gpg file ..."
    rm -f "${ROOT}/dists/${CODENAME}/Release.gpg"
    gpg --quiet --batch --default-key "${REPO_KEY_EMAIL}" --output "${ROOT}/dists/${CODENAME}/Release.gpg" --detach-sig "${ROOT}/dists/${CODENAME}/Release"

    # Create the signed InRelease file
    echo "Creating signed InRelease file ..."
    rm -f "${ROOT}/dists/${CODENAME}/InRelease"
    gpg --quiet --default-key "${REPO_KEY_EMAIL}" --output "${ROOT}/dists/${CODENAME}/InRelease" --clearsign "${ROOT}/dists/${CODENAME}/Release"

    echo "Successfully created signed release files for ${CODENAME}"

    # Loop through the architectures
    # declare -a COMPONENTS
    # for ARCHITECTURE in ${ARCHITECTURES}; do
    #   # Get the components
    #   COMPONENTS=$(getComponents "${CODENAME}" "${ARCHITECTURE}")
    # done
  done
}

# Function for getting an array of all the codenames,
# based on the codename directories in the pool directory
function getCodenames() {
  # Shorthand variables for the repo paths etc.
  local ROOT="${REPO_DIR}"

  # Get the codenames by getting the directory names in the pool directory
  local CODENAMES=$(find "${ROOT}/pool" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")

  # Transform the codenames string into an array
  IFS=' ' read -ra CODENAMES_ARRAY <<< "${CODENAMES}"

  # Print the codenames array
  echo "${CODENAMES_ARRAY[@]}"
}

# Function for getting the architectures
# for a given codename, using the pool
# directory structure
function getArchitectures() {
  # Shorthand variables for the repo paths etc.
  local ROOT="${REPO_DIR}"

  # Get the codename
  local CODENAME="${1}"

  # Get the architectures by getting the directory names in the codename directory
  local ARCHITECTURES=$(find "${ROOT}/pool/${CODENAME}" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")

  # Transform the architectures string into an array
  IFS=' ' read -ra ARCHITECTURES_ARRAY <<< "${ARCHITECTURES}"

  # Print the architectures array
  echo "${ARCHITECTURES_ARRAY[@]}"
}

# Function for getting the components
# for a given codename and architecture,
# using the pool directory structure
function getComponents() {
  # Shorthand variables for the repo paths etc.
  local ROOT="${REPO_DIR}"

  # Get the codename
  local CODENAME="${1}"

  # Get the architecture
  local ARCHITECTURE="${2}"

  # If ARCHITECTURE is an array, then loop through it
  # and get the components for every architecture
  declare -a COMPONENTS
  if [ -n "${ARCHITECTURE##* *}" ]; then
    # ARCHITECTURE is not an array
    # Get the components by getting the directory names in the codename/architecture directory
    COMPONENTS=$(find "${ROOT}/pool/${CODENAME}/${ARCHITECTURE}" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")
  else
    # ARCHITECTURE is an array
    # Loop through the architectures
    for ARCHITECTURE in ${ARCHITECTURE}; do
      # Get the components by getting the directory names in the codename/architecture directory
      local ARCH_COMPONENTS=$(find "${ROOT}/pool/${CODENAME}/${ARCHITECTURE}" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")

      # Append the components to the COMPONENTS array
      COMPONENTS+=("${ARCH_COMPONENTS}")
    done
  fi

  # # Get the components by getting the directory names in the codename/architecture directory
  # COMPONENTS=$(find "${ROOT}/pool/${CODENAME}/${ARCHITECTURE}" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")

  # Transform the components string into an array
  IFS=' ' read -ra COMPONENTS_ARRAY <<< "${COMPONENTS}"

  # Print the components array
  echo "${COMPONENTS_ARRAY[@]}"
}

# Function for generating a codename specific Changelog file
function createChangelog() {
  # Shorthand variables for the repo paths etc.
  local ROOT="${REPO_DIR}"

  # Get all the codenames
  local CODENAMES=$(getCodenames)

  # Loop through the codenames
  for CODENAME in ${CODENAMES}; do
    # Create the Changelog file for the codename
    echo "Creating changelog file for ${CODENAME} ..."
    cat << EOF > "${ROOT}/dists/${CODENAME}/Changelog"
$(date -R) - ${REPO_KEY_EMAIL}
EOF
  echo "Successfully created changelog file for ${CODENAME}"
  done
}

# Print out information about the current user,
# which is useful for troubleshooting.
printUser

# Ensure that the keys are always handled first.
createKeys

# Update the packages before creating the repository,
# as the packages also define the codename and components.
updatePackages

# Ensure that the core repository structure exists.
# createRepo

# Update the changelog file.
createChangelog

# Create or update the Release files last,
# as they will generate the contents of the
# repository, as well as sign them with the
# PGP keys.
createRelease

# At this point we should be all done.
echo "Done!"
exit 0
