#!/usr/bin/env bash
# Creates the components a catalog in mirrors/ needs, if they don't exist yet:
#   - components/catalogs/<catalog>/                from scripts/templates/catalog-component.yaml
#   - components/rename-catalogsources/<catalog>/   from scripts/templates/rename-catalogsource-component.yaml
# Existing components are never changed: clusters depend on the names and
# labels in them.
#
# <catalog> is the catalog's directory name in mirrors/<registry>/, and is also
# the CatalogSource's stable name. The index name (e.g. redhat-operator-index)
# comes from the catalog's ClusterCatalog file names.
#
# Then rebuilds the list in components/rename-catalogsources/kustomization.yaml.
source "$(dirname "$0")/lib.sh"

require envsubst
require yq

for dir in mirrors/*/*/; do
  CATALOG=$(basename "$dir")

  if [[ -d "components/catalogs/$CATALOG" && -d "components/rename-catalogsources/$CATALOG" ]]; then
    continue
  fi

  # The first ClusterCatalog file in this catalog's own cluster-resources/,
  # e.g. cc-redhat-operator-index-v4-22.yaml -> redhat-operator-index.
  cc_file=$(find "$dir/cluster-resources" -maxdepth 1 -name 'cc-*.yaml' | sort | head -n 1)
  if [[ -z "$cc_file" ]]; then
    warn "no ClusterCatalog (cc-*.yaml) in ${dir}cluster-resources, so no components created for $CATALOG."
    continue
  fi
  INDEX_NAME=$(basename "$cc_file" | sed -E 's/^cc-//; s/-v[0-9]+-[0-9]+\.yaml$//')
  export CATALOG INDEX_NAME

  if [[ ! -d "components/catalogs/$CATALOG" ]]; then
    render catalog-component.yaml "components/catalogs/$CATALOG/kustomization.yaml"
    echo "components/catalogs/$CATALOG (created; check its base-catalog label)"
  fi

  if [[ ! -d "components/rename-catalogsources/$CATALOG" ]]; then
    render rename-catalogsource-component.yaml "components/rename-catalogsources/$CATALOG/kustomization.yaml"
    echo "components/rename-catalogsources/$CATALOG (created)"
  fi
done

# List every rename component, in name order.
list=components/rename-catalogsources/kustomization.yaml
render rename-catalogsources.yaml "$list"
for dir in components/rename-catalogsources/*/; do
  name=$(basename "$dir") yq -i '.components += [strenv(name)]' "$list"
done
