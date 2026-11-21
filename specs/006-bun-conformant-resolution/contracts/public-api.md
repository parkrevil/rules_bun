# Contract: rules_bun Public API after feature 006

Constitution I: the public API is `bun/*.bzl`, `//bun/toolchain:execution_type`,
`//bun/toolchain:target_type`, `//bun/platforms/libc:libc` with its values, and the targets and
`defs.bzl` symbols the module extensions generate under their documented naming rules. This feature
adds, removes and renames nothing (FR-014, P4).

## Unchanged symbols

Every rule, macro, provider, module extension, tag class, attribute and generated target name of
features 001–005 stays. `:node_modules/<package>` and `:node_modules/<package>/bin/<bin>` keep their
names. Repositories named `<name>__...` (instance IDs) are not public API (`_NPM_DOC`) and may
change. Every package the root or a workspace declares keeps its `:node_modules/<package>` target,
also one the store links on no target platform (BC-1, BC-3, BC-5, BC-7), which then carries nothing
and whose bin targets are compatible with no platform (T111).

## What a consumer can observe

Only where the ruleset linked something other than the pinned Bun (FR-015). Each BC row is covered
by the conformance test (a difference before, none after) and listed in the PR; the R3 row by
`bun/tests/npm/platforms_test.bzl` `bun_rule_test`. The Intentional Differences ID-1 to ID-6 are the
spec's.

| Surface | Before (`main`) | After | BC |
|---|---|---|---|
| A package's optional dependency listed under `unresolved` while another package of that name is in the tree | linked to that package | not linked | BC-1 |
| A workspace named like a package the root aliases | links the root's or the aliased package's dependencies | links its own (`./<name>/<dep>`) | BC-2 |
| An optional or peer dependency of the root or a workspace without a key | evaluation fails ("declares …, which bun.lock lists no entry for") | not linked; no failure | BC-3 |
| A registry package's dependency on a workspace member | not linked | linked to the member by path, with no target dependency on it; a `bun_binary` or `bun_test` whose closure holds such a link without the member's target among its transitive `deps` (through targets that pass its `BunLibraryInfo` on: it counts only where every source and data file of its `BunLibraryInfo`, its `package.json` among them, is in the target's copy tree, so not through a `srcs`, `data`, `tools`, `entry_point` or `preload` attribute, a target without `BunLibraryInfo`, or a rule that returns `BunLibraryInfo` without the member's files, T124, T132, T140) fails analysis naming the package, the dependency and the member's target; a bin target (`:node_modules/<package>/bin/<bin>`) gets those members from the hub (T081), and the members that the packages those members declare link to, through any number of members (T123), each of which must be visible to the package that calls `npm_link_all_packages`, else Bazel's visibility error names it (T089) | BC-4 |
| A package's peer nothing provides and the lockfile does not resolve | evaluation fails (`missing_peer`) | not linked; no failure | BC-5 |
| Two keys holding one `name@version` whose walks find different versions | one instance per key, each with its walk's version | one package, bound as Bun's row evidence decides | BC-6 |
| A non-optional dependency whose package's `os`/`cpu` exclude the target platform | carried on every platform; its bins (`:node_modules/<package>/bin/<bin>`) compatible with every platform | not carried on that platform; its bins incompatible there, as an optional package's are (T117) | BC-7 |
| The dependencies of an unfetched entry (`unsupported_reason`) | not followed | followed: they get instances; the entry still fails analysis, no target name changes | BC-8 |
| An optional peer an ancestor's dependencies or the lockfile's own entry of that name provide | not linked | linked as the pinned Bun's isolated install links it | BC-9 |
| A dependency listed in a package's `bundleDependencies` | linked from the `<package>/<dep>` key | not linked; the package carries its own copy | BC-10 |
| A target reaching two store entries of one `name@version` that differ by peer bindings | analysis fails ("a target holds one instance of each package version") | both carried, each in its own store directory `<name>@<version>+<peer hash>` | BC-11 |
| A dependency of the root or a workspace that the store binds to different entries on different platform classes | evaluation fails (on the branch before BC-12; on `main` one binding for every platform) | linked per target platform through `select()` on the `[os, cpu, libc]` classes; a package entry's dependency bound by platform is BC-16's | BC-12 |
| A package whose `os`, `cpu` or `libc` list npm's `checkList` and Bun's `Negatable` read differently (`["linux", "any"]`: every OS in Bun, only Linux in npm), or an optional package with `libc` on a platform other than Linux | carried by npm's rule (`checkList`; `libc` matches no other OS) | carried by Bun's rule (`Meta::is_disabled`; off Linux `libc` excludes nothing), research R3, plan gate 2026-10-29; on a target `os` or `cpu` Bun does not name (`netbsd`, `riscv64`), by npm's rule as on `main` (T112) | BC-13 (`any` and order), BC-14 (`libc` off Linux) |
| A package's dependency the store links on some platform classes only, held by the target through another link on others | linked from the package wherever the target holds it | linked from the package only where the store links it (`select()` on the instance's edges) | BC-15 |
| A package's dependency that the store binds to different store entries on different platform classes (one package under other peer bindings) | one binding for every platform (on the branch before T107, evaluation fails: the former ID-7) | linked per target platform through `select()` on the instance's edges (`edge_targets`) | BC-16 |
| `_NPM_DOC` | states the old rules above | states Bun's, the Intentional Differences ID-1 to ID-6, and the CI runner labels the tests ran on | — |

Diagnostics added, each in English and naming the `bun.lock` label (or, at analysis, the target):

- a lockfile Bun 1.4.4 refuses to load fails evaluation naming the key or field (FR-004; research
  Part 4, "Loader refusals"), among them a container that is not an object (`patchedDependencies`,
  `overrides`, `catalog`, `catalogs`, `packages`, `workspaces`, a workspace) and a root `name` that
  is not a string (T079), and a dependency map (`dependencies`, `optionalDependencies`,
  `peerDependencies`, `devDependencies`, a workspace's dependency kinds) that is not an object of
  strings (T080), and a `configVersion` that is not a whole number of at least 0 and a
  `trustedDependencies` that is not an array of strings (T125), a present JSON `null` in each of
  these fields included (T139), each naming the field without printing the value;
- a malformed `unresolved` or `optionalPeers`, `null` included (T139), fails naming the entry and
  the field without printing its value;
- BC-4: a target whose closure holds a link to a workspace member it does not declare fails
  analysis naming the package, the dependency and the member's target to add to its `deps`;
- a package, the root or a workspace whose link to a workspace member the store makes on some
  platform classes only, or makes to a package on others, fails evaluation naming it and the
  dependency (T090; no Bun-written lockfile reaches it, research R4 "A member link"), and so does
  the root or a workspace whose dependency the store binds to different packages, not only to
  other peer bindings of one package, on different platform classes (T097; no Bun-written
  lockfile reaches it, research R4 "A holder's alias"). The failure of a package's dependency
  bound by platform (the former ID-7) is gone (BC-16).

Diagnostics that change: BC-3's and BC-5's evaluation failures disappear; the analysis failure of
two instances of one package version in one target now applies only to instances with one store
directory from several lockfiles and reads "one instance of each package version and peer
bindings" (BC-11).
