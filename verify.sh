#!/usr/bin/env bash
#
# Bash script to verify file and directory structure against a predefined template.
#

# Enable error handling.
# set -eo pipefail

# Enable script debugging.
# set -x

# Define colors.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No color.

# Define a template file and folder structure
# for a reusable, custom apt repository.
declare -A template=(
  ## FIXME: This is wrong right now!

  # Repository, release and package information.
  ["dists"]=""
    ["dists/*/arm64"]=""
    ["dists/*/arm64/Packages"]=""
    ["dists/*/arm64/Packages.gz"]=""
    # ["dists/devel"]=""
    #   ["dists/devel/arm64"]=""
    #     ["dists/devel/arm64/Packages"]=""
    #     ["dists/devel/arm64/Packages.gz"]=""
    # ["dists/kernel"]=""
    #   ["dists/kernel/arm64"]=""
    #     ["dists/kernel/arm64/Packages"]=""
    #     ["dists/kernel/arm64/Packages.gz"]=""
    ["dists/Release"]=""
    ["dists/Release.gpg"]=""
    ["dists/InRelease"]=""
    ["dists/Changelog"]=""

  # Package binaries.
  ["pool"]=""
  # ["pool/*.deb"]=""

  # Public key.
  ["gpg-pubkey.asc"]=""
)

# A simple logging function.
function log {
  local level="${1}"
  local msg="${2}"
  case "$level" in
    "info")
      echo -e "${GREEN}[INFO]${NC} ${msg}"
      ;;
    "warn")
      echo -e "${YELLOW}[WARN]${NC} ${msg}"
      ;;
    "error")
      echo -e "${RED}[ERROR]${NC} ${msg}"
      ;;
  esac
}

# Function for verifying the template structure.
function verify {
  local input_path="${1}"
  local strict="${2}"
  local path
  local found
  local missing_paths=""
  local extra_paths=""

  # set -x
  for path in "${!template[@]}"; do
    found=false

    while IFS= read -r -d '' file; do
      local relative_file_path="${file#${input_path}/}"
      if [[ ${relative_file_path} == ${path} ]]; then
        found=true
        break
      fi
    done < <(find "${input_path}" \( -path "${input_path}/${path}" -type f -o -path "${input_path}/${path}" -type d \) -printf '%P\0')

    if ! ${found}; then
      missing_paths+="${path}"$'\n'
    fi
  done
  # set +x

  if ${strict}; then
    while IFS= read -r -d '' path; do
      found=false
      for template_path in "${!template[@]}"; do
        if [[ ${path} == ${template_path} ]]; then
          found=true
          break
        fi
      done

      if ! $found; then
        extra_paths+="${path}"$'\n'
      fi
    done < <(find "${input_path}" -mindepth 1 -printf '%P\0')
  fi

  echo -n -e "${missing_paths}|${extra_paths}"
}

# Function for rendering a tree structure.
function render_tree {
  local root_name="${1}"
  local paths="${2}"
  declare -A tree

  while read -r path; do
    parent_node="tree"
    IFS="/" read -ra path_parts <<< "${path}"
    skip=false

    for part in "${path_parts[@]}"; do
      if [ "${skip}" = "true" ]; then
        break
      fi

      if [[ "${part}" == *\** ]]; then
        skip=true
      else
        if [[ -z "${tree[${parent_node}_${part}]+_}" ]]; then
          tree[${parent_node}_${part}]=""
        fi
        parent_node="${parent_node}_${part}"
      fi
    done
  done <<< "${paths}"

  # A local function for traversing the tree structure.
  function traverse_tree {
    local node_prefix="${1}"
    local prefix="${2-}"
    local last_child="${3-false}"

    local child_count=0
    local child
    for child in "${!tree[@]}"; do
      if [[ "${child}" == "${node_prefix}_"* ]]; then
        ((child_count++))
      fi
    done

    local node_name="${node_prefix##*_}"
    node_name="${node_name//\*/\*}"

    if [[ ! "${node_prefix}" == "tree_*" ]]; then
      if [ "${last_child}" = "true" ]; then
        if [[ "${node_prefix}" == *"/*" && "${node_prefix}" != */*/* ]]; then
          # This is a wildcard entry, so check if there are any matching files.
          local path="$(echo ${node_prefix} | sed -e 's/\*/\.\*/g')"
          if find "${path}" -print -quit | grep -q .; then
            # At least one matching file was found, so display the node name.
            echo -e "${prefix}└── ${node_name}"
          else
            # No matching files were found, so display the node prefix.
            echo -e "${prefix}└── ${node_prefix}"
          fi
        else
          # This is not a wildcard entry, so display the node name.
          echo -e "${prefix}└── ${node_name}"
        fi
        prefix+="    "
      else
        if [[ "${node_prefix}" == *"/*" && "${node_prefix}" != */*/* ]]; then
          # This is a wildcard entry, so check if there are any matching files.
          local path="$(echo ${node_prefix} | sed -e 's/\*/\.\*/g')"
          if find "${path}" -print -quit | grep -q .; then
            # At least one matching file was found, so display the node name.
            echo -e "${prefix}├── ${node_name}"
          else
            # No matching files were found, so display the node prefix.
            echo -e "${prefix}├── ${node_prefix}"
          fi
        else
          # This is not a wildcard entry, so display the node name.
          echo -e "${prefix}├── ${node_name}"
        fi
        prefix+="│   "
      fi
    fi

    local count=1
    for child in "${!tree[@]}"; do
      if [[ "${child}" == "${node_prefix}_"* ]]; then
        if [ ${count} -eq ${child_count} ]; then
          traverse_tree "${child}" "${prefix}" "true"
        else
          traverse_tree "${child}" "${prefix}"
        fi
        ((count++))
      fi
    done
  }

  # Traverse and print the tree structure.
  echo "${root_name}"
  for root in "${!tree[@]}"; do
    if [[ "${root}" == "tree_"* ]]; then
      root_name="${root#*_}"
      if [[ ! "${root_name}" =~ ^\* ]]; then
        traverse_tree "${root}" ""
      fi
    fi
  done
}

# Function for printing input arguments.
function print_args {
  echo
  echo -e "Running with options:"
  echo -e "> Input Path: ${YELLOW}${1}${NC}"
  echo -e "> Strict Mode: ${YELLOW}${2}${NC}"
  echo
}

# Function for printing usage information.
function usage {
  echo
  log "error" "Missing or invalid arguments!"
  echo
  echo -e "Usage: ${GREEN}${0} [-s] input_path${NC}"
  echo -e "  -s: Enable strict mode (do not allow extra files or directories, default: false)"
}

# Disable strict mode by default.
strict=false

# Parse command line arguments.
while getopts "s" opt; do
  case "${opt}" in
    s)
      strict=true
      shift
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

# Print usage information if no arguments are provided.
if [[ -z "${1}" ]]; then
  usage
  exit 1
fi

# Get input path.
input_path="${1}"

# Print input arguments.
print_args "${input_path}" "${strict}"

# Verify that the input path exists.
if [ ! -e "${input_path}" ]; then
  log "error" "Input path does not exist: ${YELLOW}${input_path}${NC}"
  exit 1
fi

# Verify the input path against the template.
IFS="|" read -r -d '' missing_paths extra_paths < <(verify "${input_path}" "${strict}" && printf '\0')

# Print error message if any missing files or directories are found.
if [[ ! -z "$missing_paths" ]]; then
  log "error" "Missing files or directories"
  echo
  # echo -e "${missing_paths}" | while read -r path; do
  #   echo -e "  ${path}"
  # done
  render_tree "$(basename "${input_path}")" "${missing_paths}"
fi

# Print error message if any extra files or directories are found.
if [[ ! -z "$extra_paths" ]]; then
  log "error" "Extra files or directories found in strict mode"
  echo
  render_tree "$(basename "${input_path}")" "${extra_paths}"
fi
