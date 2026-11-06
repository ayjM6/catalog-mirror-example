#!/usr/bin/env bash
# Rebuilds components/ocp-version/<version>/ for every OpenShift version found
# in mirrors/, from scripts/templates/version-component.yaml.
#
# Only the version directories (4.21/, 4.22/, ...) are replaced. deselect-all/,
# prune-deselected/ and README.md are left alone.
source "$(dirname "$0")/lib.sh"

require envsubst

# Delete the existing version directories.
for dir in components/ocp-version/*/; do
  name=$(basename "$dir")
  if [[ "$name" =~ ^[0-9]+\.[0-9]+$ ]]; then
    rm -rf "$dir"
  fi
done

# Create one for each version in mirrors/.
for VERSION in $(versions_in mirrors/*); do
  VERSION_SUFFIX="v${VERSION/./-}"   # 4.22 -> v4-22
  export VERSION VERSION_SUFFIX
  render version-component.yaml "components/ocp-version/$VERSION/kustomization.yaml"
  echo "components/ocp-version/$VERSION"
done
