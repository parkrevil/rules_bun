# Research: Link What the Pinned Bun Links: `unresolved` and `./<name>/<dep>`

**Feature**: `006-unresolved-workspace-keys` | **Date**: 2026-10-29 | **Spec**: [spec.md](spec.md)

Part 1 lists the sources and the approval. Part 2 states the pinned Bun's semantics, with source
lines. Part 3 records one decision per requirement (R1–R7). Part 4 is the audit FR-010 asks for.
Part 5 lists the decisions the user must confirm. Part 6 is the evidence log. Every command in
Part 6 ran on Linux x64 (WSL) on 2026-10-29 with the pinned Bun 1.4.4
(`$(bazel info output_base)/external/+bun+bun_linux-x64/bun`, `bun --version` = `1.4.4`).

## Part 1: Sources and approval

| ID | Source | Used for |
|---|---|---|
| LOCK-144 | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/bun.lock.rs (3,543 lines; byte-identical to the copy feature 004 read) | writer and loader of `unresolved` and of `./<name>/` keys (Part 2) |
| TREE-144 | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/Tree.rs | `Tree::is_unlinked_member`, the `./` prefix of a key (Part 2, S6) |
| HOOKS-144 | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install_types/resolver_hooks.rs | `Behavior::is_optional`, `is_optional_peer`, `is_peer` (S2) |
| LOCK-142 | https://github.com/oven-sh/bun/blob/bun-v1.4.2/src/install/lockfile/bun.lock.rs | what the still-known 1.4.2 loader does with the same layouts (S8) |
| BLOG | https://bun.com/blog/bun-lock-text-lockfile | the format bun.com links to; it describes neither `unresolved` nor `./` keys, so both need constitution V's approval and canaries |
| F004-G | `specs/004-bun-1-4-4-upgrade/research.md`, G1 and G2 | the gaps this feature closes |

**Approval (constitution V)**: feature 004 research G1/G2 records the user's decision of
2026-10-26: "G1 and G2 are left out of this feature and become the next feature, which reads both
keys with the approval and canaries constitution V requires." It covers the accesses L23–L25
(R1, R3). Evidence: Part 2 (source) and Part 6 (lockfiles the pinned Bun wrote). Canaries:
C-UNRESOLVED, C-UNLINKED (R5).

## Part 2: The pinned Bun's semantics

Line numbers are of LOCK-144 unless another file is named.

### S1. Which optional dependencies are written as `unresolved`

Writer, L302–321: `unresolved_names(dep_ids)` returns the names of the entry's dependencies whose
resolution is `invalid_package_id`, whose behavior `is_optional()`, and whose name hash equals the
name of some placed row of the tree (`hoisted_dependencies`, any tree). The comment states the
intent: "Optional dependencies that did not resolve, although the tree has a package of the same
name. They are written as "unresolved" so that loading does not resolve them to it."

It is written for a `packages` entry inside its info object (L1008–1011, after `optionalPeers`,
`, "unresolved": [...]`) and for a workspace entry (`write_workspace_deps`, L1238–1241, a
multi-line array). The root and every workspace go through `write_workspace_deps` (L379–425).

An optional dependency that did not resolve and whose name is nowhere in the tree is written in
`optionalDependencies` with no `unresolved` entry and no `packages` key (E3, E10).

### S2. What the loader does with `unresolved`

`parse_append_dependencies` (L3347–3543) runs for the root (L2225), each workspace (L2284) and
each `packages` entry's info object (L2577):

- L3372–3400: `optionalPeers` and `unresolved` must each be an array (`"Expected an array"`,
  L3376–3382) of strings (`"Expected a string"`, L3385–3391); a violation fails loading.
- L3531–3537: after the sort that assigns dependency IDs, every dependency of this entry whose
  `behavior.is_optional()` and whose name is listed becomes an "unresolved row".
- L3027–3031: after the root, workspace and package loops, every unresolved row's resolution is
  set to `invalid_package_id`, "even if the loops above found a package of the same name".

`Behavior::is_optional()` is `contains(OPTIONAL) && !contains(PEER)` (HOOKS-144 L210–212). So the
list applies only to the entry's `optionalDependencies`: a listed name that is a peer, an optional
peer, a `dependencies` entry or no dependency of the entry is ignored. A peer of another package
that would take that name binds as before (it is another row), E9.

### S3. Workspaces are registered under their names first

L2265–2304: each workspace is added as a package and put into the key map under its **name**
(`pkg_map.put(name, pkg_id)`, L2302). A `packages` row with a `workspace:` resolution at a key
already in the map is skipped (L2481–2486); at a new key it is mapped to the matching workspace or
fails with `Unknown workspace` (L2487–2536). Any other row at a key already in the map replaces the
workspace there, unless that row is a folder (`file:` folder), which fails with "Duplicate package
path" (L2748–2762: "Each workspace was registered under its name above. A root dependency of the
same name replaces it at that key, unless that dependency is a folder").

### S4. Unlinked workspace

L2864–2867: a workspace is **unlinked** when the key map's entry for its name is not the workspace
itself (`pkg_map.get(workspace_name) != Some(&pkg_id)`), that is, when `packages["<name>"]` exists
and is not a `workspace:` entry (S3). TREE-144 L95–112 (`is_unlinked_member`) is the same condition
on the tree: the workspace "has no symlink in the root `node_modules`, because `hoist_dependency`
gave its name to one of the root's dependencies".

### S5. How a workspace's dependencies bind

Root, L2822–2855: by `pkg_map.get(<dep>)` alone (after the peer rules); a `workspace:` dependency
whose key belongs to another package binds the workspace of that name (L2828–2836). If nothing
binds, an optional or peer dependency stays unbound (`may_stay_unresolved`, L2840–2842,
L3297–3300: `OPTIONAL | PEER`); any other fails loading.

Workspaces, L2859–2921: the key is `<name>/<dep>` for a linked workspace and `./<name>/<dep>` for
an unlinked one (L2867–2895); then `<dep>` (L2897–2901). Never deeper, never `<name>/<dep>` for an
unlinked one. If nothing binds: an unlinked workspace's dependency is left for the `packages` loop
("A bun.lock from an older Bun only has this dependency below a `packages` row of the workspace",
L2903–2907); otherwise an optional or peer one stays unbound and any other fails loading.

Packages, L2929–3025: each row's dependencies walk from the row's key (`find_resolution`,
L1580–1662): `<key>/<dep>`, then each ancestor of the key, then `<dep>`, a `@scope/name` counted as
one segment (L1623–1658). Rows whose package is the root or a **linked** workspace are skipped
(L2938–2944); a row of an unlinked workspace (for example `app/lib`, E4/U4) resolves that
workspace's dependencies again from the row's key, the evidence order of L2976–2997 deciding which
binding stays.

### S6. What a `./` key is

TREE-144 L379–388: in a key (`PkgPath` style), the path of an unlinked workspace's tree starts with
`./` followed by the workspace's folder name, its package name. Below it come the packages placed
in that workspace's own `node_modules`: `./lib/b`, `./lib/y/x`, `./@scope/lib/b` (E4, E5, U4). For
`./lib/y`, `find_resolution` walks `./lib/y/<d>`, `./lib/<d>`, `./<d>`, `<d>`; `./<d>` is never a
key Bun writes. The loader checks no other shape of a key: a `./` key no walk reaches is loaded and
never bound.

### S7. Bindings of a lockfile Bun wrote agree across rows

In U4 the rows of the unlinked `lib` reached through `app` (`app/lib/b`, `app/lib/y`,
`app/lib/y/x`) hold the same versions as `./lib/b`, `./lib/y`, `./lib/y/x`, and Bun's isolated
install links each package once with exactly the bindings of the `./lib/` walk (E11). A dependency
row has one resolution in the lockfile Bun writes, so every placement's walk finds it; the
re-binding of S5's packages loop changes nothing for such a lockfile.

### S8. Bun 1.4.2

LOCK-142: workspaces are put into the key map by name and a second row at that key fails with
"Duplicate workspace name" (L2479–2490); a non-workspace row at a key already in the map fails with
"Duplicate package path" (L3031–3034). So 1.4.2 loads no lockfile with an unlinked workspace. Its
workspace loop uses `<name>/<dep>`, then `<dep>` (L3118–3170), and reads no `unresolved` (no
occurrence in the file). Its root and workspace loops leave an optional or peer dependency with no
key unbound (`may_stay_unresolved`, L3097, L3164), as 1.4.4 does.

## Part 3: Decisions

### R1. Read `unresolved` and leave those optional dependencies unlinked (FR-001, FR-006, US1)

**Decision**: `read_lockfile` reads `unresolved` from a `packages` entry's info object (access
**L23**) and from a workspace entry (access **L24**), each as a list of strings; any other value
fails with `<file>: the packages entry "<key>" has an "unresolved" that is not a list of strings;
run `bun install` to rewrite bun.lock` (for a workspace: `the workspace "<path>"`), without
printing the value. The resolver drops, for that entry, the edge of each listed name that is in
the entry's `optionalDependencies` and not in its `dependencies`; any other listed name is ignored
(S2). Peers are unaffected: the dropped name is no longer a sibling, so a peer of that name resolves
as for any name the dependent does not declare (E9: `ident-a`'s peer `state` binds
`state@1.0.0` while `a` has no `state`).

**Rationale**: S1/S2 define the list exactly; the isolated install of E1 links no `state` for `a`.

**Alternatives**: infer "unbound" from the range (`^3.0.0` matches no listed version) — rejected:
it re-implements resolution and diverges where Bun bound an out-of-range package on purpose
(overrides).

### R2. An optional or peer dependency of the root or a workspace with no key is unlinked (FR-010, Edge Cases)

**Decision**: in `_workspace_children`, a declared `optionalDependencies` or `peerDependencies`
name for which the walk finds no key is not linked; any other kind keeps today's diagnostic. Bun
writes no key for an optional dependency it could not resolve when the name is nowhere in the tree
(S1, E3, E10), and both 1.4.2 and 1.4.4 leave such edges unbound (S5, S8). Today every such
lockfile fails evaluation with "declares …, which bun.lock lists no entry for".

**Rationale**: it is the case S1 excludes from `unresolved`; without it US1 fixes only half of
"an optional dependency Bun left unbound". A `packages` entry's missing optional dependency is
already skipped (`_ordinary_edges`). Needs D2.

### R3. Resolve an unlinked workspace's dependencies through `./<name>/` (FR-002–FR-004, US2)

**Decision**: a workspace named `N` is unlinked when `packages["N"]` exists and is not a
`workspace:` entry (S3, S4). Its walk starts at `[".", N]` instead of `[N]`: `./N/<dep>`, then
`<dep>` (the `./<dep>` step of `walk_key` matches no key Bun writes, S6). The same start is used for
the workspace's peer fallbacks (`virtual` in `resolve`). Packages at `./N/…` keys need no change:
`split_key("./lib/y")` is `[".", "lib", "y"]`, so `walk_key` walks exactly `find_resolution`'s keys
(S5, S6). A `workspace:` dependency of another workspace already binds through its own key
(`app/lib` → `lib@workspace:packages/lib`), as S5's workspace loop does (U4, US2-5). Reading the
`./` form is access **L25**.

A dependency of an unlinked workspace found at neither key keeps today's diagnostic when it is not
optional or peer (D3): S5's fallback to the `packages` rows serves "a bun.lock from an older Bun",
and neither known Bun writes one (1.4.2 cannot load the layout, S8; 1.4.4 writes `./N/<dep>`).

**Rationale**: the condition is the loader's own (L2866), decided from the lockfile alone. U3 shows
why the trigger cannot be the presence of a `./` key: Bun 1.4.4 wrote no `./` key there, and
today's walk binds `lib`'s `b` to `lib/b`, which is `a`'s `b@1.0.0`, where Bun binds `b@2.0.0`.
Needs D1.

**Alternatives**: start at `./N` only when some key starts with `./N/` — rejected by U3;
re-resolve from every `workspace:` row of `N` as S5's packages loop does — rejected: equal for every
lockfile Bun writes (S7) and an evidence order to replicate for none.

### R4. Lockfiles without the new forms (FR-009, US3)

Every lockfile Bun 1.4.2 loads has only linked workspaces (S8) and no `unresolved`, so R1 and R3
change nothing for it; every existing fixture is such a lockfile. R2 changes one diagnostic (D2):
a lockfile that fails today with "declares …, which bun.lock lists no entry for" for an optional
or peer dependency resolves instead. FR-009 is checked by an unchanged test suite and by comparing
`@npm_fixture_results` for every pre-existing fixture on `main` and on the branch (quickstart Q5).

### R5. Canaries (FR-007, US4)

Both use `support.ts` (`runInstall`, `red`, `canaryFail`, `LOCKFILE_SOURCE`) and fail naming the
reader they protect.

| Canary | Project | Asserts | Red (`RULES_BUN_CANARY_RED=1`) |
|---|---|---|---|
| C-UNRESOLVED | root `dependencies {a: 1.0.0, state: 1.0.0}`, `optionalDependencies {b: ^3.0.0, r: ^9.0.0}`; packument of `a@1.0.0` adds `optionalDependencies {state: ^3.0.0}` | `packages.a[2].unresolved` is `["state"]` with `state` in its `optionalDependencies`; `workspaces[""].unresolved` is `["b"]`; `r` has no key and is not listed (R2) | root `b` is `^1.0.0` and `a`'s `state` `^1.0.0`: both resolve, nothing is listed |
| C-UNLINKED | root `dependencies {lib: npm:a@1.0.0, "@scope/lib": npm:c@1.0.0, b: 1.0.0}`; members `lib {b: 2.0.0}`, `@scope/lib {b: 2.0.0}` | `packages.lib` is `a@1.0.0`, `./lib/b` and `./@scope/lib/b` are `b@2.0.0`, no key `lib/b` holds `b@2.0.0` | the root aliases are `liba` and `@scope/liba`: both workspaces are linked, so `./lib/b` is absent |

Reader named: C-UNRESOLVED `the unresolved of an entry in bun/private/lockfile.bzl and its use in
bun/private/resolve.bzl`; C-UNLINKED `the unlinked-workspace walk of _workspace_children in
bun/private/resolve.bzl`.

### R6. Fixtures and tests (FR-008)

New fixture archive `opt-user@1.0.0` (`dependencies {ident-a: 1.0.0}`,
`optionalDependencies {state: ^3.0.0}`), packed by `pack.ts`. New projects of `write_lockfiles.ts`,
each with a `check` asserting the keys it exists for:

| Project | Layout (from E1–E10, U4) | Main today | After |
|---|---|---|---|
| `unresolved` | root `{a, opt-user, q, state}` + `optionalDependencies {b: ^3.0.0}`; member `w` `optionalDependencies {q: ^3.0.0}` | `opt-user` → `state@1.0.0`; root `b` → `b@1.0.0`; `w`'s `q` → `q@1.0.0` | no such edges; `ident-a`'s peer `state` → `state@1.0.0` |
| `unbound` | root `optionalDependencies {state: ^3.0.0}`, `peerDependencies {r: ^9.0.0}`; member `w` `optionalDependencies {x: ^9.0.0}` | evaluation fails ("declares …, which bun.lock lists no entry for") | resolves; no `state`, `r`, `x` link |
| `unlinked` | U4 | `lib`: `b` → `b@1.0.0`, `y` → `q@2.0.0`; `@scope/lib`: `b` → `@scope/lib/b` (`b@2.0.0`) | `lib`: `b@2.0.0` (`./lib/b`), `x@2.0.0`, `y@1.0.0` (`./lib/y`) whose `x` is `x@1.0.0` (`./lib/y/x`) and `b` `b@2.0.0`; `@scope/lib`: `b@1.0.0`; `app`: members `lib`, `@scope/lib` |

The "After" column is the link set of Bun's isolated install (E1, E9, E11), which SC-001 compares
with. Tests (`resolve_test.bzl`, `lockfile_test.bzl`): one per row and edge above, plus inline
lockfiles for US1-3 (a listed name also in `dependencies` keeps its edge), a listed name that is no
optional dependency (ignored), the two malformed `unresolved` forms (FR-006), and US3-2's linked
variant of `unlinked` (key `lib` a `workspace:` entry → today's walk). Each fails on `main`
(`tdd-log.md`).

### R7. Documentation (FR-011)

`_NPM_DOC` (`bun/private/npm_extension.bzl`): `:node_modules/<package>` exists for each declared
package "the lockfile binds for that workspace package"; an optional dependency Bun left unbound
(listed under `unresolved`, or without a key) and a peer dependency without a key get no target.
`lockfile.bzl`'s docstring lists L23–L25. Feature 004 research G1 and G2 get "Resolved by feature
006". Platform statements name only the CI runner labels the PR's run used.

## Part 4: Audit of key walks (FR-010, US5)

| # | Place | Bun counterpart | Result |
|---|---|---|---|
| A1 | `walk_key` (`resolve.bzl`) | `find_resolution` L1580–1662 | agrees for every key Bun writes, `./` keys included (S6); the bundled bound (L1573–1621) applies only to optional peers, which the ruleset binds by its peer model (A8) |
| A2 | `split_key` (`lockfile.bzl`) | scope handling L1623–1658 | agrees: `./@scope/lib/b` → `[".", "@scope/lib", "b"]` |
| A3 | `_ordinary_edges` (`resolve.bzl`) | packages loop L2929–3025 | agrees, except `unresolved` (G1 → R1) |
| A4 | `_ordinary_edges`: a target that is a `workspace:` entry is skipped | L2481–2524: the key binds the workspace | **disagrees, pre-existing**: a registry package's dependency on a workspace member is linked by Bun, not by the ruleset; instances are leaf targets that cannot point at a member's target (feature 003 R7). Reported (D4) |
| A5 | `_workspace_children` start `[]` / `[N]` | L2822–2921 | disagrees for unlinked workspaces (G2 → R3) and for an optional or peer dependency with no key (→ R2, D2); agrees otherwise |
| A6 | `_workspace_children`: a `workspace:` key → member | L2828–2836, L2481–2524 | agrees (U4 `app/lib`, `app/@scope/lib`) |
| A7 | `virtual` peer fallbacks in `resolve` (walk from the workspace start) | — | same start as A5 → R3 |
| A8 | peer binding (`_siblings`: provided, sibling, fallback; missing peer fails) | version-based peers L2793–2820, L2956–2962; unbound peer allowed (L3002–3009) | not a name-to-key walk; the model is feature 003 R2's. One divergence is known: a package's non-optional peer nothing provides fails evaluation (`missing_peer` fixture) where Bun leaves it unbound. Reported (D4) |
| A9 | `npm_extension.bzl` loops over all entries (URL check, `name@version` agreement) | — | key-independent; `./` entries are checked like any other |
| A10 | `run.bzl` (`dependency_keys` in diagnostics only; layout paths from store names and aliases) | — | no key becomes a path; `./` never reaches the file system (Windows Edge Case) |
| A11 | `overrides.bzl` `split_key` | — | splits `package.json` `resolutions` keys, not lockfile keys; unaffected |
| A12 | `write_lockfiles.ts` `walk` (test helper) | `find_resolution` | agrees (same segment walk) |

Keys the loader rejects: none by shape (S6). A `packages` key equal to a workspace's name holding a
`file:` folder fails Bun's loading ("Duplicate package path", S3); the ruleset treats it as an
unlinked workspace's key and never fetches `file:` entries; this lockfile is one Bun refuses, so no
binding differs for a lockfile Bun installs. No new failure is added.

## Part 5: Decisions for the user

- **D1** (R3, R4): the `./<name>/` walk applies when the key `<name>` is not that workspace (the
  loader's L2866), not when the lockfile holds a `./` key. U3 is a 1.4.4 lockfile with no `./` key
  that `main` resolves wrongly (`lib`'s `b` → `a`'s `b@1.0.0`). Spec P4, FR-009 and US3-2 say "a
  lockfile that holds neither form … resolves as on `main`"; read literally they require that wrong
  binding. Proposed wording: "holds no `unresolved` and no unlinked workspace". Every lockfile
  1.4.2 loads satisfies it (S8).
- **D2** (R2): an optional or peer dependency of the root or a workspace that has no key is not
  linked, as both known Bun versions leave it; today evaluation fails. This changes a diagnostic
  for lockfiles that hold neither new form (an exception to FR-009) and adds no failure.
- **D3** (R3): a non-optional dependency of an unlinked workspace found at neither `./<name>/<dep>`
  nor `<dep>` keeps today's diagnostic rather than following S5's fallback to older Bun's rows.
- **D4** (A4, A8): two pre-existing divergences the audit found are reported, not changed: a
  registry package's dependency on a workspace member is not linked, and a package's non-optional
  peer nothing provides fails evaluation. Neither is a G1/G2 key walk; fixing A4 needs a design
  change to instances, A8 would reverse the tested `missing_peer` behavior. Candidates for a later
  feature.

## Part 6: Evidence log

Experiments ran with `/tmp/bun006-scripts/exp.ts` (a loopback registry from
`bun/tests/support/npm_registry.ts` serving the fixture archives, packuments changed where noted),
each in a new directory with an empty cache, `bun install` exit 0 in every case. URLs and
integrities are elided below.

- **E1**: root `{a: 1.0.0, state: 1.0.0}`, `a@1.0.0` published with
  `optionalDependencies {state: ^3.0.0}`, `--linker isolated` →
  `"a": ["a@1.0.0", …, { "dependencies": { "b": "^1.0.0" }, "optionalDependencies": { "state": "^3.0.0" }, "unresolved": ["state"] }, …]`;
  `node_modules/.bun/a@1.0.0/node_modules` holds `a`, `b`, no `state`.
- **E2**: root `{a: 1.0.0}` + `optionalDependencies {b: ^3.0.0}` → `workspaces[""]` has
  `"unresolved": ["b"]`; `packages.b` is `b@1.0.0` (from `a`).
- **E3**: root `{a: 1.0.0}` + `optionalDependencies {state: ^3.0.0}` → no `unresolved`, no key
  `state`.
- **E4**: root `{lib: npm:a@1.0.0, b: 1.0.0}`, members `lib {b: 2.0.0, c, x, y: 1.0.0}`,
  `app {lib: workspace:*, b: 1.0.0}` → `"lib": a@1.0.0`, `"./lib/b": b@2.0.0`,
  `"app/lib": lib@workspace:packages/lib`, `"app/lib/b": b@2.0.0`; `c`, `x`, `y` at the root.
- **E5**: the same with the member and alias `@scope/lib` → `"./@scope/lib/b": b@2.0.0`.
- **E6** (control, no alias): `"lib": lib@workspace:packages/lib`, `"lib/b": b@2.0.0`, no `./` key.
- **E7**: member `lib` `optionalDependencies {b: ^3.0.0}`, root `b: 1.0.0` → the member entry has
  `"unresolved": ["b"]`.
- **E8**: `a@1.0.0` published with `state: ^3.0.0` in both `dependencies` and
  `optionalDependencies` (npm's form) → the info lists it only under `optionalDependencies`, with
  `unresolved: ["state"]`.
- **E9**: as E1 with `a` also depending on `ident-a@1.0.0` (peer `state: ^1.0.0`), isolated →
  `a`'s store entry links `a`, `b`, `ident-a`; `ident-a`'s links `ident-a`, `state`
  (`state@1.0.0`).
- **E10**: root `peerDependencies {state: ^3.0.0}`, `optionalDependencies {nosuch-zz: ^1.0.0}`
  (404) → Bun warns "No version matching "^3.0.0" found for peer dependency "state"" and
  "GET …/nosuch-zz - 404"; neither name has a key or an `unresolved` entry.
- **U3**: root `{lib: npm:a@1.0.0, "@scope/lib": npm:c@1.0.0, b: 2.0.0, x: 2.0.0, y: npm:q@1.0.0}`,
  members `lib {b: 2.0.0, x: 2.0.0, y: 1.0.0}`, `@scope/lib {y: 1.0.0}`, `app {lib: workspace:*}`
  → no `./` key; `"lib/b": b@1.0.0` (`a`'s), `"b": b@2.0.0`; Bun links `packages/lib/node_modules/b`
  to `b@2.0.0`. (Bun also binds `lib`'s `y: 1.0.0` to the root's `y`, `q@1.0.0`, writing no
  `y@1.0.0`; the ruleset follows the lockfile there too.)
- **E11 (U4)**: root `{lib: npm:a@1.0.0, "@scope/lib": npm:c@1.0.0, b: 1.0.0, x: 2.0.0,
  y: npm:q@2.0.0}`, members `lib {b: 2.0.0, x: 2.0.0, y: 1.0.0}`, `@scope/lib {b: 1.0.0}`,
  `app {lib: workspace:*, "@scope/lib": workspace:*}`, default (isolated) linker → keys `lib`
  (a@1.0.0), `@scope/lib` (c@1.0.0), `b` (1.0.0), `x` (2.0.0), `y` (q@2.0.0), `./lib/b` (b@2.0.0),
  `./lib/y` (y@1.0.0), `./lib/y/x` (x@1.0.0), `@scope/lib/b` (b@2.0.0), `app/lib`, `app/@scope/lib`,
  `app/lib/b` (b@2.0.0), `app/lib/y` (y@1.0.0), `app/lib/y/x` (x@1.0.0). Links:
  `packages/lib/node_modules/{b → b@2.0.0, x → x@2.0.0, y → y@1.0.0}`,
  `packages/scoped/node_modules/b → b@1.0.0`, `y@1.0.0`'s `{b → b@2.0.0, x → x@1.0.0}`,
  `x@1.0.0`'s `b → b@2.0.0`, `c@1.0.0`'s `b → b@2.0.0`, `a@1.0.0`'s `b → b@1.0.0`,
  `packages/app/node_modules/{lib → ../../lib, @scope/lib → ../../../scoped}`.
