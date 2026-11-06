# AGENTS.md

Guidance for AI coding agents working in this repository. Read `README.md` for
the human-facing explanation. This file covers what you need in order to change
things safely.

## What this repo is

An **example** kustomize layout for storing oc-mirror v2 output in Git and
rolling the mirrored operator catalogs out to disconnected OpenShift clusters.
There is no application code, no generator and no CI. Everything is kustomize
YAML plus Markdown. The registries (`dc1-quay`, `edge-harbor`), hostnames and
catalog choice are made up. The oc-mirror output under `examples/` is real.

## Layout

```
mirrors/<registry>/kustomization.yaml            lists the registry's catalog dirs; includes components/registries/<registry>
mirrors/<registry>/<catalog>/kustomization.yaml  wrapper: resources [cluster-resources] + components/catalogs/<catalog>
mirrors/<registry>/<catalog>/cluster-resources/  raw oc-mirror output + a resources-only kustomization.yaml
components/catalogs/<catalog>/                   catalog labels (labels field) + IDMS/ITMS rename (kind-only targets)
components/rename-catalogsources/<catalog>/      CatalogSource -> stable name (name-anchored target)
components/registries/<registry>/                registry label
components/ocp-version/<x.y>/                    selects one OpenShift version (includes deselect-all)
components/ocp-version/{deselect-all,prune-deselected}/   see components/ocp-version/README.md
components/common/                               prune-deselected, then rename-catalogsources
base/                                            OperatorHub/cluster (disableAllDefaultSources)
overlays/<x.y>/<registry>/                       resources [base, mirrors/<registry>]; components [ocp-version/<x.y>, common]
examples/<catalog>/                              the real oc-mirror runs: imagesetconfig.yaml + cluster-resources/
```

## Rules that must not be broken

1. **Never edit files under `cluster-resources/`**, in `mirrors/` or `examples/`.
   They are oc-mirror output, kept byte-for-byte. The one exception is in
   `mirrors/`: the registry prefix `localhost:5000/ocp4` is replaced with the
   example registry's (`quay.dc1.example.com/ocp4`,
   `harbor.edge.example.com:8443/mirror/ocp`). Each `cluster-resources/kustomization.yaml`
   contains only `apiVersion`, `kind` and `resources`. Any customisation belongs
   in a component or a wrapper.
2. **Overlay component order is load-bearing.** It must be
   `ocp-version/<x.y>`, then `common`. Kustomize applies a kustomization's
   included components before its own patches, and patches run in order. The
   whole version-selection mechanism depends on this. Don't nest `common` inside
   a version component, and don't add anything to `common` that changes
   ClusterCatalog `availabilityMode`.
3. **Kind-only targets are only safe inside a catalog wrapper.** These are the
   `labels` field and the IDMS/ITMS patches in `components/catalogs/<catalog>`,
   and they rely on the wrapper holding one catalog's objects. In an overlay,
   which holds every catalog, use name-anchored targets instead, as
   `rename-catalogsources` does.
4. **Don't rename CatalogSources in a wrapper.** A wrapper holds every OpenShift
   version's CatalogSource, and renaming them there collides. Renaming happens
   in `common`, after the version component has deleted the other versions.
5. **The IDMS/ITMS rename must stay in the wrapper.** Every oc-mirror run names
   its mirror set `idms-operator-0`, so the names collide as soon as catalogs
   are merged.
6. **Target names are anchored Go (RE2) regexes**, with no lookahead. Write them
   as whole-name patterns, e.g. `cs-redhat-operator-index-v\d+-\d+`. Inside YAML
   flow maps (`{...}`), use `\d`, not `[0-9]`: an unquoted `[` breaks parsing.
7. **Stable names and label keys are a contract with clusters.** Don't change a
   CatalogSource name (`redhat-operators`, …) or the `catalogs.example.com/*`
   label keys and values unless asked to.

## Verifying a change

kustomize v5 is required. A pinned copy may be in the git-ignored `./bin/`
(`./bin/kustomize`); otherwise use `kustomize` from `PATH`.

```bash
# everything must build
for d in overlays/*/* mirrors/*/ mirrors/*/*/ mirrors/*/*/cluster-resources/; do
  ./bin/kustomize build "$d" >/dev/null || echo "FAIL $d"
done

# for refactors: render before and after, and diff
for d in overlays/*/*; do ./bin/kustomize build "$d" > "/tmp/before-${d//\//_}.yaml"; done
# ...make the change...
for d in overlays/*/*; do ./bin/kustomize build "$d" | diff -q "/tmp/before-${d//\//_}.yaml" - ; done
```

What correct overlay output looks like:
- one CatalogSource per catalog, with its stable name and that version's image
- only that version's ClusterCatalogs `Available`, and the rest `Unavailable`
- one IDMS per catalog, named after the catalog
- `OperatorHub/cluster`
- no `catalogs.example.com/ocp-selected` label left anywhere

After a documentation change, check that every path mentioned in the READMEs
exists.

## Conventions

- **YAML comments** say what a file does and anything order-sensitive. They
  don't mention tooling, "generated" or "hand-written". Each file starts with a
  short header comment, as the existing files do.
- **Docs.**
  - `README.md` is for platform engineers adopting the layout: concise, no
    implementation detail.
  - `components/ocp-version/README.md` holds the version-selection mechanics.
  - `examples/README.md` describes the oc-mirror runs.
  - Keep all three consistent with the YAML when you change the structure.
- **Adding a version, catalog or registry**: follow the how-tos in `README.md`.
  New version components are copies with the version strings changed. New
  catalogs need both `components/catalogs/<catalog>` and
  `components/rename-catalogsources/<catalog>`, and an entry in
  `components/rename-catalogsources/kustomization.yaml`.
- **Regenerating `examples/`** needs oc-mirror, registry credentials and a
  throwaway local registry; see `examples/README.md`. Don't do it unless asked.
  It downloads images, and it changes every file's `createdAt`.
- **Don't commit, push or stage** unless the user asks.
