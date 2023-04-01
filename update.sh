#!/usr/bin/env bash

set -eo pipefail

# set -x

# Fix GPG issues when running without a TTY/non-interactively
rm -fr ~/.gnupg
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg
# export GPG_TTY=$(tty)
touch ~/.gnupg/gpg.conf
echo "use-agent" >> ~/.gnupg/gpg.conf
echo "pinentry-mode loopback" >> ~/.gnupg/gpg.conf
touch ~/.gnupg/gpg-agent.conf
echo "allow-loopback-pinentry" >> ~/.gnupg/gpg-agent.conf

# Function for printing out information about the current user
function printUser() {
  # echo
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
    if [[ -n "${REPO_KEY_PASSPHRASE}" ]]; then
      gpg --quiet --batch --yes --passphrase "${REPO_KEY_PASSPHRASE}" --import "${REPO_KEYS_DIR}/private.key"
    else
      gpg --quiet --batch --yes --import "${REPO_KEYS_DIR}/private.key"
    fi

    # gpg --list-packets --verbose "${REPO_KEYS_DIR}/private.key"

    ## FIXME: Is the format of the filename correct? Is it even a GPG key, or is it actually a PGP key?!
    # Copy the public key to the root of the repository
    echo "Copying public key to repository root ..."
    cp "${REPO_KEYS_DIR}/public.key" "${REPO_DIR}/gpg-pubkey.asc"

    # TODO: Convert the repo root public key from PGP to GPG?
    # echo "Converting public key to GPG format ..."

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
    if [[ -n "${REPO_KEY_PASSPHRASE}" ]]; then
      gpg --quiet --batch --yes --passphrase "${REPO_KEY_PASSPHRASE}" --import "${REPO_KEYS_DIR}/private.key"
    else
      gpg --quiet --batch --yes --import "${REPO_KEYS_DIR}/private.key"
    fi

    # gpg --list-packets --verbose "${REPO_KEYS_DIR}/private.key"

    ## FIXME: Is the format of the filename correct? Is it even a GPG key, or is it actually a PGP key?!
    # Copy the public key to the root of the repository
    echo "Copying public key to repository root ..."
    cp "${REPO_KEYS_DIR}/public.key" "${REPO_DIR}/gpg-pubkey.asc"

    # TODO: Convert the repo root public key from PGP to GPG?
    # echo "Converting public key to GPG format ..."

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
  if [[ -n "${REPO_KEY_PASSPHRASE}" ]]; then
    gpg --quiet --batch --yes --gen-key <<EOF
%echo Generating keys ...
Key-Type: ${REPO_KEY_TYPE}
Key-Length: ${REPO_KEY_LENGTH}
Name-Real: ${REPO_KEY_NAME}
Name-Email: ${REPO_KEY_EMAIL}
Expire-Date: ${REPO_KEY_EXPIRE}
Name-Comment: ${REPO_KEY_COMMENT}
Passphrase: ${REPO_KEY_PASSPHRASE}
%commit
%echo Successfully generated keys
EOF
  else
    gpg --quiet --batch --yes --gen-key <<EOF
%echo Generating keys ...
Key-Type: ${REPO_KEY_TYPE}
Key-Length: ${REPO_KEY_LENGTH}
Name-Real: ${REPO_KEY_NAME}
Name-Email: ${REPO_KEY_EMAIL}
Name-Comment: ${REPO_KEY_COMMENT}
Expire-Date: ${REPO_KEY_EXPIRE}
%no-ask-passphrase
%no-protection
%commit
%echo Successfully generated keys
EOF
  fi

  # Export the public key to the keys directory
  echo "Exporting public key ..."
  gpg --quiet --armor --export "${REPO_KEY_EMAIL}" > "${REPO_KEYS_DIR}/public.key"

  # Export the private key to the keys directory
  echo "Exporting private key ..."
  ## FIXME: This seems to export the private key without a passphrase, which is not ideal, and would
  ##        defeat the whole purpose of having a passphrase, as then we can freely import it without the passphrase too..
  if [[ -n "${REPO_KEY_PASSPHRASE}" ]]; then
    gpg --quiet --batch --yes --armor --passphrase "${REPO_KEY_PASSPHRASE}" --export-secret-keys "${REPO_KEY_EMAIL}" > "${REPO_KEYS_DIR}/private.key"
  else
    gpg --quiet --batch --yes --armor --export-secret-keys "${REPO_KEY_EMAIL}" > "${REPO_KEYS_DIR}/private.key"
  fi

  ## FIXME: Is the format of the filename correct? Is it even a GPG key, or is it actually a PGP key?!
  # Copy the public key to the root of the repository
  echo "Copying public key to repository root ..."
  cp "${REPO_KEYS_DIR}/public.key" "${REPO_DIR}/gpg-pubkey.asc"

  # TODO: Convert the repo root public key from PGP to GPG?
  # echo "Converting public key to GPG format ..."

  echo "Successfully generated signing keys"
}

# Function for updating the packages in the apt repository
function updatePackages() {
  # Shorthand variables for the repo paths etc.
  ROOT="${REPO_DIR}"
  # CODENAME="${REPO_CODENAME}"
  CODENAME="${REPO_DEFAULT_DISTRIBUTION}"
  # COMPONENTS="${REPO_COMPONENTS}"
  # ARCHITECTURES="${REPO_ARCHITECTURES}"

  echo "Updating packages ..."

  # Always ensure that the root, codename, dists and pool directories exist
  mkdir -p "${ROOT}" "${ROOT}/dists/${CODENAME}" "${ROOT}/pool"

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
    # DEB_COMPONENT=$(echo "${DEB_INFO}" | grep Section | awk '{print $2}')
    DEB_COMPONENT="${REPO_DEFAULT_COMPONENT}"

    # Get the package codename
    # DEB_CODENAME=$(echo "${DEB_INFO}" | grep Maintainer | awk '{print $2}' | cut -d' ' -f2)
    DEB_CODENAME="${CODENAME}"

    # Get the package name
    DEB_NAME=$(echo "${DEB_INFO}" | grep Package | awk '{print $2}')

    # Get the package version
    DEB_VERSION=$(echo "${DEB_INFO}" | grep Version | awk '{print $2}')

    # Get the package filename
    DEB_FILENAME="${DEB_NAME}_${DEB_VERSION}_${DEB_ARCHITECTURE}.deb"

    # Get the first letter of the package name
    DEB_NAME_FIRST_LETTER=$(echo "${DEB_NAME}" | cut -c1)

    # Get the package destination directory
    # DEB_DESTINATION="${ROOT}/pool/${DEB_CODENAME}/${DEB_COMPONENT}/${DEB_ARCHITECTURE}"
    DEB_DESTINATION="${ROOT}/pool/${DEB_COMPONENT}/${DEB_NAME_FIRST_LETTER}/${DEB_NAME}"

    # Create the package destination directory if it doesn't exist
    mkdir -p "${DEB_DESTINATION}"

    # Create the appropriate repo component directories if they don't exist
    # mkdir -p "${ROOT}/dists/${DEB_CODENAME}/${DEB_COMPONENT}/${DEB_ARCHITECTURE}"
    mkdir -p "${ROOT}/dists/${DEB_CODENAME}/${DEB_COMPONENT}/binary-${DEB_ARCHITECTURE}"

    # Copy the package to the destination directory
    cp -f "${DEB}" "${DEB_DESTINATION}/${DEB_FILENAME}"

    ## TODO: Ideally we wouldn't do this every time, right?
    ##       Couldn't we instead loop through all the pool directories,
    ##       then the codename and component directories, then run this once for those?

    # Get the current pool based on the codename, component and architecture
    # POOL="${ROOT}/pool/${DEB_CODENAME}/${DEB_COMPONENT}"
    POOL="${ROOT}/pool"
    # POOL="${ROOT}/pool/${DEB_CODENAME}"

    # Get the current Packages file based on the codename, component and architecture
    PACKAGES_FILE="${ROOT}/dists/${DEB_CODENAME}/${DEB_COMPONENT}/binary-${DEB_ARCHITECTURE}/Packages"

    # Update the Changelog file
    cat << EOF > "${ROOT}/dists/${DEB_CODENAME}/ChangeLog"
$(date -R) - ${REPO_KEY_EMAIL}
EOF

    # Update the Packages and Packages.gz files
    dpkg-scanpackages --arch "${ARCHITECTURE}" "${POOL}" > "${PACKAGES_FILE}" 2> /dev/null
    # Edit in the "Filename" field in the Packages file so that the
    # absolute path is instead relative, starting at "pool/"
    # sed -i "s|Filename: ${POOL}/|Filename: pool/|g" "${PACKAGES_FILE}" # NOTE: This doesn't work with VirtioFS currently
    sed "s|Filename: ${POOL}/|Filename: pool/|g" "${PACKAGES_FILE}" > "${PACKAGES_FILE}.tmp"
    cat "${PACKAGES_FILE}.tmp" > "${PACKAGES_FILE}"
    rm "${PACKAGES_FILE}.tmp"
    cat "${PACKAGES_FILE}" | gzip -9 > "${PACKAGES_FILE}.gz"
  done

  echo "Successfully updated packages"
}

# Function for generating Release file hashes as a string
function generateHashString() {
  # Shorthand variables for the repo paths etc.
  local ROOT="${REPO_DIR}"

  local HASH_NAME="${1}"
  local HASH_CMD="${2}"
  local CODENAME="${3}"
  echo "${HASH_NAME}:"
  for f in $(find "${ROOT}/dists/${CODENAME}" -type f); do
    if [[ "$f" == *"Release"* ]] || [[ "$f" == *"ChangeLog"* ]]; then
      continue
    fi
    # echo " $(${HASH_CMD} ${f}  | cut -d" " -f1) $(wc -c $f | cut -d" " -f1) $(echo $f | cut -c$((${#ROOT}+${#CODENAME}+1))-)"
    echo " $(${HASH_CMD} ${f}  | cut -d" " -f1) $(wc -c $f | cut -d" " -f1) $(echo $f | cut -c$((${#ROOT}+${#CODENAME}))-)"
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

  # Transform COMPONENTS from an array to a space separated string
  # COMPONENTS=$(echo "${COMPONENTS[@]}" | sed 's/ /,/g')

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
  echo "CODENAMES: ${CODENAMES}"

  # Loop through the codenames, architectures and components
  # and store the results in the $CODENAMES, $ARCHITECTURES and $COMPONENTS variables

  # Loop through the codenames
  for CODENAME in ${CODENAMES}; do
    # Get the components
    local COMPONENTS=$(getComponents "${CODENAME}")
    echo "COMPONENTS: ${COMPONENTS}"

    # Get the architectures
    local ARCHITECTURES=$(getArchitectures "${CODENAME}" ${COMPONENTS})
    echo "ARCHITECTURES: ${ARCHITECTURES}"

    # Create the Release file
    echo "Creating Release file for ${CODENAME} ..."
    rm -f "${ROOT}/dists/${CODENAME}/Release"
    generateReleaseString "${CODENAME}" "${ARCHITECTURES}" "${COMPONENTS}" > "${ROOT}/dists/${CODENAME}/Release"

    # Sign the Release file
    echo "Creating signed Release.gpg file ..."
    rm -f "${ROOT}/dists/${CODENAME}/Release.gpg"
    ## TODO: Do these need the --passphrase argument?
    gpg --quiet --batch --default-key "${REPO_KEY_EMAIL}" --output "${ROOT}/dists/${CODENAME}/Release.gpg" --detach-sig "${ROOT}/dists/${CODENAME}/Release"

    # Create the signed InRelease file
    echo "Creating signed InRelease file ..."
    rm -f "${ROOT}/dists/${CODENAME}/InRelease"
    ## TODO: Do these need the --passphrase argument?
    gpg --quiet --default-key "${REPO_KEY_EMAIL}" --output "${ROOT}/dists/${CODENAME}/InRelease" --clearsign "${ROOT}/dists/${CODENAME}/Release"

    echo "Successfully created signed release files for ${CODENAME}"
  done
}

# Function for getting an array of all the codenames,
# based on the codename directories in the pool directory
function getCodenames() {
  # Shorthand variables for the repo paths etc.
  local ROOT="${REPO_DIR}"

  # Get the codenames by getting the directory names in the pool directory
  # local CODENAMES=$(find "${ROOT}/pool" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")
  local CODENAMES=$(find "${ROOT}/dists" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")

  # Transform the codenames string into an array
  IFS=' ' read -ra CODENAMES_ARRAY <<< "${CODENAMES}"

  # Print the codenames array
  echo "${CODENAMES_ARRAY[@]}"
}

# Function for getting the components
# for a given codename, using the pool
# directory structure
function getComponents() {
  # Shorthand variables for the repo paths etc.
  local ROOT="${REPO_DIR}"

  # Get the codename
  local CODENAME="${1}"

  # Get the components by getting the directory names in the codename directory
  # local COMPONENTS=$(find "${ROOT}/pool/${CODENAME}" -mindepth 1 -maxdepth 1 -type d -printf "%f ")
  local COMPONENTS=$(find "${ROOT}/pool" -mindepth 1 -maxdepth 1 -type d -printf "%f ")

  # Transform the components string into an array
  IFS=' ' read -ra COMPONENTS_ARRAY <<< "${COMPONENTS}"

  # Print the components array
  echo "${COMPONENTS_ARRAY[@]}"
}

# Function for getting the architectures
# for a given codename and components,
# using the pool directory structure
function getArchitectures() {
  # Shorthand variables for the repo paths etc.
  local ROOT="${REPO_DIR}"

  # Get the codename
  local CODENAME="${1}"

  # Get the component
  local COMPONENTS="${2}"

  ## FIXME: This needs to be fixed, so it recursively gets
  ##        all architectures from the .deb files in the pool!

  # If COMPONENTS is an array, then loop through it
  # and get the architectures for every architecture
  declare -a ARCHITECTURES
  # if [ -n "${COMPONENTS##* *}" ]; then # COMPONENTS is not an array
  #   # Get the architectures by getting the directory names in the codename/components directory
  #   ARCHITECTURES=$(find "${ROOT}/pool/${CODENAME}/${COMPONENTS}" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")
  # else # COMPONENT is an array
  #   # Loop through the architectures
  #   for COMPONENT in ${COMPONENTS}; do
  #     # Get the architectures by getting the directory names in the codename/components directory
  #     local ARCH_COMPONENTS=$(find "${ROOT}/pool/${CODENAME}/${COMPONENT}" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")

  #     # Append the architectures to the ARCHITECTURES array
  #     ARCHITECTURES+=("${ARCH_COMPONENTS}")
  #   done
  # fi
  ARCHITECTURES+=("arm64")

  # Transform the architectures string into an array
  IFS=' ' read -ra ARCHITECTURES_ARRAY <<< "${ARCHITECTURES}"

  # Print the architectures array
  echo "${ARCHITECTURES_ARRAY[@]}"
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
    cat << EOF > "${ROOT}/dists/${CODENAME}/ChangeLog"
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
