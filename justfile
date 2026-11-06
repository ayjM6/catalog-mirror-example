# Build recipes for this repo. Run `just --list` to see them.
#
# The scripts in scripts/ only run through these recipes: they check that
# JUST_RECIPE is set.

set positional-arguments

export JUST_RECIPE := "1"

# Delete target/, regenerate everything, then render the overlays into target/.
build: clean regen render

# Delete everything under target/.
clean:
    rm -rf target

# Sort mirror sets, rebuild generated files, then format.
regen: sort catalogs kustomizations versions overlays fmt

# Build every overlay into target/<version>/<registry>/, one <kind>-<name>.yaml per object.
render:
    scripts/render-overlays.sh

# Sort mirror-set entries by source (default: every mirror set in mirrors/).
sort *files:
    scripts/sort-mirror-sets.sh "$@"

# Create missing catalog and rename components; rebuild the rename list.
catalogs:
    scripts/gen-catalog-components.sh

# Rebuild every kustomization.yaml under mirrors/.
kustomizations:
    scripts/gen-mirror-kustomizations.sh

# Rebuild components/ocp-version/<version>/ from the versions in mirrors/.
versions:
    scripts/gen-version-components.sh

# Rebuild overlays/ from the registries and versions in mirrors/.
overlays:
    scripts/gen-overlays.sh

# Format YAML with yamlfmt (default: the whole repo; see .yamlfmt.yaml).
fmt *files=".":
    yamlfmt "$@"

# Rebuild generated files, format and stage them (pre-commit hook).
# Existing catalog and rename components are hand-maintained, so only new ones are staged.
generate: catalogs kustomizations versions overlays
    yamlfmt mirrors overlays components/ocp-version components/catalogs components/rename-catalogsources
    git add overlays components/ocp-version components/rename-catalogsources/kustomization.yaml ':(glob)mirrors/**/kustomization.yaml'
    git ls-files --others --exclude-standard components/catalogs components/rename-catalogsources | xargs -r git add

# Run kustomize build on every overlay and mirror directory.
check:
    #!/usr/bin/env bash
    failed=0
    for dir in overlays/*/* mirrors/*/ mirrors/*/*/ mirrors/*/*/cluster-resources/; do
      if ! kustomize build "$dir" > /dev/null; then
        echo "FAIL $dir"
        failed=1
      fi
    done
    exit $failed

# Install or update the git hooks defined in lefthook.yml.
hooks:
    lefthook install
