# Shared helpers for the scripts in this directory. Each script sources this
# file; don't run it on its own.
set -euo pipefail

# The scripts are only meant to run through just (see justfile), which sets
# JUST_RECIPE and runs them from the repo root.
if [[ -z "${JUST_RECIPE:-}" ]]; then
  echo "Error: run this through just, e.g. 'just build' (see justfile)." >&2
  exit 1
fi

# require <tool>: stop with an error if <tool> isn't on PATH.
require() {
  if ! command -v "$1" >/dev/null; then
    echo "Error: $1 not found on PATH." >&2
    exit 1
  fi
}

# warn <message>: print a warning to stderr and carry on.
warn() {
  echo "Warning: $1" >&2
}

# render <template> <output>: copy scripts/templates/<template> to <output>,
# replacing ${VERSION}, ${VERSION_SUFFIX}, ${REGISTRY}, ${CATALOG} and
# ${INDEX_NAME} with the values of those variables. Nothing else in the
# template is touched.
render() {
  local template="scripts/templates/$1"
  local output="$2"
  mkdir -p "$(dirname "$output")"
  envsubst '${VERSION} ${VERSION_SUFFIX} ${REGISTRY} ${CATALOG} ${INDEX_NAME}' < "$template" > "$output"
}

# versions_in <dir>...: print every OpenShift version found under <dir>, one
# per line, oldest first. A catalog file such as
# cs-redhat-operator-index-v4-22.yaml means version 4.22.
versions_in() {
  # 1. list the versioned catalog files
  # 2. turn each file name into a version: ...-v4-22.yaml -> 4.22
  # 3. sort by major, then minor version, and drop duplicates
  find "$@" -path '*/cluster-resources/*' -name '*-v[0-9]*-[0-9]*.yaml' \
    | sed -nE 's/.*-v([0-9]+)-([0-9]+)\.yaml$/\1.\2/p' \
    | sort -t. -k1,1n -k2,2n -u
}
