# Implementation Plan: npm Dependencies from `bun.lock`

**Branch**: `003-npm-dependencies` | **Date**: 2026-10-19, updated 2026-10-20 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-npm-dependencies/spec.md` (Revision 5)

**Status**: Phase 0 and Phase 1 done. Spec Revision 4 adopted G1–G4; the implementer's plan fixes
A–M of 2026-10-20 are applied (research Part 1 maps each fix to its section) and spec Revision 5
restates the requirements they touch. No gap is open: every decision uses documented APIs.

## Summary

A module extension `npm` in `bun/extensions.bzl` reads a consumer's `bun.lock` (JSONC, versions 1–3)
and root `package.json`, checks them against each other and the workspace members (overrides
normalized first, R9), resolves every dependency and peer statically into package instances whose
identity includes their resolved edges (R2), and creates one hub repository per lockfile and one
lazily fetched repository per `name@version`. A package repository downloads and extracts the
archive with Bazel's own `repository_ctx.download_and_extract` and the lockfile's integrity (R3,
R4); one bazel-lib copy action per package turns the extracted files into an instance tree. The
hub's `defs.bzl` provides `npm_link_all_packages()`, which creates `:node_modules/<package>` and
`:node_modules/<package>/bin/<bin>` targets in each workspace package (R7). The root-only tag
`npm.replace_package` swaps a download for a checked-in archive, for every lockfile, verified
against the lockfile's integrity by a build action (G3). `bun_binary` and `bun_test` lay the
packages they reach out in their own copy tree as rules_js's strict store: each instance tree copied
into `<name>.bun/.store/`, linked by directory symlinks (junctions on Windows, which keep the disk
cache portable, G1), with direct links in each workspace package's `node_modules` (R5); the load
guard admits each store entry as a declared directory and rejects everything else, including a
source-tree `node_modules` reachable through `execroot/_main` (R6, G9). Optional platform packages
are chosen by `select()` on the target platform (R8). No lifecycle script runs (R12). The JSX proof
renders a React component with `react-dom/server` in a `bun_test` and a `bun_binary`, in the root and
in `e2e/smoke`, with Bazel's default settings on every OS. Failures at evaluation and fetch are
tested Bazel-in-Bazel by `bun_test` targets that spawn a pinned Bazel, offline (G5, G10).

## Technical Context

**Language/Version**: Starlark on Bazel 9.2.0 (`bazel_compatibility = [">=9.2.0"]`); JavaScript run
by Bun 1.4.2 (launcher, guard, integrity check of replaced packages, test helpers, integration
runner, loopback registry)

**Primary Dependencies**: no new non-dev dependency; existing `bazel_lib` 3.0.0
(`copy_to_directory_bin_action`, `copy_directory_bin_action`), `bazel_skylib` 1.9.0 (`selects`),
`platforms` 1.1.0, `hermetic_launcher` 0.0.16, `rules_shell` 0.6.1. Dev-only `http_file`
repositories (`use_repo_rule`, with integrity, `dev_dependency = True` on each call): the Bazel
9.2.0 binary per platform (G10), and the module source archives and Bun release archive the
loopback server gives the inner builds (G5). They and every test-only extension usage are declared
directly in `MODULE.bazel`; rules_bun's `MODULE.bazel` uses no `include()`, which bazel.build allows
only to "the root module and modules subject to a non-registry override" (research G5).
`tar.bzl` and `rules_bazel_integration_test` are not used (R4, G10).

**Storage**: N/A (Bazel repository cache and output base only)

**Testing**: skylib `unittest` for the JSONC reader, lockfile reader, scope-aware key split,
overrides normalization, resolver (peer context, instance identity, cycles) and glob matcher on
fixture lockfiles the pinned Bun wrote; `analysistest` for generated targets, platform selection on
all five platforms, instance uniqueness, copy-tree placement and failures; `bun_test` real runs
(JSX proof, layout, phantom, peers, workspaces, bins, guard); both on root fixture hubs whose every
package is replaced through `npm.replace_package` (G3), since an analysis test that loads an
instance target fetches its package repository too; Bazel-in-Bazel `bun_test` targets with a loopback registry for evaluation and fetch failures,
credentials, mirrors, laziness (SC-005), host independence (US2-7); canaries C-* (research Part 3);
`e2e/smoke` against the public npm registry; CI network-denied job (R16) and Windows disk-cache
check (G1)

**Target Platform**: linux-x64, linux-aarch64, darwin-x64, darwin-aarch64, windows-x64; CI on
ubuntu-latest, macos-latest, windows-latest

**Project Type**: Bazel ruleset (library)

**Performance Goals**: SC-010 bounds for the 2,000-package fixture on Linux CI (research G8):
evaluation ≤ 10 s; actions per target exactly `P + E + L + A`; launcher start ≤ 2 s over the
no-package baseline, measured on one clock (`Date.now()`)

**Constraints**: no tool run in repository rules and no host tool in actions (III); `ctx.actions.run`
only (VI); documented APIs only (V); every `bun.lock` access the blog post does not describe has a
canary (FR-024); tree artifacts hold only files and directories; guard pattern ≤ 1,048,576
characters; Windows `MAX_PATH` for the longest store path (G8); nothing credential-related in
attributes, files or output (FR-020); English everywhere

**Scale/Scope**: about 10 new Starlark files in `bun/private/` (extension, reader, resolver, glob,
overrides, repositories, hub generation, link and instance rules), changes to `run.bzl`,
`library.bzl`, `providers.bzl`, `launcher.js`; fixtures and tests under `bun/tests/npm/`,
`bun/tests/canary/npm/`, `bun/tests/integration/`; `e2e/smoke` gains `package.json`, `bun.lock`, a
JSX app and test

No NEEDS CLARIFICATION remains.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Pre-research | Post-design | Evidence |
|---|---|---|---|
| I. Public API boundary | PASS | PASS | New public names: `npm` extension (tags `translate_lock`, `replace_package`) in `bun/extensions.bzl`; generated targets under documented naming rules (constitution I, "targets that the ruleset's module extensions generate"); the hub's generated `defs.bzl` macro `npm_link_all_packages`, public under constitution v2.2.1 I, which makes the `.bzl` symbols the extensions generate public API (plan fix J); a new `packages` field on `BunLibraryInfo`. Implementation in `bun/private/`; tests in `bun/tests/`, `e2e/smoke/`. [contracts/public-api.md](contracts/public-api.md). |
| II. Tested claims | PASS | PASS | Every scenario maps to a test ([data-model.md](data-model.md) "Test map"); Windows and macOS claims only after CI; junction resolution by Bun on Windows, Windows-invalid names (C-WINNAME records what Bazel does), native add-ons, WebAssembly and archives with symbolic links are reported unverified until a test covers them. |
| III. Pinned, verified downloads | PASS | PASS | Each package is downloaded and extracted by `repository_ctx.download_and_extract` with the integrity the registry published, as the lockfile records it (R3, R4); no repository rule runs a tool. A replaced package's archive is checked against that integrity in a build action whose output every carrying target needs (G3). Copies run bazel-lib's registered toolchains; the hash check runs the execution Bun. Integration-harness downloads (Bazel binaries, module and Bun archives) are `http_file`s with integrity (G5, G10). |
| IV. Minimum dependency versions | PASS | PASS | No new non-dev `bazel_dep`; no version changes. Dev additions are `http_file` repositories only. |
| V. Supported APIs only | PASS (approvals: `bun.lock` fields 2026-10-18, rules_js 2026-10-18) | PASS | Sources for every API in research Part 6; `bun.lock` accesses L2–L16 and L18–L22 under the 2026-10-18 approval with canaries (Part 3); rules_js patterns, including `npm_replace_package`'s scope (plan fix I), recorded with the approval and why no bazelbuild or bazel-contrib pattern serves (Part 4). Rejected for V: `--distdir` (deprecated), a `--downloader_config` rewrite to `file://` (G3), a source-directory reference to the extracted package (discouraged by `filegroup` docs, R4), Bun's store hash, Bun's built-in trusted list. |
| VI. Shell-free actions; launchers | PASS | PASS | Actions: `ctx.actions.run` (copy, hash check), `ctx.actions.symlink`, `ctx.actions.write`; executables reuse feature 002's launchers (bins share `bun_binary`'s implementation). The repository's own integration tests are `bun_test` targets, not `sh_test` (G10). |
| VII. Releases from tags | PASS | PASS | No `version`; additions only (a new provider field is optional). |

Complexity Tracking: none.

## Gate decisions

Details, evidence and options in research.md Part 1.

| Gap | Decision |
|---|---|
| G1 `--windows_enable_symlinks` | spec Revision 4: requirement dropped (junctions through `target_type = "directory"`); E8 shows junctions keep disk-cache hits across output bases and workspace paths; Windows CI runs with and without the flag and checks cross-output-base cache hits |
| G2 Windows-invalid file names | spec Revision 5: no promised failure; Bazel's extractor decides; canary C-WINNAME pins it on Windows |
| G3 root fixtures | spec Revision 4: root-only `npm.replace_package` with an integrity check; applies to every lockfile, never fails for an unlisted package (rules_js semantics) |
| G4 empty `trustedDependencies` | spec Revision 4: absent and empty treated alike, not read; documented; canary C-TD |
| G5 offline inner builds | own empty repository cache per inner build; modules from a local `file://` registry and `--override_module`; archives from the loopback server; `block-network` on Linux, request log elsewhere |
| G6 `libc` | not in `bun.lock`; all variants included; documented |
| G7 lockfile versions | 1, 2, 3 accepted (canaries C-VER, C-VER1); 0 and others rejected (FR-007) |
| G8 SC-010 bounds | evaluation ≤ 10 s; actions `P + E + L + A`; launcher ≤ 2 s over baseline (`Date.now()`); copy cost and Windows path length recorded |
| G9 source-tree `node_modules` | reachable through `execroot/_main` unless `ignore_directories` covers it (then Bun's module-not-found error, spec Revision 6); the guard rejects every module outside the declared set; "cannot load" in spec Revision 5 |
| G10 integration harness | `bun_test` spawning a pinned Bazel from `http_file`; not `manual`; `test_suite` `integration_tests` |

## Project Structure

### Documentation (this feature)

```text
specs/003-npm-dependencies/
├── spec.md
├── plan.md              # this file
├── research.md          # Part 1 gaps G1–G10; Part 2 R1–R17; Part 3 lockfile accesses and canaries; Part 4 approvals; Part 5 evidence; Part 6 sources
├── data-model.md        # entities, generated repositories and targets, providers, layout, launch config, test map
├── quickstart.md        # validation commands
├── contracts/
│   └── public-api.md    # extension tags, hub defs.bzl, target naming rules, provider field, documented limits
├── checklists/requirements.md
├── tdd-log.md           # written during /speckit-implement (FR-030 records)
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
MODULE.bazel                          # no new bazel_dep; no include(); dev (dev_dependency = True): http_file repos (Bazel binaries, inner-build archives), fixture_results, npm.translate_lock + replace_package for every package of the root fixture hubs
.bazelrc                              # test:linux --modify_execution_info=TestRunner=+block-network (G5)
bun/
├── extensions.bzl                    # + npm (re-export)
├── defs.bzl                          # doc: packages in deps; JSX limitation removed after US1 passes on 3 OSes (FR-021)
├── private/
│   ├── npm_extension.bzl             # tag classes, module walk, hub name conflicts (FR-032), name@version conflicts, reproducible metadata
│   ├── jsonc.bzl                     # comments and trailing commas outside strings (FR-007)
│   ├── lockfile.bzl                  # accesses L1–L16, L18–L22 only (research Part 3); scope-aware key split
│   ├── workspaces.bzl                # Bun glob matching, member discovery, package.json comparison (FR-006)
│   ├── overrides.bzl                 # overrides/resolutions precedence and normalization (R9)
│   ├── resolve.bzl                   # key-path walk, peers in workspace context, instance identity, cycles, closures (R2)
│   ├── npmrc.bzl                     # registry and scope keys only (R11)
│   ├── npm_repositories.bzl          # package repository rule (download_and_extract or extract of a replacement, renames, BUILD); hub repository rule (BUILD, defs.bzl)
│   ├── npm_package.bzl               # instance-tree rule (copy_to_directory, replace_prefixes), replacement check, link rule, bin rule, unsupported-entry rule
│   ├── providers.bzl                 # BunLibraryInfo.packages; private instance/link providers
│   ├── library.bzl                   # merge packages transitively (FR-014)
│   ├── run.bzl                       # store copies, edge and direct links, instance uniqueness (US5-4), launch config "directories"; bin copy trees under _npm_bin/
│   └── launcher.js                   # copy-tree root for programs; directory prefixes in the guard trie (R6); RULES_BUN_LAUNCH_TIMESTAMP (G8, private)
└── tests/
    ├── npm/                          # reader/resolver/glob/overrides unit tests, analysis tests, real runs, fixtures (registry/, lockfiles/, workspaces/)
    ├── canary/npm/                   # C-* canaries (research Part 3); test_suite canaries
    └── integration/                  # bun_test Bazel-in-Bazel runner, loopback registry, local registry fixtures, inner workspaces; test_suite integration_tests
e2e/smoke/
├── REPO.bazel                        # ignore_directories(["**/node_modules"]) as documented to consumers
├── package.json, bun.lock            # react, react-dom (public registry)
├── MODULE.bazel(.lock)               # npm.translate_lock; use_repo hub
└── jsx/                              # BUILD (npm_link_all_packages at root package), component, bun_test, bun_binary
.github/workflows/ci.yaml             # integration suite on 3 OSes; Windows with and without the flag and the disk-cache check (G1); C-WINNAME on Windows; network-denied Linux job; US2-7 comparison; SC-010 check
```

**Structure Decision**: keep the baseline layout of features 001 and 002. The lockfile pipeline is
split into pure Starlark modules (`jsonc`, `lockfile`, `workspaces`, `overrides`, `resolve`,
`npmrc`) that unit tests call directly; repository rules and build rules only consume their results.
The hub carries all generated targets except the per-workspace links, which the macro creates in
the consumer's packages, as rules_js does; the instance-tree target lives in each package
repository.

## Implementation Order

Dependencies drive the order; tasks.md is authoritative. Each behavior step records a genuine red
first (FR-030) in `tdd-log.md`. Where Bazel owns the behavior or it cannot be produced before
implementation (plan fix K, research R15), the step says so: **mutation** means feature 002's
procedure (a mutation that breaks the behavior, marked and reverted), **characterization** means a
test of behavior no change of rules_bun can break, recorded with the reason. Canaries record a red
by altering their pinned access.

1. **Setup**: record the starting state (root and `e2e/smoke` pass). Fixture tooling: the
   loopback registry and packing scripts (research Part 5) under `bun/tests/npm/registry/`;
   generate and check in fixture lockfiles and archives with the pinned Bun.
2. **G5 and G10 proof (integration infrastructure)**: one `bun_test` that runs the pinned Bazel on
   an inner module that loads rules_bun and evaluates offline: own empty repository cache, local
   registry, `--override_module`, loopback archives, `block-network` on Linux. Red first (no
   harness). If it cannot pass without external network, stop and report (FR-004). The inner flags
   it needs are recorded in research G5.
3. **Reader** (FR-007, L1–L16, L18–L22): JSONC unit tests (comments, trailing commas, both inside
   strings), version and shape checks, scope-aware key split (H); each canary, C-VER1 included, in
   the step that adds its access.
4. **Workspaces and comparison** (FR-006, R9): glob unit tests, the Bun-comparison test over fixture
   trees, catalogs, overrides normalization and precedence for every accepted form (G), member
   add/remove (US4-5 via Bazel-in-Bazel), error messages.
5. **Resolver** (R2, FR-017): key-path walk, aliases, peers (provided, workspace-context fallback,
   optional absent, missing), peer cycles, instance identity from the edge map (two entries of one
   `name@version` with different resolutions), closures; unit tests on E1-like fixtures.
6. **Repositories and hub** (FR-005, FR-008, FR-009, FR-010, FR-032, R3, R11, R13): extension tags,
   reproducible metadata (no `MODULE.bazel.lock` entry), URL construction from `.npmrc`, unsupported
   entries as failing targets, hub name conflicts, `name@version` URL/integrity conflicts (M);
   evaluation-time failures in Bazel-in-Bazel.
7. **Extraction and replacement** (R4, G3, FR-026, FR-033–FR-035): `download_and_extract` with
   `strip_components = 1`, renames of `BUILD` files and label-invalid names restored by
   `replace_prefixes`, exclusions, non-`package/` top directory, an archive with `BUILD` files and
   one with a space in a file name; replaced archives with the integrity check for each of
   `sha256`, `sha384`, `sha512` (red: a wrong archive is accepted; Bazel-in-Bazel); replacement
   across two lockfiles, an unlisted package that is ignored, and evaluation failures for a
   non-root use and a double replacement (I).
8. **Layout and guard** (FR-003, FR-013, FR-021, R5, R6, G9): analysis tests of copies and links,
   then real runs: direct import, scoped package, library import (US1-3), phantom (US1-7: with no
   source `node_modules`, and with an ignored and an unignored one holding the package), undeclared
   package (US1-5), two versions (US1-6), guard directories; the JSX proof (US1-1, US1-2) and
   React's single instance (US5-1). No lifecycle script (FR-023): **mutation** (the instance rule
   made to run the fixture's `postinstall`, so the marker appears). Isolation still holds with
   packages (FR-022): **mutation** of feature 002's isolation (auto-install, `bunfig.toml`, `.env`).
9. **Peers across targets and uniqueness** (US5-2–US5-4, including two instances of one
   `name@version` that differ by an ordinary dependency).
10. **Workspaces in targets** (US4-1–US4-3, US4-6, FR-015): member links, member targets,
    per-member versions, all four dependency kinds.
11. **Platforms** (FR-016, US3, SC-004): config settings, analysis tests on all five platforms,
    exec-configuration tool test, the no-match fixture error on a CI platform.
12. **Executables** (FR-018, US6): bin targets, naming rule, copy trees outside `node_modules/`
    (analysis test, M), non-JS entry failure, `directories.bin` absence, `bazel run` and
    `run_binary` tool use.
13. **Fetching** (US2, US7, SC-005; Bazel-in-Bazel): integrity mismatch (US2-1, **mutation**:
    integrity dropped from the download), missing integrity (US2-2), lazy fetch with an unreachable
    package and request counting (US2-3, SC-005, **mutation**: every package repository referenced
    from the hub), credential helper and `.netrc` (US7-3, US7-4, **mutation**: `auth` dropped),
    failure without credentials (US7-2, **characterization**: Bazel's download error), mirror by
    `--downloader_config` (US7-5, **characterization**), `.npmrc` scope mapping (US7-6), auth values
    ignored (US7-7), host-independent repository set (US2-7: `bazel mod show_extension` and
    `bazel mod show_repo`) compared across CI OSes.
14. **Several lockfiles and modules** (US9).
15. **Scale** (FR-037, SC-010): the 2,000-package fixture generator; measurements (evaluation,
    actions, launcher start through `RULES_BUN_LAUNCH_TIMESTAMP`, per-target copy cost, largest
    guarded set) recorded in research G8; CI check enforcing the bounds; the longest fixture store
    path recorded and run on Windows CI.
16. **Consumer module** (US8): `e2e/smoke` JSX proof with the public registry, `ignore_directories`,
    `git grep` record.
17. **CI** (FR-027, FR-011, FR-036): integration suite on three OSes; Windows package tests with
    Bazel's defaults and again with `--windows_enable_symlinks`; the Windows disk-cache check (two
    output bases, one disk cache, cache hits for store-link consumers, G1); C-WINNAME on Windows
    (G2); network-denied Linux job; per-OS results recorded.
18. **Polish**: `doc` strings and the documentation of naming rules, limits (G2, G6, G9, Windows
    path length, symlinks and empty directories in archives, non-optional platform packages,
    `directories.bin`, lifecycle scripts and the empty-`trustedDependencies` difference (G4),
    `ignore_directories`, no Windows flag (G1)); remove the JSX limitation from `_FILES_DOC` after
    US1 passes on three OSes; hand-back checks from AGENTS.md; adversarial review.

## Upstream canaries (FR-024)

One canary per `bun.lock` access the blog post does not describe (research Part 3: C-VER, C-VER1,
C-WSKEY, C-WSNAME, C-WSDEPS, C-KEYPATH, C-SLOT0, C-URL1, C-URL2, C-INFO, C-INTEGRITY, C-INFODEPS,
C-PEERS, C-OSCPU, C-BIN, C-TD, C-OVERRIDES, C-CATALOG, C-PATCHED, C-ALIAS), plus C-WINNAME for
Bazel's extractor on Windows (G2). Feature 002's C1 (resolution from the real path) covers the
layout's reliance on realpath resolution. Each `bun.lock` canary runs the pinned Bun's installer
against a loopback registry inside the test (FR-011 exception), fails with an English message
naming the access, what to revisit and the source, and has a recorded red (SC-007). The canaries
form the `test_suite` `//bun/tests/canary/npm:canaries`.

## Risks

- **Bun through junctions on Windows** (G1): unverified until Windows CI; if Bun does not resolve
  through junctions, FR-004 applies and the user is told. Disk-cache portability rests on E8 until
  the CI check passes.
- **Renamed files** (R4): `BUILD` files and label-invalid names are renamed in the repository and
  restored by `replace_prefixes`; the fixtures with `BUILD` files and a space in a name pin it, and
  a generated name that already exists in the archive fails the repository rule in English
  (`repository_ctx.rename` fails when the destination exists).
- **Replacement archives** (G3): the root JSX proof's checked-in `react`, `react-dom` and
  `scheduler` archives must be byte-identical to what the registry served when the lockfile was
  written, or the integrity check fails; the fixture script fetches them once and records the
  integrity it verified.
- **Offline Bazel-in-Bazel** (G5): proven first (step 2); failure stops the integration-dependent
  requirements and is reported. The local registry must list every module the inner graph
  resolves, Bazel's built-in dependencies included; the maintenance script regenerates it.
- **Per-target copies at scale**: hardlinked copies keep the cost to one action per instance;
  SC-010 measures it, and a bound violation is a plan amendment, not a silent change.
- **Glob semantics**: Bun's glob is documented by syntax only; the Bun-comparison test is the
  safeguard, and any pattern the matcher rejects fails evaluation in English.
- **Override forms**: a manifest form no fixture pins fails evaluation in English (R9) rather than
  being compared by guess.
- **Archives with symbolic links** are reported unverified until a fixture covers them.
