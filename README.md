# oc-mirror catalogs: example GitOps layout

> **This is an example repository.**
> It shows a layout for keeping oc-mirror v2 output in Git, so mirrored operator catalogs can be rolled out to OpenShift clusters on disconnected networks with Argo CD or `oc apply -k`.
> The registries, hostnames and choice of catalogs are made up.
> The oc-mirror output is real, but each catalog is trimmed to one small operator, and one file (the `redhat-operators` ImageTagMirrorSet) is hand-written.
> See [examples/](examples/README.md) for the runs that produced it.

## Why several oc-mirror runs?

You could mirror every catalog with one big ImageSetConfiguration.
This layout assumes **one oc-mirror run per catalog** instead, because that lets you:

- re-mirror a catalog on its own schedule, without touching or re-checking the others
- give different registries (sites, networks) different sets of catalogs
- keep runs small, so a failure only affects one catalog
- build custom catalogs, such as a single operator split out of the Red Hat index with `targetCatalog`, without mixing them into the others
- review each catalog's changes on their own

## The problem that creates

oc-mirror assumes one run produces everything a cluster needs, so its output is only unique *within* that run.
Combining several runs, and serving several OpenShift versions from them, runs into this:

- **Every run names its mirror set `idms-operator-0`.**
  Two catalogs on the same registry collide.
- **Catalog names include the OpenShift version**, e.g. `cs-redhat-operator-index-v4-21`.
  They change on every upgrade, and the Subscriptions that refer to them break.
- **One run usually covers several OpenShift versions**, but a cluster needs only its own.
- **The same catalog may be mirrored to several registries.**

This repo keeps each run's output exactly as oc-mirror wrote it, and uses kustomize to combine and fix it.
The result is one overlay per OpenShift version and registry, which is what a cluster points at.

## Layout

```
mirrors/
  registry-a/                       one directory per mirror registry
    kustomization.yaml              combines the registry's catalogs
    redhat-operators/               one directory per catalog (oc-mirror run), named after its CatalogSource
      kustomization.yaml            applies the catalog's component to cluster-resources/
      cluster-resources/            oc-mirror output
    community-operators/
    redhat-operators-nmstate/
  registry-b/
    redhat-operators/

components/
  catalogs/<catalog>/               labels a catalog's objects; renames its mirror set
  rename-catalogsources/<catalog>/  gives a catalog's CatalogSource a stable name
  registries/<registry>/            labels objects with their registry
  ocp-version/<version>/            keeps one OpenShift version (see its README)
  common/                           steps every overlay runs after the version component

base/                               OperatorHub/cluster: turns off the default online catalogs

overlays/<version>/<registry>/      what a cluster deploys (generated)
  4.21/registry-a  4.22/registry-a  4.21/registry-b  4.22/registry-b

examples/                           the oc-mirror runs behind mirrors/

target/<version>/<registry>/        rendered overlays, one <kind>-<name>.yaml per object (git-ignored)

justfile                            build recipes (see Development)
scripts/                            what the recipes run
  templates/                        templates for the generated files
lefthook.yml                        pre-commit hook
.yamlfmt.yaml                       YAML formatting settings
```

`just build` generates these from what's in `mirrors/`, so don't edit them by hand (change `scripts/templates/` instead):

- every `kustomization.yaml` under `mirrors/`
- `components/ocp-version/<version>/` and `overlays/`
- the list in `components/rename-catalogsources/kustomization.yaml`

It also creates `components/catalogs/<catalog>/` and `components/rename-catalogsources/<catalog>/` for a new catalog, but only once: after that they're yours to edit (see [Stable names and labels](#stable-names-and-labels)).

**Never edit anything under `cluster-resources/`.**
To update a catalog, replace the whole directory with oc-mirror's:

```bash
rm -rf mirrors/registry-a/redhat-operators/cluster-resources
cp -r <oc-mirror-workspace>/working-dir/cluster-resources mirrors/registry-a/redhat-operators/
```

Then run `just build`.

## One OpenShift version per overlay

When one oc-mirror run covers several OpenShift versions, it writes a separate CatalogSource and ClusterCatalog for each version into the same `cluster-resources/` directory.
For example, a run for 4.21 and 4.22 produces:

```
cs-redhat-operator-index-v4-21.yaml   cc-redhat-operator-index-v4-21.yaml
cs-redhat-operator-index-v4-22.yaml   cc-redhat-operator-index-v4-22.yaml
```

Each overlay deploys a single OpenShift version, but it includes the files for every version.
It then removes or switches off the objects for the versions it isn't deploying.
CatalogSources and ClusterCatalogs are handled differently:

- **CatalogSources for other versions are deleted.**
  Each catalog should have exactly one CatalogSource on a cluster, under one stable name such as `redhat-operators`.
  The 4.22 overlay keeps `cs-…-v4-22` and drops `cs-…-v4-21`.
- **ClusterCatalogs for other versions are set `Unavailable`.**
  They stay on the cluster, but OLM doesn't serve them.
  The 4.22 overlay sets `cc-…-v4-22` `Available` and `cc-…-v4-21` `Unavailable`.
  Switching versions then only flips availability; nothing is created or deleted.

How the overlays do this is explained in [components/ocp-version/README.md](components/ocp-version/README.md).

## Stable names and labels

Clusters refer to catalogs in two ways, and each gets a name or label that doesn't change between mirror runs or OpenShift upgrades:

- **CatalogSources** are renamed, e.g. to `redhat-operators`, because Subscriptions refer to a CatalogSource by name.
- **ClusterCatalogs** keep oc-mirror's name and are labelled instead, because ClusterExtensions select catalogs by label:

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

| Catalog (and CatalogSource name) | `catalogs.example.com/catalog`  | `catalogs.example.com/base-catalog` |
|----------------------------------|---------------------------------|-------------------------------------|
| `redhat-operators`               | `redhat-operator-index`         | `redhat-operator-index`             |
| `community-operators`            | `community-operator-index`      | `community-operator-index`          |
| `redhat-operators-nmstate`       | `redhat-operator-index-nmstate` | `redhat-operator-index`             |

`base-catalog` records which index a catalog was built from.
`redhat-operators-nmstate` is one operator split out of the Red Hat index.

Every object also carries `catalogs.example.com/ocp-version`.
Every object from `mirrors/` also carries `catalogs.example.com/registry`.

The names and labels are set in `components/catalogs/<catalog>` and `components/rename-catalogsources/<catalog>`.
`just build` creates both when a catalog first appears:

- the CatalogSource is renamed to the catalog's directory name
- `catalog` and `base-catalog` are both set to the index name, taken from the catalog's ClusterCatalog files (`cc-<index>-v<maj>-<min>.yaml`)

After that, `just build` never changes them.

A catalog directory with the same name on several registries (e.g. `redhat-operators` on both `registry-a` and `registry-b`) is assumed to hold the same index.
Its components are created from whichever copy `just build` finds first.
They're kept separate from the oc-mirror output on purpose: clusters depend on them, so they should change only when someone decides to change them, never as a side effect of a mirror run.
Those components are also where to set anything else oc-mirror leaves at its default, such as catalog priority.

## How-tos

### Upgrade a cluster to a new OpenShift version

1. Upgrade the cluster.
2. Point it at the next overlay, e.g. from `overlays/4.21/registry-a` to `overlays/4.22/registry-a`.

The CatalogSource keeps its name; only its image changes.
ClusterCatalogs aren't created or deleted: the old version's becomes `Unavailable` and the new one's `Available`.
To roll back, point the cluster at the old overlay again.

### Refresh a catalog

Re-run oc-mirror for that catalog and replace its `cluster-resources/`, as shown under [Layout](#layout), then run `just build`.
Replacing the directory drops any OpenShift version the new run didn't include.
To keep serving a version, either include it in every run, or copy its `-v<maj>-<min>` files across from the old directory.

### Add an OpenShift version

For example, 4.23:

1. Mirror it, so its `-v4-23` files appear in the catalogs' `cluster-resources/`.
2. Run `just build`.
   It creates `components/ocp-version/4.23` and an `overlays/4.23/<registry>` for every registry with a 4.23 catalog.

### Add a catalog

For example, certified operators on `registry-a`:

1. Mirror it into `mirrors/registry-a/certified-operators/cluster-resources/`.
   The directory name becomes the CatalogSource's name on clusters, so choose it with care.
2. Run `just build`.
   It creates `components/catalogs/certified-operators` and `components/rename-catalogsources/certified-operators`, and adds the catalog to the registry and its overlays.
3. Check the two new components.
   If the catalog was split out of another index, set `base-catalog` (see `components/catalogs/redhat-operators-nmstate`).

### Add a registry

1. Create `mirrors/<registry>/` with a directory per catalog, as above.
2. Copy `components/registries/registry-a` to `components/registries/<registry>`, and change the label.
   If you skip this, `just build` warns and leaves the registry label off.
3. Run `just build` to create its kustomizations and `overlays/<version>/<registry>/`.

## Things to check on a real cluster

- **Default ClusterCatalogs.**
  OpenShift creates its own `openshift-*` ClusterCatalogs pointing at `registry.redhat.io`.
  Check whether `disableAllDefaultSources` turns those off too.
  If not, they'll fail to pull on a disconnected network, and you may want to disable them separately.
- **Overlapping catalogs.**
  A full Red Hat index also contains nmstate, so a ClusterExtension that selects `base-catalog: redhat-operator-index` would find the operator twice.
  Select by `catalog` to pin one, or set catalog priorities.
- **Mirror sets in every version.**
  Mirror sets have no version in their name, so each overlay includes every catalog's mirror set, even for a version that catalog wasn't mirrored for.
  That's harmless.
- **One mirror set per run.**
  The rename assumes each run writes at most one IDMS (`idms-operator-0`) and one ITMS.
  If a run writes more than one of either, that catalog won't build until they're renamed separately.
- **Noisy diffs.**
  oc-mirror stamps a `createdAt` time on every file, so every run changes every file, even when nothing else did.
  Entry order is handled by sorting (see [Why mirror sets are sorted](#why-mirror-sets-are-sorted)), but `createdAt` isn't.

## Development

### Prerequisites

You need these on your `PATH`:

- [just](https://github.com/casey/just): runs the recipes below
- [kustomize](https://github.com/kubernetes-sigs/kustomize) v5: builds the overlays
- [yq](https://github.com/mikefarah/yq) v4, mikefarah's (not the Python one): sorts the mirror sets
- [yamlfmt](https://github.com/google/yamlfmt): formats the YAML
- `envsubst`, from gettext: fills in the templates for generated files
- [lefthook](https://github.com/evilmartians/lefthook): runs the pre-commit hook

The recipes stop with an error if one of them is missing.

Run `just hooks` once after cloning to install the pre-commit hook.

### Recipes

Run `just --list` to see these from the command line.

| Recipe                | What it does                                                                                                                                    |
|-----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| `just` / `just build` | Runs `clean`, `regen`, then `render`                                                                                                            |
| `just clean`          | Deletes everything under `target/`                                                                                                              |
| `just regen`          | Runs `sort`, `catalogs`, `kustomizations`, `versions`, `overlays` and `fmt`, in that order                                                      |
| `just render`         | Builds every overlay into `target/<version>/<registry>/`, one `<kind>-<name>.yaml` file per object (e.g. `catalogsource-redhat-operators.yaml`) |
| `just sort [files]`   | Sorts mirror-set entries by `source` (default: every mirror set in `mirrors/`)                                                                  |
| `just catalogs`       | Creates missing catalog and rename components for new catalogs, and rebuilds the rename list                                                    |
| `just kustomizations` | Rebuilds every `kustomization.yaml` under `mirrors/`                                                                                            |
| `just versions`       | Rebuilds `components/ocp-version/<version>/` for each OpenShift version found in `mirrors/`                                                     |
| `just overlays`       | Rebuilds `overlays/`: one per registry, for each version any of its catalogs has                                                                |
| `just fmt [files]`    | Formats YAML with yamlfmt (default: everything except `examples/`)                                                                              |
| `just generate`       | Runs `catalogs`, `kustomizations`, `versions` and `overlays`, formats the result and stages it (used by the hook)                               |
| `just check`          | Runs `kustomize build` on every overlay and mirror directory                                                                                    |
| `just hooks`          | Installs or updates the git hooks from `lefthook.yml`                                                                                           |

The scripts in `scripts/` only run through just.

### Pre-commit hook

The hook does what `just regen` does, for the files you commit:

1. Sorts staged mirror sets.
2. Regenerates the generated files (and creates components for new catalogs) when `mirrors/`, `scripts/` or a generated file changes.
   Warnings, such as a missing registry component, are shown but don't stop the commit.
3. Formats staged YAML.

### Why mirror sets are sorted

oc-mirror doesn't write the entries of its mirror sets in a stable order: the `imageDigestMirrors` of an ImageDigestMirrorSet, and the `imageTagMirrors` of an ImageTagMirrorSet, can come out in a different order on every run.
Re-mirroring a catalog that hasn't changed then produces a diff that reorders every entry, and a real change, such as one new source, is hard to spot among them.

`just sort` sorts those entries by `source`, and `just fmt` then gives every file the same layout.
A re-run's diff only shows what really changed.
These are the only changes made to oc-mirror's output in `mirrors/`; `examples/` keeps it exactly as written.
