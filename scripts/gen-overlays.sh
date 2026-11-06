#!/usr/bin/env bash
# Rebuilds overlays/ from scratch, from scripts/templates/overlay.yaml.
#
# Each registry in mirrors/ gets one overlay for every OpenShift version that
# at least one of its catalogs was mirrored for.
source "$(dirname "$0")/lib.sh"

require envsubst

rm -rf overlays

for dir in mirrors/*/; do
  REGISTRY=$(basename "$dir")
  versions=$(versions_in "$dir")

  if [[ -z "$versions" ]]; then
    warn "no OpenShift versions found in $dir, so it gets no overlays."
    continue
  fi

  for VERSION in $versions; do
    export VERSION REGISTRY
    render overlay.yaml "overlays/$VERSION/$REGISTRY/kustomization.yaml"
    echo "overlays/$VERSION/$REGISTRY"
  done
done
