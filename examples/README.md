# Example oc-mirror runs

These are the real oc-mirror v2 runs behind `mirrors/`. Each directory is one
run, which mirrors one catalog:

```
examples/<catalog>/
  imagesetconfig.yaml     the ImageSetConfiguration used (one small operator)
  cluster-resources/      oc-mirror's working-dir/cluster-resources, unchanged
```

| Run | Catalog | OpenShift versions | Operator |
|---|---|---|---|
| `redhat` | `registry.redhat.io/redhat/redhat-operator-index` | 4.21, 4.22 | `cincinnati-operator` |
| `community` | `registry.redhat.io/redhat/community-operator-index` | 4.22 | `cert-utils-operator` |
| `nmstate` | `redhat-operator-index`, published as `custom/redhat-operator-index-nmstate` | 4.22 | `kubernetes-nmstate-operator` |

The files in `mirrors/<registry>/<catalog>/cluster-resources/` are these files,
with the registry prefix `localhost:5000/ocp4` replaced by each example
registry's:

| Registry | Prefix | Catalogs |
|---|---|---|
| `dc1-quay` | `quay.dc1.example.com/ocp4` | redhat, community, nmstate |
| `edge-harbor` | `harbor.edge.example.com:8443/mirror/ocp` | redhat |

## Splitting one operator into its own catalog (`nmstate`)

The `nmstate` run takes a single operator out of the Red Hat index and publishes
it as a separate catalog, using oc-mirror's `targetCatalog`:

```yaml
- catalog: registry.redhat.io/redhat/redhat-operator-index:v4.22
  targetCatalog: custom/redhat-operator-index-nmstate
  packages:
    - name: kubernetes-nmstate-operator
```

oc-mirror pushes the filtered catalog to
`<registry>/custom/redhat-operator-index-nmstate:v4.22`. `targetTag` is left
unset, so the `v4.22` tag is kept. It names the objects after the target:
`cs-redhat-operator-index-nmstate-v4-22` and
`cc-redhat-operator-index-nmstate-v4-22`.

In this repo it's treated like any other catalog:

- `components/catalogs/nmstate` renames its mirror set to
  `redhat-operator-index-nmstate`. It also labels its objects
  `catalogs.example.com/catalog: redhat-operator-index-nmstate` and
  `catalogs.example.com/base-catalog: redhat-operator-index`.
- `components/rename-catalogsources/nmstate` renames its CatalogSource to
  `nmstate-operators`.

Naming the target `redhat-operator-index-nmstate` keeps its origin visible, but
the name contains `redhat-operator-index`. The redhat rename matches the whole
name `cs-redhat-operator-index-v<maj>-<min>`, so it doesn't pick up the nmstate
CatalogSource. A looser pattern such as `.*redhat-operator-index.*` would, and
the two would collide as `redhat-operators`.

## How the runs were made

Each run used oc-mirror 4.22.0 (`--v2`) in mirror-to-mirror mode, against a
throwaway local registry (`crane registry serve`). Each ImageSetConfiguration
picks a single operator, so each run copied only 5–7 images:

```bash
crane registry serve --address localhost:5000 --disk ./registry-data &

oc-mirror --v2 -c examples/<catalog>/imagesetconfig.yaml \
  --workspace file://$PWD/ws-<catalog> \
  --dest-tls-verify=false \
  docker://localhost:5000/ocp4

cp -r ws-<catalog>/working-dir/cluster-resources examples/<catalog>/
```

Credentials for `registry.redhat.io` must be in
`${XDG_RUNTIME_DIR}/containers/auth.json`, or passed with `--authfile`.

## What the output shows

- Catalog objects are named `cs-<index>-v<maj>-<min>` (CatalogSource) and
  `cc-<index>-v<maj>-<min>` (ClusterCatalog), and the files have the same names.
- One run can cover several OpenShift versions. The `redhat` run wrote 4.21 and
  4.22 files side by side.
- Every run writes `idms-oc-mirror.yaml`, and the mirror set in it is always
  named `idms-operator-0`. That's why each catalog's component renames it.
- No ImageTagMirrorSet is written, because nothing was mirrored by tag.
- The files have no `status`, but have `createdAt`, `createdBy` and
  `oc-mirror_version` annotations.
