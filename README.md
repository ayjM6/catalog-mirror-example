# oc-mirror catalogs: example GitOps layout

> **This is an example repository.** It shows a layout for keeping oc-mirror v2
> output in Git, so mirrored operator catalogs can be rolled out to OpenShift
> clusters on disconnected networks with Argo CD or `oc apply -k`. The
> registries, hostnames and choice of catalogs are made up. The oc-mirror output
> is real, but each catalog is trimmed to one small operator. See
> [examples/](examples/README.md) for the runs that produced it.

## Why several oc-mirror runs?

You could mirror every catalog with one big ImageSetConfiguration. This layout
assumes **one oc-mirror run per catalog** instead, because that lets you:

- re-mirror a catalog on its own schedule, without touching or re-checking the
  others
- give different registries (sites, networks) different sets of catalogs
- keep runs small, so a failure only affects one catalog
- build custom catalogs, such as a single operator split out of the Red Hat index
  with `targetCatalog`, without mixing them into the others
- review each catalog's changes on their own

## The problem that creates

oc-mirror assumes one run produces everything a cluster needs, so its output is
only unique *within* that run. Combining several runs, and serving several
OpenShift versions from them, runs into this:

- **Every run names its mirror set `idms-operator-0`.** Two catalogs on the same
  registry collide.
- **Catalog names include the OpenShift version**, e.g.
  `cs-redhat-operator-index-v4-21`. They change on every upgrade, and the
  Subscriptions that refer to them break.
- **One run usually covers several OpenShift versions**, but a cluster needs only
  its own.
- **The same catalog may be mirrored to several registries.**

This repo keeps each run's output exactly as oc-mirror wrote it, and uses
kustomize to combine and fix it. The result is one overlay per OpenShift version
and registry, which is what a cluster points at.

## Layout

```
mirrors/
  dc1-quay/                         one directory per mirror registry
    kustomization.yaml              combines the registry's catalogs
    redhat/                         one directory per catalog (oc-mirror run)
      kustomization.yaml            applies the catalog's component to cluster-resources/
      cluster-resources/            oc-mirror output, copied as-is
    community/
    nmstate/
  edge-harbor/
    redhat/

components/
  catalogs/<catalog>/               labels a catalog's objects; renames its mirror set
  rename-catalogsources/<catalog>/  gives a catalog's CatalogSource a stable name
  registries/<registry>/            labels objects with their registry
  ocp-version/<version>/            keeps one OpenShift version (see its README)
  common/                           steps every overlay runs after the version component

base/                               OperatorHub/cluster: turns off the default online catalogs

overlays/<version>/<registry>/      what a cluster deploys
  4.21/dc1-quay  4.22/dc1-quay  4.21/edge-harbor  4.22/edge-harbor

examples/                           the oc-mirror runs behind mirrors/
```

**Never edit anything under `cluster-resources/`.** To update a catalog, replace
the whole directory with oc-mirror's:

```bash
rm -rf mirrors/dc1-quay/redhat/cluster-resources
cp -r <oc-mirror-workspace>/working-dir/cluster-resources mirrors/dc1-quay/redhat/
```

Then give it a `kustomization.yaml` that just lists the files.

## One OpenShift version per overlay

When one oc-mirror run covers several OpenShift versions, it writes a separate
CatalogSource and ClusterCatalog for each version into the same
`cluster-resources/` directory. For example, a run for 4.21 and 4.22 produces:

```
cs-redhat-operator-index-v4-21.yaml   cc-redhat-operator-index-v4-21.yaml
cs-redhat-operator-index-v4-22.yaml   cc-redhat-operator-index-v4-22.yaml
```

Each overlay deploys a single OpenShift version, but it includes the files for
every version. It then removes or switches off the objects for the versions it
isn't deploying. CatalogSources and ClusterCatalogs are handled differently:

- **CatalogSources for other versions are deleted.** Each catalog should have
  exactly one CatalogSource on a cluster, under one stable name such as
  `redhat-operators`. The 4.22 overlay keeps `cs-…-v4-22` and drops `cs-…-v4-21`.
- **ClusterCatalogs for other versions are set `Unavailable`.** They stay on the
  cluster, but OLM doesn't serve them. The 4.22 overlay sets `cc-…-v4-22`
  `Available` and `cc-…-v4-21` `Unavailable`. Switching versions then only flips
  availability; nothing is created or deleted.

How the overlays do this is explained in
[components/ocp-version/README.md](components/ocp-version/README.md).

## Stable names and labels

Clusters refer to catalogs in two ways, and each gets a name or label that
doesn't change between mirror runs or OpenShift upgrades:

- **CatalogSources** are renamed, e.g. to `redhat-operators`, because
  Subscriptions refer to a CatalogSource by name.
- **ClusterCatalogs** keep oc-mirror's name and are labelled instead, because
  ClusterExtensions select catalogs by label:

  ```yaml
  # ClusterExtension
  spec:
    source:
      sourceType: Catalog
      catalog:
        packageName: kubernetes-nmstate-operator
        selector:
          matchLabels:
            catalogs.example.com/catalog: redhat-operator-index-nmstate
  ```

| Catalog | CatalogSource name | `catalogs.example.com/catalog` | `catalogs.example.com/base-catalog` |
|---|---|---|---|
| `redhat` | `redhat-operators` | `redhat-operator-index` | `redhat-operator-index` |
| `community` | `community-operators` | `community-operator-index` | `community-operator-index` |
| `nmstate` | `nmstate-operators` | `redhat-operator-index-nmstate` | `redhat-operator-index` |

`base-catalog` records which index a catalog was built from. `nmstate` is one
operator split out of the Red Hat index.

Every object also carries `catalogs.example.com/ocp-version`. Every object from
`mirrors/` also carries `catalogs.example.com/registry`.

The names and labels are set in `components/catalogs/<catalog>` and
`components/rename-catalogsources/<catalog>`. They're kept separate from the
oc-mirror output on purpose: clusters depend on them, so they should change only
when someone decides to change them, never as a side effect of a mirror run.
Those components are also where to set anything else oc-mirror leaves at its
default, such as catalog priority.

## How-tos

### Upgrade a cluster to a new OpenShift version

1. Upgrade the cluster.
2. Point it at the next overlay, e.g. from `overlays/4.21/dc1-quay` to
   `overlays/4.22/dc1-quay`.

The CatalogSource keeps its name; only its image changes. ClusterCatalogs aren't
created or deleted: the old version's becomes `Unavailable` and the new one's
`Available`. To roll back, point the cluster at the old overlay again.

### Refresh a catalog

Re-run oc-mirror for that catalog and replace its `cluster-resources/`, as shown
under [Layout](#layout). Replacing the directory drops any OpenShift version the
new run didn't include. To keep serving a version, either include it in every
run, or copy its `-v<maj>-<min>` files across from the old directory.

### Add an OpenShift version

For example, 4.23:

1. Mirror it, so its `-v4-23` files appear in the catalogs' `cluster-resources/`.
2. Copy `components/ocp-version/4.22` to `components/ocp-version/4.23`, and
   change `4.22` to `4.23` and `v4-22` to `v4-23`.
3. Copy each `overlays/4.22/<registry>` to `overlays/4.23/<registry>`, and change
   the version component it references.

### Add a catalog

For example, certified operators on `dc1-quay`:

1. Mirror it into `mirrors/dc1-quay/certified/cluster-resources/`.
2. Copy `mirrors/dc1-quay/redhat/kustomization.yaml` to
   `mirrors/dc1-quay/certified/`, change `redhat` to `certified`, and add
   `certified` to `mirrors/dc1-quay/kustomization.yaml`.
3. Copy `components/catalogs/redhat` to `components/catalogs/certified`, and set
   its labels and mirror-set name.
4. Copy `components/rename-catalogsources/redhat` to
   `components/rename-catalogsources/certified`, and set the CatalogSource's
   oc-mirror name, new name and display name. Add `certified` to
   `components/rename-catalogsources/kustomization.yaml`.

### Add a registry

1. Create `mirrors/<registry>/` with a directory per catalog, as above, and a
   `kustomization.yaml` copied from `mirrors/dc1-quay/` listing them.
2. Copy `components/registries/dc1-quay` to `components/registries/<registry>`,
   and change the label.
3. Add `overlays/<version>/<registry>/` for each version, copied from an
   existing overlay.

## Things to check on a real cluster

- **Default ClusterCatalogs.** OpenShift creates its own `openshift-*`
  ClusterCatalogs pointing at `registry.redhat.io`. Check whether
  `disableAllDefaultSources` turns those off too. If not, they'll fail to pull
  on a disconnected network, and you may want to disable them separately.
- **Overlapping catalogs.** A full Red Hat index also contains nmstate, so a
  ClusterExtension that selects `base-catalog: redhat-operator-index` would find
  the operator twice. Select by `catalog` to pin one, or set catalog priorities.
- **Mirror sets in every version.** Mirror sets have no version in their name,
  so each overlay includes every catalog's mirror set, even for a version that
  catalog wasn't mirrored for. That's harmless.
- **One mirror set per run.** The rename assumes each run writes a single
  `idms-operator-0`. If a run writes more than one, that catalog won't build
  until they're renamed separately.
- **Noisy diffs.** oc-mirror stamps a `createdAt` time on every file, so every
  run changes every file, even when nothing else did.
