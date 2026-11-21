# Data Model: Link What the Pinned Bun Links

**Feature**: `006-bun-conformant-resolution` | **Date**: 2026-10-29 | **Research**: [research.md](research.md)

The resolver's data is Bun's, carried over (research R1): arrays indexed by IDs, as in Bun's
`Lockfile` and `Store`. Field names follow Bun's so a Bun line and its Starlark carry-over read
alike. Only fields that decide a link are carried.

## Loaded lockfile (`bun_lockfile.bzl`; LOCK S1–S2, LOCKFILE)

| Entity | Fields | Rules |
|---|---|---|
| **Package** (ID = index; 0 is the root) | `name`, `name_hash` (the name itself), `resolution` (`tag`: root, workspace, npm, folder, symlink, tarball, git, …; `value`: version or path), `dependencies` (`[begin, end)` into the dependency list), `meta` (`os`, `arch`, `libc`, `bundled`) | One package per `name@resolution` (`append_package_dedupe`): two keys with one resolution are one package. Workspaces come first after the root. |
| **Dependency** (ID = index) | `name`, `name_hash`, `version` (`tag`: npm, dist_tag, workspace, catalog, folder, …; `literal`; `npm.is_alias`), `behavior` (bit set: prod, dev, optional, peer, workspace, bundled) | Sorted per package as `parse_append_dependencies` sorts them (LOCK L3531). `optionalPeers` turns a peer into an optional peer; `unresolved` marks rows (L23, L24). |
| **Resolutions** | `resolutions[dependency ID]` → package ID or `invalid` | Filled by S2, rewritten by S4 (hoisting) and S6 (clean). `invalid` means "not linked". |
| **Key map** (`PkgMap`) | `bun.lock` key → package ID | Workspaces put under their names first; `./<name>/…` keys of unlinked workspaces (L25). Keys are strings, never paths. |
| **Package index** | name → package IDs, ordered by `Resolution::order` (descending version) | Used by version-based peers (S3, S5). |
| **Row evidence** | per dependency: `Unbound` < `RootDependency` < `Walked` < `WalkedToRoot` < `Refused` < `OwnEntry` < `Unprovided` | The strongest walk over all rows of a package keeps the binding; equal evidence: the later row (LOCK L2993). |
| **Overrides, catalogs** | as LOCKFILE `OverrideMap`, `CatalogMap` | Read through `version_based_peer_range` (L3174–3208). |

## Hoisted trees (`bun_tree.bzl`; TREE, LOCKFILE `resolve`, `clean`)

| Entity | Fields | Rules |
|---|---|---|
| **Tree** | `id`, `parent`, `dependency_id`, `dependencies` (placed dependency IDs) | Built by `hoist::<Resolvable>` until no peer is bound late. Tree 0's placed rows decide `is_unlinked_member`. |
| **Served peers** | `(dependency ID, package ID)` | Applied by `bind_served_peers` unless the peer is itself placed. |

## Isolated store (`bun_isolated_store.bzl`; ISO `build_store`)

| Entity | Fields | Rules |
|---|---|---|
| **Node** | `pkg_id`, `dep_id` (`invalid` for the root), `parent_id`, `nodes` (children), `dependencies` (`(dep_id, pkg_id)`), `peers` (ordered set of **transitive peers** `(dep_id, pkg_id, auto_installed)`) | First pass, DFS from the root (ISO L728–1240). Early dedupe key `(pkg_id, ctx)`, `ctx` the exact list of `(peer name, ancestor resolution)` for the package's leaking peers. |
| **Leaking peers** | package ID → set of peer names its closure does not provide | Fixpoint of ISO L573–672. |
| **Entry** | `node_id`, `dependencies` (ordered set of `(entry_id, dep_id)`), `parents` | Second pass (ISO L1251–1470): nodes with equal `pkg_id` and equal `peers` are one entry. |
| **Platform class** | the `(os, cpu, libc)` tuples whose disabled-package set is equal; the store built for it | Research R3; a lockfile without restricted packages has one class. |

## Ruleset output (`resolve.bzl`)

`struct(instances, links, members)`, the top-level shape `main` returns (research R4). Instances
and links carry fields `main`'s do not; each is named below with the change that added it
(`resolve`'s docstring is the full description):

- **Instance** = one entry, merged over platform classes by `(package, peer bindings)`: `id`
  (`name@version__<h>[__<n>]`), `name`, `version`, `store_name`, `peer_hash` (16 hexadecimal
  digits naming the entry's transitive peer bindings, `""` without peers, BC-11), `key`, `edges`
  (alias → instance ID), `edge_conditions` (alias of `edges` → the tuples an edge holds on, when
  not on every class, BC-15), `edge_targets` (alias → instance ID → tuples, for a dependency bound
  to different entries by class, BC-16), `dependency_keys`, `peers` (aliases that are peers),
  `members` (alias → the path of the workspace member a dependency links, BC-4), `status` (`ok` or
  why it cannot be used), `unfetched` (whether that is because rules_bun does not fetch it, ID-4).
- **Link** `links[path][alias]` = `struct(alias, root, roots, closure, optional, key)`: `root` the
  instance ID the alias links, or `None` when that differs by class or the store links it on no
  class; `roots` root ID → the tuples it is the root on, when it differs by class (BC-12), else
  empty; `closure` reached in every class, `optional` ID → the `[os, cpu, libc]` requirements of
  the classes it is reached in; `key` the `bun.lock` key of the package it links, whose `bin`
  entries name its bin targets, or `None` (T111). Every declared dependency has a link; one the
  store links on no class has no root and reaches nothing (T111).
- **Members** `members[path][alias]` → member path, for `workspace:` links.

## Conformance graph (test data; [contracts/conformance-graph.md](contracts/conformance-graph.md))

| Entity | Fields | Rules |
|---|---|---|
| **Holder** | `path` (`""` root, else workspace path), `links` (name → node) | One per root and workspace. |
| **Entry node** | `name`, `version`, `links` (name → node) | One per Bun store directory / ruleset instance in the host's class. |
| **Equality** | partition refinement on the union of both graphs | Equal iff every class has as many nodes of each side and each holder matches its counterpart (research R8). |
| **Intentional difference** | `id` (`ID-1` … `ID-11`, ID-7 withdrawn), what it excludes | ID-1 to ID-4 are the test's only exclusions; ID-1 by `--ignore-scripts`, ID-2 by comparing the host class only, ID-3 by not reading `node_modules/.bun/node_modules`, ID-4 by skipping only the `status` of an entry marked `unfetched` (its links are compared). ID-5 (Bun's registry-dependent integrity refusal), ID-6 (Bun's default `linkWorkspacePackages`) and ID-9 (BC-12's two evaluation failures) exclude nothing: no compared lockfile reaches them (the oracle refuses ID-5's lockfile; the corpus uses Bun's default; no lockfile the pinned Bun writes reaches ID-9). ID-8 (declared workspace members, BC-4) excludes nothing either: the graph links the member as Bun does, and analysis tests check the declaration. ID-10 (credentials in `bun.lock`) and ID-11 (a workspace row of `lockfileVersion` 0) are evaluation failures; no compared lockfile reaches them. |

## State transitions

A dependency's binding: `invalid` → bound by S2 (row evidence may replace it) → reset to `invalid`
if `unresolved` → possibly rebound by S4/S6 (peers) → followed or skipped per platform class by S7
→ a node's link by S8. Only the last state is linked.
