#!/usr/bin/env bash
# Builds every overlay with kustomize and writes the result to target/, one file
# per object, in the same tree as overlays/:
#   overlays/4.22/registry-a  ->  target/4.22/registry-a/<kind>-<name>.yaml
# e.g. target/4.22/registry-a/catalogsource-redhat-operators.yaml
#
# target/ is git-ignored. Run `just clean` first to clear out old files
# (`just build` does).
source "$(dirname "$0")/lib.sh"

require kustomize
require yq

for overlay in overlays/*/*; do
  out="target/${overlay#overlays/}"
  mkdir -p "$out"

  objects=$(kustomize build "$overlay")

  # yq -s writes one file per object, named by the expression plus ".yml".
  echo "$objects" | (cd "$out" && yq -N -s '(.kind | downcase) + "-" + .metadata.name')

  for file in "$out"/*.yml; do
    mv "$file" "${file%.yml}.yaml"
  done

  # Two objects with the same kind and name would end up in one file.
  object_count=$(echo "$objects" | yq -N '.kind' | wc -l)
  file_count=$(find "$out" -name '*.yaml' | wc -l)
  if [[ "$object_count" -ne "$file_count" ]]; then
    echo "Error: two objects in $overlay share a kind and name, so $out is incomplete." >&2
    exit 1
  fi
  echo "$out"
done
