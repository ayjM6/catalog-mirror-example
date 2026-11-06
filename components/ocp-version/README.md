# Selecting an OpenShift version

A single oc-mirror run can cover several OpenShift versions, so each catalog's
`cluster-resources/` contains a CatalogSource and a ClusterCatalog for every
version it was mirrored for:

```
cs-redhat-operator-index-v4-21.yaml   cc-redhat-operator-index-v4-21.yaml
cs-redhat-operator-index-v4-22.yaml   cc-redhat-operator-index-v4-22.yaml
```

Every overlay pulls all of them in, and the components in this directory then
keep only the overlay's version. The two kinds are handled differently:

- **ClusterCatalogs** have `spec.availabilityMode`, so every version is kept,
  and all but the selected one are set `Unavailable`. Switching versions just
  flips availability; nothing is created or deleted.
- **CatalogSources** have no on/off switch, and every version is renamed to the
  same stable name later on (e.g. `redhat-operators`). So the other versions'
  CatalogSources are deleted.

## How it works

Deleting "every CatalogSource except 4.22" would be a one-liner with a negative
regex, but kustomize's patch targets use Go regexes, which don't support
negative lookahead. So the selection uses a temporary label,
`catalogs.example.com/ocp-selected`, in three steps:

| Step | Component | What it does |
|---|---|---|
| 1 | `deselect-all` | Sets every ClusterCatalog `Unavailable`. Labels every CatalogSource whose name ends in `-v<maj>-<min>` with `ocp-selected: "false"`. |
| 2 | `<version>`, e.g. `4.22` | Sets the ClusterCatalogs ending in `-v4-22` to `Available`. Sets the label on the CatalogSources ending in `-v4-22` to `"true"`. Labels everything `catalogs.example.com/ocp-version: "4.22"`. |
| 3 | `prune-deselected` | Deletes every CatalogSource still labelled `"false"`, then removes the label from the rest, so it never reaches a cluster. |

CatalogSources without a version suffix are never labelled, so they're always
kept.

## Why the order is what it is

Two kustomize behaviours decide where each step lives:

1. **In a kustomization or component, included components run before its own
   patches.** So the version component can include `deselect-all` (step 1) and
   be sure it runs before the version's own patches (step 2). For the same
   reason, step 3 can't be included by the version component: it would run
   before step 2. It's in `components/common` instead, and every overlay lists
   `common` **after** the version component:

   ```yaml
   components:
     - ../../../components/ocp-version/4.22
     - ../../../components/common
   ```

2. **Patches run in order, and each one sees the result of the previous
   ones.** That's what lets step 3 select by a label that steps 1 and 2 set.

`common` then renames the one CatalogSource left per catalog
(`components/rename-catalogsources`). That rename has to come after step 3,
because before it there are several CatalogSources per catalog, and they'd all
get the same name.

## Adding a version

Copy an existing version directory and change the version in it. For 4.23,
copy `4.22/` to `4.23/`, then replace `4.22` with `4.23` and `v4-22` with
`v4-23`. Nothing else in this directory changes.
