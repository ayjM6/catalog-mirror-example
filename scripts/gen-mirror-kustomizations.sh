#!/usr/bin/env bash
# Rebuilds every kustomization.yaml under mirrors/ with
# `kustomize create --autodetect --recursive`, then adds the components:
#   - mirrors/<registry>/<catalog>/cluster-resources/   lists the oc-mirror files
#   - mirrors/<registry>/<catalog>/                     cluster-resources + components/catalogs/<catalog>
#   - mirrors/<registry>/                               the catalog dirs + components/registries/<registry>
#
# Deepest first, so each level finds the kustomization below it.
#
# components/registries/<registry> isn't created automatically. If it's
# missing, its reference is left commented out and a warning is printed.
source "$(dirname "$0")/lib.sh"

require kustomize
require yq

# create_kustomization <dir>: replace <dir>/kustomization.yaml with one listing
# the files and subdirectories in <dir>.
create_kustomization() {
  rm -f "$1/kustomization.yaml"
  (cd "$1" && kustomize create --autodetect --recursive)
  echo "$1/kustomization.yaml"
}

for dir in mirrors/*/*/cluster-resources; do
  create_kustomization "$dir"
done

for dir in mirrors/*/*; do
  [[ -d "$dir" ]] || continue
  catalog=$(basename "$dir")
  create_kustomization "$dir"
  component="../../../components/catalogs/$catalog" yq -i '.components = [strenv(component)]' "$dir/kustomization.yaml"
done

for dir in mirrors/*; do
  [[ -d "$dir" ]] || continue
  registry=$(basename "$dir")
  create_kustomization "$dir"
  component="../../components/registries/$registry" yq -i '.components = [strenv(component)]' "$dir/kustomization.yaml"

  if [[ ! -d "components/registries/$registry" ]]; then
    sed -i -e 's|^components:$|# components:|' -e "s|^\( *\)\(- \.\./\.\./components/registries/$registry\)$|\1# \2|" "$dir/kustomization.yaml"
    warn "no components/registries/$registry, so $dir/kustomization.yaml has it commented out. Add the component by hand (see README, Add a registry)."
  fi
done
