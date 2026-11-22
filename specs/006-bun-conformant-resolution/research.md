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
| BASE64 | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/base64/lib.rs | the standard-base64 decoder `Integrity::parse_entry` checks a digest with: `calc_size_upper_bound` L548–L564, `calc_size_for_slice` L566–L581, `decode` L583–L641 (T147) |
| BIN | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/bin.rs (1,981 lines) | how a row's `bin` is read: `Bin::parse_append` L193–L229, `parse_append_object` L231–L263 (T144) |
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
`select()` (https://bazel.build/docs/configurable-attributes), `json.decode`, which keeps the last
value of a key an object holds twice (https://bazel.build/rules/lib/core/json, ID-13). Each is used
as documented.

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
unless Part 2 records, with lines, that it cannot. **Decided at T044: carried over in full**
(`lockfile_clean`): it drops the packages no root reaches, which can change the version a
version-based peer binds to (S3, S5), and binds weak peers after copying, so no step of it is
recorded as deciding no link.

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
| `entry_hash`, global virtual store | ISO L111–150 | directory names only |
| the `Wyhash11` of a `peer_hash`, and the integrity it starts from | ISO L1353–L1386 | `_ids` carries the peer hash as the store directory `<name>@<version>+<peer hash>` (BC-11) but hashes the peers' names and resolutions with `hash_fn` and numbers colliding hashes (same equality, no shared directory); a tarball's integrity names only an entry rules_bun does not fetch (ID-4) |
| an entry's `nested_folder` | ISO L1404, L1424, L2365–L2390 | whether the installer installs a nested folder package or links it through the package containing it; the entry and its links are the same (T054) |
| workspace filters, `packages_to_install`, `--omit` | ISO L1005–1031, TREE L1393–1404 | the ruleset links every workspace; its consumers select targets |
| lifecycle scripts, `trustedDependencies` | ISO Installer | ID-1 |
| `Wyhash` of `ctx_hash` | ISO L814–867 | replaced by the exact key it hashes (same equality, no collisions) |
| `BuilderMethod::Filter` hoisting, `keep_linked_rows`, shipped and contested rows | TREE L436–L452, L929–L1249 | the hoisted linker's install tree; the isolated linker reads the `Resolvable` trees of `Lockfile::resolve` (`build_store` reads `trees[0]` only, ISO L713–L720) |
| optional-peer omission, pruned-workspace links, workspace filters in `is_filtered_dependency_or_workspace` | TREE L1364–L1404, PRUNED L36–L53, reachable.rs L93–L137 | a default install enables dev and optional dependencies (no omission), a frozen install keeps every workspace (PRUNED L11–L16, no pruned one), and no `--filter` is given; all three then skip nothing |
| `HostedGitInfo::from_url` beyond the host, and the control-character check of a GitHub fragment | HOSTED L231–L326, L874–L1259; DEP L1356–L1359, L1376 | it chooses between the `git`, `github` and `tarball` tags of a URL, and refuses a GitHub literal it cannot parse or whose fragment holds a control character; the carry-over decides by the URL's host alone (`_hosted_git_tag`). The tag decides a binding only for a peer written as such a URL, bound to a git or GitHub resolution (RES L39–L49), which rules_bun does not fetch (FR-010) |
| the registry check of an npm row's URL | LOCK L2452–L2476, L2653–L2669 | it refuses a row whose URL is outside the configured registry and has no integrity; the configured registry comes from `bunfig.toml`, the environment and `.npmrc`, of which the ruleset reads only the `npmrc` attribute (FR-003). rules_bun refuses to fetch any row without integrity (FR-010, ID-4). Not reproduced: ID-5 (user, 2026-11-21; Part 4, "Loader refusals"; Part 6) |
| the `.bun-tag` of a git or GitHub row beyond its checks | LOCK L2671–L2720 | it is the `resolved` commit, compared only when two git rows have the same text (`Repository::eql`); read only to refuse what Bun refuses (L36, T147) |
| the version-0 branches of a `packages` row of a workspace and of the workspaces' own resolutions | LOCK L2479–L2536, L2553–L2591, L2859–L2921 | on `lockfileVersion` 0 a member is a package only through its `packages` row, which carries the member's dependencies in an object in slot 1; rules_bun does not read that object (Part 4) and fails evaluation on such a row (ID-11), so the branches are not reached. L2263's branch is carried over (`load_lockfile`: no `workspaceOnly` package on version 0), so a member without its row fails as Bun's loader fails it (L2843, T155) |
| a target `os` or `cpu` Bun does not name | CLI L37–L64 | Bun refuses such a `--os` or `--cpu`, so no Bun behavior exists. For one the hub selects on (`NPM_OS`, `NPM_CPU`: `netbsd`, `riscv64`) the adapter (ID-2) gives the value its own bit and reads a package's list for it as npm's `checkList` does, as `main` did (`platforms.bzl` `package_platforms`, `npm_only_names`, `platform_bits`; T112); a platform with no npm value gets a bit no package names that "every value" includes (`bun_install_types.bzl` `platform_value`) |

### Walks outside the carry-over (T049)

The audit of PRIOR's key walks, re-done on the branch: no code outside `bun/private/bun_*.bzl` and
the adapter `resolve.bzl` decides which package a dependency links.

| Code | Lines | What it decides |
|---|---|---|
| `lockfile.bzl` `split_key`, an entry's `segments` and `alias` | `lockfile.bzl` `split_key`, `_entry` | read for each key and kept for the lockfile tests; no resolver reads them (the loader binds by `find_resolution`, LOCK L1580–L1662) |
| `workspaces.bzl` member patterns, `compare_manifests`, `match_members` | `workspaces.bzl` | that `package.json` and `bun.lock` agree (the frozen-lockfile check, INSTALL L826–L891); no link |
| `npm_extension.bzl` first entry of each `name@version`, `packages`, `identities` | `npm_extension.bzl` `_npm_impl` | which archive is downloaded and verified for a package version; no link |
| `run.bzl` `_check_unique`, `_package_layout` | `run.bzl` | that a program gets one copy per store directory (`<name>@<version>` or `<name>@<version>+<peer hash>`, BC-11), and the store and link paths of the instances and links `resolve.bzl` gives; no binding |

### Function-level map (T055)

Each function of the rebuilt resolver and the Bun lines it carries over, as its docstring cites them
(`citations_test` checks every docstring; T054 re-reads each range at the tag, `tdd-log.md`).

**Accounting (SC-004)**: every binding-relevant step of S1–S8 is carried over by a function below,
recorded in "Not carried over" with its lines and why it decides no link (S6's `clean` is carried
over, T044), or, outside the carry-over, recorded in "Walks outside the carry-over" (T049), so 0
binding-relevant Bun steps are unaccounted.

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
| `bun_semver.bzl` `first_of_partial` (nested in `_to_range`, T128) | `src/semver/SemverQuery.rs` L710–L718 |
| `bun_semver.bzl` `_or_range` | `src/semver/SemverQuery.rs` L519–L538 |
| `bun_semver.bzl` `_and_range` | `src/semver/SemverQuery.rs` L510–L517; `src/semver/SemverQuery.rs` L324–L345 |
| `bun_semver.bzl` `_null_set_group` | `src/semver/SemverQuery.rs` L480–L486 |
| `bun_semver.bzl` `parse_query` | `src/semver/SemverQuery.rs` L767–L769; `src/semver/SemverQuery.rs` L777–L1030 |
| `bun_semver.bzl` `skip_spaces` (nested in `parse_query`, T128) | `src/semver/SemverQuery.rs` L801–L803 |
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
| `bun_lockfile.bzl` `is_valid` | `src/install_types/resolver_hooks.rs` L32 (`INVALID_PACKAGE_ID`) |
| `bun_lockfile.bzl` `_meta` | `src/install/lockfile/bun.lock.rs` L2593–L2604; `src/install/lockfile/Package/Meta.rs` L51–L66 |
| `bun_lockfile.bzl` `_package` | `src/install/lockfile/Package.rs` L244–L282 |
| `bun_lockfile.bzl` `_dependency` | `src/install_types/resolver_hooks.rs` L517–L528 |
| `bun_lockfile.bzl` `dependency_ids` | `src/install_types/resolver_hooks.rs` L133–L140 |
| `bun_lockfile.bzl` `_parse_catalog` | `src/install/lockfile/bun.lock.rs` L1727–L1795 |
| `bun_lockfile.bzl` `_catalog_find` | `src/install/lockfile/CatalogMap.rs` L54–L115 |
| `bun_lockfile.bzl` `in_group` (nested in `_catalog_find`, T128) | `src/install/lockfile/CatalogMap.rs` L83–L96 |
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
| `bun_lockfile.bzl` `_owner_package_id` | `src/install/lockfile/OverrideMap.rs` L392–L419 |
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
| `bun_lockfile.bzl` `_integrity_tag_parse` | `src/install/integrity.rs` L307–L324 |
| `bun_lockfile.bzl` `_integrity_parse_entry` | `src/install/integrity.rs` L99–L164; `src/base64/lib.rs` L548–L641 |
| `bun_lockfile.bzl` `_integrity_is_supported` | `src/install/integrity.rs` L88–L97; `src/install/integrity.rs` L290–L293 |
| `bun_lockfile.bzl` `_parse_integrity` | `src/install/lockfile/bun.lock.rs` L1688–L1711 |
| `bun_lockfile.bzl` `_is_safe_resolved_tag` | `src/install/repository.rs` L114–L123 |
| `bun_lockfile.bzl` `_row_tail` | `src/install/lockfile/bun.lock.rs` L2636–L2735 |
| `bun_lockfile.bzl` `load_lockfile` | `src/install/lockfile/bun.lock.rs` L1797–L3034 |
| `bun_lockfile.bzl` `_resolve_rows` | `src/install/lockfile/bun.lock.rs` L2765–L3025 |
| `bun_lockfile.bzl` `linked_member` (nested in `_resolve_rows`, T128) | `src/install/lockfile/bun.lock.rs` L2793–L2807 |
| `bun_lockfile.bzl` `peer_by_version` (nested in `_resolve_rows`, T128) | `src/install/lockfile/bun.lock.rs` L2809–L2819 |
| `bun_lockfile.bzl` `own_peer` (nested in `_resolve_rows`, T128) | `src/install/lockfile/bun.lock.rs` L2820–L2820 |
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
| `bun_tree.bzl` `resolves_elsewhere` (nested in `_hoist_root_resolves_elsewhere`, T128) | `src/install/lockfile/Tree.rs` L2077–L2088 |
| `bun_tree.bzl` `nested_in` (nested in `_hoist_root_resolves_elsewhere`, T128) | `src/install/lockfile/Tree.rs` L2090–L2103 |
| `bun_tree.bzl` `_hoist_level` | `src/install/lockfile/Tree.rs` L1782–L2016 |
| `bun_tree.bzl` `is_in_peer_range` (nested in `_hoist_level`, T128) | `src/install/lockfile/Tree.rs` L1870–L1881 |
| `bun_tree.bzl` `is_always_linked` (nested in `_hoist_level`, T128) | `src/install/lockfile/Tree.rs` L1882–L1884 |
| `bun_tree.bzl` `_hoist_bottom` | `src/install/lockfile/Tree.rs` L2018–L2050 |
| `bun_tree.bzl` `_hoist_dependency` | `src/install/lockfile/Tree.rs` L1778–L2051 |
| `bun_tree.bzl` `_process_subtree` | `src/install/lockfile/Tree.rs` L1411–L1776 |
| `bun_tree.bzl` `hoist_dep` (nested in `_process_subtree`, T128) | `src/install/lockfile/Tree.rs` L1526–L1535 |
| `bun_tree.bzl` `stays_on` (nested in `_process_subtree`, T128) | `src/install/lockfile/Tree.rs` L1536–L1553 |
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
| `bun_isolated_store.bzl` `is_contained_folder` (nested in `build_store`, T128) | `src/install/isolated_install.rs` L544–L544 |
| `bun_isolated_store.bzl` `is_filtered` (nested in `build_store`, T128) | `src/install/isolated_install.rs` L1035–L1044 |
| `bun_isolated_store.bzl` `is_unlinked_member` (nested in `build_store`, T128) | `src/install/isolated_install.rs` L717–L720 |
| `bun_isolated_store.bzl` `resolve_up` (nested in `build_store`, T128) | `src/install/isolated_install.rs` L829–L856 |
| `bun_isolated_store.bzl` `is_omitted_peer` (nested in `build_store`, T128) | `src/install/isolated_install.rs` L998–L1003 |
| `resolve.bzl` `_error` | the adapter (research R4) |
| `resolve.bzl` `unsupported_reason` | the adapter (research R4) |
| `resolve.bzl` `_target_safe` | the adapter (research R4) |
| `resolve.bzl` `_holder_path` | the adapter (research R4) |
| `resolve.bzl` `_entry_key` | the adapter (research R4) |
| `resolve.bzl` `_class_graph` | the adapter (research R4) |
| `resolve.bzl` `_reached` | the adapter (research R4) |
| `resolve.bzl` `_hex16` | the adapter (research R4): Bun's `{:016x}` of a peer hash |
| `resolve.bzl` `_ids` | `src/install/isolated_install/Store.rs` L450–L466; `src/install/isolated_install.rs` L1353–L1386 (the store directory `<name>@<version>+<peer hash>`, BC-11); the instance ID and the numbering of colliding hashes are the adapter (research R4) |
| `resolve.bzl` `_label` | the adapter (research R4) |
| `resolve.bzl` `_declared_key` | the adapter (research R4): the key the cleaned lockfile binds a declared dependency to, also one the store links on no class (T111); for an optional dependency under `unresolved`, `_hoisted_key`'s (T169) |
| `resolve.bzl` `_hoisted_key` | the adapter (research R4): the key `main`'s lookup found for a declared dependency, `<workspace name>/<alias>`, then `<alias>` (T169) |
| `resolve.bzl` `_differing_member` | the adapter (research R4) |
| `resolve.bzl` `class_member_conflict` | the adapter (research R4): a member link that differs by platform class (BC-4, BC-12) |
| `resolve.bzl` `resolve` | the adapter (research R4) |
| `resolve.bzl` `conditions` (nested in `resolve`, T128) | the adapter (research R4) |
| `resolve.bzl` `_mask` | the adapter (research R4) |
| `resolve.bzl` `_conditions` | the adapter (research R4) |
| `platforms.bzl` `_npm_only` | the adapter (research R3, ID-2): a bit for each `NPM_OS`/`NPM_CPU` value Bun does not name (T112) |
| `platforms.bzl` `npm_only_names` | the adapter (research R3, ID-2) |
| `platforms.bzl` `_check_list` | the adapter (research R3): npm-install-checks `checkList`, as `main` read every value |
| `platforms.bzl` `package_platforms` | the adapter (research R3, ID-2): Bun's `negatable_from_json_value` for the values Bun names, `_check_list` for the others |
| `platforms.bzl` `platform_tuples` | the adapter (research R3, ID-2): the target platforms the hub's `select()` tells apart |
| `platforms.bzl` `platform_bits` | `src/install/PackageManager/PackageManagerOptions.rs` L1174–L1176; the bits of values Bun does not name are the adapter's (T112) |
| `platforms.bzl` `platform_classes` | `src/install/lockfile/Package/Meta.rs` L70–L74 |

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
`OperatingSystem`/`Architecture`/`Libc` `is_match`, not npm-install-checks; `main`'s npm-rule
matchers (`platforms.bzl` `check_list`, `npm_repositories.bzl` `libc_matches`) are removed with their
tests (T086), since the hub selects by the resolver's platform tuples (`conditions_hold`) and no
toolchain file calls them; the canaries C-OSCPU and C-LIBC stay.

**Rationale**: the only way to have Bun's result for every target platform, including peers bound
differently where a disabled package was the provider. A lockfile with no restricted package has one
class, so the common case costs one store.

**Alternatives**: one store, platform conditions on edges (today's `_closure`) — rejected: wrong
when a disabled package changes a peer binding or a dedupe.

**Targets Bun does not name (T112)**: `NPM_OS` maps `netbsd` and `NPM_CPU` maps `riscv64` to
`@platforms` constraints, which Bun's `negatable_names!` tables do not name (resolver_hooks.rs
L795–L965) and its `--os`/`--cpu` refuse (CLI L37–L64), so Bun has no behavior for such a target.
Bun's `Negatable` reads such a value in a package's list as unrecognized, so `cpu: ["riscv64"]`
(`@esbuild/linux-riscv64`) would match no platform, including the linux/riscv64 target it is for.
The adapter gives each such value its own bit and reads a package's list for it with npm's
`checkList`, the rule `main` applied to every value (`git show main:bun/private/platforms.bzl`
`check_list`); Bun's reading still decides every value Bun names. `platforms_test.bzl`
`bun_rule_test` checks both and that every `NPM_OS`/`NPM_CPU` value is either Bun's or one of these.

**BC-13 and BC-14 on lockfiles (T096)**: Bun 1.4.4 and 1.4.2 write a package's `os` list as they
read it: `rule-linux-any` (`["linux", "any"]` in its `package.json`) gets no `os`, `rule-any-linux`
(`["any", "linux"]`) gets `"linux"` (`conformance_platform_rule`, both writers), so npm's
`checkList` and Bun's `Negatable` read a Bun-written list alike and BC-13 shows only on a lockfile
written otherwise (`bun/tests/npm/conformance/accepted/platform_rule_raw/bun.lock`, by hand,
which the conformance test compares with both oracles, T110). BC-14 shows on the
Bun-written lockfile: `rule-libc-glibc` (`libc` `glibc`, no `os`) is carried on darwin and Windows.
`platform_rule_test.bzl` checks both lockfiles on four platforms; run on `main`'s resolver it fails
on darwin and Windows (`tdd-log.md`).

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

**Declared dependencies the store links nowhere (T111)**. `_NPM_DOC`'s naming rule gives every
package the root or a workspace declares its `:node_modules/<package>` target, and `main` made one
for each (`git show main:bun/private/resolve.bzl` `_workspace_children`), while the store has a
holder edge only where it links the dependency. A declared dependency the store links on no
platform class (an optional or non-optional package no platform matches, BC-7; an optional
dependency under `unresolved`, BC-1; an optional or peer dependency without a key, BC-3, BC-5) gets
a link with no root that reaches nothing, as `main`'s link of an optional package no platform
matches reaches nothing; its bin targets are named after the package the cleaned lockfile binds
the dependency to (`resolutions[dep_id]`, LOCK L2923–L3023), when that is a package rules_bun
fetches, and are compatible with no platform. An optional dependency under `unresolved` is bound to
no package (LOCK L3027–L3031); `main` linked it to the row its lookup found (`<workspace
name>/<alias>`, then `<alias>`) and generated that row's bin targets, so its bin targets are named
after that row (`_hoisted_key`, T169: `conformance_unresolved`'s root `single-bin`, under
`unresolved`, keeps `:node_modules/single-bin/bin/single-bin` of `w`'s `single-bin@1.0.0`).
`declared_test.bzl`, the fixtures' `names_test` (`generated_names.bzl`), `resolve_test.bzl`
`unresolved_key_test`, and a comparison of every `:node_modules/...` name of `main` with the
branch (`tdd-log.md`, T111, T169).

**Bindings that differ by platform class (T077)**. The store's first pass skips a dependency whose
package `is_disabled` for the platform (ISO L1032–L1047, through TREE L1313–L1405), so a skipped
package is no node dependency, and a peer looked up the node chain (ISO L1074–L1170) can find a
provider on one class and not on another. An entry's key holds its transitive peers, which every
node the lookup passes is marked with (ISO L1097–L1176, L1198–L1210), so the bindings of one entry key differ by
class only when the lookup ends without a provider (`best_version` invalid, ISO L1084–L1090, then
`continue` at L1183–L1186, marking nothing).

- **A holder's alias**: reachable. `conformance_platform_peer` (the root's `plat-peer-host`, whose
  `p`'s peer `q` is `plat-peer-host`'s own `q: npm:q-darwin@1.0.0` on darwin and the root's
  `q@1.0.0` elsewhere) and `conformance_platform_peer_workspace` (the same through workspace `w`):
  the pinned Bun writes both lockfiles and installs them. Expressed (BC-12, user 2026-11-21): the
  link's `roots` map each root to the platform tuples it is the root on, and the hub selects the
  root with `select()` on the settings it selects optional instances by (`npm_repositories.bzl`
  `_root_selections`); every root is the same package under other peer bindings, so the link's
  bins are the same. `resolve_test.bzl` `platform_holder_test`, `platforms_test.bzl`
  `root_linux_x64_test`/`root_darwin_aarch64_test`, the fixture test
  `conformance_platform_peer:platform_peer_test`, and `conformance_test` (both projects, `0
  differences`). Roots of different packages (T097, the review's case: workspace `w` with peer
  `plat-p: ^1.0.0`, the root's optional `plat-p@2.0.0` restricted to darwin) are not written: a
  workspace's peer binds a row whose version its range matches (`own_peer`, LOCK L2820), else the
  row the key walk finds (`w/plat-p`, else the root's `plat-p`, L2897–L2901), the store's lookup
  for a workspace's peer looks only at the root above it (ISO L1074–L1170), and the pinned Bun, like Bun 1.4.2, writes no `w/plat-p` row when the
  root has a `plat-p`, even one the range does not match (`conformance_platform_root_package`: one
  root, `plat-p@2.0.0`, linked on darwin only). With such a row written by hand the store binds
  `plat-p@2.0.0` on darwin and `plat-p@1.0.0` elsewhere, whose bins and fetch status differ, so
  `resolve.bzl` fails it (`the store links "<alias>" of the workspace "<path>" to different packages
  on different platforms, which rules_bun cannot express`); `resolve_test.bzl`
  `platform_root_package_test` covers both.
- **An entry's alias** (`the store links "<alias>" of <package> to different packages on different
  platforms`): needs an optional peer that no row on the peer's key path resolves (LOCK L1580–L1662)
  while the parent's own platform-restricted dependency provides it. The pinned Bun hoists that
  dependency's row to the root when nothing there conflicts (experiment: `plat-r-host` with
  `r: npm:r-darwin@1.0.0` and `p`'s optional peer `r` is written with the key `r`, not
  `plat-r-host/r`), so the row is on the peer's key path, the peer resolves, and the lookup marks
  the parent; a conflicting root `r` would provide the peer on every class. Bun 1.4.4 was not seen
  writing a lockfile that reaches it. Bun 1.4.2 writes one: for `conformance_platform_peer`, in 5
  of 6 runs (T091), it resolves the root's `q: "1.0.0"` to the row `"q": ["q-darwin@1.0.0", …,
  { "os": "darwin" }]` and writes no `plat-peer-host/q`, so off darwin the root's `q` is disabled
  and `plat-peer-host`'s `p` binds its peer `q` to `q-darwin@1.0.0` on darwin and to nothing
  elsewhere, while `plat-peer-host` (no peers) is one entry; Bun 1.4.4's and 1.4.2's frozen
  installs both accept it. Expressed (BC-16, T107, replacing the former ID-7): the merged instance
  keeps each entry an alias binds with the platform tuples it binds it on (`edge_targets`), and the
  hub selects the instance's `edges`, `dependency_keys` and `peers` by platform as for an edge
  (`npm_repositories.bzl` `_edge_fields`). The entries are one package: an ordinary dependency has
  one resolution (`resolutions[dep_id]`, LOCK L2923–L3023), and a peer's package is part of the
  entry's key (ISO L1097–L1176), so the dependency's key and bins are the same on every class and no
  error remains for an entry's alias. `resolve_test.bzl` `platform_entry_test`, `platforms_test.bzl`
  `entry_linux_x64_test`/`entry_darwin_aarch64_test`, `graph_test.bzl` `edge_targets_test`, the
  runtime test `platform_peer_1_4_2_test`, and both conformance runs on that Bun-written lockfile
  (`bun/tests/npm/conformance/accepted/platform_peer_1_4_2/bun.lock`, md5 `4a5419e2`, `0
  differences`).
- **A member link** (T090): the hub links a workspace member by path on every platform (BC-4),
  so a member link of an entry or a holder must be the same on every class that entry or holder
  exists on. The pinned Bun writes no lockfile where it is not: a workspace row has no `os`, `cpu`
  or `libc` (LOCK L2593–L2604, `bun_lockfile.bzl` `_meta`), so no class disables a member and
  `behavior_is_placed` does not depend on the platform; a non-peer dependency resolves to one
  package on every class; a peer bound to a member on some classes only is part of the entry's
  key, so it makes another entry, as above. `class_member_conflict` checks it before the classes
  are merged, so a merge no longer applies a member on every platform or links an alias as a
  member and a package; it fails with the entry error's text (`of <package>`, `of the workspace
  "<path>"`, `of the root workspace`). `resolve_test.bzl` `platform_member_test` reaches it with
  per-class graphs written by hand.
- **An edge** (T101, BC-15): an entry that exists on several classes can have an edge on some of
  them only, an optional dependency `is_disabled` on the others being no node dependency there
  (ISO L1032–L1047). The merged instance keeps such an edge's platform tuples
  (`edge_conditions`), and the hub selects the instance's `edges`, `dependency_keys` and `peers`
  by platform with the settings its links select by (`npm_repositories.bzl` `_edge_fields`):
  `run.bzl` links an instance's edge whenever its target is among the target's instances, and a
  target can hold that target through another link (`conformance_platform_edge`: the root's
  non-optional `native-linux-x64-musl`, whose `libc` does not apply to it, HOOKS L882–L890). The
  conformance graph takes an edge where its conditions hold and its target is carried by any link
  (`graph.bzl`), the closure of a target holding every link, so it shows such an edge.
  `platforms_test.bzl` `edge_glibc_test`/`edge_musl_test`, `resolve_test.bzl`
  `platform_edge_test`, `graph_test.bzl` `combined_test`/`edge_conditions_test`, and
  `conformance_test` (`conformance_platform_edge`, `0 differences`).

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
from the directory name. The directory tells whether the entry is a registry package (T127):
DOC-ISO names a package's store directory `<package>@<version>` (a scope's `/` written `+`, as
Store.rs does), to which Bun appends `+<peer hash>`; Bun names the directory of a package from
another resolution after that resolution (`foo@file+vendor+foo` for `file:./vendor/foo`, seen with
the pinned Bun, Linux x64, 2026-11-21), so an entry whose directory is not the registry form of
its `package.json` is from another resolution. It is identified by the resolution of the `bun.lock`
row whose store key names the directory, alone or with a `+<peer hash>` (T172): `graph.ts` carries
over Bun's store key for a `file:` folder and a tarball URL (`fmt_store_key`, `write_resolution`,
`fmt_store_url`, Store.rs L341–L428, resolution.rs L541–L656, semver lib.rs L657–L686; E19), and
fails the read for a directory no such row names. The ruleset's entry records the same resolution
as its version (R8). On Windows `realpath` resolves Bun's junctions the same way.

### R8. The ruleset's graph and the comparison

A dev-only extension (extending `fixture_results.bzl`) writes, for every project, the ruleset's
graph per platform class as JSON (contract: [contracts/conformance-graph.md](contracts/conformance-graph.md)),
from `resolve.bzl`'s output — the same function the hub uses — after every check the extension's
evaluation runs, by the extension's own functions (`evaluate_lockfile`, `link_targets`, T160), so a
lockfile the extension fails and Bun installs is a difference ("the ruleset fails"), except ID-12. The
test picks the class of the host
(`process.platform`, `process.arch`, and on Linux the C library as canary C-LIBC detects it).

Equality (FR-008): both graphs are labelled digraphs (holders labelled by path, entries by
`name@version`, or by name and resolution for a package from another resolution, on each side by
its own resolution, R7, T127 and T172; edges by dependency name). The test refines a partition of the disjoint union
(start: labels; refine by sorted `(edge name, class of target)`) until stable; the graphs are equal
iff every class has as many Bun nodes as ruleset nodes and every holder's class holds one node of
each side. This compares entry counts (a package with two peer contexts must be two entries on both
sides) without relying on either side's naming. A failure prints, per FR-012, the project, the first
holder or entry whose links differ, the dependency name, and both targets as `name@version` with
their own links (peer bindings). When the links agree but a class's entry counts differ, it names
the first two links, walking the corresponding nodes down from the holders, that one side binds to
two entries of that class and the other to one, each with its dependent and the holder that reaches
it (T161). A holder of one side only is named with each of its links and their targets, which the
other side links to no link; a holder whose links reach several entries of one store directory,
which `run.bzl` fails analysis of in one target (`conflicts`), with each of those entries' bindings
and the holder's links that reach it (T164); and an entry the hub fails analysis of, other than
ID-4's, by the first link, walking down from the holders, that reaches it, with its dependent and
both sides' targets, or as reached by no holder (T166).

**Red mode** (FR-011): `RULES_BUN_CONFORMANCE_RED=1` redirects one edge of the ruleset's graph of a
fixed project to another entry; the test must fail naming it. The project,
`bun/tests/npm/conformance/bun_1_4_2/conformance_overrides`, has no BC and is a lockfile Bun 1.4.2
wrote, so the 1.4.2 run (R10) compares it as well and fails in red mode too (T168).

### R9. Coverage

The test's projects are every directory under `bun/tests/npm/fixtures/` holding a `bun.lock` (the
corpus included, R11), `bun/tests/npm/scale/`, each `bun.lock` under
`bun/tests/integration/workspaces/`, and the 1.4.2-written lockfiles under
`bun/tests/npm/conformance/bun_1_4_2/` (R10), the lockfiles Bun installs that `write_lockfiles.ts`
does not write with the pinned Bun under `bun/tests/npm/conformance/accepted/` (one Bun 1.4.2
writes; three written by hand, `platform_rule_raw` for BC-13, `extra_slots`, whose npm row has 5
slots, for BC-18, and `lockfile_version_0`, stamped `lockfileVersion` 0, for BC-19; T107, T110,
T150, T155), which the 1.4.2 run compares as well, and the lockfiles Bun refuses to load under
`bun/tests/npm/conformance/refused/`, written by hand (`patch_path`, T099;
`lockfile_version_0_member`, a version-0 member without its `packages` row, T155). The extension and
the test enumerate the same directories; a project present on one side only fails the test (FR-009,
US2-4). A project the oracle cannot install (each `refused/` project) is listed in the test with its
reason, the list is asserted exactly, and for each the test asserts that Bun's loader refuses it
(the install prints `failed to parse lockfile: 'bun.lock'`, `report_lockfile_load_error`, not just
any failed install) and that the ruleset fails it with an error naming the `bun.lock` label (T109;
spec Edge Cases: no graph for a lockfile Bun does not install). Each corpus project has a Bun 1.4.2
lockfile or a reason in `not_applicable_1_4_2.ts`, which the test asserts (T095). `e2e/smoke`, the
consumer module's project, is compared as well (T113, which supersedes T098's exclusion): `e2e` is
no package of the root module (`REPO.bazel` `ignore_directories`), so the dev extension
`fixture_results.bzl` reads its `bun.lock` and `package.json` from the source tree with
`module_ctx.read`, resolves it into `graphs.json`, and writes the two files to
`@npm_fixture_results//e2e/smoke:files`, which the test installs; the loopback registry serves it
the archives of `bun/tests/npm/fixtures/jsx/archives`, which `fetch_react.ts` downloaded from
`https://registry.npmjs.org` for the same three package versions (`react`, `react-dom`, `scheduler`)
and verified against the integrity their packuments publish, the integrity both lockfiles record.
`_NPM_DOC` names the compared directories.

The integration tests that wrote their lockfiles inline (T143, decided by the lead under the
user's delegation, 2026-11-21: compare every one the ruleset resolves, record the rest).
`conflict.test.ts`, `registries.test.ts`, `credentials.test.ts`, `rename.test.ts` and
`stale_link.test.ts` now take every lockfile the ruleset resolves from a committed `bun.lock`
(`workspaces/conflict`, and `workspaces/conflict/integrity` and `workspaces/conflict/url`, whose
`c/b` row records another integrity or URL than `b`'s, written by hand as no Bun writes them and
installed by the pinned Bun, BC-17, T148; `workspaces/registries`, which both registry tests use;
`workspaces/rename`; `workspaces/stale_link` and `workspaces/stale_link/edited`, the two lockfiles
`stale_link.test.ts` filled in from a template that Bun could not load and the test listed as not
applicable), which this test compares as it compares every `bun.lock` under
`bun/tests/integration/workspaces/`; a case changes only a row's download URL (the registry tests,
each replacement checked to match) or writes one of the lockfiles below. The other integration
tests read a committed `bun.lock` listed above (a fixture, or `scale`'s, with their URLs
rewritten). Not compared, each with its reason:

- `credentials.test.ts`, the cases (a)–(l): a URL with user information in `bun.lock`,
  `package.json` or `.npmrc` fails evaluation without being printed (feature 005 FR-002), so the
  ruleset resolves no graph. The pinned Bun loads such a `bun.lock` (an npm row's URL
  `http://u:t@127.0.0.1:9/…` and a dependency specifier holding `u:t@`, `bun install
  --frozen-lockfile --dry-run` exits 0, `tdd-log.md` T156), so this is ID-10.
- `credentials.test.ts`, the lockfile with the row `g@git+ssh://git@host/r.git#abc`: the ruleset
  resolves it (the row unfetched, ID-4), but the oracle's install is offline against the loopback
  registry (FR-007), which serves no git repository, so the pinned Bun cannot install it.
- `lockfile_errors.test.ts`, every lockfile: a `bun.lockb`, a `packages` row of a workspace on
  `lockfileVersion` 0 (ID-11), `lockfileVersion` 4, an unclosed comment, and a `packages` key equal
  to a workspace's name holding a `file:` folder ("Loader refusals", L2759) each fail evaluation,
  and the cases of an invalid `name` or `workspace_target_name` fail on the `npm.translate_lock`
  tag, so the ruleset resolves no graph.

The Starlark unit tests (`bun/tests/npm/*_test.bzl`) resolve lockfile texts written in the test,
without the `package.json` files and archives an install needs: they are unit tests of the reader
and the resolver, not projects. Spec P2's exceptions are the lockfiles listed above as not
compared.

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
a project it cannot write or install would be listed with the reason in
`bun/tests/npm/conformance/not_applicable_1_4_2.ts`. Planning expected two (an unlinked workspace,
which 1.4.2's loader was read to reject, LOCK-142 L2479–2490; `unresolved`, which 1.4.2 was read
not to write), but run with the 1.4.2 oracle, Bun 1.4.2 writes and installs every corpus project
(T091, `tdd-log.md`). The list holds one project added since: `conformance_root_row` (T171), a
member depending on the root package, which Bun 1.4.2 cannot write by `workspace:*` and whose
lockfile, written by `workspace:../..`, its own frozen install refuses (Part 6, E18). Its usual lockfile
for `conformance_platform_peer` differs from the committed one; both conformance runs compare it
as `bun/tests/npm/conformance/accepted/platform_peer_1_4_2` (BC-16, R4).

### R11. The edge-case corpus

New projects in `write_lockfiles.ts`, written under `bun/tests/npm/fixtures/conformance_<case>/`
(so R9 and `fixture_results` cover them unchanged), each with a `check` asserting the lockfile form
it exists for. New archives are packed by `pack.ts`, never served by altering a packument, so the
oracle's tarballs carry the dependencies the lockfile records.

| Project | FR-009 layout | BC or edge case it exercises | Added by |
|---|---|---|---|
| `conformance_alias_workspace` | workspace `lib` and `@scope/lib`, root aliases `lib: npm:a@1.0.0`, `@scope/lib: npm:c@1.0.0` (PRIOR U4) | BC-2 | T007 |
| `conformance_unresolved` | package and workspace optional dependencies listed under `unresolved` (PRIOR E1, E7, E9; archive `opt-user@1.0.0`); the root's unresolved `single-bin`, whose row of that name (`w`'s `single-bin@1.0.0`) has a bin | BC-1; SC-005 | T007, T169 |
| `conformance_unbound` | optional and peer dependencies without a key, root and workspace (PRIOR E3, E10) | BC-3 | T007 |
| `conformance_registry_to_workspace` | a registry package depending on a workspace member's name, resolved to the member | BC-4 | T007 |
| `conformance_unprovided_peer` | a non-optional and an optional peer nothing provides | BC-5 | T007 |
| `conformance_nested` | nested and hoisted keys of one `name@version` with different walks (`dependency_conflict`'s shape, deeper) | BC-6 | T007 |
| `conformance_peer_contexts` | one package reached under two peer providers (two entries) and under one (deduped) | — | T007 |
| `conformance_shared_peer` | two packages with an unprovided peer on one name (S5) | — | T007 |
| `conformance_platform` | a non-optional and an optional dependency restricted to another OS | BC-7 | T007 |
| `conformance_overrides`, `conformance_catalog` | an override of a peer's range; a `catalog:` peer | — | T007 |
| `conformance_bundled` | `bundler@1.0.0` with `bundleDependencies`, whose bundled `b` Bun writes as `bundler/b` with `bundled: true`, beside the root's `b@2.0.0` | BC-10 | T006 |
| `conformance_unfetched` | `a@1.0.0` patched with `bun patch` (an entry Bun does not fetch, `unsupported_reason`), with its dependency `b ^1.0.0` | BC-8 | T069 |
| `conformance_unresolved_peer` | `ident-a`'s peer `state` whose only provider on its chain is `opt-user`'s optional `state ^3.0.0`, listed under `unresolved`, while `state2-user` holds `state@2.0.0` and the root declares no `state` | spec Edge Cases | T074 |
| `conformance_platform_peer` | `plat-peer-host`'s `p`, whose peer `q` is provided up the chain by `plat-peer-host`'s optional `q: npm:q-darwin@1.0.0` (darwin) and by the root's `q@1.0.0` elsewhere | BC-12 | T077 |
| `conformance_platform_peer_workspace` | workspace `w`'s `p`, whose peer `q` is provided by `w`'s optional `q: npm:q-darwin@1.0.0` (darwin) and by the root's `q@1.0.0` elsewhere | BC-12 | T077 |
| `conformance_platform_root_package` | workspace `w`'s peer `plat-p: ^1.0.0` and the root's optional `plat-p@2.0.0`, restricted to darwin, whose bins differ from `plat-p@1.0.0`'s: a link whose root could be a different package by platform, which Bun's lockfile binds to the root's one package | BC-12 (the case Bun does not write) | T097 |
| `conformance_platform_rule` | `rule-user`'s optional `rule-linux-any` (`os: ["linux", "any"]`), `rule-any-linux` (`["any", "linux"]`) and `rule-libc-glibc` (`libc: glibc`, no `os`) | BC-13, BC-14 | T096 |
| `conformance_platform_edge` | `native`'s optional `native-linux-x64-musl` (`libc: musl`), which the root depends on as well | BC-15 | T101 |
| `conformance_declared_nowhere` | the root's optional `bin-sunos` (`os: sunos`, a bin) and `nomatch-aix-ppc64` (`cpu: ppc64`), workspace `w`'s non-optional `nomatch-sunos-x64` and optional `bin-sunos`: declared dependencies the store links on no platform class, each keeping its `:node_modules/<package>` target | BC-7; SC-005 | T111 |
| `conformance_member_chain` | the root's `chain-cli` (a bin) depends on member `chain-w1`, which declares the registry package `chain-helper`, which depends on member `chain-w2` | BC-4 (a bin's members across two workspace boundaries) | T123 |
| `conformance_member_workspace_chain` | the root's `chain-cli` depends on member `chain-w1`, which declares member `chain-mid` by `workspace:*`, which declares `chain-helper`, which depends on member `chain-w2` | BC-4 (a bin's members through a `workspace:` link and more than one further member) | T131 |
| `conformance_member_alias` | `conformance_registry_to_workspace`'s layout, whose member's target `pkg` is an `alias` of a target in the fixture's root package that carries the member's files | BC-4 (a member's target that is an alias) | T146 |
| `conformance_root_row` | member `w` depends on the root package (`workspace:*`), whose `bin` Bun writes in the root's `root:` row | L38 (a `root:` row the pinned Bun writes); not applicable to Bun 1.4.2 (R10) | T171 |
| `conformance_local_tarball` | the root's `b: file:loc-1.0.0.tgz`, a tarball the project holds (`loc@1.0.0`, depending on `a@1.0.0`), written `["loc@loc-1.0.0.tgz", { … }, "sha512-…"]` | BC-20 (with BC-8, ID-4) | T175 |
| `conformance_catalog_missing` | optional and peer `catalog:` dependencies with no catalog entry (`catalog:`, `catalog:nope`), of the root and of workspace `w` | BC-21 (with BC-3) | T176 |
| `conformance_override_forms` | overrides `b: "$b"` (the root's `b: file:./b`) and `p-user: { p: { q: "2.0.0" } }` (nested one level too deep), written `{ "b": "file:./b" }` | BC-22 | T177 |
| `conformance_folder_ids` | the root's `x: file:./a/b` and `y: file:./a_b`, two folders of package `foo@1.0.0` with different dependencies | BC-23 | T178 |

T006 added the archives the T007 rows need and `conformance_bundled`. Each row is checked against
its `write_lockfiles.ts` entry (the `files` it writes and the `check` it asserts). The existing
`overrides_*`, `catalog`, `hoisted`, `workspace*`, `missing_peer` fixtures also count.

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

The `scale` fixture has no `os`, `cpu` or `libc`, so it measures one platform class. Its platform
variant (T100, `bun/tests/npm/scale/platform/`, `generate.ts --platform`) adds 23 esbuild-like
per-platform packages under `scale-native`, which every tenth package depends on, so the store is
built for 22 classes; `scale_test` asserts the same bound on its evaluation. With the adapter
walking each holder's links once per class it measured 10,295 ms, over the bound. The adapter's
walk (`resolve.bzl` `_reached`, not one of Bun's stages) now propagates each entry's classes as a
bit mask in one walk; its output is unchanged (`graphs.json` and the unit tests' results were
identical, so every test depending on them stayed cached), and the variant measures 4,810 ms, the
`scale` fixture 1,759 ms (`tdd-log.md` T100).

### R14. Behavior changes and existing tests

Each BC of Part 5 is first recorded as a conformance difference (`tdd-log.md`), then fixed by the
carry-over. Existing tests asserting a non-Bun behavior are changed and listed (FR-016): at least
`missing_peer` (fails today, links nothing for `state` after), the `resolve_test.bzl` cases on
per-key instances of one `name@version` (BC-6), `_NPM_DOC`'s "A non-optional dependency is carried
whatever its `os`, `cpu` and `libc` say" (BC-7). T148 (BC-17) changed `conflict.test.ts`, which
asserted that two rows of one `name@version` with different integrity or URL fail evaluation, and
removed that case from `lockfile_errors.test.ts`. T155 (BC-19) changed `lockfile_errors.test.ts`'s
`lockfileVersion` 0 case, which asserted that version 0 fails evaluation, into a version-0
`packages` row of a workspace (ID-11), and `lockfile_test.bzl` `versions_test`, which asserted the
same.

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
| L31 | the info object in slot 1 of a row that is not an npm version (`file:`, tarball URL, local tarball, git, GitHub, `link:`); a resolution `Tag::infer` reads as a tarball that is no URL is a local tarball (RES L192–L201, T175) | LOCK L2346, L2557–L2591 (writer L720–L728) | `unsupported` (`local`, `tb`); E12; E20 (`conformance_local_tarball`) | C-ROWINFO (T075, T175) |
| L32 | a row's `devDependencies` | LOCK L1478–L1483, L3405–L3490 (writer L950–L1004 for a folder, resolver_hooks.rs L1251–L1256 `Features::FOLDER`) | E13 | C-ROWDEVDEPS (T075) |
| L33 | a workspace's `optionalPeers` | LOCK L3372–L3400 (root and workspaces, L2225, L2284; writer L1184–L1240) | E14 | C-WSOPTPEERS (T075) |
| L34 | top-level `configVersion` (read only to refuse what Bun refuses, T125) | LOCK L1861–L1869 (writer L373: a whole number) | E15 | C-ROOTFIELDS (T130) |
| L35 | top-level `trustedDependencies` (read only to refuse what Bun refuses, T125) | LOCK L1871–L1888 (writer L510–L527: an array of the names) | E15 | C-ROOTFIELDS (T130) |
| L36 | a git or GitHub row's `.bun-tag`, the slot after its info object (read only to refuse what Bun refuses, T147) | LOCK L2671–L2722 (writer L860–L894: the `resolved` tag, for GitHub the root folder of the tarball, REPO L125–L130) | E16 | C-ROWTAIL (T147) |
| L37 | the integrity after a tarball row's info object (a tarball URL or a local tarball) or a git or GitHub row's tag (read only to refuse what Bun refuses, T147) | LOCK L2724–L2735, L1688–L1711 (writer L799–L818, L889–L893: written only when supported) | E16; E20 | C-ROWTAIL (T147), C-ROWINFO (local tarball, T175) |
| L38 | a `root:` row, `["<name>@root:", { bin, binDir }]`, the root package's row when a workspace depends on it, and the object in its slot 1 (read only to refuse what Bun refuses, T170) | LOCK L2375–L2432, L2612–L2627 (writer L751–L780: the root's `bin` or `binDir`, `{}` when it has none) | E18 (`conformance_root_row`) | C-ROOTROW (T171) |

The list is closed (T050): every `root.get(...)`/`value.get(...)`/`info.get(...)` of LOCK
L1797–3543 at `bun-v1.4.4`, and each slot of a `packages` row, is an access with a canary or read by
Bun and deciding no binding:

| Bun reads | Lines | Access |
|---|---|---|
| `lockfileVersion` | L1815, L1836 (0 to 3, `Version::from_int` L116–L124) | L2: 0 is the version BLOG shows (BC-19, T155); canary C-VER0 pins that the pinned Bun loads 0 and re-saves it as 1 (`Stringifier::version_to_write`, L163–L202) |
| `configVersion` | L1861 | L34 (read only to refuse what Bun refuses; the value decides no binding: the default linker of a later install, and this one is `--linker isolated`) |
| `trustedDependencies` | L1872 | L35 (read only to refuse what Bun refuses; the value decides no binding: lifecycle scripts, ID-1) |
| `patchedDependencies` | L1899 | L20 (a patched package is unfetched, ID-4) |
| `packageExtensions` | L1928 | L27 (not read: the rows carry the extended dependencies) |
| `overrides` | L1934 | L18 |
| `catalog`, `catalogs` | L2037, L2056 | L19 |
| `workspaces` and its keys | L2100 | L3, L4 |
| a workspace's `name` | L2137, L2211, L2275, L3496 | L5 |
| a workspace's `version` | L2162 | L28 |
| `packages`, its keys and row order | L2308, L2929, L2993 | L7, L8, L21, L25, L29 |
| slot 0 | L2375–L2432 | L9, L22, L38 (`<name>@root:`) |
| an npm row's slots 1–3 | L2433–L2476, L2636–L2669 | L10, L11, L12 |
| an npm row's slots after 3 | never read | not read: a row of more slots is read by its first 4 (BC-18, T149) |
| slot 1 of any other row | L2557–L2591 | L31 |
| slot 1 of a workspace row on `lockfileVersion` 0 | L2553–L2591 | not read: the row fails evaluation (ID-11). BLOG shows no workspace row, and since v1 no Bun writes the object (L170–L177: "v1 stopped listing a workspace package's dependencies as a trailing object"), so no canary can pin it (constitution V) |
| `bundled` | L2351 | L26 |
| `os`, `cpu`, `libc` | L2594–L2602 | L15, C-LIBC |
| `hasInstallScript` | L2606 | decides no binding (lifecycle scripts, ID-1) |
| `bin`, `binDir` | L1714–L1721, BIN L193–L263 | L16 (`binDir` decides no binding: which files are bins) |
| the root row's `{ bin, binDir }` | L2612–L2634 | L38 (read only to refuse what Bun refuses, T170; its content decides no binding: the root's own bins) |
| a git or GitHub row's `.bun-tag` | L2671–L2722 | L36 (read only to refuse what Bun refuses; decides no binding, "Not carried over") |
| the integrity of a tarball (URL or local), git or GitHub row | L2724–L2735 | L37 (read only to refuse what Bun refuses; these rows are not fetched, ID-4) |
| `dependencies`, `devDependencies`, `optionalDependencies`, `peerDependencies` of a row or workspace | L3405–L3490 | L6, L13, L14, L30, L32 |
| `optionalPeers`, `unresolved` | L3372–L3400 | L14, L23, L24, L33 |

No access the carry-over reads is without a canary (constitution V).

### Loader refusals (T079)

Every refusal of Bun's text-lockfile loader at `bun-v1.4.4`, LOCK L1797–L3543, with `parse_catalog`
(L1727–L1795) and `parse_integrity` (L1688–L1711), which it calls. L1809 and L3365 are the `fail!`
macros, not sites. Each text of the `bun/tests/npm/lockfile_test.bzl` tables `_LOADER_REFUSALS`
and `_CONTAINER_REFUSALS` was installed with the pinned Bun (`bun install --frozen-lockfile`,
Linux x64, 2026-11-21), which refused it with the message of its line; the ruleset fails evaluation
with an English error naming the `bun.lock` label and the key or field (`npm_extension.bzl` fails
on any `read_lockfile` or `resolve` error). "Not written" means no supported Bun writes the form,
for the reason given; the ruleset does not read that field, or reads only what decides a binding.

| Line | Bun's message | Ruleset | Test, or why no supported Bun writes it |
|---|---|---|---|
| L1816 | Missing lockfile version | refused | `_LOADER_REFUSALS` L1816 |
| L1829 | Invalid lockfile version | refused | `_LOADER_REFUSALS` L1829 |
| L1855 | Unsupported lockfile version | refused, except where `lockfileVersion` is written twice (**ID-13**): Bun reads the first value (L1815), the reader the last, so `2` then `99` fails evaluation where Bun loads, and `99` then `2` loads where Bun refuses | `_LOADER_REFUSALS` L1855; `versions_test` (4; 0 is loaded, BC-19); `lockfile_errors.test.ts`; `duplicate_keys_test`, both texts checked against Bun 1.4.4 and 1.4.2 (T174) |
| L1864 | Invalid "configVersion". Expected a number | refused | `_LOADER_REFUSALS` L1864, three rows: a string, a fraction and a number below 0, which ConfigVersion.rs `from_expr` maps to none (red first, T125); a whole number above 1 and `1.0` are read as Bun reads them (`config_version_test`). The value decides no binding (table above) |
| L1875, L1884 | Expected an array / a string (`trustedDependencies`) | refused | `_LOADER_REFUSALS` L1875, L1884 (red first, T125); an array of strings is read (`config_version_test`). The value decides no binding (ID-1) |
| L1901 | Expected an object (`patchedDependencies`) | refused | `_CONTAINER_REFUSALS` L1901 (red first) |
| L1910 | Expected a string (a patch path) | refused | `_CONTAINER_REFUSALS` L1910 (red first, T099); `conformance/refused/patch_path`, which the conformance test checks Bun and the ruleset both refuse; canary C-PATCHED pins the value as a string |
| L1936 | Expected an object (`overrides`) | refused | `_CONTAINER_REFUSALS` L1936 (red first) |
| L1946, L1968, L1978, L1986, L1992, L2007, L2027 | the `overrides` refusals | refused | `_LOADER_REFUSALS`, one row each |
| L1738, L1746, L1765 | the `parse_catalog` refusals | refused | `_LOADER_REFUSALS`, one row each |
| L1782 | Duplicate catalog entry | not refused (**ID-13**, which covers every key written twice in one object, T174): loaded with the entry's last value | not written: it needs one key twice in one JSON object, which the writer never prints (it iterates a map, L586–L615, `write_catalog` L912); Starlark's `json.decode` keeps the last value of a key written twice (https://bazel.build/rules/lib/core/json), so the ruleset cannot see it; `lockfile_test.bzl` `duplicate_keys_test` (`catalog` and a `catalogs` group), each text refused by Bun 1.4.4 and 1.4.2 (T170) |
| L2039 | Expected an object (`catalog`) | refused | `_CONTAINER_REFUSALS` L2039 (red first) |
| L2058 | Expected an object (`catalogs`) | refused | `_CONTAINER_REFUSALS` L2058 (red first) |
| L2068, L2076 | the `catalogs` refusals | refused | `_LOADER_REFUSALS`, one row each |
| L2101 | Missing a workspaces object property | refused | `_CONTAINER_REFUSALS` L2101 (red first; one check for missing and not an object) |
| L2114 | Expected an object (a workspace) | refused | `_CONTAINER_REFUSALS` L2114 (red first) |
| L2126 | Duplicate root package | not refused (**ID-13**, every key written twice): loaded with the last root workspace | not written: a second `""` key in `workspaces`; the writer prints each workspace path once, and `json.decode` keeps the last (as L1782); `duplicate_keys_test`, the text refused by Bun 1.4.4 and 1.4.2 (T170) |
| L2138, L2146, L2164, L2181, L2200 | the workspace refusals | refused | `_LOADER_REFUSALS`, one row each |
| L2215 | Expected a string (the root's `name`) | refused | `_CONTAINER_REFUSALS` L2215 (red first) |
| L2313 | Expected an object (`packages`) | refused | `_CONTAINER_REFUSALS` L2313 (red first) |
| L2339, L2368, L2380, L2394, L2403, L2427, L2434, L2445, L2536, L2558, L2569, L2640, L2643 | the row refusals | refused | `_LOADER_REFUSALS`, one row each |
| L2561, L2569 (a workspace row on `lockfileVersion` 0) | Missing dependencies object / Expected an object | refused, and so is a version-0 workspace row with the object, which Bun loads (ID-11) | `lockfile_test.bzl` `version_0_workspace_row_test`, `lockfile_errors.test.ts` (T155) |
| L2614, L2623 | Missing package binaries object / Expected an object (a `root:` row) | refused | `_LOADER_REFUSALS` L2614, L2623 and `conformance/refused/root_row_without_bins`, `refused/root_row_bins_not_object`, which the conformance test checks Bun and the ruleset both refuse (red first, T170); not written: the writer prints the object (L751–L780); its content is not read (the root's own bins, table above) |
| L2650 (L1688–L1711) | Unsupported or malformed integrity hash (an npm row) | refused, from lockfileVersion 2, where no whitespace-separated entry has a known algorithm and a digest `Integrity::parse_entry` accepts (standard base64 without padding, at most the algorithm's length, zero bits after the last byte; INTEGRITY L88–L164, BASE64 L548–L641); before 2 Bun warns and loads | `_LOADER_REFUSALS` L2650; `lockfile_test.bzl` `_INTEGRITY_REFUSALS` and `row_tail_accepted_test`, each text checked against the pinned Bun (red first, T147) |
| L2664 (L2652–L2669) | Missing integrity hash for npm package resolved to a tarball URL outside the configured registry | not refused; the row is unfetched (ID-4) | **ID-5** (user, 2026-11-21, Part 6): Bun's configured registry comes from `bunfig.toml` (`install.registry`, `install.scopes`), the environment and `.npmrc` (PackageManagerOptions L690–L780, L941–L943); the ruleset reads only the `npmrc` attribute's `.npmrc` (FR-003), so it cannot tell which URLs are under the configured registry. It loads such a lockfile and a target that needs the row fails analysis (ID-4), as `restricted` and `integration/workspaces/multi_nointegrity` show for rows without integrity (`conformance_test`, ID-4) |
| L2674, L2685, L2707 | Missing / Expected a string / Invalid git dependency tag | refused: a missing or non-string slot on every lockfile, a tag over 256 bytes on every lockfile, and one `is_safe_resolved_tag` rejects (REPO L114–L123) for a GitHub row on every lockfile and for a git row from lockfileVersion 2 | `lockfile_test.bzl` `_GIT_TAG_REFUSALS` and `row_tail_accepted_test`, each text checked against the pinned Bun (red first, T147); canary C-ROWTAIL |
| L2733 (L1688–L1711) | Unsupported or malformed integrity hash (a tarball, git or GitHub row) | refused as L2650; a slot that is not a string is skipped, as Bun skips it | `_INTEGRITY_REFUSALS` (L2733 rows) and `row_tail_accepted_test` (red first, T147); canary C-ROWTAIL |
| L2759 | Duplicate package path | refused where two keys reach one path (a key equal to a workspace's name holding a `file:` folder); not refused (**ID-13**) where one `packages` key is written twice, which `json.decode` reads as its last row | `bun_lockfile_test.bzl` (T031), `lockfile_errors.test.ts` (T035); `duplicate_keys_test` (a key written twice, refused by Bun 1.4.4 and 1.4.2, T174) |
| L2843, L2908, L3010 | Failed to resolve … dependency (`dependency_resolution_failure`, L3302–L3345) | refused | `_LOADER_REFUSALS`, one row each, and a second L2843 row: a `lockfileVersion` 0 member without its `packages` row, which is no package on version 0 (L2263), as `refused/lockfile_version_0_member` shows (T155) |
| L2888 | Workspace and dependency name too long | not refused | not written: `./<workspace>/<dependency>` must exceed the path buffer (4,096 bytes on Linux), but each name is a directory under `node_modules`, at most 255 bytes on every supported file system |
| L2933 | `InvalidPackagesObject` | refused (unreachable) | unreachable in Bun: the first loop puts every row in the key map (L2360–L2762); `bun_lockfile.bzl` keeps the same refusal |
| L3000 | Invalid package path | refused | `_LOADER_REFUSALS` L3000 |
| L3377, L3386 | Expected an array / a string (`optionalPeers`, `unresolved`) | refused | `lockfile_test.bzl` `unresolved_test`, `workspace_fields_test` (T030) |
| L3408, L3422 | Expected an object / a string (a dependency map) | refused | `lockfile_test.bzl` `dependency_maps_test` (T080) |
| L3451 | Invalid dependency version | refused | `_LOADER_REFUSALS` L3451 |
| L1590–L1592 (`find_resolution`) | `InvalidPackageKey` for `<key>/<dependency>` beyond the path buffer, reported as "Invalid package path" | not refused | not written: as L3470 |
| L3470 | Package path and dependency name too long | not refused | not written: the key would be a `node_modules` path beyond the 4,096-byte path buffer, which Bun's own install cannot create |

A present JSON `null` (T139). Bun's `get` returns a key whose value is `null` as a value (it is
`Some`), so every site above that checks a value's type refuses `null` as it refuses any other value
of the wrong type. `lockfile_test.bzl` `_NULL_REFUSALS` and `_NULL_CONTAINER_REFUSALS` hold one text
per field, each with the line it fails at: `lockfileVersion` (L1829), `configVersion` (L1864),
`trustedDependencies` (L1875), `patchedDependencies` (L1901), `overrides` (L1936), `catalog`
(L2039), `catalogs` (L2058), `workspaces` (L2101), a workspace (L2114), a member's `name` (L2146)
and `version` (L2164), the root's `name` (L2215), `packages` (L2313), slot 2 of a row (L2569), and
`optionalPeers`, `unresolved` (L3377) and the four dependency maps (L3408) of the root, a member and
a row. The pinned Bun refused each of the 29 texts with that line's message (`bun install
--frozen-lockfile`, Linux x64, 2026-11-21). The reader read a present `null` as a missing key: it
loaded the texts for `configVersion`, `trustedDependencies`, the dependency maps, `optionalPeers`,
`unresolved` and a member's `version`, and evaluation crashed with a bare Starlark error for
`patchedDependencies`, `overrides`, `catalog`, `catalogs` and `packages` (red first); the other
texts were already refused (green on the first run). Now only a missing key is skipped. Bun loads
`null` where it reads one type and skips any other value: `os`, `cpu`, `libc`
(`negatable_from_json_value`, npm.rs L850–L865, gives every platform), `bin` and `bundled` (L2351);
the reader reads each as missing (`null_accepted_test`). Any other `bin` Bun loads too (T144):
`parse_bin` hands the value to `Bin::parse_append` (BIN L193–L229), which reads a string that is not
empty as one bin named after the package, an object as its entries whose value is a string
(`parse_append_object` L231–L263; npm's normalize-package-bin skips the others), and anything else,
an empty string, a number, an array, a boolean, as no bin. The pinned Bun loaded each of 12 such
rows and linked exactly those bins (`bun install --frozen-lockfile`, Linux x64, 2026-11-22). The
reader crashed evaluation with a bare Starlark error on a number, an array or a boolean and kept an
empty string and an object's other entries; it now reads `bin` as Bun does (`lockfile_test.bzl`
`bin_values_test`, `bin_objects_test`).

## Part 5: Differences found so far

BC-1 to BC-5 are the spec's. Found while planning:

- **BC-6 (new): one package per `name@version`**. Bun keeps one package per resolution (S1) and binds
  its dependencies once (S2); the ruleset makes one instance per key. `dependency_conflict` (E2): Bun
  links `y@1.0.0 → x@1.0.0 → b@1.0.0` (the `z/x` row's walk to the root, `WalkedToRoot`, outranks
  `y/x`'s `Walked` to `y/b`), the ruleset `y`'s `x@1.0.0 → b@2.0.0`.
- **BC-7 (new): non-optional dependencies on another platform**. Bun skips a dependency whose package
  `is_disabled` for the platform, optional or not (S7; `libc` only for optional ones); `_NPM_DOC` says
  a non-optional one is carried whatever its `os`, `cpu` and `libc` say.

Found by the eighth Claude review (2026-11-22), each a lockfile the pinned Bun installs and `main`
fails to evaluate. The conformance test shows BC-18 (the loader refuses the row: "the ruleset fails
…, Bun installs the lockfile", `accepted/extra_slots`, T150) and, since its ruleset side runs the
extension's evaluation checks (T160), BC-17, whose failure was the extension's check of the
download:

- **BC-17: two rows of one `name@version` with different integrity or URL**. Bun's
  `append_package_dedupe` (LOCKFILE L2684–L2711) returns the package the first row appended, whose
  `meta` keeps that row's integrity and URL; the pinned Bun installs such a lockfile, requesting
  the package once from the first row's URL (`tdd-log.md` T148). The ruleset failed evaluation.
- **BC-18: an npm row with more than 4 slots**. Bun reads slots 1–3 by index (LOCK L2433–L2669) and
  never looks past them; the pinned Bun loads rows of 5 and 7 slots (`tdd-log.md` T149). The
  reader required exactly 4.

Found by the thirteenth Claude review (2026-11-22), each on a lockfile the pinned Bun writes and
installs, from a check or ID scheme `main` has (`main`'s `_kind`, `compare_manifests`,
`normalize_overrides` and `_ids` are the branch's before T175–T178); each corpus project's
conformance difference is recorded red in `tdd-log.md`:

- **BC-20: a local tarball's row**. Bun reads `loc-1.0.0.tgz` (slot 0 after `loc@`) as a local
  tarball (RES L192–L201); the reader read it as an npm version and refused its 3 slots.
- **BC-21: an optional or peer `catalog:` dependency without a catalog entry**. Bun writes no key and
  installs (`may_stay_unresolved`, LOCK L3297–L3299); the manifest comparison failed. Bun refuses a
  `dependencies` or `devDependencies` one (E20), so that failure stays.
- **BC-22: override forms `$<name>` and an object nested too deep**. Bun resolves `$<name>` to the
  declared specifier and ignores the nested object (OVERRIDE L902–L905, L1278–L1335,
  L1405–L1452); the comparison failed on both.
- **BC-23: unfetched entries' instance IDs**. Two unfetched entries whose `name@version` keep the same
  target-name characters got one ID, the second overwriting the first.

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
listed and fixed under it. BC-5 shows on `conformance_unprovided_peer`; on `missing_peer` it shows
since T071, which carries an instance's analysis-failing `status` into the graph (`missing_peer:
ident-a@1.0.0 fails analysis in the ruleset …`), besides its FR-016 test change at T048. BC-8 gets a corpus project `conformance_unfetched` (a patched package with a
dependency) so it is red before its fix.
**BC-9 and BC-10 approved by the user (2026-10-30)**, at T068.

**T072, T050 and BC-4 decided by the user (2026-11-21)**: ID-4 (unfetched entries fail analysis,
constitution III) is an intentional difference; L31–L33 get canaries with red modes; BC-4 links by
path, and a target that reaches such a link without declaring the member fails analysis naming it
(T073), rather than a target dependency (a member that depends on the package would form a Bazel
cycle) or a silent run-time failure.

**T079 (2026-11-21)**: Bun 1.4.4 refuses a lockfile v2+ whose npm row has a URL
outside both the configured and the default registry and no supported integrity (LOCK L2652–L2669,
"Missing integrity hash for npm package resolved to a tarball URL outside the configured
registry"). The ruleset loads it and treats the row as unfetched (ID-4: a target that needs it
fails analysis). Following Bun needs its configured registry, which comes from `bunfig.toml`
(`install.registry`, `install.scopes`), the environment (`BUN_CONFIG_REGISTRY`,
`NPM_CONFIG_REGISTRY`) and `.npmrc` files (PackageManagerOptions L690–L780, L941–L943); the ruleset reads only
the `.npmrc` its `npmrc` attribute names, and nothing from the host (FR-003). Options: list it as
an Intentional Difference (the row stays ID-4), or refuse every such row whose URL is outside the
default registry and the `npmrc` attribute's registries (refusing some lockfiles Bun loads when
`bunfig.toml` or the environment configures the registry).

**T054 (2026-11-21)**: Bun reads `[install] linkWorkspacePackages` from
`bunfig.toml` (default `true`, PackageManagerOptions L149, L725–L726). With `false`,
`linked_workspace_path` returns nothing (LOCKFILE L2247–L2249): an npm range on a workspace's name
binds to an npm row instead of the workspace, in the loader's peers (LOCK L2795–L2807) and in
`tag_workspace_links` (LOCKFILE L2319, L2377–L2385). The ruleset reads no `bunfig.toml` (FR-003)
and binds as with the default. Example: with `false`, a workspace `q` at version `1.5.0`, a member
with peer `q: ^1.0.0` and an npm row `q@1.2.0`: Bun binds the peer to `q@1.2.0`, the ruleset to the
workspace. Options: list it as an Intentional Difference (the ruleset links as Bun's default does),
or read the option from a `bunfig.toml` the consumer names.

**T076, T077, T079, T054 and T083 decided by the user (2026-11-21)**, each on the recommended
option:
- T076: BC-11. Two store entries of one `name@version` that differ by peer bindings are each laid
  out in their own store directory, named as Bun's isolated store names them
  (`<name>@<version>+<peer hash>`, Store.rs L450–L466), so a target reaching both builds, rather
  than an Intentional Difference keeping the analysis failure.
- T077: BC-12. An alias bound to different packages on different platform classes is linked
  through `select()` on the existing `[os, cpu, libc]` classes, rather than an Intentional
  Difference keeping the evaluation error.
- T079: ID-5. The integrity refusal for a row outside the configured registry is not reproduced;
  such a row stays unfetched (ID-4).
- T054: ID-6. The ruleset binds as Bun's default `linkWorkspacePackages = true` and reads no
  `bunfig.toml`.
- T083: `.specify/workflows/overlays/speckit/rules-bun.yml` (57a1326) ships in this feature's PR,
  listed in the PR body as outside feature 006's scope.

**T087 and the platform rule's differences decided by the user (2026-11-21)**, on the recommended
options:
- T087: the 9 loops bounded by `_LIMIT` (2^30) stay as they are and end without an error, as
  `main`'s resolver loops do (`git show main:bun/private/resolve.bzl` L275, L332, L365): no
  evaluation reaches the bound, and an error no test can reach would break constitution II. The
  "Carry over" convention in `tasks.md` is corrected to say so.
- BC-13 and BC-14: the two differences from `main` that Bun's platform rule (R3) brings, `any` and
  entry order in `os`/`cpu` lists and `libc` off Linux, are numbered as Behavior Changes, so every
  difference from `main` is stated (as D3).

**Final gate rejected by the user (2026-11-21)** to fix the Claude review's findings first: a bin's
private member (T089), member links merged across platform classes (T090), R10 against the empty
1.4.2 not-applicable list (T091), a displaced `MODULE.bazel` comment (T092), and BC-11's wording
(the store directory takes Bun's form, not Bun's hash value; corrected in the spec). The CI runner
labels in `_NPM_DOC` stay with T062/T067.

**T091 decided by the lead, under the user's delegation (2026-11-21)**: the user asked the lead to
make such choices. Bun 1.4.2 refuses no corpus project, so the not-applicable list is rightly empty
and R10 is corrected. Its usual `conformance_platform_peer` lockfile (`4a5419e2`) reaches the
entry-level "cannot express" error, which the pinned Bun 1.4.4 was not seen writing; the error is
kept as **ID-7** and pinned with that Bun-written lockfile, rather than expressing an entry's
per-class binding in this feature (a new BC and hub work for a layout only the second oracle
writes). The second Claude review's findings become T094–T100.

**T101 decided by the lead, under the user's delegation (2026-11-21)**: Codex's branch review
found that the adapter kept an edge when any platform class had it. Each edge now keeps its
classes and the hub selects it by platform (R4 "An edge"). `main` carries an instance's edges
without conditions as well (`git show main:bun/private/resolve.bzl` L422–L441), so the change is
one in what a consumer's build links and is numbered **BC-15** (as D3).

**T100 decided by the lead, under the user's delegation (2026-11-21)**: the platform variant of
`scale_test` exceeded the 10,000 ms bound (10,295 ms). R13 forbids a shortcut that departs from
Bun's structure; the time was in the adapter's per-class walk of each link, which is not Bun's, so
that walk was made one walk over class bit masks with unchanged output (R13), rather than raising
the bound or stopping.

**T107 decided by the lead, under the user's delegation (2026-11-21)**: the third Claude review
found that the error ID-7 kept fails a case the hub can already express: the `4a5419e2`
lockfile's `plat-peer-host` binds its `p` to two entries of one package by platform class, which
BC-12 links per platform for the root and workspaces and BC-15's per-platform edges carry for a
package. The edge now selects its entry by platform (R4 "An entry's alias"). No error remains for
an entry's alias: the entries an alias binds by class are one package by construction. `main`
binds the alias once for every platform (verified in a worktree of `main` on that lockfile:
`p`'s `q` is `q-darwin@1.0.0` on every platform), so the change is one in what a consumer's build
links and is numbered **BC-16**; ID-7 is removed. The lockfile and BC-13's hand-written one move
to `bun/tests/npm/conformance/accepted/`, which both conformance runs compare (T110).

**T111 decided by the lead, under the user's delegation (2026-11-21)**: the fourth Claude review
found that a declared dependency the store links on no platform class lost its
`:node_modules/<package>` target, which `main` generated (P4, FR-014, SC-005). Every declared
dependency now has its target; where the store links it nowhere the target carries nothing and its
bins are compatible with no platform (R4 "Declared dependencies the store links nowhere"). What
such a target links is BC-1's, BC-3's, BC-5's or BC-7's change; no target name changes, so no new
BC is numbered.

**T112 decided by the lead, under the user's delegation (2026-11-21)**: the fourth Claude review
found that a package restricted to `riscv64` or `netbsd` was disabled on every target, including
the one it is for. Bun has no behavior for such a target (it refuses it as `--cpu`/`--os`), so
there is no Bun result to follow; npm's `checkList` is the rule research R3 records for these
values and the one `main` applied. The adapter reads a list with it for those values only (R3
"Targets Bun does not name"); for those values the branch now reads a list as `main` does, so no
BC is numbered, and BC-13 states the exception.

**T140 decided by the lead, under the user's delegation (2026-11-21)**: Codex's sixth review found
that a member counted as declared wherever `declared_targets_aspect` reached its target through an
attribute it walks, so `consumer_library(extras = [member])`, which returns a `BunLibraryInfo`
without the member's files, passed and the store linked an uncopied directory. The member check
now decides from what the program's `BunLibraryInfo` carries: the aspect collects each target that
provides `BunLibraryInfo` with that provider's `srcs` and `data` depsets, through every attribute,
and `run.bzl` `_member_links` accepts a member only where every one of those files is in the copy
tree (`File` identity, not path). The list of skipped attributes (T124, T132) is gone: a member in
`srcs`, `data`, `tools`, `entry_point` or `preload` fails because its `package.json` is not copied,
and every T124 and T132 test keeps failing with the "add … to its deps" message. "Package record"
in T140 is read as the member's `package.json`, which `workspace_target_name`'s doc asks the member
target to carry; the member's npm package records are not compared, as no root-module fixture has a
member with npm dependencies to test it on (constitution II), and a member whose files are copied
gets its records through the same `BunLibraryInfo` unless a rule drops them on purpose.

**T146 decided by the lead, under the user's delegation (2026-11-22)**: the eighth Claude review
found that a member whose `workspace_target_name` target is an `alias` failed BC-4's check, because
`run.bzl` compared the member's label with the labels `declared_targets_aspect` collects, and Bazel
reports a target reached through an alias under the label of the target the alias names (checked
on Bazel 9.2.0 in `/tmp/bun006-alias-probe`: both `Target.label` in the depending rule and the
aspect's `target.label` are the named target's, the aspect is not applied to the alias, and
`Target` has no field holding the alias's label). The hub cannot resolve the alias itself: it does
not depend on the member's target, so that a member that depends on the package forms no cycle
(BC-4). The member is therefore also recognized by its `package.json`, the source file
`<member package>:package.json`: a collected target whose files are all in the copy tree (T124,
T140) counts as the member's target where its label is the member's or its files hold that
`package.json`. The link still points at the member's package, the directory of that `package.json`,
where Bun's member is and where the copy tree puts the file, rather than at the package of the target
the alias names, which can hold none of the member's files (in `conformance_member_alias` it is the
fixture's root package). A `workspace:` link (`npm_package.bzl` `_npm_member_link`) keeps feature
003's rule, the package of the target Bazel reports; for an alias of a target in the member's own
package, both are the member's package.

**T147 decided by the lead, under the user's delegation (2026-11-22)**: the eighth Claude review
found that the loader read an npm row's integrity only for its algorithm and a git or GitHub row's
`.bun-tag` not at all, so it loaded lockfiles the pinned Bun refuses (FR-004). `Integrity::parse`
is carried over with the standard-base64 decoder it calls (BASE64, Part 1, the same tag's
`src/base64/lib.rs`): an entry counts where its digest is standard base64 without padding of at
most the algorithm's length, so a shorter digest loads, as the pinned Bun loads `sha512-AA`. The
tag and the integrity after the info object of a tarball, git or GitHub row (L36, L37) are read
only to refuse; they decide no binding. The pinned Bun loaded or refused each of 75 texts as
`Integrity::parse_entry`, `parse_integrity` and `is_safe_resolved_tag` read (`tdd-log.md` T147),
and canary C-ROWTAIL pins the form it writes, through a GitHub dependency served on the loopback
registry with `GITHUB_API_URL` (which the pinned Bun's GitHub download reads, E16); a `git+` row
would need a git executable, which the canaries do not run (constitution III), and the writer
prints both forms in one branch (LOCK L860–L894). The refusals reach a lockfile with a git or
GitHub row too, which rules_bun does not fetch (FR-010, ID-4) but whose dependencies it links
(BC-8).

**T148 and T149 decided by the lead, under the user's delegation (2026-11-22)**: the eighth Claude
review found that the ruleset failed evaluation of two lockfile forms the pinned Bun installs. Both
are numbered as Behavior Changes (BC-17, BC-18, Part 5) before the fix, as the spec requires of a
difference no BC explains. BC-17 follows the loader the carry-over already has: the package of a
`name@version` is the first row's (`_append_package_dedupe`), so the extension's check that every
row agree on the download is removed, and the package repository downloads from the first row's
URL with its integrity, as the pinned Bun does. `conflict.test.ts` now builds both lockfiles and
checks the one request; the conformance test compares the pinned Bun's install of each, which it
linked alike before the change and after it while it did not run the extension's checks (T150), and
since T160 fails both with `main`'s check and passes them after the change.

**T155 and T156 decided by the lead, under the user's delegation (2026-11-22)**: the convergence
check of phase 34 found two lockfile forms the pinned Bun loads that the ruleset fails without
listing the difference. `lockfileVersion` 0 is the version BLOG shows and Bun 1.4.4 loads, so it is
read as Bun reads it (BC-19): every field and slot reads as on version 1 except a `packages` row of
a workspace, which on version 0 carries the member's dependencies in slot 1 (L2553–L2591), while the
`workspaces` entry of a member makes no package (L2263). That object is a field neither BLOG
describes nor the pinned Bun writes (it floors a version-0 lockfile to 1 on re-save, L170–L177), so
constitution V allows no reader for it: such a row fails evaluation with the remedy `bun install`
with Bun 1.4.4, which rewrites the lockfile as version 1 (ID-11, canary C-VER0). The pinned Bun
would not install most such lockfiles either: a member's dependencies stay unresolved on version 0
(L2859, L2920), so its frozen install fails in `verify_resolutions` ("is-number@7.0.0 failed to
resolve", `PackageManager/PackageManagerResolution.rs` L120–L268, E17); only for a member without
dependencies does Bun 1.4.4 plan the install (`--dry-run`), and Bun 1.4.2 refuses even that one ("No
matching version for workspace dependency"), so no such project is compared. A URL with user
information in `bun.lock` keeps failing evaluation, as feature 005 FR-002 and constitution III
require (credentials only through Bazel's downloader), and is listed as ID-10, since the pinned Bun
loads it.

**T160 decided by the lead, under the user's delegation (2026-11-22)**: with the extension's
evaluation checks on the conformance test's ruleset side, one compared lockfile the pinned Bun
installs fails: `bun/tests/npm/fixtures/bins_clash`, whose package `clash-bin@1.0.0` has the bins
`a b` and `a:b`, which the naming rule of the generated targets (`_NPM_DOC` "Generated targets")
writes as one target name `a_b`. Bun links both bins; the ruleset cannot declare two targets of one
name in one package, and renaming either would change the public naming rule (constitution I, P4),
so the failure stays and is listed as ID-12. The test excludes only that failure, recorded by the
ruleset side as `target_names`, and still compares the project's links. Two packages of one
workspace whose names become one target name fail the same way; no lockfile a test holds reaches it
(unverified). The 23 other lockfiles it failed at first were the integration tests' `{REGISTRY}`
placeholder, which the oracle fills in with its registry and the ruleset side then did not; it now
reads the files as the oracle installs them (`tdd-log.md` T160).

**T169 and T170 decided by the lead, under the user's delegation (2026-11-22)**: the eleventh
Claude review found two gaps. An optional dependency under `unresolved` lost the bin targets `main`
generated for it, from the row of its name `main` linked it to; its link keeps them, compatible
with no platform (T111), so no generated target name of `main` is gone (SC-005; Part 3 "Declared
dependencies the store links nowhere"). The reader skipped a `root:` row whole, so it loaded a row
without its binaries object, or with a non-object there, which Bun refuses (L2614, L2623); it
refuses both now. Other refusals of the loader need a key written twice in one JSON object (a
catalog entry, L1782; the root workspace, L2126; a `packages` key, L2759); `json.decode` keeps the
last value of such a key (bazel.build: "If the same key string occurs more than once in the object,
the last value for the key is kept"), so the reader cannot see the first and loads the lockfile.
The twelfth review widened this to every key (T174): where Bun reads one field it reads the first
value (`lockfileVersion` `2` then `99` installs in Bun and fails evaluation), so ID-13 lists every
key written twice, refused or read. No Bun writes any of these forms.

**T171 decided by the lead, under the user's delegation (2026-11-22)**: the `root:` row T170 reads
is access L38, pinned by canary C-ROOTROW and compared through the corpus project
`conformance_root_row`, which the pinned Bun writes and links as the ruleset does. The task asked
for that project to be compared by both oracles, which Bun 1.4.2 does not allow: it cannot write a
member's `workspace:*` dependency on the root, and the lockfile it writes for `workspace:../..`
(the same `root:` row) its own frozen install refuses (E18). A consumer on Bun 1.4.2 therefore never
holds such a lockfile, so the project is listed in `NOT_APPLICABLE_1_4_2` with the reason (FR-013,
US5 scenario 2) rather than compared. Bun 1.4.2 installs the lockfile Bun 1.4.4 writes, linking the
member's dependency to a copy of the root in its store (`node_modules/.bun/<name>@root`) where 1.4.4
links the root itself; that lockfile is not one Bun 1.4.2 writes, so the spec's Edge Case (a
lockfile 1.4.2 writes that 1.4.4 links differently) does not reach it.

**T175–T178 decided by the lead, under the user's delegation (2026-11-22)**: each of the four
lockfile forms the thirteenth review found is written by the pinned Bun and installs, so each is
linked as Bun links it and listed as a Behavior Change (BC-20 to BC-23), as the spec requires of a
change from `main`. A local tarball is an unfetched entry (ID-4), like a tarball URL, since
constitution III allows only registry downloads verified by the lockfile's integrity, and its
dependencies are linked (BC-8). A `dependencies` or `devDependencies` `catalog:` reference without
an entry keeps failing evaluation, as Bun refuses it (E20). Of Bun's override parser only the two
forms found are carried over (`$<name>`, a nested object); other forms Bun ignores with a warning
(an empty key, `-`, `patch:`, a non-string value) keep failing evaluation as forms rules_bun does
not compare, which no corpus project reaches. An unfetched entry's instance ID is numbered as a
colliding hash is, so no `:node_modules/...` name changes and only those entries' hub-internal
targets, which are not public, are renamed.

**Stop rule for the final reviews (the lead, under the user's delegation, 2026-11-22)**: thirteen review rounds before the final gate each
found new differences, mostly in forms only a hand-written lockfile reaches, while Codex approved the
last six. After T175–T178, the final gate is approved unless a review finds a regression against
`main` or a difference on a lockfile the pinned Bun writes that this branch introduced; any other
difference found then is listed as a follow-up in the PR body, not fixed in this feature.

**Follow-ups after feature 006 (the lead, under the user's delegation, 2026-11-22)**: the fourteenth final review found four differences
on lockfiles the pinned Bun writes and installs that `main` has too, each in `compare_manifests` or
the overrides reader. Under the stop rule above they are not fixed in this feature; they are known
defects under P3, listed in the PR body and to be fixed in a later feature:
- override values Bun ignores with a warning (a non-string, `""`, `"-"`) fail evaluation
  (`overrides.bzl` about L105–L127);
- a top-level `catalog`/`catalogs` is merged with `workspaces.` ones, while Bun reads the top level
  only when `workspaces` exists and holds neither (`Package.rs` L3418–L3440; `workspaces.bzl` about
  L253–L256);
- a peer listed only in `peerDependenciesMeta` (Bun writes `"*"` and `optionalPeers`) fails
  (`workspaces.bzl` about L320);
- a name in both `dependencies` and `optionalDependencies` (Bun keeps the optional one, L2473)
  fails (`workspaces.bzl` about L320).

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
- **E15** (C-ROOTFIELDS, T130): a project declaring `dependencies { a: "1.0.0" }` and
  `trustedDependencies: ["a"]` is written as `"configVersion": 1` (LOCK L373; a project without a
  lockfile gets `ConfigVersion::CURRENT`, lockfile.rs L558) and `"trustedDependencies": ["a"]`
  (LOCK L510–L527); a `--frozen-lockfile` install loads that text and keeps it. With either field
  removed from the held lockfile, a frozen install keeps the text without it.
- **E16** (C-ROWTAIL, T147): with `GITHUB_API_URL` set to a local server, `bun add
  github:o/r#<commit>` requested `/repos/o/r/tarball/<commit>` and wrote
  `"r": ["r@github:o/r#0123456", {}, "o-r-0123456", "sha512-…"]`; a tarball URL dependency is written
  `["<name>@<url>", {…}, "sha512-…"]` (E12). A frozen install loads both.
- **E17** (T155, T156, 2026-11-22): `bun install --frozen-lockfile --dry-run` with Bun 1.4.4 and
  1.4.2 loads a `lockfileVersion` 0 lockfile without workspace rows; with a member that no
  `packages` row holds, both refuse it ("Failed to resolve root workspace dependency 'm'"); with a
  member row `["m@workspace:packages/m"]`, both refuse it ("Missing dependencies object"); with a
  member row whose slot 1 is `{}` and a member without dependencies, Bun 1.4.4 plans the install
  (exit 0) and Bun 1.4.2 fails ("No matching version for workspace dependency"); with a member whose
  dependency is `is-number@7.0.0` (the registry's integrity), Bun 1.4.4's frozen install fails
  ("is-number@7.0.0 failed to resolve", exit 1), while the same lockfile stamped 1 without the
  object installs, and a non-frozen install rewrites the version-0 lockfile as `"lockfileVersion":
  1`. Bun 1.4.4 loads a lockfile whose npm row's URL is `http://u:t@127.0.0.1:9/b/-/b-1.0.0.tgz`,
  and one whose root dependency and row are `http://u:t@127.0.0.1:9/b-1.0.0.tgz` (`--frozen-lockfile
  --dry-run`, exit 0).
- **E18** (C-ROOTROW, `conformance_root_row`, T171, 2026-11-22): a root package `x` with
  `"bin": { "xb": "cli.js" }` and member `w` declaring `"x": "workspace:*"`: Bun 1.4.4 writes
  `"x": ["x@root:", { "bin": { "xb": "cli.js" } }]` and links `packages/w/node_modules/x` to the
  root (`../../..`) and `packages/w/node_modules/.bin/xb` to its `cli.js`; with slot 1 removed, its
  frozen install refuses the lockfile ("Missing package binaries object"). Bun 1.4.2 fails that
  install ("Workspace dependency \"x\" not found"); with `"x": "workspace:../.."` it writes the
  same row, and its own frozen install of that lockfile fails ("No matching version for workspace
  dependency", Package.rs L1965 at bun-v1.4.2), while Bun 1.4.4 installs it. Bun 1.4.2's frozen
  install of the lockfile Bun 1.4.4 writes links `packages/w/node_modules/x` to
  `node_modules/.bun/x@root/node_modules/x`.
- **E19** (T172, 2026-11-22): `bun install --linker isolated` with Bun 1.4.4 of a project declaring
  `"x": "file:./a"`, `"y": "file:./b"` (two folders of package `foo`) and
  `"@s/long": "file:./dir-<70 x>/c"` writes the rows `["foo@file:a", {}]`, `["foo@file:b", {}]`,
  `["@s/long@file:dir-<70 x>/c", {}]` and names the store directories `foo@file+a`, `foo@file+b`
  and `@s+long@file+dir-<54 x>+29f4eee30e89905a`: the 81-byte resolution `file+dir-<70 x>+c` cut to
  63 bytes and `Bun.hash.wyhash` of all of it, as `write_resolution` does (Store.rs L366–L384).
- **E20** (T175–T178, 2026-11-22): `write_lockfiles.ts` with Bun 1.4.4 and with Bun 1.4.2 writes and
  installs the four corpus projects of R11 (`conformance_local_tarball`,
  `conformance_catalog_missing`, `conformance_override_forms`, `conformance_folder_ids`); Bun 1.4.2
  writes the same lockfiles except the override project's nested `a/b` row, `["b@file:./b", {}]`
  where 1.4.4 writes `["b@file:b", {}]`. Bun 1.4.4 writes the local tarball's row
  `["loc@loc-1.0.0.tgz", { "dependencies": { "a": "1.0.0" } }, "sha512-89Wi…"]` and stores it in
  `node_modules/.bun/loc@loc-1.0.0.tgz+f3d5a20e448a231c`, the first 8 bytes of the integrity
  (ISO L1353–L1368). `bun install` of a project whose `dependencies` (or `devDependencies`) hold
  `"q": "catalog:"` with no catalog entry fails ("q@catalog: not in catalog", "q@catalog: failed to
  resolve") and writes no lockfile; a frozen install of a hand-written lockfile holding that
  workspace dependency and no `q` row is refused ("Failed to resolve root prod dependency 'q'",
  LOCK L3338).
