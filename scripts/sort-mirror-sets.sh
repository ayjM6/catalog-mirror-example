#!/usr/bin/env bash
# Sorts the entries of oc-mirror's mirror sets by their source, so re-running
# oc-mirror doesn't reorder them:
#   - imageDigestMirrors in an ImageDigestMirrorSet (idms-*.yaml)
#   - imageTagMirrors in an ImageTagMirrorSet (itms-*.yaml)
#
# Usage: sort-mirror-sets.sh [file...]
# With no files, sorts every mirror set in mirrors/*/*/cluster-resources/.
source "$(dirname "$0")/lib.sh"

require yq

# There are two different tools called yq; this needs mikefarah's.
if ! yq --version | grep -q mikefarah; then
  echo "Error: yq must be mikefarah's yq (https://github.com/mikefarah/yq)." >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  shopt -s nullglob
  set -- mirrors/*/*/cluster-resources/idms-*.yaml mirrors/*/*/cluster-resources/itms-*.yaml
fi

for file in "$@"; do
  # Each document in the file is checked on its own; only mirror sets change.
  yq -i 'with(select(.kind == "ImageDigestMirrorSet"); .spec.imageDigestMirrors |= sort_by(.source))' "$file"
  yq -i 'with(select(.kind == "ImageTagMirrorSet"); .spec.imageTagMirrors |= sort_by(.source))' "$file"
done
