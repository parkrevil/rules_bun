# Research: Link What the Pinned Bun Links, by Construction and by Test

**Feature**: `006-bun-conformant-resolution` | **Date**: 2026-10-29 | **Spec**: [spec.md](spec.md)

Part 1 lists the sources and the approval. Part 2 is the pinned Bun's pipeline from `bun.lock` to
links, with source lines (FR-001). Part 3 records one decision per design question (R1–R14).
Part 4 is the inventory of `bun.lock` fields and key forms (FR-005, FR-006). Part 5 lists the
differences found so far (Behavior Changes). Part 6 lists the decisions the user must confirm.
Part 7 is the evidence log. Every command in Part 7 ran on Linux x64 (WSL) on 2026-10-29 with the
pinned Bun 1.4.4 (`$(bazel info output_base)/external/+bun+bun_linux-x64/bun`, `bun --version` =
`1.4.4`).

Line numbers are of the files at tag `bun-v1.4.4` unless another tag is named. The step-by-step map
of Part 2 is the plan-level map: it names each stage, its file and line range, and what the
ruleset does with it. The function-level map (each Bun function → the ruleset function citing it)
is written into Part 2 as each stage is carried over (tasks), so SC-004 is checked against the
code, not against this plan.

## Part 1: Sources and approval

| ID | Source | Used for |
|---|---|---|
| LOCK | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/bun.lock.rs (3,543 lines) | text-lockfile loader (S1–S3), peer ranges (S5) |
| LOCKFILE | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile.rs (3,914 lines) | `resolve`, `hoist`, `clean_with_logger`, `append_package_dedupe`, `DepSorter` (S1, S4, S6) |
| TREE | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/Tree.rs (2,242 lines) | hoisting, `bind_served_peers`, `is_filtered_dependency_or_workspace`, `is_unlinked_member` (S4, S7) |
| REACH | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/reachable.rs | packages without a peer provider (S5) |
| PRUNED | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/pruned_workspaces.rs | `skips_link_to_pruned_workspace` (S7) |
| META | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/Package/Meta.rs | `is_disabled` (S7) |
| ISO | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/isolated_install.rs (2,714 lines) | the isolated linker's store: `build_store` (S7, S8) |
| STORE | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/isolated_install/Store.rs | node, entry and peer-set types (S8) |
| HOOKS | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install_types/resolver_hooks.rs | `Behavior`, `Libc::for_dependency` (S7) |
| SEMVER | https://github.com/oven-sh/bun/tree/bun-v1.4.4/src/semver (`Version.rs`, `SemverQuery.rs`, `SemverRange.rs`, `lib.rs`) | `satisfies_dependency_version`, version order (R5) |
| INSTALL | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/PackageManager/install_with_manager.rs | the order of the stages in an install (S0) |
| ISO-142, LOCK-142, TREE-142 | the same files at `bun-v1.4.2` | the 1.4.2 oracle (R10) |
| DEP, RES, NPM, CATALOG, OVERRIDE, SELECTOR, PKG, OPTIONS, CLI, HOSTED, REPO, INTEGRITY, INSTALLER, INTERSECTS, STRINGS | the same tag's `src/install/dependency.rs`, `resolution.rs`, `npm.rs`, `lockfile/CatalogMap.rs`, `lockfile/OverrideMap.rs`, `lockfile/override_selector.rs`, `lockfile/Package.rs`, `PackageManager/PackageManagerOptions.rs`, `PackageManager/CommandLineArguments.rs`, `hosted_git_info.rs`, `repository.rs`, `integrity.rs`, `PackageInstaller.rs`, `src/semver/intersects.rs`, `src/bun_core/string/immutable.rs` | the types and helpers the stages above call: dependency versions and `Tag::infer`, resolutions and their order, `os`/`cpu`/`libc` sets, catalogs, overrides, `Package::clone`, the install's default features, `--os`/`--cpu`, repository and integrity parsing, `alias_is_safe_install_target`, range intersection, string helpers. Fetched while carrying over (T037–T045), each range re-read at the tag before it is cited |
| DOC-ISO | https://bun.com/docs/install/isolated | the layout the oracle reads: `node_modules/.bun/<package>@<version>/node_modules/…` and the symlinks into it (R7) |
| BLOG | https://bun.com/blog/bun-lock-text-lockfile | the format outline bun.com links to; it describes none of the fields Part 4 marks new |
| PRIOR | the earlier attempt's research, committed as `prior-research.md` in this directory | S1–S8 of that file, re-read at the tag: every line range it cites for LOCK and TREE was found unchanged (`bun.lock.rs` and `Tree.rs` are byte-identical to its copies) |
| F004-G | `specs/004-bun-1-4-4-upgrade/research.md`, G1, G2 | the gaps this feature closes |

**Approval (constitution V)**: on 2026-10-29 the user approved reading every `bun.lock` field and
key form that Bun 1.4.4's text-lockfile loader and isolated linker read, each pinned by a canary
with a red mode. It supersedes the approval of 2026-10-26 (F004-G G1/G2). Part 4 lists each field,
the Bun lines that read it, the evidence and its canary.

**Bazel sources** (constitution V): toolchain resolution order and `target_compatible_with`
(https://bazel.build/extending/toolchains, https://bazel.build/extending/platforms#skipping-incompatible-targets),
platform inheritance (`parents`, https://bazel.build/reference/be/platforms-and-toolchains#platform),
`module_extension` / `module_ctx.read` (https://bazel.build/rules/lib/builtins/module_ctx),
`select()` (https://bazel.build/docs/configurable-attributes). Each is used as documented.

## Part 2: The pinned Bun's pipeline

### S0. Stages of an isolated install of a frozen lockfile

INSTALL: the lockfile is loaded (S1–S4: `parse_into_binary_lockfile`, which ends by calling
`Lockfile::resolve`), compared with `package.json` (frozen: a difference fails, L826–891), cleaned
(`clean_lockfile`, L707 → LOCKFILE `clean_with_logger` L1236, S6), and handed to
`install_isolated_packages` (ISO L1739), whose `build_store` (ISO L510–1470) decides every link
(S7, S8). Lifecycle scripts and file copying come after `build_store` and decide no link.

### S1. Packages and dependencies (loader)

LOCK `parse_into_binary_lockfile` L1797–3043. Top-level fields L1815–2099 (Part 4). The root and
each workspace become packages from the `workspaces` section (L2100–2304), each workspace put into
the key map under its **name** (L2302). Each `packages` row becomes a package through
`append_package_dedupe` (LOCKFILE L2685–2711): **a row whose resolution equals an existing
package's is that package** — one package per `name@resolution`, whatever its key. Dependencies of
each package come from `parse_append_dependencies` (L3347–3543), which also reads `optionalPeers`
and `unresolved` (L3372–3400) and sorts the dependencies (L3531). Keys: S3 of PRIOR (workspace
rows, "Duplicate package path", unlinked workspaces).

### S2. Resolutions (loader)

`resolutions[dep_id]` (one package per dependency) is filled at L2765–3031:

- root dependencies by key `<dep>`, a `workspace` dependency by workspace name, a peer first by
  `linked_member`/`peer_by_version` (L2793–2855);
- workspace dependencies by `<name>/<dep>` or, for an unlinked workspace, `./<name>/<dep>`, then
  `<dep>` (L2859–2921);
- each row's dependencies by `find_resolution` (L1580–1662) from the row's key, a peer of a registry
  package first by version (L2956–2962). Because a package is shared by every row with its
  resolution, **all rows of one package bind the same dependency IDs**; the walk with the strongest
  `RowEvidence` (L1524–1542; a later row of equal evidence replaces an earlier one, L2993) keeps it
  (L2963–2997);
- every `unresolved` row is reset to unresolved (L3027–3031).

An optional or peer dependency with no binding stays unresolved (`may_stay_unresolved`, L3298);
any other fails loading (`dependency_resolution_failure`, L3302).

### S3. Version-based peers (loader and hoister)

`resolve_peer_dep_version_based` (L3067–3089) and `version_based_peer_range` (L3174–3208): a
non-optional, non-bundled peer binds to the highest package of its name (by `Resolution::order`)
whose version satisfies the range, after catalogs and overrides; `linked_member` binds a root's or
workspace's peer to a workspace whose version matches. This needs npm range semantics (R5).

### S4. `Lockfile::resolve` (loader's last step)

LOCKFILE L1618–1625: `hoist::<Resolvable>` (L1648–) repeated while a peer is bound late, then
`rebind_peers_to_printed_packages` (LOCK L3244). The hoister (TREE `process_subtree` L1412,
`hoist_dependency` L1782, `bind_served_peers` L816–834, `bind_peer` / `peer_by_version`
L851–878) builds `trees` / `hoisted_dependencies` and **rewrites `resolutions` of peers**. The root
tree's placed rows decide `is_unlinked_member` in S7.

### S5. Shared peer versions

LOCK `PeerRanges::shared_version` L3091–3172 with REACH `packages_without_peer_provider`: a peer
no ancestor provides binds to the highest installed version that satisfies every unprovided range
on that name (pnpm's rule), when the name has at least two packages.

### S6. Clean

LOCKFILE `clean_with_logger` L1236: copies the reachable packages into a new lockfile
(`Package::clone`, which resets optional peers) and hoists again. Whether a clean of a frozen,
unchanged lockfile can change a binding is settled when it is carried over (R2): it is carried over
unless Part 2 records, with lines, that it cannot.

### S7. Which dependencies a node follows

TREE `is_filtered_dependency_or_workspace` L1313–1405: a dependency is skipped when its package
`is_disabled` for the host `cpu`/`os`/`libc` (META L72–74; `libc` applies to optional dependencies
only, HOOKS L884–890) **whether or not the dependency is optional**; when its behavior is not
placed (`is_placed`, HOOKS L271: bundled, or a kind the features omit, e.g. a registry package's
`devDependencies`); when an optional peer is omitted; when it links a pruned workspace. An
unresolved dependency is skipped unless it is an optional peer (L1324–1326).

### S8. The isolated store

ISO `build_store` L510–1470:

- `leaking_peers` (L573–672): per package, the peer names its closure does not provide;
- first pass (L728–1240): a DFS from the root creating nodes; cycles (L730–776); workspace
  dependencies owned once (L779–799); early dedupe by `(pkg_id, ctx_hash)` where `ctx_hash` is the
  ancestors' resolution of each leaking peer (L801–937); non-peer dependencies queued (L1032–1072,
  `is_unlinked_member` L711–720 keeps an unlinked workspace out of its parent's links); each peer
  resolved by walking up the node chain — the node's own dependencies, then each ancestor's
  dependencies and transitive peers, else `shared_version` or the lockfile's resolution
  (L1074–1224); a peer nothing provides and with no resolution is not linked (L1183–1186);
- second pass (L1251–1470): nodes with the same package and the same peer set are one **entry**;
  an entry's dependencies are its children's entries (L1307–1346, L1430–1455).

The linked graph of FR-008 is exactly: the entries, and for each entry its `dependencies` (name →
entry). Root and workspace entries are the holders of `node_modules/<name>` links.

### Not carried over (each decides no link)

| Bun step | Lines | Reason |
|---|---|---|
| hidden and public hoisting (`claim_hidden_hoist`, `public_hoist_pattern`) | ISO L219–228, L1271–1455 | writes `node_modules/.bun/node_modules` and root fallbacks, not entry dependencies; outside FR-008's graph (D1) |
| `peer_hash`, `entry_hash`, global virtual store | ISO L111–150, L1353–1386 | directory names only |
| workspace filters, `packages_to_install`, `--omit` | ISO L1005–1031, TREE L1393–1404 | the ruleset links every workspace; its consumers select targets |
| lifecycle scripts, `trustedDependencies` | ISO Installer | ID-1 |
| `Wyhash` of `ctx_hash` | ISO L814–867 | replaced by the exact key it hashes (same equality, no collisions) |
| `BuilderMethod::Filter` hoisting, `keep_linked_rows`, shipped and contested rows | TREE L436–L452, L929–L1249 | the hoisted linker's install tree; the isolated linker reads the `Resolvable` trees of `Lockfile::resolve` (`build_store` reads `trees[0]` only, ISO L713–L720) |
| optional-peer omission, pruned-workspace links, workspace filters in `is_filtered_dependency_or_workspace` | TREE L1364–L1404, PRUNED L36–L53, reachable.rs L93–L137 | a default install enables dev and optional dependencies (no omission), a frozen install keeps every workspace (PRUNED L11–L16, no pruned one), and no `--filter` is given; all three then skip nothing |
| `HostedGitInfo::from_url` beyond the host | HOSTED L231–L326, L874–L1259 | it chooses between the `git`, `github` and `tarball` tags of a URL; the carry-over decides by the URL's host alone (`_hosted_git_tag`). The tag decides a binding only for a peer written as such a URL, bound to a git or GitHub resolution (RES L39–L49), which rules_bun does not fetch (FR-010) |
| the digest of an `integrity` | INTEGRITY L99–L120 | its base64 is not decoded; an unknown algorithm is still refused (LOCK L1688–L1711). A malformed digest decides no link; rules_bun verifies the digest when it downloads (feature 003 FR-021) |
| the registry check of an npm row's URL | LOCK L2452–L2476, L2653–L2669 | it refuses a row whose URL is outside the configured registry and has no integrity; the configured registry is the consumer's `.npmrc`, which the loader does not read. rules_bun refuses to fetch any row without integrity (FR-010) |
| the `.bun-tag` of a git or GitHub row | LOCK L2671–L2720 | it is the `resolved` commit, compared only when two git rows have the same text (`Repository::eql`); not read |
| a target `os` or `cpu` Bun does not name | CLI L37–L64 | Bun refuses such a `--os` or `--cpu`, so no Bun behavior exists; the adapter (ID-2) gives it a value no package names, npm's rule for an unknown value (`bun_install_types.bzl` `platform_value`) |

### Walks outside the carry-over (T049)

The audit of PRIOR's key walks, re-done on the branch: no code outside `bun/private/bun_*.bzl` and
the adapter `resolve.bzl` decides which package a dependency links.

| Code | Lines | What it decides |
|---|---|---|
| `lockfile.bzl` `split_key`, an entry's `segments` and `alias` | `lockfile.bzl` `split_key`, `_entry` | read for each key and kept for the lockfile tests; no resolver reads them (the loader binds by `find_resolution`, LOCK L1580–L1662) |
| `workspaces.bzl` member patterns, `compare_manifests`, `match_members` | `workspaces.bzl` | that `package.json` and `bun.lock` agree (the frozen-lockfile check, INSTALL L826–L891); no link |
| `npm_extension.bzl` first entry of each `name@version`, `packages`, `identities` | `npm_extension.bzl` `_npm_impl` | which archive is downloaded and verified for a package version; no link |
| `run.bzl` `_check_unique`, `_package_layout` | `run.bzl` | that a program gets one copy per package version, and the store and link paths of the instances and links `resolve.bzl` gives; no binding |

### Function-level map (T055)

Each function of the rebuilt resolver and the Bun lines it carries over, as its docstring cites them
(`citations_test` checks every docstring; T054 re-read each range at the tag).

| Ruleset function | Carries over (bun-v1.4.4) |
|---|---|
| `bun_semver.bzl` `_version` | `src/semver/Version.rs` L56–L66 |
| `bun_semver.bzl` `_parse_ascii` | `src/semver/Version.rs` L27–L38 |
| `bun_semver.bzl` `_length_of_leading_whitespace_ascii` | `src/semver/SemverQuery.rs` L912–L942; `src/bun_core/string/immutable.rs` L1956–L1971 |
| `bun_semver.bzl` `parse_tag` | `src/semver/Version.rs` L1140–L1252 |
| `bun_semver.bzl` `parse_version` | `src/semver/Version.rs` L520–L728; `src/semver/Version.rs` L963–L983 |
| `bun_semver.bzl` `_parse_result` | `src/semver/Version.rs` L1264–L1286; `src/semver/Version.rs` L963–L972 |
| `bun_semver.bzl` `_cmp` | `src/semver/Version.rs` L469–L500 |
| `bun_semver.bzl` `_order_pre` | `src/semver/Version.rs` L1014–L1075 |
| `bun_semver.bzl` `_tag_order` | `src/semver/Version.rs` L1077–L1088 |
| `bun_semver.bzl` `_tag_order_without_build` | `src/semver/Version.rs` L1090–L1096 |
| `bun_semver.bzl` `_order_without_tag` | `src/semver/Version.rs` L469–L500 |
| `bun_semver.bzl` `version_order` | `src/semver/Version.rs` L502–L509 |
| `bun_semver.bzl` `version_order_without_build` | `src/semver/Version.rs` L511–L518 |
| `bun_semver.bzl` `version_eql` | `src/semver/Version.rs` L275–L280; `src/semver/Version.rs` L1136–L1138 |
| `bun_semver.bzl` `_is_zero` | `src/semver/Version.rs` L158–L160 |
| `bun_semver.bzl` `_comparator` | `src/semver/SemverRange.rs` L184–L188 |
| `bun_semver.bzl` `_range` | `src/semver/SemverRange.rs` L20–L24 |
| `bun_semver.bzl` `_null_set` | `src/semver/SemverRange.rs` L191–L200 |
| `bun_semver.bzl` `_lt_next_major` | `src/semver/SemverRange.rs` L202–L224 |
| `bun_semver.bzl` `_lt_next_minor` | `src/semver/SemverRange.rs` L226–L248 |
| `bun_semver.bzl` `_lt_next_patch` | `src/semver/SemverRange.rs` L250–L273 |
| `bun_semver.bzl` `_gte_next_major` | `src/semver/SemverRange.rs` L275–L289 |
| `bun_semver.bzl` `_gte_next_minor` | `src/semver/SemverRange.rs` L291–L306 |
| `bun_semver.bzl` `_comparator_satisfies` | `src/semver/SemverRange.rs` L320–L337 |
| `bun_semver.bzl` `_init_wildcard` | `src/semver/SemverRange.rs` L26–L75 |
| `bun_semver.bzl` `_range_satisfies` | `src/semver/SemverRange.rs` L101–L118 |
| `bun_semver.bzl` `_range_satisfies_pre` | `src/semver/SemverRange.rs` L120–L157 |
| `bun_semver.bzl` `_to_range` | `src/semver/SemverQuery.rs` L602–L743 |
| `bun_semver.bzl` `_or_range` | `src/semver/SemverQuery.rs` L519–L538 |
| `bun_semver.bzl` `_and_range` | `src/semver/SemverQuery.rs` L510–L517; `src/semver/SemverQuery.rs` L324–L345 |
| `bun_semver.bzl` `_null_set_group` | `src/semver/SemverQuery.rs` L480–L486 |
| `bun_semver.bzl` `parse_query` | `src/semver/SemverQuery.rs` L767–L769; `src/semver/SemverQuery.rs` L777–L1030 |
| `bun_semver.bzl` `query_satisfies` | `src/semver/SemverQuery.rs` L540–L547; `src/semver/SemverQuery.rs` L259–L300; `src/semver/SemverQuery.rs` L122–L156 |
| `bun_semver.bzl` `query_is_star` | `src/semver/SemverQuery.rs` L495–L503 |
| `bun_semver.bzl` `_raise` | `src/semver/intersects.rs` L22–L34 |
| `bun_semver.bzl` `_cap` | `src/semver/intersects.rs` L36–L48 |
| `bun_semver.bzl` `_narrow` | `src/semver/intersects.rs` L50–L67 |
| `bun_semver.bzl` `_and_query` | `src/semver/intersects.rs` L69–L76 |
| `bun_semver.bzl` `_is_non_empty` | `src/semver/intersects.rs` L78–L93 |
| `bun_semver.bzl` `_exact_version` | `src/semver/SemverQuery.rs` L93–L98 |
| `bun_semver.bzl` `_query_is_star` | `src/semver/intersects.rs` L213–L220 |
| `bun_semver.bzl` `_admits` | `src/semver/intersects.rs` L230–L233 |
| `bun_semver.bzl` `_admits_an_exact_version_of` | `src/semver/intersects.rs` L235–L242 |
| `bun_semver.bzl` `query_intersects` | `src/semver/intersects.rs` L244–L266 |
| `bun_install_types.bzl` `_has` | `src/install_types/resolver_hooks.rs` L171–L188 |
| `bun_install_types.bzl` `behavior_is_prod` | `src/install_types/resolver_hooks.rs` L204–L207 |
| `bun_install_types.bzl` `behavior_is_optional` | `src/install_types/resolver_hooks.rs` L208–L212 |
| `bun_install_types.bzl` `behavior_is_optional_peer` | `src/install_types/resolver_hooks.rs` L213–L216 |
| `bun_install_types.bzl` `behavior_is_dev` | `src/install_types/resolver_hooks.rs` L217–L220 |
| `bun_install_types.bzl` `behavior_is_peer` | `src/install_types/resolver_hooks.rs` L221–L224 |
| `bun_install_types.bzl` `behavior_is_workspace` | `src/install_types/resolver_hooks.rs` L225–L228 |
| `bun_install_types.bzl` `behavior_is_bundled` | `src/install_types/resolver_hooks.rs` L229–L232 |
| `bun_install_types.bzl` `behavior_is_enabled` | `src/install_types/resolver_hooks.rs` L261–L267 |
| `bun_install_types.bzl` `behavior_is_placed` | `src/install_types/resolver_hooks.rs` L269–L273 |
| `bun_install_types.bzl` `behavior_cmp` | `src/install_types/resolver_hooks.rs` L275–L297 |
| `bun_install_types.bzl` `dependency_sort_key` | `src/install_types/resolver_hooks.rs` L552–L558; `src/install/lockfile.rs` L320–L341 |
| `bun_install_types.bzl` `_features` | `src/install_types/resolver_hooks.rs` L1183–L1215 |
| `bun_install_types.bzl` `tag_is_local_package` | `src/install/resolution.rs` L1047–L1049 |
| `bun_install_types.bzl` `tag_can_enqueue_install_task` | `src/install/resolution.rs` L1074–L1080 |
| `bun_install_types.bzl` `dependency_features` | `src/install/PackageManager/PackageManagerOptions.rs` L276–L282; `src/install/PackageManager/PackageManagerOptions.rs` L150–L159 |
| `bun_install_types.bzl` `_all` | `src/install_types/resolver_hooks.rs` L810–L817 |
| `bun_install_types.bzl` `platform_names` | `src/install_types/resolver_hooks.rs` L847–L850; `src/install_types/resolver_hooks.rs` L904–L904; `src/install_types/resolver_hooks.rs` L961–L965 |
| `bun_install_types.bzl` `platform_value` | `src/install/PackageManager/CommandLineArguments.rs` L37–L64 |
| `bun_install_types.bzl` `negatable_from_json_value` | `src/install/npm.rs` L850–L865; `src/install_types/resolver_hooks.rs` L610–L687 |
| `bun_install_types.bzl` `_is_match` | `src/install_types/resolver_hooks.rs` L833–L836; `src/install_types/resolver_hooks.rs` L876–L880; `src/install_types/resolver_hooks.rs` L947–L950 |
| `bun_install_types.bzl` `libc_for_dependency` | `src/install_types/resolver_hooks.rs` L882–L890 |
| `bun_install_types.bzl` `meta_is_disabled` | `src/install/lockfile/Package/Meta.rs` L70–L74 |
| `bun_install_types.bzl` `_resolution` | `src/install/resolution.rs` L66–L72 |
| `bun_install_types.bzl` `_parse_repository_git` | `src/install/repository.rs` L152–L168 |
| `bun_install_types.bzl` `_parse_repository_github` | `src/install/repository.rs` L170–L198 |
| `bun_install_types.bzl` `repository_with_resolved` | `src/install/lockfile/bun.lock.rs` L2714–L2719 |
| `bun_install_types.bzl` `_repository_eql` | `src/install_types/resolver_hooks.rs` L1035–L1046 |
| `bun_install_types.bzl` `_repository_order` | `src/install_types/resolver_hooks.rs` L996–L1012 |
| `bun_install_types.bzl` `resolution_from_text_lockfile` | `src/install/resolution.rs` L161–L252 |
| `bun_install_types.bzl` `resolution_order` | `src/install/resolution.rs` L358–L383; `src/install_types/resolver_hooks.rs` L1089–L1092 |
| `bun_install_types.bzl` `resolution_eql` | `src/install/resolution.rs` L497–L534; `src/install_types/resolver_hooks.rs` L1085–L1087 |
| `bun_install_types.bzl` `resolution_satisfies_dependency_version` | `src/install/resolution.rs` L25–L52 |
| `bun_install_types.bzl` `_has_suffix_ignore_ascii_case` | `src/install/dependency.rs` L429–L432 |
| `bun_install_types.bzl` `is_tarball` | `src/install/dependency.rs` L420–L432 |
| `bun_install_types.bzl` `is_remote_tarball` | `src/install/dependency.rs` L434–L438 |
| `bun_install_types.bzl` `_is_scp_like_path` | `src/install/dependency.rs` L354–L391 |
| `bun_install_types.bzl` `_is_github_tarball_path` | `src/install/dependency.rs` L393–L418 |
| `bun_install_types.bzl` `_is_github_shorthand` | `src/install/hosted_git_info.rs` L544–L601 |
| `bun_install_types.bzl` `_hosted_git_tag` | `src/install/hosted_git_info.rs` L231–L326; `src/install/dependency.rs` L1635–L1649 |
| `bun_install_types.bzl` `_is_dist_tag_with_leading_digit` | `src/install/dependency.rs` L440–L469 |
| `bun_install_types.bzl` `_split_npm_alias` | `src/install/dependency.rs` L1191–L1199 |
| `bun_install_types.bzl` `version_tag_infer` | `src/install/dependency.rs` L794–L1113 |
| `bun_install_types.bzl` `_infer` | `src/install/dependency.rs` L794–L1113 |
| `bun_install_types.bzl` `_is_range_after_npm_protocol` | `src/install/dependency.rs` L1201–L1208 |
| `bun_install_types.bzl` `_trim` | `src/semver/Version.rs` L166–L174; `src/install/dependency.rs` L1610–L1623 |
| `bun_install_types.bzl` `_trim_literal` | `src/install/dependency.rs` L1140–L1145 |
| `bun_install_types.bzl` `_version_value` | `src/install_types/resolver_hooks.rs` L439–L444 |
| `bun_install_types.bzl` `dependency_version` | `src/install_types/resolver_hooks.rs` L405–L444 |
| `bun_install_types.bzl` `dependency_parse` | `src/install/dependency.rs` L1147–L1189; `src/install/dependency.rs` L1229–L1625 |
| `bun_install_types.bzl` `split_name_and_maybe_version` | `src/install/dependency.rs` L485–L516 |
| `bun_install_types.bzl` `split_name_and_version` | `src/install/dependency.rs` L529–L532 |
| `bun_install_types.bzl` `is_safe_install_folder_name` | `src/install/dependency.rs` L570–L596 |
| `bun_lockfile.bzl` `_refusal` | `src/install/lockfile/bun.lock.rs` L1806–L1811 |
| `bun_lockfile.bzl` `_failure` | `src/install/lockfile/bun.lock.rs` L3302–L3345 |
| `bun_lockfile.bzl` `is_valid` | `src/install/lockfile/bun.lock.rs` L3269–L3270 |
| `bun_lockfile.bzl` `_meta` | `src/install/lockfile/bun.lock.rs` L2593–L2604; `src/install/lockfile/Package/Meta.rs` L51–L66 |
| `bun_lockfile.bzl` `_package` | `src/install/lockfile/Package.rs` L244–L282 |
| `bun_lockfile.bzl` `_dependency` | `src/install_types/resolver_hooks.rs` L517–L528 |
| `bun_lockfile.bzl` `dependency_ids` | `src/install_types/resolver_hooks.rs` L133–L140 |
| `bun_lockfile.bzl` `_parse_catalog` | `src/install/lockfile/bun.lock.rs` L1727–L1795 |
| `bun_lockfile.bzl` `_catalog_find` | `src/install/lockfile/CatalogMap.rs` L54–L115 |
| `bun_lockfile.bzl` `catalogs_resolve_range` | `src/install/lockfile/CatalogMap.rs` L195–L207 |
| `bun_lockfile.bzl` `_strip_reference` | `src/install/lockfile/CatalogMap.rs` L209–L237 |
| `bun_lockfile.bzl` `_parse_package_segment` | `src/install/lockfile/override_selector.rs` L25–L52 |
| `bun_lockfile.bzl` `_lockfile_range` | `src/install/lockfile/OverrideMap.rs` L1081–L1116 |
| `bun_lockfile.bzl` `_put_lockfile_rule` | `src/install/lockfile/OverrideMap.rs` L671–L737; `src/install/lockfile/OverrideMap.rs` L644–L668 |
| `bun_lockfile.bzl` `_parse_overrides` | `src/install/lockfile/bun.lock.rs` L1934–L2035 |
| `bun_lockfile.bzl` `overrides_has_rule_for_name` | `src/install/lockfile/OverrideMap.rs` L446–L449 |
| `bun_lockfile.bzl` `overrides_contains_name` | `src/install/lockfile/OverrideMap.rs` L422–L434 |
| `bun_lockfile.bzl` `_is_npm_alias` | `src/install/lockfile/OverrideMap.rs` L74–L77 |
| `bun_lockfile.bzl` `_range_selects` | `src/install/lockfile/OverrideMap.rs` L88–L114 |
| `bun_lockfile.bzl` `_cmp_range_text` | `src/install/lockfile/OverrideMap.rs` L116–L128 |
| `bun_lockfile.bzl` `package_version` | `src/install/lockfile.rs` L831–L843 |
| `bun_lockfile.bzl` `_owner_package_id` | `src/install/lockfile/OverrideMap.rs` L395–L419 |
| `bun_lockfile.bzl` `_scoped_rule_for` | `src/install/lockfile/OverrideMap.rs` L307–L369 |
| `bun_lockfile.bzl` `is_overridden_dependency` | `src/install/lockfile.rs` L1145–L1148; `src/install/lockfile/OverrideMap.rs` L234–L297 |
| `bun_lockfile.bzl` `_index_insert` | `src/install/lockfile.rs` L3205–L3226; `src/install/lockfile.rs` L2713–L2729 |
| `bun_lockfile.bzl` `_append_package_dedupe` | `src/install/lockfile.rs` L2684–L2711 |
| `bun_lockfile.bzl` `_parse_append_dependencies` | `src/install/lockfile/bun.lock.rs` L3347–L3543 |
| `bun_lockfile.bzl` `_workspace_obj` | `src/install/lockfile/bun.lock.rs` L2225–L2235; `src/install/lockfile/bun.lock.rs` L2284–L2294 |
| `bun_lockfile.bzl` `_row_obj` | `src/install/lockfile/bun.lock.rs` L2565–L2587 |
| `bun_lockfile.bzl` `_find_resolution` | `src/install/lockfile/bun.lock.rs` L1573–L1662 |
| `bun_lockfile.bzl` `_peer_candidate_name` | `src/install/lockfile/bun.lock.rs` L3208–L3223 |
| `bun_lockfile.bzl` `version_based_peer_range` | `src/install/lockfile/bun.lock.rs` L3172–L3206 |
| `bun_lockfile.bzl` `resolve_peer_dep_by_range` | `src/install/lockfile/bun.lock.rs` L3225–L3241 |
| `bun_lockfile.bzl` `resolve_peer_dep_version_based` | `src/install/lockfile/bun.lock.rs` L3045–L3085 |
| `bun_lockfile.bzl` `linked_workspace_path` | `src/install/lockfile.rs` L2218–L2256 |
| `bun_lockfile.bzl` `may_stay_unresolved` | `src/install/lockfile/bun.lock.rs` L3297–L3300 |
| `bun_lockfile.bzl` `_dependency_resolution_failure` | `src/install/lockfile/bun.lock.rs` L3302–L3345 |
| `bun_lockfile.bzl` `_integrity_is_supported` | `src/install/integrity.rs` L88–L120; `src/install/integrity.rs` L291–L324 |
| `bun_lockfile.bzl` `load_lockfile` | `src/install/lockfile/bun.lock.rs` L1797–L3034 |
| `bun_lockfile.bzl` `_resolve_rows` | `src/install/lockfile/bun.lock.rs` L2765–L3025 |
| `bun_lockfile.bzl` `tag_workspace_links` | `src/install/lockfile.rs` L2313–L2429 |
| `bun_lockfile.bzl` `rebind_peers_to_printed_packages` | `src/install/lockfile/bun.lock.rs` L3243–L3295 |
| `bun_lockfile.bzl` `lockfile_resolve` | `src/install/lockfile.rs` L1615–L1625 |
| `bun_lockfile.bzl` `_peer_provider` | `src/install/lockfile/reachable.rs` L190–L221 |
| `bun_lockfile.bzl` `_packages_without_peer_provider` | `src/install/lockfile/reachable.rs` L223–L254 |
| `bun_lockfile.bzl` `_packages_reached_without_peer_provider` | `src/install/lockfile/reachable.rs` L256–L284 |
| `bun_lockfile.bzl` `_collect` | `src/install/lockfile/bun.lock.rs` L3135–L3169 |
| `bun_lockfile.bzl` `shared_version` | `src/install/lockfile/bun.lock.rs` L3102–L3133 |
| `bun_lockfile.bzl` `is_weak_peer` | `src/install/lockfile.rs` L845–L858 |
| `bun_lockfile.bzl` `_held_at_load` | `src/install/lockfile.rs` L2296–L2311 |
| `bun_lockfile.bzl` `_clone_dependency` | `src/install/dependency.rs` L185–L239 |
| `bun_lockfile.bzl` `_clone_package` | `src/install/lockfile/Package.rs` L423–L566 |
| `bun_lockfile.bzl` `_peer_on_last_copy` | `src/install/lockfile.rs` L1540–L1555 |
| `bun_lockfile.bzl` `lockfile_clean` | `src/install/PackageManager/install_with_manager.rs` L2378–L2410; `src/install/lockfile.rs` L1236–L1436; `src/install/lockfile.rs` L1557–L1608 |
| `bun_tree.bzl` `_result` | `src/install/lockfile/Tree.rs` L148–L171 |
| `bun_tree.bzl` `_in_slice` | `src/install_types/resolver_hooks.rs` L105–L110 |
| `bun_tree.bzl` `_name_is_single_path_entry` | `src/install/PackageInstaller.rs` L564–L574 |
| `bun_tree.bzl` `_alias_is_safe_install_target` | `src/install/PackageInstaller.rs` L576–L589; `src/install/lockfile/Tree.rs` L1727–L1745 |
| `bun_tree.bzl` `is_unlinked_member` | `src/install/lockfile/Tree.rs` L95–L112 |
| `bun_tree.bzl` `bind_served_peers` | `src/install/lockfile/Tree.rs` L814–L834 |
| `bun_tree.bzl` `_builder` | `src/install/lockfile/Tree.rs` L501–L565; `src/install/lockfile.rs` L1657–L1699 |
| `bun_tree.bzl` `_with_peers` | `src/install/lockfile/Tree.rs` L606–L618 |
| `bun_tree.bzl` `_regular_targets` | `src/install/lockfile/Tree.rs` L745–L758 |
| `bun_tree.bzl` `_probes_begin` | `src/install/lockfile/Tree.rs` L590–L683 |
| `bun_tree.bzl` `_is_hidden_by` | `src/install/lockfile/Tree.rs` L685–L742 |
| `bun_tree.bzl` `_repeating_period` | `src/install/lockfile/Tree.rs` L777–L812 |
| `bun_tree.bzl` `_peer_by_version` | `src/install/lockfile/Tree.rs` L855–L869 |
| `bun_tree.bzl` `_bind_peer` | `src/install/lockfile/Tree.rs` L871–L883 |
| `bun_tree.bzl` `_bind_pending_peers` | `src/install/lockfile/Tree.rs` L843–L849 |
| `bun_tree.bzl` `_hoist_root_resolves_elsewhere` | `src/install/lockfile/Tree.rs` L2053–L2143 |
| `bun_tree.bzl` `_hoist_level` | `src/install/lockfile/Tree.rs` L1782–L2016 |
| `bun_tree.bzl` `_hoist_bottom` | `src/install/lockfile/Tree.rs` L2018–L2050 |
| `bun_tree.bzl` `_hoist_dependency` | `src/install/lockfile/Tree.rs` L1778–L2051 |
| `bun_tree.bzl` `_process_subtree` | `src/install/lockfile/Tree.rs` L1411–L1776 |
| `bun_tree.bzl` `hoist` | `src/install/lockfile.rs` L1645–L1725; `src/install/lockfile/Tree.rs` L1250–L1303 |
| `bun_tree.bzl` `is_filtered_dependency_or_workspace` | `src/install/lockfile/Tree.rs` L1313–L1405 |
| `bun_isolated_store.bzl` `_dependency_is_contained_folder` | `src/install/isolated_install.rs` L392–L405 |
| `bun_isolated_store.bzl` `contained_folders` | `src/install/isolated_install.rs` L407–L451 |
| `bun_isolated_store.bzl` `_leaking_peers` | `src/install/isolated_install.rs` L561–L672 |
| `bun_isolated_store.bzl` `_sorted_peers` | `src/install/isolated_install/Store.rs` L209–L211 |
| `bun_isolated_store.bzl` `_insert_peer` | `src/install/isolated_install/Store.rs` L234–L245; `src/install/isolated_install/Store.rs` L635–L656 |
| `bun_isolated_store.bzl` `_peers_eql` | `src/install/isolated_install/Store.rs` L218–L232 |
| `bun_isolated_store.bzl` `_named` | `src/install/isolated_install.rs` L471–L492 |
| `bun_isolated_store.bzl` `build_store` | `src/install/isolated_install.rs` L510–L1470; `src/install/isolated_install.rs` L494–L508 |
| `resolve.bzl` `_error` | the adapter (research R4) |
| `resolve.bzl` `unsupported_reason` | the adapter (research R4) |
| `resolve.bzl` `_target_safe` | the adapter (research R4) |
| `resolve.bzl` `_holder_path` | the adapter (research R4) |
| `resolve.bzl` `_entry_key` | the adapter (research R4) |
| `resolve.bzl` `_class_graph` | the adapter (research R4) |
| `resolve.bzl` `_reached` | the adapter (research R4) |
| `resolve.bzl` `_ids` | the adapter (research R4) |
| `resolve.bzl` `_label` | the adapter (research R4) |
| `resolve.bzl` `resolve` | the adapter (research R4) |

## Part 3: Decisions

### R1. Structure: one Starlark file per Bun stage

**Decision**: the resolver becomes five private files, each carrying over one Bun file's part with
the same function structure, each function's docstring citing `<file> L<a>–L<b> @ bun-v1.4.4`:

| Ruleset file | Carries over |
|---|---|
| `bun/private/bun_semver.bzl` | SEMVER: version parse and order, npm range parse, `satisfies` |
| `bun/private/bun_install_types.bzl` | HOOKS `Behavior`, `Libc`; META `is_disabled` with Bun's `os`/`arch` matching; LOCKFILE `DepSorter` |
| `bun/private/bun_lockfile.bzl` | LOCK `parse_into_binary_lockfile`, `parse_append_dependencies`, `PkgMap::find_resolution`, peer-version helpers, `shared_version`; LOCKFILE `append_package_dedupe`, `resolve`, `clean_with_logger`; REACH |
| `bun/private/bun_tree.bzl` | TREE hoisting, `bind_served_peers`, `is_filtered_dependency_or_workspace`; PRUNED |
| `bun/private/bun_isolated_store.bzl` | ISO `contained_folders`, `build_store` (both passes) |

`resolve.bzl` keeps its name and its output (`struct(instances, links, members)`, consumed
unchanged by `npm_extension.bzl`, `npm_repositories.bzl`, `run.bzl`) and becomes the adapter from
Bun's store to it (R4). `lockfile.bzl` keeps JSONC decoding, the version check and the diagnostics;
the new accesses get `# L<n>` IDs (Part 4).

**Rationale**: P1 asks for the same structure; one file per Bun file makes "diff Bun's cited lines
between tags" (US3) a file-by-file review. Bun's packages, dependencies and resolutions are arrays
indexed by IDs; the Starlark carry-over keeps them as lists indexed by the same IDs, so a Bun line
and its carry-over read alike.

**Alternatives**: patch `resolve.bzl` per difference (the feature-003 approach the user rejected);
derive bindings from the hoisted keys alone — rejected: S2 shows bindings are per package, not per
key (BC-6).

**Starlark constraints**: no `while` and no recursion; each Bun loop becomes a `for` over
`range(_LIMIT)` with an explicit stack or queue, as `resolve.bzl` does today. Bun's hash maps keyed
by hashes become dicts keyed by the hashed value.

### R2. Stages carried over in Bun's order

load (S1, S2) → `resolve` (S3–S5) → `clean` (S6) → `build_store` (S7, S8), per platform class
(R3). No stage is merged or reordered; S6 is read in full while carried over and either carried
over or recorded as binding-neutral, with lines.

### R3. Target platforms: one store per platform class (ID-2)

Bun filters by the host (S7). The ruleset selects by target platform (ID-2), so it computes the
store for each **platform class**: the tuples `(os, cpu, libc)` of `platforms.bzl` (every `NPM_OS`
× `NPM_CPU`, `libc` ∈ {glibc, musl, unconstrained} on Linux, none elsewhere, plus "unmapped") are
grouped by the set of packages `is_disabled` leaves out; `build_store` runs once per group. Linux
with `:unconstrained` uses Bun's `Libc::ALL` (every variant matches). Matching uses Bun's
`OperatingSystem`/`Architecture`/`Libc` `is_match`, not npm-install-checks (`platforms.bzl`
`check_list` stays for the toolchain only, or is replaced where the two agree; the canary C-OSCPU
and C-LIBC stay).

**Rationale**: the only way to have Bun's result for every target platform, including peers bound
differently where a disabled package was the provider. A lockfile with no restricted package has one
class, so the common case costs one store.

**Alternatives**: one store, platform conditions on edges (today's `_closure`) — rejected: wrong
when a disabled package changes a peer binding or a dedupe.

### R4. Adapter to today's output

`resolve.bzl` maps each store entry (union over classes, keyed by package and peer bindings) to an
instance: `name`, `version`, `store_name`, `key` (one key of the package, for diagnostics),
`edges` (alias → instance), `peers`, `status`. `links[path][alias]` keep `closure` (reached in
every class) and `optional` (reached in some classes), each condition being the tuples of those
classes written as `[os, cpu, libc]` requirements, which `npm_repositories.bzl` already turns into
`select()`. Instance IDs keep the form `name@version__<h>` (not public API: "Repositories named
`<name>__...` and other targets of the hub are not public API", `_NPM_DOC`).

**Unfetched entries** (`unsupported_reason`): the store links them and their dependencies like any
other (Bun installs them); the reason still makes the instance's target fail analysis and tags
links `manual`, as today. Today their dependencies are not followed; that becomes a non-difference
in the graph and changes no generated target name.

### R5. npm ranges: carry over Bun's semver

S3, S5 and the hoister compare versions with ranges (`satisfies_dependency_version`; TREE L659,
L716, L1717, L1876). `bun_semver.bzl` carries over SEMVER's version parse/order and npm query
parse/`satisfies` (`||`, hyphen, x-ranges, `~`, `^`, comparators, prerelease rule), only the parts
these call. Unit tests take their cases from Bun's own semver tests at the tag
(`test/cli/install/semver.test.ts`), each case cited
with its line at the tag.

**Alternatives**: `semver.bzl` (exact versions only) — insufficient; a third-party Starlark semver —
none in bazelbuild/bazel-contrib (constitution V).

### R6. The oracle: the pinned Bun's isolated install, run in the test

`bun install --frozen-lockfile --ignore-scripts --linker isolated --registry=<loopback>` in a copy of
the project under `TEST_TMPDIR`, with an empty `BUN_INSTALL_CACHE_DIR`, the Bun being the test's own
runtime (`process.execPath`: the registered target toolchain's Bun, constitution III), the loopback
registry of `bun/tests/support/npm_registry.ts` on `FIXTURE_PORT` serving the fixture archives (and a
project's own archives, e.g. `fixtures/jsx/archives`). `--frozen-lockfile` makes Bun fail rather than
re-resolve, so the oracle links exactly the committed lockfile. E1: all 27 fixture projects install
this way except `jsx`, whose archives the experiment did not serve.

### R7. Extracting Bun's graph (DOC-ISO layout)

Holders: the project root and each workspace path of the lockfile's `workspaces`; each store
directory `node_modules/.bun/<dir>` except `node_modules/.bun/node_modules` (hidden hoist, D1).
For each holder, each symlink in its `node_modules` (scoped names one level down; `.bin` and dot
entries skipped) is a link; its `realpath` is a store directory (target = that entry) or a
workspace directory (target = that workspace). An entry's identity is the `name` and `version` of
the `package.json` in `node_modules/.bun/<dir>/node_modules/<name>` (npm's format), never parsed
from the directory name. On Windows `realpath` resolves Bun's junctions the same way.

### R8. The ruleset's graph and the comparison

A dev-only extension (extending `fixture_results.bzl`) writes, for every project, the ruleset's
graph per platform class as JSON (contract: [contracts/conformance-graph.md](contracts/conformance-graph.md)),
from `resolve.bzl`'s output — the same function the hub uses. The test picks the class of the host
(`process.platform`, `process.arch`, and on Linux the C library as canary C-LIBC detects it).

Equality (FR-008): both graphs are labelled digraphs (holders labelled by path, entries by
`name@version`, edges by dependency name). The test refines a partition of the disjoint union
(start: labels; refine by sorted `(edge name, class of target)`) until stable; the graphs are equal
iff every class has as many Bun nodes as ruleset nodes and every holder's class holds one node of
each side. This compares entry counts (a package with two peer contexts must be two entries on both
sides) without relying on either side's naming. A failure prints, per FR-012, the project, the first
holder or entry whose links differ, the dependency name, and both targets as `name@version` with
their own links (peer bindings).

**Red mode** (FR-011): `RULES_BUN_CONFORMANCE_RED=1` redirects one edge of the ruleset's graph of a
fixed project to another entry; the test must fail naming it.

### R9. Coverage

The test's projects are every directory under `bun/tests/npm/fixtures/` holding a `bun.lock`
(the corpus included, R11), `bun/tests/npm/scale/`, each `bun.lock` under
`bun/tests/integration/workspaces/`, and the 1.4.2-written lockfiles under
`bun/tests/npm/conformance/bun_1_4_2/` (R10). The extension and the test enumerate the same directories; a
project present on one side only fails the test (FR-009, US2-4). A project the oracle cannot install
(e.g. `manifest_mismatch`, whose `package.json` disagrees with the lockfile on purpose) is listed in
the test with its reason, and the list is asserted exactly.

### R10. Bun 1.4.2 (US5)

1.4.2's `build_store` differs from 1.4.4's in 965 changed lines (no `shared_version`, other peer
rules); both write `lockfileVersion` 1/2/3 alike (F004 research), so the ruleset cannot tell from a
lockfile which Bun wrote it, and carries over 1.4.4 only. The 1.4.2-written lockfiles are therefore
compared twice, each run using only its own registered toolchain's Bun: `conformance_test` (Bun
1.4.4) installs them like any project, and `conformance_1_4_2_test` installs them with Bun 1.4.2.
Both must equal the ruleset's graph. When only the 1.4.2 run differs, the two Bun versions link the
lockfile differently: the 1.4.2 test fails with "Bun 1.4.2 links <project> differently from Bun 1.4.4,
which the ruleset follows" (the spec's Edge Case: work stops and the user is told), and neither side
is changed to pass.

Toolchain (constitution III): a dev-only `bun_dev.toolchain(name = "bun_1_4_2", bun_version = "1.4.2")`
fetches 1.4.2 with `versions.bzl`'s integrity; `bun/tests/npm/conformance/BUILD.bazel` declares
`toolchain()` targets for `//bun/toolchain:target_type` on those archives, constrained by a dev-only
`constraint_setting` `bun_version` with value `bun_1_4_2`, registered dev-only **before**
`@bun_toolchains//:all`; a platform `host_bun_1_4_2` (`parents = ["@platforms//host"]`, plus that
value) selects them. The 1.4.2 test has `target_compatible_with` that value, so `bazel test //...`
skips it, and CI runs it with `--platforms=//bun/tests/npm/conformance:host_bun_1_4_2` on Linux,
macOS and Windows. Its oracle is then a registered toolchain's Bun.

Lockfiles: `write_lockfiles.ts` gains `--bun-1-4-2`, run by hand with Bun 1.4.2, writing
`bun/tests/npm/conformance/bun_1_4_2/<project>/bun.lock` for each corpus project 1.4.2 can write;
the others are listed with the reason (unlinked workspace: 1.4.2's loader rejects it, LOCK-142
L2479–2490; `unresolved`: 1.4.2 does not write it).

### R11. The edge-case corpus

New projects in `write_lockfiles.ts`, written under `bun/tests/npm/fixtures/conformance_<case>/`
(so R9 and `fixture_results` cover them unchanged), each with a `check` asserting the lockfile form
it exists for. New archives are packed by `pack.ts`, never served by altering a packument, so the
oracle's tarballs carry the dependencies the lockfile records.

| Project | FR-009 layout | Expected difference before (BC) |
|---|---|---|
| `conformance_alias_workspace` | workspace `lib` and `@scope/lib`, root aliases `lib: npm:a@1.0.0`, `@scope/lib: npm:c@1.0.0` (PRIOR U4) | BC-2 |
| `conformance_unresolved` | package and workspace optional dependencies listed under `unresolved` (PRIOR E1, E7, E9; archive `opt-user@1.0.0`) | BC-1 |
| `conformance_unbound` | optional and peer dependencies without a key, root and workspace (PRIOR E3, E10) | BC-3 |
| `conformance_registry_to_workspace` | a registry package depending on a workspace member's name, resolved to the member | BC-4 |
| `conformance_unprovided_peer` | a non-optional and an optional peer nothing provides | BC-5 |
| `conformance_nested` | nested and hoisted keys of one `name@version` with different walks (`dependency_conflict`'s shape, deeper) | BC-6 |
| `conformance_peer_contexts` | one package reached under two peer providers (two entries) and under one (deduped) | — |
| `conformance_shared_peer` | two packages with an unprovided peer on one name (S5) | — |
| `conformance_platform` | a non-optional and an optional dependency restricted to another OS | BC-7 |
| `conformance_overrides`, `conformance_catalog` | an override of a peer's range; a `catalog:` peer | — |

The existing `overrides_*`, `catalog`, `hoisted`, `workspace*`, `missing_peer` fixtures also count.

### R12. Canaries

Each new field or key form of Part 4 gets a canary in `bun/tests/canary/npm`, using `support.ts`
(`runInstall`, `red`, `canaryFail`), naming the reader it protects, with a red mode. PRIOR R5's
C-UNRESOLVED and C-UNLINKED are taken over with the reader names updated to the new files.

### R13. Performance

The existing bound holds: `bun/tests/integration/scale.test.ts` (feature 003 SC-010) asserts the
`scale` hub's extension evaluation (2,000 packages) at most `MAX_EVALUATION_MS` = 10,000 ms and
prints the measurement. The branch keeps that test passing unchanged; its printed time on `main` and
on the branch goes into the PR, with `--starlark_cpu_profile` output if the branch is slower. If the
bound fails, work stops and the measurement is reported; no shortcut that departs from Bun's
structure is taken to meet it.

### R14. Behavior changes and existing tests

Each BC of Part 5 is first recorded as a conformance difference (`tdd-log.md`), then fixed by the
carry-over. Existing tests asserting a non-Bun behavior are changed and listed (FR-016): at least
`missing_peer` (fails today, links nothing for `state` after), the `resolve_test.bzl` cases on
per-key instances of one `name@version` (BC-6), `_NPM_DOC`'s "A non-optional dependency is carried
whatever its `os`, `cpu` and `libc` say" (BC-7).

## Part 4: Fields and key forms the carried-over algorithm reads

Existing accesses L1–L22 (feature 003 research Part 3) and C-LIBC (feature 004) keep their canaries.
New accesses:

| ID | Field or key form | Bun reads at | Evidence | Canary |
|---|---|---|---|---|
| L23 | info `unresolved` (list of strings) | LOCK L3372–3400, L3531–3537, L3027–3031 | PRIOR E1, E8; E5 (written only while the tree holds a package of the name, LOCK L302–L320) | C-UNRESOLVED |
| L24 | workspace `unresolved` | same, via L2225/L2284 | PRIOR E2, E7; E5 | C-UNRESOLVED |
| L25 | key `./<name>/<dep>` of an unlinked workspace | LOCK L2864–2895, TREE L379–388 | PRIOR E4, E5, U4; E6 | C-UNLINKED |
| L26 | info `bundled: true` | LOCK L2351, L1575–1621 | E7 (`conformance_bundled`) | C-BUNDLED |
| L27 | top-level `packageExtensions` | LOCK L1928–1931 | E8: the package rows already carry the extended dependencies; the top-level field lists only their names, so the carry-over does not read it | C-PKGEXT (pins that the rows carry them) |
| L28 | workspace `version` (peer → workspace by range) | LOCK L2162, L2793–2807 | E9 | C-WSVERSION |
| — | top-level `patchedDependencies` | LOCK L1899 | read by Bun but decides no binding (a patch changes a package's files, not which package a dependency binds); rules_bun keeps treating a patched package as unsupported (feature 003 FR-010, canary C-PATCHED) | C-PATCHED (existing) |
| L29 | order of `packages` rows (equal evidence: later row wins) | LOCK L2929, L2993 | E10: sorted by the parent path's depth, the parent path, then the name (writer LOCK L506–L508, L646) | C-ROWORDER |
| L30 | `dependencies`, `optionalDependencies`, `peerDependencies` ranges (read as npm ranges, R5) | LOCK L3347–3543, L3174–3208 | existing fixtures; E11 (`range-user@1.0.0`) | C-INFODEPS / C-PEERS (range tests) |
| L31 | the info object in slot 1 of a row that is not an npm version (`file:`, tarball URL, git, GitHub, `link:`) | LOCK L2346, L2557–L2591 (writer L720–L728) | `unsupported` (`local`, `tb`); E12 | C-ROWINFO (T075) |
| L32 | a row's `devDependencies` | LOCK L1478–L1483, L3405–L3490 (writer L950–L1004 for a folder, resolver_hooks.rs L1251–L1256 `Features::FOLDER`) | E13 | C-ROWDEVDEPS (T075) |
| L33 | a workspace's `optionalPeers` | LOCK L3372–L3400 (root and workspaces, L2225, L2284; writer L1184–L1240) | E14 | C-WSOPTPEERS (T075) |

The list is closed (T050): every `root.get(...)`/`value.get(...)`/`info.get(...)` of LOCK
L1797–3543 at `bun-v1.4.4`, and each slot of a `packages` row, is an access with a canary or read by
Bun and deciding no binding:

| Bun reads | Lines | Access |
|---|---|---|
| `lockfileVersion` | L1815 | L2 |
| `configVersion` | L1861 | decides no binding (the default linker of a later install; this one is `--linker isolated`) |
| `trustedDependencies` | L1872 | decides no binding (lifecycle scripts, ID-1) |
| `patchedDependencies` | L1899 | L20 (a patched package is unfetched, ID-4) |
| `packageExtensions` | L1928 | L27 (not read: the rows carry the extended dependencies) |
| `overrides` | L1934 | L18 |
| `catalog`, `catalogs` | L2037, L2056 | L19 |
| `workspaces` and its keys | L2100 | L3, L4 |
| a workspace's `name` | L2137, L2211, L2275, L3496 | L5 |
| a workspace's `version` | L2162 | L28 |
| `packages`, its keys and row order | L2308, L2929, L2993 | L7, L8, L21, L25, L29 |
| slot 0 | L2375–L2432 | L9, L22 |
| an npm row's slots 1–3 | L2433–L2476, L2636–L2669 | L10, L11, L12 |
| slot 1 of any other row | L2557–L2591 | L31 |
| `bundled` | L2351 | L26 |
| `os`, `cpu`, `libc` | L2594–L2602 | L15, C-LIBC |
| `hasInstallScript` | L2606 | decides no binding (lifecycle scripts, ID-1) |
| `bin`, `binDir` | L1714–L1721 | L16 (`binDir` decides no binding: which files are bins) |
| the root row's `{ bin, binDir }` | L2612–L2634 | decides no binding (the root's own bins) |
| a git or GitHub row's `.bun-tag` | L2671–L2720 | decides no binding ("Not carried over") |
| `dependencies`, `devDependencies`, `optionalDependencies`, `peerDependencies` of a row or workspace | L3405–L3490 | L6, L13, L14, L30, L32 |
| `optionalPeers`, `unresolved` | L3372–L3400 | L14, L23, L24, L33 |

No access the carry-over reads is without a canary (constitution V).

## Part 5: Differences found so far

BC-1 to BC-5 are the spec's. Found while planning:

- **BC-6 (new): one package per `name@version`**. Bun keeps one package per resolution (S1) and binds
  its dependencies once (S2); the ruleset makes one instance per key. `dependency_conflict` (E2): Bun
  links `y@1.0.0 → x@1.0.0 → b@1.0.0` (the `z/x` row's walk to the root, `WalkedToRoot`, outranks
  `y/x`'s `Walked` to `y/b`), the ruleset `y`'s `x@1.0.0 → b@2.0.0`.
- **BC-7 (new): non-optional dependencies on another platform**. Bun skips a dependency whose package
  `is_disabled` for the platform, optional or not (S7; `libc` only for optional ones); `_NPM_DOC` says
  a non-optional one is carried whatever its `os`, `cpu` and `libc` say.

## Part 6: Decisions for the user

- **D1 (spec)**: Bun's isolated install also writes `node_modules/.bun/node_modules` (hidden hoisting,
  E2), through which a store package's undeclared import resolves; the ruleset's isolation tests
  (`phantom`, `undeclared`) assert the opposite. FR-008's graph excludes it, but US1's "nothing more"
  reads as including it. Proposed: add **ID-3 No hoisting**: `node_modules/.bun/node_modules` and the
  root `node_modules` fallback are not reproduced; the graph is FR-008's.
- **D2 (spec)**: add BC-6 and BC-7 to Behavior Changes (the spec requires listing a difference before
  it is fixed).
- **D3 (spec)**: R4's unfetched entries: their dependencies get instances (not fetched unless a
  target needs them). This changes no target name; confirm it is not a Behavior Change to list.

**Answers (user, 2026-10-29, plan gate)**: D1 approved (ID-3 No hoisting, from Bazel's declared
dependencies). D2 approved (BC-6, BC-7). D3: list it as a Behavior Change as well, so every
difference from `main` is stated.

**T017 findings (2026-10-30)**: the conformance test found BC-9 and BC-10 (spec, Behavior Changes),
both consequences of principle P1 the user approved (link what the pinned Bun links), so they are
listed and fixed under it. BC-5 shows on `conformance_unprovided_peer` and not on `missing_peer`
(the graph does not carry `main`'s analysis failure); `missing_peer` is covered by its FR-016 test
change at T048. BC-8 gets a corpus project `conformance_unfetched` (a patched package with a
dependency) so it is red before its fix.
**BC-9 and BC-10 approved by the user (2026-10-30)**, at T068.

**T072, T050 and BC-4 decided by the user (2026-11-21)**: ID-4 (unfetched entries fail analysis,
constitution III) is an intentional difference; L31–L33 get canaries with red modes; BC-4 links by
path, and a target that reaches such a link without declaring the member fails analysis naming it
(T073), rather than a target dependency (a member that depends on the package would form a Bazel
cycle) or a silent run-time failure.

## Part 7: Evidence log

Scripts: `/tmp/bun006c-scripts/oracle.ts` (copies a project, serves the fixture archives on
`FIXTURE_PORT`, runs `bun install --frozen-lockfile --ignore-scripts --linker isolated`, prints each
holder's links). Sources: `/tmp/bun006-src/` (files of Part 1 fetched at the tags).

- **E1**: oracle over every project of `bun/tests/npm/fixtures/`: 27 of 28 install; `jsx` fails
  ("failed to download scheduler@0.27.0: 404") because its archives (`fixtures/jsx/archives`) were not
  served.
- **E2**: `dependency_conflict`: root links `a, b → b@1.0.0, x → x@2.0.0, y, z`; `y@1.0.0` links
  `b → b@2.0.0, x → x@1.0.0`; `z@1.0.0` links `x → x@1.0.0`; one store entry `x@1.0.0` links
  `b → b@1.0.0`; `node_modules/.bun/node_modules` holds `a, b, x, y, z`.
- **E3**: `diff` of `build_store` between `bun-v1.4.2` and `bun-v1.4.4` ISO: 965 changed lines;
  `shared_version` absent at 1.4.2.
- **E4**: LOCK L1797–3543 field reads: `lockfileVersion` L1815, `configVersion` L1861,
  `trustedDependencies` L1872, `patchedDependencies` L1899, `packageExtensions` L1928, `overrides`
  L1934, `catalog` L2037, `catalogs` L2056, `workspaces` L2100, `name` L2137, `version` L2162,
  `packages` L2308, `bundled` L2351, `os`/`cpu`/`libc` L2594–2602, `hasInstallScript` L2606,
  `optionalPeers`/`unresolved` L3372.
- **E5** (C-UNRESOLVED, T019): `opt-user@1.0.0` (optional `state ^3.0.0`) gets info
  `"unresolved": ["state"]`; the root (optional `b ^3.0.0`) and workspace `w` (optional `q ^3.0.0`)
  get `"unresolved": ["b"]` and `["q"]` only while the tree holds a `b` and a `q` (from `a` and the
  root's `q`); without them Bun writes no `unresolved` (LOCK L302–L320 `unresolved_names` filters by
  a placed row of the same name).
- **E6** (C-UNLINKED, T020): root aliases `lib: npm:a@1.0.0`, `@scope/lib: npm:c@1.0.0`; workspaces
  `lib` and `@scope/lib` depending on `b@2.0.0` get keys `./lib/b` and `./@scope/lib/b` (`b@2.0.0`);
  without the aliases the keys are `lib/b` and `@scope/lib/b`.
- **E7** (C-BUNDLED, T021): `bundler@1.0.0` (`bundleDependencies: ["b"]`) gets the row
  `"bundler/b": ["b@1.0.0", "<registry>/b/-/b-1.0.0.tgz", { "bundled": true }, "sha512-…"]`, the
  info holding only `bundled`; published without `bundleDependencies`, the row's info is `{}`.
- **E8** (C-PKGEXT, T022): `packageExtensions: { "a@1.0.0": { dependencies: { c: "1.0.0" } } }` gives
  the row `a` the info `{ "dependencies": { "b": "^1.0.0", "c": "1.0.0" } }` and the top-level
  `"packageExtensions": { "a@1.0.0": { "dependencies": ["c"] } }` (names only).
- **E9** (C-WSVERSION, T023): workspace `q` with `version: "1.5.0"` is written as
  `"packages/q": { "name": "q", "version": "1.5.0" }`; member `w` with peer `q ^1.0.0` links
  `packages/w/node_modules/q` to `packages/q` (isolated linker). With `q` at `3.0.0` the link is the
  same (the key `q` binds it by name), so the canary pins the field and the link, not the version
  match alone.
- **E10** (C-ROWORDER, T024): the `conformance_alias_workspace` layout is written as `@scope/lib, app,
  b, lib, q, x, y, ./@scope/lib/b, ./lib/b, ./lib/y, @scope/lib/b, app/@scope/lib, app/lib,
  ./lib/y/x, app/@scope/lib/b, app/lib/b, app/lib/y, app/lib/y/x`, and a `--frozen-lockfile` install
  keeps the text.
- **E11** (C-INFODEPS, C-PEERS, T025): `range-user@1.0.0`'s row holds `dependencies { a: "~1.0.0", b:
  "1.0.0 - 1.9.9", c: "1.x" }`, `optionalDependencies { ident-a: "^1.0.0 || ^2.0.0" }`,
  `peerDependencies { q: ">=1.0.0 <3.0.0", state: "1.0.x" }`, as its `package.json` writes them.

- **E12** (C-ROWINFO, T075): a `file:./local` folder declaring `dependencies { c: "1.0.0" }` is
  written as `"local": ["local@file:local", { "dependencies": { "c": "1.0.0" } }]`, and a tarball URL
  dependency `tb` on `<registry>/a/-/a-1.0.0.tgz` as
  `"tb": ["a@<registry>/a/-/a-1.0.0.tgz", { "dependencies": { "b": "^1.0.0" } }, "sha512-…"]`; the
  folder declaring nothing gets `["local@file:local", {}]`.
- **E13** (C-ROWDEVDEPS, T075): a folder declaring `devDependencies { b: "1.0.0" }` is written as
  `"local": ["local@file:local", { "devDependencies": { "b": "1.0.0" } }]`, with a row `b` for
  `b@1.0.0`; declared as an ordinary dependency, it is written under `dependencies`.
- **E14** (C-WSOPTPEERS, T075): member `w` with `peerDependencies { q: "^1.0.0" }` and
  `peerDependenciesMeta { q: { optional: true } }` is written as
  `"packages/w": { "name": "w", "version": "1.0.0", "peerDependencies": { "q": "^1.0.0" },
  "optionalPeers": ["q"] }`; without the meta, no `optionalPeers`.
