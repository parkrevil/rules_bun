---

description: "Task list for npm dependencies from bun.lock"
---

# Tasks: npm Dependencies from `bun.lock`

**Input**: Design documents from `specs/003-npm-dependencies/`

**Prerequisites**: plan.md (Implementation Order steps 1–18), spec.md (Revision 5), research.md
(Part 1 G1–G10, Part 2 R1–R17, Part 3 L1–L22 and canaries, Part 5 E1–E8), data-model.md (test
map), contracts/public-api.md, quickstart.md

**Tests**: Requested (test-first, FR-030). Every behavior task writes or changes a test first,
runs it, and records in `specs/003-npm-dependencies/tdd-log.md` that it fails for the expected
reason, then implements until it passes. Where Bazel owns the behavior or the behavior exists
before its test (plan fix K, research R15), the task says **mutation** (feature 002's procedure: a
change that breaks the behavior, run, recorded, reverted) or **characterization** (no change of
rules_bun can break it; the reason is recorded). A canary records its red by altering its pinned
access in its fixture, then reverting (SC-007): the fixture is the project, lockfile text or
packument fields the canary's test file gives the pinned Bun (T008 `alter`), never the expectation
the canary compares with.

**Organization**: Grouped by user story in spec priority order, refining plan "Implementation
Order". Foundational holds what every story needs: fixture tooling, the offline Bazel-in-Bazel
harness (plan step 2), the pure Starlark reader and resolver core (steps 3, 5), the reader's
canaries, and the extension with its package and hub repositories and the root-only replacement
(steps 6–7) up to the point where generated targets analyze. Decisions this file adds to the plan,
all technical (research gives the sources):

1. **Errors as values**: `jsonc.bzl`, `lockfile.bzl`, `overrides.bzl`, `workspaces.bzl`,
   `npmrc.bzl` and `resolve.bzl` return `struct(value = ..., error = ...)` instead of calling
   `fail()`; only `npm_extension.bzl` and the rules call `fail()`. Starlark cannot catch `fail()`,
   so this lets unit tests assert every English message without Bazel-in-Bazel, which then checks
   each evaluation failure once end to end (FR-025).
2. **Fixture results extension**: Starlark unit tests cannot read files at analysis, so a
   dev-only, reproducible module extension `bun/tests/npm/fixture_results.bzl` reads the checked-in
   fixture lockfiles and manifests with `module_ctx.read`, runs the pure modules on them and
   writes their results into `@npm_fixture_results//:results.bzl`, which the unit tests load. The
   reader is thus tested on lockfiles the pinned Bun wrote, through the real read path (FR-001).
3. **Unknown sources**: slot 0 kinds the pinned Bun writes offline (npm version, `workspace:`,
   `file:`, tarball URL) are classified by fixtures; every other resolution (`git+`, `github:`,
   `link:`, anything new) is one kind, `unsupported`, whose FR-010 error quotes the resolution. No
   reader branch depends on a shape the pinned Bun was not seen to write (research R1 lists `git+`
   and `github:` from Bun source only).
4. **G9 through Bazel-in-Bazel**: a source-tree `node_modules` is reachable only at the
   workspace root (`execroot/_main/node_modules`), and the ignored and unignored cases need two
   different `REPO.bazel` files, so the source-`node_modules` cases of US1-7, US5-2 and the Edge
   Case run in inner workspaces (T055, extended by T091); the no-`node_modules` case runs in the
   root module.
5. **US7-3 is characterization, not mutation** (data-model test map says mutation for US7-3 and
   US7-4): research R3 records that `--credential_helper` "needs nothing from the rule", so
   dropping `auth` cannot break it. US7-4 (`.netrc`) gets a genuine red, because `auth` is first
   implemented in T101.
6. **Credential helper without a shell**: the US7-3 test compiles a Bun program into a native
   executable with the pinned Bun's `bun build --compile` under `TEST_TMPDIR` (no script file in the
   repository, constitution VI).
7. **No `include()`**: bazel.build: "Only the root module and modules subject to a non-registry
   override may use `include()`", and consumers get rules_bun from a registry, so rules_bun's
   `MODULE.bazel` uses no `include()` (`e2e/smoke`'s `local_path_override` would hide the
   failure). Every test-only usage sits directly in `MODULE.bazel`: `use_extension(...,
   dev_dependency = True)` for `npm` and `fixture_results`, and the integration harness's
   `http_file` repositories through `use_repo_rule` with `dev_dependency = True` on each call
   ("a certain repo is only to be created when the current module is the root module"). The
   maintenance script rewrites only the region of `MODULE.bazel` between the marker comments
   `# BEGIN integration archives (bun/tests/integration/registry/update.ts)` and
   `# END integration archives`.
8. **Scale entirely in Bazel-in-Bazel**: the 2,000-package lockfile is checked in (FR-037); its
   archives are regenerated deterministically at test time and served by the loopback registry, so
   the inner build's integrity check doubles as the determinism check (T111).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1–US9 from spec.md

## Conventions for every task

- **Record**: append one row to `specs/003-npm-dependencies/tdd-log.md` with the columns
  `Task | Kind | Red | Green | Platforms` (feature 002 FR-020 record rules). Kind is one of
  baseline, behavior, mutation, characterization, canary, fixture, refactor, dependency, research,
  documentation, verification. Red: command, exit code, the failure line naming the missing
  behavior (for a mutation: what was mutated and that it was reverted). Green: command and result.
  Platforms: Linux (WSL) for local runs; macOS and Windows only with a named CI run (constitution
  II). Fixture tasks record the self-check that exercises the fixture.
- **Genuine red**: write each implementation step minimal; it MUST NOT already contain behavior a
  later task tests (in particular: no peer fallback, optional-peer handling or missing-peer error
  before T087; no renames, exclusion or `replace_prefixes` before T058; no `npm_unsupported` reasons
  before T068; no platform `select()` before T076; no member links before T085; no `bin` targets
  before T094; no `.npmrc` before T099; no `auth` before T101; no hub-name conflict check before
  T107; no `RULES_BUN_LAUNCH_TIMESTAMP` before T109). A test that passes
  before its implementation and is not marked mutation or characterization is wrong; change it
  until it fails for the expected reason (spec Edge Cases).
- **Parallel marker** (feature 002 finding P1): [P] is set only on a task that edits none of
  `bun/private/run.bzl`, `bun/private/launcher.js`, `bun/private/npm_extension.bzl`,
  `bun/private/npm_repositories.bzl`, `bun/private/npm_package.bzl`, `bun/private/resolve.bzl`,
  `MODULE.bazel` and `MODULE.bazel.lock`, not even for a mutation. Canary tasks are [P]: each adds
  one file and one target line to `bun/tests/canary/npm/BUILD.bazel`; merge that line last.
- **Root lockfile**: `.bazelrc` sets `--lockfile_mode=error`; after every change to
  `MODULE.bazel` run `bazel mod deps --lockfile_mode=update` (and in `e2e/smoke` for US8). The
  `npm` and `fixture_results` extensions are reproducible, so they add no entry (FR-008). The root
  `MODULE.bazel` holds no `include()` (decision 7).
- **Fixture hubs** (root `MODULE.bazel`, `dev_dependency = True`): `npm_basic`
  (`//bun/tests/npm/fixtures/basic:bun.lock`), `npm_workspace` (`…/fixtures/workspace`),
  `npm_jsx` (`…/fixtures/jsx`), `npm_unsupported` (`…/fixtures/unsupported`). Analysis tests fetch
  the package repositories of the instance targets they load, just as real runs do, and the
  fixture lockfiles record full URLs with the loopback port of the run that wrote them. So every
  package a root hub creates a package repository for (every supported `name@version` its
  lockfile lists, whether a real run or only an analysis test reaches it) gets an
  `npm.replace_package` tag with `replacement = "//bun/tests/npm/registry/archives:<store
  name>.tgz"` (`npm_jsx`: `//bun/tests/npm/fixtures/jsx/archives:<file>`) (G3, FR-026). One tag
  covers every hub listing that `name@version`; the task that adds a hub adds the tags its
  lockfile still lacks. No fixture lockfile URL is fetched outside the integration tests; root
  tests use no network beyond loopback (T118 checks it).
- **Integration tests** (FR-025, G5, G10): `bun_test` targets in `bun/tests/integration/` (or
  `bun/tests/canary/npm/` for a canary) that use `bun/tests/integration/support/inner.ts` (T012) to
  run the pinned Bazel 9.2.0 on an inner workspace under `bun/tests/integration/workspaces/<name>/`
  with its own empty repository cache and output user root under `TEST_TMPDIR`, modules from the
  local registry, archives from the loopback registry, every other URL rewritten to it. Each
  asserts the loopback request log holds no unknown path. Not `manual`; listed in the
  `test_suite` `//bun/tests/integration:integration_tests`; `size = "enormous"`.
- **Spawn tests** (feature 002 FR-021): expected-failure targets are tagged `manual`, listed in a
  passing `bun_test`'s `data`, started with `bun/tests/support/spawn.ts`, and their exit code and
  output asserted.
- **Canaries** (FR-024, R17): a `bun_test` in `bun/tests/canary/npm/` using `support.ts` (T008):
  it starts the loopback registry, writes a project under `TEST_TMPDIR`, runs the pinned Bun
  (`process.execPath install`, or `--lockfile-only`), asserts its one access, and on failure
  prints exactly `rules_bun canary <id>: Bun's bun.lock <access> changed: revisit <reader
  function>; source <URL>`. Part of `//bun/tests/canary/npm:canaries`.
- **English and docs**: every `fail()` message, `doc =`, docstring, comment, test name and thrown
  `Error` is English (FR-031); every new rule, attribute, tag and provider field gets an English
  `doc` when created; T115 completes the limitation lists.
- **No shell** (constitution VI): actions only through `ctx.actions.run` (with `Args`),
  `ctx.actions.write`, `ctx.actions.symlink`; no `run_shell`; no `.sh`, `.bat`, `.cmd` or `.ps1`
  file; no repository rule runs a tool (constitution III; no `repository_ctx.execute`); fixture
  and maintenance scripts are TypeScript run with the pinned Bun by hand.
- **Access markers**: each line of `bun/private/lockfile.bzl`, `overrides.bzl` and
  `workspaces.bzl` that reads a `bun.lock` key or slot carries a trailing comment `# L<n>` naming
  its research Part 3 access, so T116 can match the inventory to the code (SC-007).
- **BUILD hygiene**: after adding a `.bzl` file run `bazel run //:gazelle`; add `bzl_library`
  dependencies on `@bazel_lib`, `@bazel_skylib` or `@bazel_tools` by hand where gazelle guesses
  wrong (feature 002 T010).
- **Stop rule**: if a step needs an undocumented or deprecated API, or a `bun.lock` access research
  Part 3 does not list, stop and report the gap (constitution V, FR-004). Do not widen a task to
  fix an unrelated failure; report it (AGENTS.md).

---

## Phase 1: Setup

**Purpose**: Record file, starting state, the loopback registry, fixture packages, archives and
lockfiles that every later phase consumes (plan step 1, research R14, Part 5 E1).

- [X] T001 Create `specs/003-npm-dependencies/tdd-log.md` with a title, a one-paragraph purpose
  citing FR-030, FR-024 and SC-007, the note that local runs are Linux (WSL2, Bazel 9.2.0) and
  macOS and Windows appear only with a named CI run, and the table header
  `| Task | Kind | Red | Green | Platforms |`.
- [X] T002 Record the starting state in `specs/003-npm-dependencies/tdd-log.md` (Kind: baseline):
  root `bazel test //...` and `(cd e2e/smoke && bazel test //...)`, exit codes and the list of test
  targets of each.
- [X] T003 [P] Write the loopback npm registry `bun/tests/support/npm_registry.ts` (research R15):
  `startRegistry({ archives, files, credential })` runs `Bun.serve` on `127.0.0.1` port 0; serves
  packuments at `/<name>` and `/@scope%2fname` built from the archives' `package.json` (with
  `dist.tarball` and `dist.integrity`, the algorithm selectable per archive: `sha256`, `sha384`,
  `sha512`, or none), tarballs at `/{name}/-/{basename}-{version}.tgz`, and arbitrary static
  `files` by path; with `credential` set, answers 401 unless the request carries it (Basic or
  Bearer); logs every request (method, path, status) and answers unknown paths with 404, logged as
  unknown. Add `bun/tests/support/npm_registry.test.ts` and its `bun_test` in
  `bun/tests/support/BUILD.bazel` checking each of these. Record (Kind: fixture).
- [X] T004 [P] Write the fixture package sources under `bun/tests/npm/registry/packages/<name>@<version>/`
  (each a `package.json` plus files), from E1 and the cases later tasks need: `a@1.0.0` (deps
  `b ^1.0.0`), `b@1.0.0`, `b@2.0.0`, `c@1.0.0` (deps `b ^2.0.0`), `@scope/s@1.0.0` (object `bin`
  `{"s-tool": "bin/tool.js", "s-other": "bin/other.mjs"}`), `single-bin@1.0.0` (string `bin`
  `cli.ts`, prints its arguments as JSON), `dirbin@1.0.0` (`directories.bin` only), `nonjs-bin@1.0.0`
  (`bin` `{"nonjs": "bin/tool"}`, a file without extension), `weird-bin@1.0.0` (`bin` `{"run tool":
  "a.js", "run:tool2": "b.js"}`), `p@1.0.0` (peers `q ^1.0.0 || ^2.0.0` and `r`, `r` optional in
  `peerDependenciesMeta`; exports the `q` version it loads and whether it can load `r`), `q@1.0.0`,
  `q@2.0.0`, `r@1.0.0`, `p-user@1.0.0` (deps `p`), `q2-user@1.0.0` (deps `p`, `q 2.0.0`),
  `state@1.0.0` and `state@2.0.0` (export a module-level object and their version), `ident-a@1.0.0`
  (peer `state`; exports the `state` object it loads), `native@1.0.0` (optional deps on
  `native-linux-x64`, `native-linux-x64-musl`, `native-linux-arm64`, `native-darwin-x64`,
  `native-darwin-arm64`, `native-win32-x64`; returns the name of the one it loads, else throws
  `native: no platform package for <process.platform>-<process.arch>`), the six `native-*@1.0.0`
  (with `os`/`cpu`; `native-linux-x64` with `"libc": ["glibc"]`, `native-linux-x64-musl` with
  `"libc": ["musl"]`), `negated@1.0.0` (optional dep `negated-not-win@1.0.0`, `"os": ["!win32"]`),
  `nomatch@1.0.0` (optional deps `nomatch-sunos-x64` (`os` `sunos`) and `nomatch-aix-ppc64`
  (`os` `aix`, `cpu` `ppc64`); entry throws exactly `nomatch: no optional package matches this
  platform`), `scripted@1.0.0` (`postinstall` writing `postinstall-ran` into its package
  directory), `phantom-user@1.0.0` (imports `b` without declaring it), `x@1.0.0` (deps `b >=1.0.0`),
  `x@2.0.0`, `y@1.0.0` (deps `x 1.0.0`, `b 2.0.0`), `z@1.0.0` (deps `x 1.0.0`), `cyc-a@1.0.0` and
  `cyc-b@1.0.0` (depend on each other), `pc-a@1.0.0` and `pc-b@1.0.0` (peer on each other, each
  also a dependency of the other), `build-files@1.0.0` (files `BUILD`, `sub/BUILD.bazel`,
  `sub/x.js`), `spaced@1.0.0` (`file with space.js`), `excluded@1.0.0` (`index.js`,
  `docs/guide.md`, `test/x.test.js`), `deep@1.0.0` (one file at a deliberately deep path for G8),
  `toplevel@1.0.0` and `winname@1.0.0` (sources only; their archives are special, T005). Record
  (Kind: fixture).
- [X] T005 Write `bun/tests/npm/registry/pack.ts` (after T004): packs every source with the pinned
  Bun (`bun pm pack`) into `bun/tests/npm/registry/archives/<store name>.tgz` (`/` in a scope
  written `+`); repacks `toplevel@1.0.0` with a single top-level directory `toplevel/` instead of
  `package/` (FR-034) and writes `winname@1.0.0` holding `package/aux.js` and `package/a:b.js`
  (G2), both with fixed modes and mtimes; prints each archive's `sha512` SRI. Run it and check in
  the archives with `bun/tests/npm/registry/archives/BUILD.bazel` holding
  `exports_files(glob(["*.tgz"]))` (the `replace_package` labels). Record (Kind: fixture) the
  pinned Bun version and the archive list.
- [X] T006 Write `bun/tests/npm/registry/write_lockfiles.ts` (after T003, T005): for each fixture
  project under `bun/tests/npm/fixtures/<project>/` it starts the loopback registry with the
  archives, runs the pinned Bun's `install` against it, rewrites nothing, and asserts the keys the
  project exists for; projects: `basic` (root deps on every package root real runs use, including
  `a`, `c`, `@scope/s`, `p`, `q 1.0.0`, `p-user`, `q2-user`, `state 1.0.0`, `ident-a`, `x 2.0.0`, `y`,
  `z`, `b 1.0.0`, `cyc-a`, `pc-a`, `native`, `negated`, `nomatch`, `scripted` (also in
  `trustedDependencies`), `phantom-user`, `single-bin`, `dirbin`, `nonjs-bin`, `weird-bin`,
  `build-files`, `spaced`, `excluded`, `toplevel`, `deep`; asserts `y/x` and `z/x` are both
  `x@1.0.0` and that their `b` walks reach different keys, else adjusts until they do),
  `workspace` (E1: `workspaces: {packages: ["packages/*", "!packages/excluded"], catalog: {q:
  "1.0.0"}}`, `overrides: {r: "1.0.0"}`, an `npm:` alias; members `w1` (D `a`, V `single-bin`
  in devDependencies, R `state` in peerDependencies, O `native-linux-x64` in optionalDependencies,
  `q 2.0.0`, `w2: "workspace:*"`, `p`), `w2` (deps `c`), `excluded`; each member with a
  `BUILD.bazel` stub), `version1` (a copy of a version-2 project whose stamp is edited to 1 and
  re-saved by Bun, G7), one project per override form `overrides_top`, `overrides_object` (with
  `"."`), `overrides_gt`, `overrides_range`, `overrides_path` (`resolutions` `a/b`),
  `overrides_glob` (`resolutions` `**/a/**/b`), `overrides_both` (both fields), `overrides_deep`
  (`a>b>c`), `catalog` (`catalog` and named `catalogs`), `unsupported` (a `file:` dependency, a
  tarball-URL dependency from the loopback host, a package patched with `bun patch` and
  `bun patch --commit`, a package `nointegrity` whose packument has no integrity — if Bun refuses
  to write it, record that and drop it), `alg_sha256`, `alg_sha384` (packuments with those
  integrity algorithms). Run it; check in each `package.json` and `bun.lock`. Record (Kind:
  fixture) every project and the `lockfileVersion` Bun wrote.
- [X] T007 Write `bun/tests/npm/registry/fetch_react.ts` and the fixture project
  `bun/tests/npm/fixtures/jsx/` (research R14, G3): `package.json` with `react 19.2.0` and
  `react-dom 19.2.0`; the script downloads `react-19.2.0.tgz`, `react-dom-19.2.0.tgz` and
  `scheduler-0.27.0.tgz` from `https://registry.npmjs.org`, verifies each against the packument's
  `dist.integrity`, writes them to `bun/tests/npm/fixtures/jsx/archives/` (with a `BUILD.bazel`
  holding `exports_files(glob(["*.tgz"]))`), and runs the pinned
  Bun's `install` against the public registry to write `bun.lock` (by hand, with network; the only
  network use of the root fixtures). Record (Kind: fixture) the three integrities and that they
  equal the `bun.lock` slot 3 values. `e2e/smoke` pins the same versions (T104).
- [X] T008 [P] Write `bun/tests/canary/npm/support.ts` and `bun/tests/canary/npm/BUILD.bazel`
  (after T003; R17): `runInstall(project, { lockfileOnly, alter })` starts the loopback registry
  with the fixture archives, writes the project under `TEST_TMPDIR`, runs `process.execPath install
  --registry=<loopback>` and returns the decoded lockfile (through a JSONC-tolerant read) and the
  request log; `alter` (default none) edits the project files, lockfile text or served packument
  fields before the run, and is how a canary's fixture is altered for its recorded red; `canaryFail(id, access, readerFunction, source)` throws the R17 message. The BUILD
  file declares `test_suite(name = "canaries")`. Record (Kind: fixture).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the offline Bazel-in-Bazel harness (G5, G10), the JSONC step and lockfile reader
(FR-007, R1) with their canaries, the resolver core (R2: ordinary dependencies, aliases, cycles,
identity, closures, peers the dependent provides), and the extension with hub and package
repositories, instance trees, link targets and the root-only replacement with its integrity check
(FR-005, FR-009, FR-026, R3, R4, R7, G3).

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Bazel-in-Bazel harness (plan step 2)

- [X] T009 Write the red harness test `bun/tests/integration/harness.test.ts` with its `bun_test`
  in `bun/tests/integration/BUILD.bazel` and the inner workspace
  `bun/tests/integration/workspaces/toolchain/` (`MODULE.bazel` with `bazel_dep(name = "rules_bun")`,
  `bun.toolchain(bun_version = "1.4.2")`, `register_toolchains`; a `bun_test` that passes): the test
  imports `./support/inner.ts`, runs inner `bazel test //...`, and asserts exit 0, no unknown path
  in the loopback log, and that the inner repository cache started empty. Red: the import fails
  (no harness). Record (Kind: behavior).
- [X] T010 Add the harness downloads (G5, G10; Kind: dependency; decision 7): directly in the
  root `MODULE.bazel`, between the marker comments `# BEGIN integration archives
  (bun/tests/integration/registry/update.ts)` and `# END integration archives`, `http_file =
  use_repo_rule("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")` and one
  `http_file(name = ..., urls = [...], integrity = ..., dev_dependency = True)` call each for the
  Bazel 9.2.0 binary of each of `linux-x86_64`, `linux-arm64`, `darwin-x86_64`, `darwin-arm64`,
  `windows-x86_64` (`executable = True`; integrity from the release's `.sha256` files), the source
  archives of every module the inner graph resolves (BCR integrity) and the Bun 1.4.2 release
  archive of each platform (`bun/private/versions.bzl` integrity); no `include()` and no
  `*.MODULE.bazel` segment file; an `alias` `bazel_binary` in `bun/tests/integration/BUILD.bazel`
  with `select()` on `@platforms`. Write the maintenance script
  `bun/tests/integration/registry/update.ts` (pinned Bun, network, by hand) that rewrites only the
  marked region of `MODULE.bazel` (failing in English when either marker is missing) and the local registry
  templates under `bun/tests/integration/registry/modules/<name>/<version>/` (`MODULE.bazel`,
  `source.json` with URLs `{LOOPBACK}/<path>` and the BCR integrity) plus `metadata.json` and
  `bazel_registry.json`. Run it, check in its output, refresh `MODULE.bazel.lock`. Record the
  module list.
- [X] T011 Add the test-only `filegroup` `//:rules_bun_files` in `BUILD.bazel` (with `all_files`
  filegroups in `bun/BUILD.bazel`, `bun/private/BUILD.bazel`, `bun/toolchain/BUILD.bazel`) holding
  every file a consumer of the module needs (`MODULE.bazel`, `REPO.bazel`, `BUILD.bazel` files,
  `bun/**/*.bzl`, `bun/private/*.js`, templates), `visibility = ["//bun/tests:__subpackages__"]`
  (G5). Record (Kind: fixture).
- [X] T012 Write `bun/tests/integration/support/inner.ts` (G5): `runInner(workspace, args, opts)`
  copies `//:rules_bun_files` into an override directory, writes the local registry from the
  templates with `{LOOPBACK}` replaced, writes a `--downloader_config` that rewrites every URL the
  inner build may request to the loopback server, starts the loopback registry (T003) with the
  module archives, the Bun archive and the test's npm archives, and spawns the Bazel binary with
  `--output_user_root` (short, under `TEST_TMPDIR`; on Windows the shortest available) and, after
  the command, `--registry=file://…`, `--override_module=rules_bun=…`, `--repository_cache=…`
  (fresh), `--downloader_config=…`; returns exit code, stdout, stderr, the request log and the
  output base path; `assertOffline(log)` fails naming any unknown path. Record (Kind: fixture).
- [X] T013 Make T009 pass (G5): add `test:linux --modify_execution_info=TestRunner=+block-network`
  to `.bazelrc` (the preset already sets `--enable_platform_specific_config`); add
  `test_suite(name = "integration_tests")` to `bun/tests/integration/BUILD.bazel`; run
  `bazel test //bun/tests/integration:integration_tests`. Record every inner flag the build needed
  (for example a strategy for nested sandboxing) in research G5. If the inner build cannot finish
  without external network, stop: FR-004, report to the user. Record (Kind: behavior).

### JSONC and lockfile reader (plan step 3)

- [X] T014 Write the red unit test `bun/tests/npm/jsonc_test.bzl` (skylib `unittest`) with its
  suite in `bun/tests/npm/BUILD.bazel` (FR-007, L1): `//` and `/* */` comments removed, trailing
  commas in objects and arrays removed, the same characters inside strings kept, escaped quotes
  and backslashes in strings, an unterminated comment or string returns an error naming the file.
  Red: `bun/private/jsonc.bzl` does not exist. Record (Kind: behavior).
- [X] T015 Implement `bun/private/jsonc.bzl` `jsonc_to_json(text, file)` (decision 1: returns
  `struct(value, error)`), then `json.decode`. T014 green; `bazel run //:gazelle`. Record.
- [X] T016 Write the red reader tests (decision 2; R1, data-model "Lockfile model"): the dev-only
  reproducible extension `bun/tests/npm/fixture_results.bzl` (used directly in the root
  `MODULE.bazel` with `use_extension("//bun/tests/npm:fixture_results.bzl", "fixture_results",
  dev_dependency = True)` and `use_repo(..., "npm_fixture_results")`) reads `bun.lock` and `package.json` of every
  project under `bun/tests/npm/fixtures/` and writes `results.bzl` with the reader's output per
  project; `bun/tests/npm/lockfile_test.bzl` asserts: versions 1 (`version1`), 2 (`basic`) and 3
  (`overrides_gt`) accepted and inline texts with 0 and 4 rejected with the FR-007 message naming
  the file and the remedy; invalid JSONC rejected naming the file; workspaces by path with `name`
  and the four dependency maps as written (`workspace`); entries with `key`, scope-aware
  `segments` (`@s/a/@s/b` → `["@s/a", "@s/b"]`, plus inline keys), `alias`, `kind` (`npm`,
  `workspace`, `file`, `tarball`, and `unsupported` with the resolution for an inline `git+…`
  slot 0, decision 3), `name`, `version`, `url` (`""` and full), `integrity`, `dependencies`,
  `optional_dependencies`, `peers`, `optional_peers`, `os` and `cpu` as lists (string and array
  forms), `bin` as a name → path map (a string `bin` named after the package without its scope);
  an alias entry whose slot 0 names another package (`workspace`); an npm entry with a non-string
  slot returns an error naming the key and the slot. Red: `bun/private/lockfile.bzl` missing.
  Record (Kind: behavior).
- [X] T017 Implement `bun/private/lockfile.bzl` `read_lockfile(text, file)`: accesses L1–L16, L21,
  L22 only, each marked `# L<n>`; no `configVersion`, `binDir` or `trustedDependencies` read. T016
  green; gazelle; refresh `MODULE.bazel.lock`. Record.

### Reader canaries (FR-024; research Part 3)

Each adds `bun/tests/canary/npm/<id>.test.ts` and a `bun_test` line; red by altering the access
in its fixture through T008's `alter`, then reverting (SC-007).

- [X] T018 [P] C-VER in `bun/tests/canary/npm/c_ver.test.ts` (L2): a plain install writes
  `lockfileVersion: 2`; a scoped override (`"a>b": "2.0.0"`) writes 3. Record (Kind: canary).
- [X] T019 [P] C-VER1 in `bun/tests/canary/npm/c_ver1.test.ts` (L2, G7): a version-2 lockfile with
  its stamp edited to 1 and re-saved by `install` keeps `lockfileVersion: 1` and entries of the L9–L16
  shapes. Record.
- [X] T020 [P] C-WSKEY in `bun/tests/canary/npm/c_wskey.test.ts` (L4): member keys are paths
  relative to the lockfile (`packages/w1`). Record.
- [X] T021 [P] C-WSNAME in `bun/tests/canary/npm/c_wsname.test.ts` (L5): each workspace value holds
  `name`. Record.
- [X] T022 [P] C-WSDEPS in `bun/tests/canary/npm/c_wsdeps.test.ts` (L6): `devDependencies`,
  `optionalDependencies`, `peerDependencies` are recorded exactly as written (`catalog:`,
  `workspace:*`, `npm:b@2.0.0`). Record.
- [X] T023 [P] C-KEYPATH in `bun/tests/canary/npm/c_keypath.test.ts` (L8): `c/b` resolves `b@2.0.0`
  under `c`, `w1/q` keys a workspace-scoped resolution by package name, and a scoped nested key
  joins two scoped names with `/`. Record.
- [X] T024 [P] C-SLOT0 in `bun/tests/canary/npm/c_slot0.test.ts` (L9, L22): slot 0 is
  `<name>@<version>` for npm, `<name>@workspace:<path>` (one-element array), `<name>@file:<path>`,
  `<name>@<url>` for a tarball URL. Record.
- [X] T025 [P] C-URL1 in `bun/tests/canary/npm/c_url1.test.ts` (L10 writer): with
  `--lockfile-only` and a manifest whose tarball is under `https://registry.npmjs.org/`, slot 1 is
  `""`; a full URL elsewhere is written in full (E2, E4). Record.
- [X] T026 [P] C-INFO in `bun/tests/canary/npm/c_info.test.ts` (L11): slot 2 is an object. Record.
- [X] T027 [P] C-INTEGRITY in `bun/tests/canary/npm/c_integrity.test.ts` (L12): slot 3 is the SRI
  the packument published. Record.
- [X] T028 [P] C-INFODEPS in `bun/tests/canary/npm/c_infodeps.test.ts` (L13): info
  `dependencies` and `optionalDependencies`. Record.
- [X] T029 [P] C-PEERS in `bun/tests/canary/npm/c_peers.test.ts` (L14): info `peerDependencies`
  and `optionalPeers` (array of names), and one entry for `p` installed with two peer resolutions
  (E1). Record.
- [X] T030 [P] C-OSCPU in `bun/tests/canary/npm/c_oscpu.test.ts` (L15): `os`/`cpu` as a string for
  one value and an array otherwise; no `libc` (G6). Record.
- [X] T031 [P] C-BIN in `bun/tests/canary/npm/c_bin.test.ts` (L16): info `bin` as a string and as
  an object; `directories.bin` written as `binDir`, not `bin`. Record.
- [X] T032 [P] C-ALIAS in `bun/tests/canary/npm/c_alias.test.ts` (L21): `"aliased": "npm:b@2.0.0"`
  gives key `aliased` and slot 0 `b@2.0.0`. Record.

### Resolver core (plan step 5, first part)

- [X] T033 Write the red resolver tests `bun/tests/npm/resolve_test.bzl` (R2, data-model
  "Resolution model") on `@npm_fixture_results` and inline lockfiles: a dependency of key `K`
  resolves to the first existing of `K/D`, `parent(K)/D`, …, `D` (`c` → `c/b`, `a` → `b`), never
  splitting a scoped segment; a workspace named `N` starts at `N/D`; alias edges keep the alias;
  `cyc-a` ↔ `cyc-b` give finite instances whose closures contain each other; `y/x` and `z/x`
  (same `x@1.0.0`, different `b`) are distinct instances; `id` = `name@version__<h>` with `<h>`
  from `hash()` of the sorted encoded edge map, and with an injected constant hash function two
  different edge maps get `__0` and `__1` in sorted order of their encodings (`instance_ids(...,
  hash_fn = hash)`); `store_name` writes `/` as `+`; a link's closure holds every instance reachable
  through edges; a peer the dependent provides resolves to that instance (`react-dom` → `react` in
  `jsx`). Red: `bun/private/resolve.bzl` missing. Record (Kind: behavior).
- [X] T034 Implement `bun/private/resolve.bzl` with exactly those rules (no workspace-context
  fallback, optional-peer or missing-peer handling: an unprovided peer gets no edge yet). T033
  green; gazelle. Record.

### Extension, repositories, generated targets (plan steps 6–7, first part)

- [X] T035 Write the red analysis tests `bun/tests/npm/generated_test.bzl` (FR-005, FR-012, R7):
  add to the root `MODULE.bazel` `npm = use_extension("//bun:extensions.bzl", "npm",
  dev_dependency = True)`, `npm.translate_lock(name = "npm_basic", bun_lock =
  "//bun/tests/npm/fixtures/basic:bun.lock")`, `npm.replace_package` for every `name@version`
  `basic`'s lockfile lists (Fixture hubs convention; this includes packages only later analysis
  tests reach: the `native-*`, `negated-not-win`, `nomatch-*`, `x`, `y`, `z`, `q2-user`,
  `nonjs-bin`, `dirbin`, `build-files`, `spaced`, `excluded`, `toplevel`), `use_repo(npm, "npm_basic")`; in
  `bun/tests/npm/fixtures/basic/BUILD.bazel` `load("@npm_basic//:defs.bzl",
  "npm_link_all_packages")` and `npm_link_all_packages()`. Assert: `:node_modules/a` provides
  `BunLibraryInfo` with empty `srcs` and `data` and `packages` holding one record with alias `a`
  whose root instance is `a@1.0.0__<h>` and whose closure holds `a` and `b@1.0.0`;
  `:node_modules/@scope/s` exists with alias `@scope/s`; the instance target provides
  `NpmInstanceInfo` with `store_name` `@scope+s@1.0.0` and a tree artifact. Red: `//bun:extensions.bzl`
  has no `npm`. Record (Kind: behavior).
- [X] T036 Add the provider fields (data-model "Build-time targets and providers"): `packages`
  (`depset` of link records) on `BunLibraryInfo` in `bun/private/providers.bzl` with its `doc`;
  private `NpmInstanceInfo` (`id`, `store_name`, `tree`, `edges`, `check`) and `NpmLinkInfo`
  (`link_dir`, `alias`, `root`, `instances`, `workspace_target`) in the same file, not exported
  from `bun/defs.bzl`. Record (Kind: refactor): root `bazel test //...` still passes.
- [X] T037 Implement `bun/private/npm_extension.bzl` and export `npm` from `bun/extensions.bzl`
  (FR-005, FR-008, FR-009, R3): tag classes `translate_lock` (`name` default `npm`, `bun_lock`,
  `npmrc`, `workspace_target_name` default `pkg`, `exclude_package_contents`; `npmrc`,
  `workspace_target_name` and `exclude_package_contents` declared but unused until T099, T085,
  T058) and `replace_package` (`package`, `replacement`); walk every module's tags; read the
  lockfile and fail with the reader's error; resolve; one package repository per `name@version`
  named `<hub>__<sanitized name>__<sanitized version>` (characters outside `[A-Za-z0-9.-]` → `_`,
  `__<n>` on a clash); URL as recorded, or `https://registry.npmjs.org/{name}/-/{basename}-{version}.tgz`
  for `""`; `os_dependent = False`, `arch_dependent = False`,
  `module_ctx.extension_metadata(reproducible = True)`. Record (Kind: behavior, green in T040).
- [X] T038 Implement `bun/private/npm_repositories.bzl` (R3, R4): the package repository rule
  (attributes `url`, `integrity`, `package`, `version`, `exclude`, `replacement` only) calling
  `repository_ctx.download_and_extract(url, output = "package", integrity = ..., canonical_id =
  url, type = "tgz", strip_components = 1)`, or `repository_ctx.extract(replacement, output =
  "package", type = "tgz", strip_components = 1)` for a replaced package, and writing `BUILD.bazel`
  with the instance-tree target over `glob(["package/**"])`; the hub repository rule writing
  `BUILD.bazel` (one `npm_instance` per instance) and `defs.bzl` (`npm_link_all_packages()` with
  per-workspace link tables, creating `:node_modules/<package>` targets). No renames, exclusion,
  member links, `bin` targets, platform `select()` or `auth` yet. Record (green in T040).
- [X] T039 Implement `bun/private/npm_package.bzl` (R4, R7): the instance-tree rule (one
  `copy_to_directory_bin_action` per configuration into a tree artifact), `npm_instance`
  (returns `NpmInstanceInfo`) and `npm_link` (returns `BunLibraryInfo` with one `NpmLinkInfo`
  record); `COPY_TO_DIRECTORY_TOOLCHAINS` declared. Record (green in T040).
- [X] T040 Make T035 green: `bazel run //:gazelle`, `bzl_library` dependencies on `@bazel_lib`,
  refresh `MODULE.bazel.lock` (no `npm` entry, FR-008), `bazel test //bun/tests/npm:all`. Record
  (Kind: behavior, the green of T035–T039).
- [X] T041 [P] C-URL2 in `bun/tests/canary/npm/c_url2.test.ts` (L10 reader, R11, E4): with slot 1
  `""` and the loopback registry as default, `install --frozen-lockfile` requests exactly
  `/{name}/-/{basename}-{version}.tgz` (scoped and unscoped). Record (Kind: canary).

### Replacement integrity and scope (G3, FR-026)

- [X] T042 Write the red integration test `bun/tests/integration/replace.test.ts` (inner workspaces
  under `bun/tests/integration/workspaces/replace_*`, lockfiles from `alg_sha256`, `alg_sha384`
  and `basic`): `bazel build` of a link target with a matching replacement passes for each of
  `sha256`, `sha384`, `sha512`; a wrong archive fails with an English error naming the package,
  the archive label and both values; one replacement applies to two lockfiles in the module; a
  replacement no lockfile lists is ignored; `replace_package` in a non-root module fails
  evaluation naming the module; one package replaced twice fails naming it. Red: a wrong archive
  is accepted; non-root and double use are accepted. Record (Kind: behavior).
- [X] T043 Implement the replacement check and scope: rule `npm_replacement_check` in
  `bun/private/npm_package.bzl` running the execution-platform Bun (`//bun/toolchain:execution_type`) with a new
  `bun/private/check_integrity.js` (`Bun.CryptoHasher` with the integrity's algorithm) through
  `ctx.actions.run`, writing a stamp and failing with the FR-026 message; the hub declares one per
  replaced instance and `NpmInstanceInfo.check` carries the stamp; the instance tree depends on
  the stamp; non-root and double-use checks in `bun/private/npm_extension.bzl`. T042 green.
  Record.

**Checkpoint**: generated targets analyze, replaced archives are verified, the harness runs offline.

---

## Phase 3: User Story 1 - Import npm packages, proven by JSX with React (Priority: P1) 🎯 MVP

**Goal**: `bun_binary` and `bun_test` lay out the packages they reach in the strict store inside
their copy tree, the guard admits store entries, libraries carry packages, and a TSX test and
program render React (FR-003, FR-013, FR-014, FR-021, FR-022, FR-023, FR-033–FR-036, R5, R6).

**Independent Test**: `bazel test //bun/tests/npm/fixtures/jsx:all //bun/tests/npm/imports:all`
passes on Linux; CI on macOS and Windows (POST-1).

### Tests for User Story 1 ⚠️

- [X] T044 [US1] Write the red real-run tests: `bun/tests/npm/fixtures/basic/imports.test.ts`
  (`bun_test` `imports_test`, deps `:node_modules/a`, `:node_modules/c`, `:node_modules/@scope/s`):
  `a` loads and reports `b@1.0.0`, `c` reports `b@2.0.0` (US1-6 first part), `@scope/s` loads
  (US1-4); in `bun/tests/npm/fixtures/jsx/` (`npm_jsx` hub with `replace_package` for `react`,
  `react-dom`, `scheduler` from `archives/`): `render.tsx` (a component using `useState` and
  `useId`), `render.test.tsx` (`renderToString` from `react-dom/server`, exact expected markup;
  US1-1), `render_main.tsx` (`bun_binary` `render` printing the markup and exiting non-zero on a
  mismatch; US1-2), a `manual` variant `render_mismatch` expecting different markup and
  `render_spawn.test.ts` asserting it exits non-zero. Red: Bun's module-not-found error for `a`
  and `react`. Record (Kind: behavior).
- [X] T045 [US1] Write the red analysis tests `bun/tests/npm/layout_test.bzl` (R5, R6, G3, G8): for
  `imports_test`, one `copy_directory_bin_action` per carried instance to
  `<name>.bun/.store/<store name>/node_modules/<package>/`; one `declare_symlink` output per edge at
  `.store/<store name>/node_modules/<dep>` and per direct link at
  `<name>.bun/_main/bun/tests/npm/fixtures/basic/node_modules/<alias>`; no copy-tree path with a
  `node_modules` ancestor outside `.store`; `launch.json` `directories` lists the store-entry tree
  paths; a carried instance's replacement stamp is in runfiles; the target's action count equals
  `P + E + L + A` (A from the same target without packages). Red: none of these exist. Record
  (Kind: behavior).

### Implementation for User Story 1

- [X] T046 [US1] Implement the layout in `bun/private/run.bzl` (R5): collect `NpmLinkInfo`
  records from direct `deps`, copy each instance tree once with `copy_directory_bin_action`
  (`hardlink = "auto"`), create edge and direct links with `ctx.actions.declare_symlink` and
  `ctx.actions.symlink(target_path = <relative>, target_type = "directory")`, add the replacement
  stamps to runfiles, write `directories` into `launch.json`. Re-run T044: it now fails with the
  load guard's error naming a store file; record that line. Record (Kind: behavior).
- [X] T047 [US1] Implement the guard's directory branches in `bun/private/launcher.js` (R6): compute
  the copy-tree root's real path for programs as for tests, add `root + sep + directory + sep` as a
  prefix branch of the trie for each `directories` entry. T044 and T045 green; root
  `bazel test //...` passes. Record.
- [X] T048 [US1] Write the red library test (US1-3, FR-014): `bun/tests/npm/fixtures/basic/lib/`
  with a `bun_library` `lib` (`srcs = ["lib.ts"]` importing `a`, `deps = ["//bun/tests/npm/fixtures/basic:node_modules/a"]`)
  and a `bun_test` depending only on `lib`; and in `bun/tests/npm/layout_test.bzl` an analysis test
  that a `BunLibraryInfo` created by a test-only rule without `packages` is read as empty. Red:
  module-not-found for `a` (the library drops packages). Record.
- [X] T049 [US1] Implement the transitive merge in `bun/private/library.bzl` and its use in
  `bun/private/run.bzl` (`getattr(info, "packages", None)` read as empty). T048 green. Record.
- [X] T050 [US1] Write the undeclared-package spawn test (US1-5): `bun/tests/npm/fixtures/basic/undeclared/`
  with a `manual` `bun_binary` depending on `:node_modules/a` that imports `c` (listed, not
  reached) and a `bun_test` asserting a non-zero exit and Bun's module-not-found message or the
  guard's error naming the file. **Mutation**: the macro adds `c`'s closure to `a`'s link record
  in `bun/private/npm_repositories.bzl`; the test fails; reverted. Record.
- [X] T051 [US1] Write the phantom test without a source `node_modules` (US1-7):
  `bun/tests/npm/fixtures/basic/phantom.test.ts` depending on `:node_modules/phantom-user` and
  `:node_modules/b` (the root declares `b`), spawning a `manual` program that calls
  `phantom-user`, asserting Bun's module-not-found error for `b`. **Mutation**: an edge from
  `phantom-user` to `b` added in `bun/private/resolve.bzl`; reverted. Record.
- [X] T052 [US1] Run the JSX proof (US1-1, US1-2): `bazel test //bun/tests/npm/fixtures/jsx:all`
  green and `bazel run //bun/tests/npm/fixtures/jsx:render` exits 0 printing the markup; record
  both (the `bazel run` part also goes into CI, T114). Record (Kind: verification).
- [X] T053 [US1] Write the lifecycle test (FR-023, R12): `bun/tests/npm/fixtures/basic/scripted.test.ts`
  imports `scripted` and asserts it loads and that `postinstall-ran` is absent from its store
  entry. **Mutation**: the instance-tree rule in `bun/private/npm_package.bzl` also runs the
  execution Bun on the package's `postinstall`, so the marker appears; reverted. Record.
- [X] T054 [P] [US1] C-TD in `bun/tests/canary/npm/c_td.test.ts` (FR-023, G4): `trustedDependencies:
  []` writes no key; `["scripted"]` writes the list; the message names the documentation of
  `trustedDependencies` in `bun/private/run.bzl` to revisit. Record (Kind: canary).
- [X] T055 [US1] Write the integration test `bun/tests/integration/source_node_modules.test.ts`
  (decision 4; G9, US1-7, Edge Case): two inner workspaces under
  `bun/tests/integration/workspaces/source_nm_{ignored,unignored}/`, each with a root
  `node_modules/b/` holding a copy of `b` and a target whose package imports `b` undeclared
  (`phantom-user`) and whose source imports an undeclared `b`; one `REPO.bazel` has
  `ignore_directories(["**/node_modules"])`, the other none. Run the inner test with the default
  strategy and with `--spawn_strategy=local`; assert that each of the four runs fails with the
  guard's English error naming a file under the source `node_modules` (spec Revision 5 (1): the
  source `node_modules` stays reachable through the execution root under every strategy). If a
  run fails with another reason, such as Bun's module-not-found error, stop and report it with the
  strategy and OS (Stop rule; spec Revision 5 (1) and research G9 would not hold). **Mutation**:
  the guard's directory prefixes in `bun/private/launcher.js` cover the copy-tree root's parent;
  the runs load `b`; reverted. Record.
- [X] T056 [US1] Write the isolation tests with packages (FR-022): `bun/tests/npm/fixtures/basic/isolation/`
  with a `bunfig.toml` and `.env` declared by no target and a `bun_test` depending on
  `:node_modules/a` that imports a package not in the lockfile (spawned: module-not-found, no
  install attempted) and asserts neither the `bunfig.toml` nor the `.env` took effect.
  **Mutation** of feature 002's isolation in `bun/private/launcher.js` (auto-install allowed);
  reverted. Record.
- [X] T057 [US1] Write the red archive tests (FR-033, FR-034, FR-035): in
  `bun/tests/npm/fixtures/basic/archives/` real runs that read every file of `build-files`
  (including `BUILD` and `sub/BUILD.bazel`) and of `spaced` (`file with space.js`), and that load
  `toplevel`; `exclude_package_contents = {"excluded": ["docs/**"], "*": ["test/**"]}` on
  `npm_basic` and an analysis test in `bun/tests/npm/layout_test.bzl` that `excluded`'s tree lacks
  `docs/guide.md` and `test/x.test.js` and the guard's declared set does not contain them. Red: the
  `BUILD` files' directories are subpackages (files missing), the spaced name is not a valid label,
  the exclusions are carried. `toplevel` passes already (FR-034): **mutation** `strip_components =
  0` in `bun/private/npm_repositories.bzl`; reverted. Record.
- [X] T058 [US1] Implement renames and exclusion (R4, FR-033, FR-035): in
  `bun/private/npm_repositories.bzl` walk `package/` with `path.readdir`, rename every `BUILD` and
  `BUILD.bazel` file and every name with a character outside Bazel's target-name set with
  `repository_ctx.rename` to a generated safe name (an existing destination fails in English
  naming the package and both names), record the renames; pass `exclude` patterns under
  `package/` to the `glob`; in `bun/private/npm_package.bzl` give `copy_to_directory_bin_action`
  `replace_prefixes` mapping each safe path back. T057 green. Record.
- [X] T059 [P] [US1] C-WINNAME in `bun/tests/canary/npm/c_winname.test.ts` (FR-036, G2), using
  `bun/tests/integration/support/inner.ts`, `target_compatible_with = ["@platforms//os:windows"]`:
  an inner workspace replaces `winname` and builds a target carrying it; the canary pins what
  Bazel 9.2.0 does with `aux.js` and `a:b.js` (the first CI run records it) and fails naming the
  FR-036 documentation to revisit when that changes. Red: not run locally (Windows only); recorded
  from CI in POST-1. Record (Kind: canary).
- [X] T060 [US1] Write the path-length test (G8): `bun/tests/npm/fixtures/basic/path_length.test.ts`
  depending on `:node_modules/deep` computes the longest store path its copy tree holds from the
  real path, prints it, and asserts it below 260 characters on Windows CI with the CI
  `--output_user_root`; the value goes into research G8 in T112. Record (Kind: behavior).

**Checkpoint**: US1 complete on Linux; root `bazel test //...` passes.

---

## Phase 4: User Story 2 - Fetching is pinned, verified, lazy and offline after fetch (Priority: P1)

**Goal**: evaluation errors, manifest comparison with catalogs and overrides, unsupported entries,
integrity, laziness, conflicts and reproducibility (FR-006, FR-007, FR-008, FR-010, R3, R9, R13).

**Independent Test**: `bazel test //bun/tests/integration:integration_tests //bun/tests/npm:all`;
the network-denied CI job (T114).

### Tests for User Story 2 ⚠️

- [X] T061 [US2] Write the red integration test `bun/tests/integration/lockfile_errors.test.ts`
  (US2-5, FR-007): `bun_lock` labeling `bun.lockb`, `lockfileVersion` 0 and 4, invalid JSONC; each
  fails evaluation with an English error naming the file and the remedy. Red: the `bun.lockb`
  label is read as text and fails with a JSONC error. Record (Kind: behavior).
- [X] T062 [US2] Write the red unit tests `bun/tests/npm/overrides_test.bzl` and
  `bun/tests/npm/compare_test.bzl` on `@npm_fixture_results` (R9, FR-006): each `overrides_*`
  project's manifest form normalizes to the nested form its `bun.lock` records; `overrides` wins
  over `resolutions`; `a>b>c` and `a/b/c` are dropped; scoped names split scope-aware; a form no
  fixture pins returns an error naming the form; a root or member manifest whose dependencies,
  catalogs or overrides differ from the lockfile returns an error naming the file, the package and
  the difference and telling the consumer to run `bun install` and commit `bun.lock`; `catalog:`
  references resolve through `catalog` and named `catalogs`. Red: `bun/private/overrides.bzl`
  missing. Record.
- [X] T063 [US2] Write the red integration test `bun/tests/integration/manifest_mismatch.test.ts`
  (US2-6): a root dependency added, a catalog entry changed and an override changed without
  updating `bun.lock`; each fails evaluation with T062's message. Red: evaluation succeeds. Record.

### Implementation for User Story 2

- [X] T064 [US2] Implement the `bun.lockb` check in `bun/private/npm_extension.bzl`, and
  `bun/private/overrides.bzl` and the manifest comparison in `bun/private/workspaces.bzl` (members
  taken from the lockfile's `workspaces` keys here; glob discovery is T083), wired into the
  extension (accesses L18, L19 marked). T061 (the version and JSONC cases pass already:
  **mutation** the extension ignores the reader's error; reverted), T062 and T063 green. Record.
- [X] T065 [P] [US2] C-OVERRIDES in `bun/tests/canary/npm/c_overrides.test.ts` (L18): the lockfile
  form of each accepted manifest form (flat; `a>b` → `{a: {b}}`; range parent; `resolutions`
  paths). Record (Kind: canary).
- [X] T066 [P] [US2] C-CATALOG in `bun/tests/canary/npm/c_catalog.test.ts` (L19): top-level
  `catalog` and `catalogs` as written. Record.
- [X] T067 [US2] Write the red unsupported-entry tests (US2-2, FR-010, R13): unit cases in
  `bun/tests/npm/lockfile_test.bzl` for the reasons (`file:`, tarball URL, `unsupported`
  resolution, patched, no integrity, an inline `sha1-` integrity); in the root `MODULE.bazel` the
  hub `npm_unsupported` (`//bun/tests/npm/fixtures/unsupported:bun.lock`, with the macro called in
  its `BUILD.bazel`) plus a `replace_package` tag for each supported `name@version` of its
  lockfile that T035 does not cover (the unsupported entries get no package repository, T068), and `bun/tests/npm/unsupported_test.bzl` with `analysistest`
  `expect_failure` on each unsupported `:node_modules/<package>` asserting the English error naming
  the package and the reason, and a sibling npm link that analyzes. Red: the hub fails to generate
  or the entries are fetched. Record.
- [X] T068 [US2] Implement `npm_unsupported` in `bun/private/npm_package.bzl`, the statuses in
  `bun/private/resolve.bzl` and the hub entries in `bun/private/npm_repositories.bzl` (algorithm
  check: `sha256`, `sha384`, `sha512`; L20 `patchedDependencies` keys read, marked). T067 green;
  no package repository is created for an unsupported entry. Record.
- [X] T069 [P] [US2] C-PATCHED in `bun/tests/canary/npm/c_patched.test.ts` (L20): `bun patch
  --commit` writes `patchedDependencies` keyed `name@version`. Record (Kind: canary).
- [X] T070 [US2] Write the red integration test `bun/tests/integration/conflict.test.ts` (R3, Edge
  Case): a lockfile edited to hold two entries of one `name@version` with different integrities,
  and one with different URLs; evaluation fails naming both keys and both values. Red: evaluation
  succeeds. Record.
- [X] T071 [US2] Implement the conflict check in `bun/private/npm_extension.bzl`. T070 green.
  Record.
- [X] T072 [US2] Write the integration test `bun/tests/integration/integrity.test.ts` (US2-1): the
  loopback registry serves an altered `a` archive; building a target that needs `a` fails and the
  error names the package. **Mutation**: `integrity` dropped from `download_and_extract` in
  `bun/private/npm_repositories.bzl`; the build succeeds; reverted. Record.
- [X] T073 [US2] Write the integration test `bun/tests/integration/laziness.test.ts` (US2-3,
  SC-005): fresh output base and empty repository cache; a target needing no package causes no
  archive request; one needing `a` requests only `a` and `b@1.0.0`; a package whose archive is
  404 and that no target needs leaves the build and test green. **Mutation**: the hub's
  `BUILD.bazel` references every package repository; reverted. Record.
- [X] T074 [US2] Write the integration test `bun/tests/integration/reproducible.test.ts` (FR-008,
  US2-7): inner `bazel mod deps --lockfile_mode=update` leaves no `npm` extension entry in
  `MODULE.bazel.lock`; the test writes `bazel mod show_extension @rules_bun//bun:extensions.bzl%npm`
  and `bazel mod show_repo` of every listed repository into
  `$TEST_UNDECLARED_OUTPUTS_DIR/mod_output.txt` for the CI comparison (T114). **Mutation**:
  `reproducible = False`; the entry appears; reverted. Record.

**Checkpoint**: US1 and US2 pass; every evaluation and fetch failure has an integration test.

---

## Phase 5: User Story 3 - Platform-specific optional dependencies follow the Bazel platform (Priority: P2)

**Goal**: optional dependencies restricted by `os`/`cpu` are selected by the target platform
(FR-016, R8, G6).

**Independent Test**: `bazel test //bun/tests/npm:platforms` (five platforms) plus the real run
on each CI OS.

- [X] T075 [US3] Write the red analysis tests `bun/tests/npm/platforms_test.bzl` for
  `:node_modules/native`, `:node_modules/negated` and `:node_modules/nomatch` under each of the
  five platforms in `bun/tests/platforms/BUILD.bazel` (US3-1, SC-004): exactly the matching
  `native-*` instances (both `native-linux-x64` and `native-linux-x64-musl` on `linux_x64`, G6),
  `negated-not-win` everywhere except `windows_x64`, no `nomatch-*` anywhere. Red: every optional
  package is carried. Record (Kind: behavior).
- [X] T076 [US3] Implement R8 in `bun/private/npm_repositories.bzl`: the hub generates
  `config_setting`s from the R8 table (`!` negation; values without a constraint, such as `sunos`,
  match nothing; `aix` → `@platforms//os:aix`), and link closures put each platform-restricted
  optional instance behind `select()`; non-optional dependencies ignore `os`/`cpu`. T075 green.
  Record.
- [X] T077 [US3] Write the exec-configuration test (US3-2) in `bun/tests/npm/platforms_test.bzl`:
  a test-only rule with a `cfg = "exec"` attribute on a `bun_binary` depending on
  `:node_modules/native`, analyzed with `--platforms=//bun/tests/platforms:windows_x64` and
  `--extra_execution_platforms=//bun/tests/platforms:linux_x64`, carries `native-linux-x64`, not
  `native-win32-x64`. **Mutation**: the hub writes the host's platform package unconditionally;
  reverted. Record.
- [X] T078 [US3] Write the real run `bun/tests/npm/fixtures/basic/native.test.ts`: `native` returns
  the package matching `process.platform`/`process.arch`. Linux local; macOS and Windows from CI
  (POST-1). Record.
- [X] T079 [US3] Write the no-match spawn test (US3-3): `bun/tests/npm/fixtures/basic/nomatch/` with
  a `manual` program importing `nomatch` and a `bun_test` asserting a non-zero exit and exactly
  `nomatch: no optional package matches this platform`. Record (its red is T075's state: before
  T076 every `nomatch-*` was carried; if it passes on first run, record as mutation by restoring
  that).

**Checkpoint**: platform selection holds on five platforms by analysis and per CI OS by run.

---

## Phase 6: User Story 4 - Workspaces declared in the root `package.json` (Priority: P2)

**Goal**: member discovery by glob, member-set comparison, member links and per-member packages
(FR-006, FR-012, FR-015, R7, R9).

**Independent Test**: `bazel test //bun/tests/npm/fixtures/workspace/... //bun/tests/npm:workspaces`
and `bun/tests/integration/members.test.ts`.

### Tests for User Story 4 ⚠️

- [X] T080 [US4] Write the red glob unit tests `bun/tests/npm/workspaces_test.bzl` (R9, US4-4): `?`,
  `*`, `**`, `[...]`, `{a,b}`; a negative pattern removes matches wherever it appears in the list;
  a directory listed by path is not removed by a negative glob; a matched directory is a member
  only when it holds `package.json`. Red: no matcher in `bun/private/workspaces.bzl`. Record.
- [X] T081 [US4] Write the red Bun-comparison test (R9): `bun/tests/npm/workspaces/glob_cases.bzl`
  (`GLOB_CASES`: directory listings and `workspaces` patterns, including `node_modules`
  directories holding `package.json` inside a matched tree), a test-only rule
  `bun/tests/npm/workspaces/glob_members.bzl` that writes the matcher's member set per case to a
  JSON file with `ctx.actions.write`, and `bun/tests/npm/workspaces/glob_compare.test.ts` that
  builds each tree under `TEST_TMPDIR`, runs the pinned Bun's `install --lockfile-only` against the
  loopback registry, and asserts the lockfile's `workspaces` keys equal the JSON. Red: the rule
  cannot load the matcher. Record.
- [X] T082 [US4] Write the red integration test `bun/tests/integration/members.test.ts` (US4-4,
  US4-5): a member directory matched by a glob but missing from `bun.lock` fails evaluation naming
  it; adding and then removing a member with `bun.lock` updated (both lockfiles prewritten by
  `bun/tests/npm/registry/write_lockfiles.ts`, project `workspace_added`) adds and removes its
  targets at the next build without changing the root `package.json`; `npm_link_all_packages()`
  called in a package that is no workspace package fails naming the valid packages. Red: the extra
  member is accepted; the misplaced call creates targets. Record.

### Implementation for User Story 4

- [X] T083 [US4] Implement the matcher and member discovery in `bun/private/workspaces.bzl`
  (`path.readdir(watch = "auto")` from the root `package.json`'s `workspaces`, array or object with
  `packages`), the member-set comparison in `bun/private/npm_extension.bzl`, and the
  calling-package check in the generated `defs.bzl` (`bun/private/npm_repositories.bzl`). T080,
  T081, T082 green. Record.
- [X] T084 [US4] Write the red real runs in `bun/tests/npm/fixtures/workspace/` (hub
  `npm_workspace` in the root `MODULE.bazel`, with a `replace_package` tag for each `name@version`
  of its lockfile that T035 does not cover, such as `r@1.0.0`; macro in the root and each member's `BUILD.bazel`; `//packages/w2:pkg` a
  `bun_library` with `w2`'s sources and `package.json` in `data`): US4-1 (`w1` imports `a`; a
  `manual` program in `w2` importing `a`, spawned: fails as in US1-5), US4-2 (`w1` imports `w2` by
  package name and gets `//packages/w2:pkg`'s sources), US4-3 (root gets `q@1.0.0`, `w1` gets
  `q@2.0.0`), US4-6 (`w1` imports D `a`, V `single-bin`, R `state` at the lockfile's versions, and
  O `native-linux-x64` on `linux_x64` only: analysis tests in `bun/tests/npm/workspaces_test.bzl`
  for the five platforms, and a spawned import on other CI OSes failing with module-not-found),
  and the alias Edge Case (a root target depending on `:node_modules/aliased` imports `aliased`
  and gets `b@2.0.0`, as Bun does). Red: no `:node_modules/w2` target; the member link is missing.
  Record.
- [X] T085 [US4] Implement member links (FR-015, R5, R7): the hub's link tables map a `workspace:`
  dependency to `//<member>:<workspace_target_name>` (attribute from T037); `npm_link` returns
  `NpmLinkInfo.workspace_target`; `bun/private/run.bzl` creates
  `<name>.bun/<repo>/<A>/node_modules/<B>` → `<name>.bun/<repo>/<B>` and copies B's files as
  declared inputs. T084 green. Record.

**Checkpoint**: workspace members link and resolve per member.

---

## Phase 7: User Story 5 - Peer dependencies resolve by npm's semantics (Priority: P2)

**Goal**: workspace-context fallback, optional peers absent, missing-peer error, peer cycles, one
instance per package version per target (FR-017, R2).

**Independent Test**: `bazel test //bun/tests/npm:resolve //bun/tests/npm/fixtures/basic/peers:all`.

- [X] T086 [US5] Extend `bun/tests/npm/resolve_test.bzl` with red cases: an unprovided non-optional
  peer resolves by the walk from the workspace start key (`N/P`, then `P`), not the package's key
  (`p` via `p-user` → `q@1.0.0`; via `w1` → `q@2.0.0`); an unprovided optional peer (`r`) gets no
  edge; a non-optional peer with no version in the workspace gives the status naming the package
  and the peer; `pc-a` ↔ `pc-b` terminate with a back-edge recorded by lockfile key; `p` reached
  with `q@1.0.0` and with `q@2.0.0` are distinct instances. Red: unprovided peers get no edge.
  Record.
- [X] T087 [US5] Implement these rules in `bun/private/resolve.bzl`; a missing peer becomes an
  `npm_unsupported` instance with the FR-017 reason. T086 green. Record.
- [X] T088 [US5] Write the red analysis tests `bun/tests/npm/uniqueness_test.bzl` (US5-4): a target
  depending on `:node_modules/y` and `:node_modules/z` fails naming `x@1.0.0`, the dependency `b`
  and both versions; a target depending on `:node_modules/p` and `:node_modules/q2-user` fails
  naming `p@1.0.0`, the peer `q` and `1.0.0` and `2.0.0`; a target needing a missing-peer instance
  fails with the FR-017 error. Red: the first two analyze. Record.
- [X] T089 [US5] Implement the per-target uniqueness check in `bun/private/run.bzl`. T088 green.
  Record.
- [X] T090 [US5] Write the real runs in `bun/tests/npm/fixtures/basic/peers/`: US5-1 (`ident-a`'s
  `state` object is the one the test imports), US5-2 (`p-user`'s `p` loads `q@1.0.0`; `p` cannot
  load `r`: module-not-found), US5-3 (two `bun_test`s: one through `:node_modules/p` sees `q@1.0.0`,
  one through `:node_modules/q2-user` sees `q@2.0.0`). Record (each passes after T087 and T089; if
  one passes before T087, record it as a mutation of T087's fallback).
- [X] T091 [US5] Extend `bun/tests/integration/source_node_modules.test.ts` (T055) with the
  optional-peer case (US5-2, G9): `r` in the inner root `node_modules`, `p` imports it; with the
  default strategy and with `--spawn_strategy=local` the guard rejects it naming the file (another
  failure reason is reported as in T055). Record.

**Checkpoint**: React's single instance and every peer case hold.

---

## Phase 8: User Story 6 - Package executables as tools (Priority: P2)

**Goal**: `bin` entries become `bun_binary`-based targets usable with `bazel run` and as tools
(FR-018, R10).

**Independent Test**: `bazel test //bun/tests/npm:bins //bun/tests/npm/fixtures/basic/bins:all`.

- [X] T092 [US6] Write the red unit tests `bun/tests/npm/naming_test.bzl` (FR-012 naming rule):
  characters outside Bazel's target-name set written `_` (`run tool` → `run_tool`, `run:tool2` →
  `run_tool2`), scope kept, a string `bin` named after the package without its scope, two names
  that become equal reported naming both. Red: no naming function. Record.
- [X] T093 [US6] Write the red analysis tests `bun/tests/npm/bins_test.bzl`: targets
  `:node_modules/single-bin/bin/single-bin`, `:node_modules/@scope/s/bin/s-tool`,
  `:node_modules/@scope/s/bin/s-other`, `:node_modules/weird-bin/bin/run_tool` exist; the copy tree
  of each is under `_npm_bin/<package>/<bin>.bun/`, never under a `node_modules` ancestor;
  `:node_modules/nonjs-bin/bin/nonjs` fails analysis naming the package, the entry and the reason
  (US6-4). Red: no bin targets. Record.
- [X] T094 [US6] Implement the naming function (in `bun/private/npm_repositories.bzl` or a new
  `bun/private/npm_names.bzl`), the bin rule in `bun/private/run.bzl` sharing `bun_binary`'s
  implementation with the entry point inside the store entry, and the macro's bin targets for
  directly declared packages. T092, T093 green. Record.
- [X] T095 [US6] Write the bin real runs in `bun/tests/npm/fixtures/basic/bins/`: a `bun_test`
  spawning `:node_modules/single-bin/bin/single-bin` with arguments `["x", "a b"]` and asserting
  the printed JSON (US6-1), and `s-tool` likewise. Record.
- [X] T096 [US6] Write the tool test (US6-2): bazel-lib `run_binary` with tool
  `:node_modules/single-bin/bin/single-bin` writing a file, and a `bun_test` asserting its content.
  Record (passes after T094; red recorded as the missing target before T094 if written then,
  otherwise as mutation: the bin rule ignores its arguments).
- [X] T097 [US6] Write the integration test `bun/tests/integration/bins.test.ts`: `bazel query`
  lists no `node_modules/dirbin/bin/*` target (US6-5); two bins whose names sanitize alike fail
  evaluation naming both (inner fixture). Red: the collision is accepted. Implement the collision
  failure in `bun/private/npm_extension.bzl`. Record.

**Checkpoint**: package executables run and serve as tools.

---

## Phase 9: User Story 7 - Private registries, mirrors and credentials through Bazel's downloader (Priority: P3)

**Goal**: `.npmrc` registry and scope mappings, full URLs, `.netrc` and credential helpers,
mirrors, and no credential in any attribute or file (FR-009, FR-019, FR-020, R11).

**Independent Test**: `bun/tests/integration/registries.test.ts` and
`bun/tests/integration/credentials.test.ts`.

- [X] T098 [US7] Write the red unit tests `bun/tests/npm/npmrc_test.bzl` (R11): `registry=` and
  `@scope:registry=` read; comments and blank lines ignored; lines whose key starts with `//` or
  names `_auth`, `_authToken`, `_password`, `username`, `certfile`, `keyfile` skipped and absent from
  the result; URL construction: scope registry, else `.npmrc` default, else
  `https://registry.npmjs.org`, a trailing `/` on the registry not doubled, a full URL used as
  recorded. Red: `bun/private/npmrc.bzl` missing. Record.
- [X] T099 [US7] Implement `bun/private/npmrc.bzl` and wire `npmrc` into
  `bun/private/npm_extension.bzl`'s URL construction. T098 green. Record.
- [X] T100 [US7] Write the red integration test `bun/tests/integration/registries.test.ts`: US7-1 (a
  full URL on a second loopback host is requested there), US7-6 (a scope mapped in the passed
  `.npmrc` to the second host gets `/{name}/-/{basename}-{version}.tgz` there), US7-4 (the
  registry requires a credential; a `.netrc` in the inner `HOME` supplies it; the fetch succeeds),
  US7-7 (authentication values in the passed `.npmrc` and in the inner `HOME/.npmrc`, no helper or
  `.netrc`: the fetch fails as in US7-2); every case greps the inner output base's `external/`
  files and `bazel mod show_repo` output for the secret and finds none. Red: US7-4 fails with 401
  (no `auth`). Record.
- [X] T101 [US7] Implement `auth` in the package repository rule of
  `bun/private/npm_repositories.bzl` with `read_user_netrc` and `use_netrc` from
  `@bazel_tools//tools/build_defs/repo:utils.bzl`. T100 green. **Mutation** for the record:
  `auth` dropped again, US7-4 fails; reverted. Record.
- [X] T102 [US7] Write the integration test `bun/tests/integration/credentials.test.ts`
  (decisions 5, 6): US7-2 (no credential: Bazel's download error naming the URL;
  **characterization**, Bazel's downloader owns the message), US7-3 (a credential helper compiled
  with `bun build --compile` under `TEST_TMPDIR`, passed by `--credential_helper=<loopback host>=…`:
  the fetch succeeds; **characterization**, the rule takes no part), US7-5 (a
  `--downloader_config` rewrite to a mirror host: the request goes to the mirror and an altered
  archive there fails integrity; **characterization**); each greps for the secret as T100. Record.

**Checkpoint**: registries, mirrors and credentials follow Bazel's downloader.

---

## Phase 10: User Story 8 - The consumer module uses npm packages (Priority: P3)

**Goal**: `e2e/smoke` proves the feature from outside with the public registry (SC-001, SC-002).

**Independent Test**: `(cd e2e/smoke && bazel test //...)` and `bazel run //jsx:render`.

- [X] T103 [US8] Write the red consumer test: `e2e/smoke/jsx/BUILD.bazel` with `bun_test`
  `render_test` (`render.test.tsx`, deps `//:node_modules/react`, `//:node_modules/react-dom`) and
  `bun_binary` `render` (the same component and markup as T044), and the
  `load("@npm//:defs.bzl", "npm_link_all_packages")` plus `npm_link_all_packages()` call in
  `e2e/smoke/BUILD.bazel`. Red: `@npm` is not a visible repository. Record (Kind: behavior).
- [X] T104 [US8] Set up the consumer exactly as SC-001 counts: `e2e/smoke/package.json` (`react
  19.2.0`, `react-dom 19.2.0`), `e2e/smoke/bun.lock` written by the pinned Bun against the public
  registry (by hand), `e2e/smoke/REPO.bazel` with `ignore_directories(["**/node_modules"])`,
  `npm = use_extension("@rules_bun//bun:extensions.bzl", "npm")`, `npm.translate_lock(bun_lock =
  "//:bun.lock")`, `use_repo(npm, "npm")` in `e2e/smoke/MODULE.bazel`; refresh
  `e2e/smoke/MODULE.bazel.lock` (no `npm` entry). T103 green with Bazel's default settings. Record.
- [X] T105 [US8] Record (Kind: verification) `(cd e2e/smoke && bazel run //jsx:render)` (exit 0,
  markup) and `git grep -n 'bun/private' -- e2e` (prints nothing) in
  `specs/003-npm-dependencies/tdd-log.md` (US8-2, SC-006).

**Checkpoint**: the consumer module uses npm packages through the public API only.

---

## Phase 11: User Story 9 - Several lockfiles and non-root modules (Priority: P3)

**Goal**: one hub per lockfile in any module; hub-name conflicts fail (FR-032).

**Independent Test**: `bun/tests/integration/multi.test.ts`.

- [X] T106 [US9] Write the red integration test `bun/tests/integration/multi.test.ts` (inner
  workspaces under `bun/tests/integration/workspaces/multi_*`): a root module with two lockfiles
  under distinct hub names, each project's target getting its own versions (US9-1); a root module
  depending (local registry) on a module that uses the extension for its own lockfile, building
  that module's target (US9-2); two tags asking for one hub name in one module and across two
  modules each fail evaluation naming every module and the name (US9-3). Red: the conflict is
  accepted. Record (US9-1 and US9-2 pass on first run: **mutation** the extension reads only the
  root module's tags; reverted).
- [X] T107 [US9] Implement the hub-name conflict check in `bun/private/npm_extension.bzl`. T106
  green. Record.

**Checkpoint**: all user stories pass.

---

## Phase 12: Scale (FR-037, SC-010, G8)

**Purpose**: the 2,000-package fixture, the launcher timestamp, the bounds and their enforcement.

- [X] T108 Write the red launcher-timestamp test `bun/tests/run/timestamp/timestamp.test.ts`: it
  spawns a program with `RULES_BUN_LAUNCH_TIMESTAMP` naming a file under `TEST_TMPDIR`; the
  program's first line reads the file and prints `Date.now()` minus its content; the test asserts
  the file holds an integer and the difference is non-negative. Red: the file is not written.
  Record (Kind: behavior).
- [X] T109 Implement the first statement of `bun/private/launcher.js`: when
  `RULES_BUN_LAUNCH_TIMESTAMP` is set, write `Date.now()` to that file (private, test-only, not
  documented to consumers). T108 green. Record.
- [X] T110 Write `bun/tests/npm/scale/generate.ts` (decision 8): 2,000 deterministic packages
  (fixed mtimes and modes, fixed gzip level; widths and depths giving many edges, scoped names and
  one deep path), written as archives under a given directory, and the lockfile
  `bun/tests/npm/scale/bun.lock` written by the pinned Bun against the loopback registry; run it and
  check in `bun.lock` and the root `package.json`. Record (Kind: fixture) the package and edge
  counts.
- [X] T111 Write the integration test `bun/tests/integration/scale.test.ts`: regenerates the
  archives with `generate.ts` under `TEST_TMPDIR` and serves them; measures extension evaluation as
  inner `bazel mod deps` wall time minus the same with the tag removed; counts the target's actions
  with inner `bazel aquery --output=jsonproto` and asserts `P + E + L + A`; measures launcher start
  through `RULES_BUN_LAUNCH_TIMESTAMP` against the same program without packages; asserts the plan
  bounds (≤ 10 s, exact count, ≤ 2 s more) when `process.platform === "linux"`, and prints every
  value, the per-target copy wall time and bytes written, and the guard pattern length. Record.
- [X] T112 Record the measured values of T111 (Linux, local and CI), the largest guarded package set
  and the longest store path of T060 in research G8 (Kind: research). A bound that does not hold is
  reported to the user as a plan amendment, not changed silently.

---

## Phase 13: Polish & Cross-Cutting Concerns

- [X] T113 Extend `.github/workflows/ci.yaml` for Windows (FR-027, G1; steps call only `bazel`): a
  `windows-symlinks` job running the root and `e2e/smoke` test sets with
  `bazel --windows_enable_symlinks`; a `windows-disk-cache` job building
  `//bun/tests/npm/...` with `--output_base=A` and again with `--output_base=B`, one
  `--disk_cache`, and `--execution_log_json_file` per build, then
  `bazel run //bun/tests/integration:disk_cache_check -- <log B>`, a new `bun_binary`
  (`bun/tests/integration/disk_cache_check.ts`) asserting every spawn consuming a store link is a
  cache hit (field name from `spawn.proto` at Bazel 9.2.0, recorded). Add both to
  `conclusion.needs`. Record (Kind: verification): `prek run --all-files` passes; CI results in
  POST-1.
- [X] T114 Extend `.github/workflows/ci.yaml` (FR-011, FR-027, US2-4, US2-7, SC-003): a Linux
  `network-denied` job running, in `.` and `e2e/smoke`, `bazel fetch //...` then
  `bazel test //... --nosandbox_default_allow_network`; in the `test` matrix, for `e2e/smoke`, a
  `bazel run //jsx:render` step and an upload of `bazel mod show_extension` / `bazel mod show_repo`
  output (quickstart 6), and for `.`, `bazel run //bun/tests/npm/fixtures/jsx:render` and
  `bazel run //bun/tests/npm/fixtures/basic:node_modules/single-bin/bin/single-bin -- x`; a
  `mod-compare` job downloading the three outputs and running
  `bazel run //bun/tests/integration:compare_mod_output -- <linux> <macos> <windows>` (a new
  `bun_binary`, `bun/tests/integration/compare_mod_output.ts`, failing with the first differing
  line). Add both jobs to `conclusion.needs`. Record.
- [X] T115 Complete the documentation (FR-012, FR-018, FR-019, FR-020, FR-021, FR-023, FR-036,
  contracts/public-api.md; Kind: documentation): `doc` strings of the `npm` extension, both tags
  and every attribute in `bun/private/npm_extension.bzl`; the `bun/extensions.bzl` docstring with
  the quickstart setup; `BunLibraryInfo.packages`; in `bun/private/run.bzl` and `bun/defs.bzl` the
  package layout, the generated-target naming rules, peers, the load guard with packages and its
  limits restated (a `package.json` outside the set may be read, G9), `ignore_directories`,
  lifecycle scripts and `trustedDependencies` (G4, `bun pm default-trusted`, `bun pm untrusted`),
  `directories.bin`, non-optional platform packages, `sunos` and `libc` (G6), empty directories
  and symbolic links in archives, Windows junctions and no flag (G1), Windows-invalid names (G2),
  Windows path length with the longest tested path and the `--output_user_root` advice (G8),
  mirrors and credentials; claim only tested behavior and name its platforms. Keep the JSX
  limitation until POST-2. Record: root `bazel test //...` passes.
- [X] T116 Check the access inventory (SC-007; Kind: verification): list every `# L<n>` marker in
  `bun/private/lockfile.bzl`, `overrides.bzl`, `workspaces.bzl` and compare with research Part 3;
  every undescribed access has a canary in `//bun/tests/canary/npm:canaries` with a recorded red.
  Record the comparison; a mismatch is fixed in research or code before hand-back.
- [X] T117 Write the scenario coverage table (SC-006, SC-008; Kind: verification): a section in
  `specs/003-npm-dependencies/tdd-log.md` mapping every acceptance scenario US1-1 … US9-3 and every
  Edge Case to its test target or CI step, and every behavior task to its record; list what is
  uncovered or unverified per OS.
- [X] T118 Run the static checks and record their output (constitution III, V, VI, I; FR-020; Kind:
  verification): `git grep -n run_shell -- bun e2e` and `git grep -n 'repository_ctx.execute\|rctx.execute' -- bun`
  print nothing; `git grep -n 'include(' -- MODULE.bazel` and `git ls-files '*.MODULE.bazel'` print
  nothing (decision 7); for every package repository `bazel mod show_extension
  //bun:extensions.bzl%npm` lists for the root module's fixture hubs, `bazel mod show_repo` shows
  a `replacement` (Fixture hubs convention); `git ls-files '*.sh' '*.bat' '*.cmd' '*.ps1'` lists no file this feature added;
  no `bazel_dep` without `dev_dependency` was added (FR-028); `bazel query 'attr(visibility,
  "//visibility:public", //bun/...)'` differs from `main` only by `bzl_library` targets of new
  public files; the inner-test secrets appear in no checked-in file.
- [X] T119 Run the quickstart validation on Linux (rows 1–7, 10) and record each row's result;
  rows 8–9 and the macOS and Windows parts are left to POST-1.
- [X] T120 Run the AGENTS.md hand-back checks: in the root `bazel run //:gazelle`,
  `prek run --all-files`, `bazel test //...`; in `e2e/smoke/` `bazel test //...`. Record each
  result. Report a failure; do not widen the task to fix it.

---

## Post-workflow (run by the operator after the `review-final` gate, not by `speckit.implement`)

- POST-0 Adversarial review by a subagent and by Codex (the workflow's `review-claude` and
  `review-codex` steps); fix confirmed findings within this feature and record each finding and
  its outcome in `tdd-log.md`.
- POST-1 Commit, push `003-npm-dependencies` and open a pull request to `main` only when the user
  authorizes it; record the `CI` run ID with per-OS, per-folder results: the JSX proof as test and
  `bazel run` on three OSes (SC-002), Windows with and without `--windows_enable_symlinks` and the
  disk-cache check (G1; a failure of Bun through junctions is reported as FR-004, not worked
  around), C-WINNAME's observed behavior and red (T059), the network-denied job (SC-003), the
  `mod-compare` job (US2-7), the native real run per OS (T078), US4-6's O case per OS, the scale
  values on Linux CI (T111), and the integration suite per OS. Report every OS or job that did not
  run or failed as unverified (constitution II).
- POST-2 After POST-1 shows US1 passing on Linux, macOS and Windows, remove "JSX needs the `react`
  package" from `_FILES_DOC` in `bun/private/run.bzl` (FR-021), re-run T120's checks, record, and
  push only with the user's authorization.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T008)**: first. T001 → T002; T003, T004 in parallel; T005 after T004; T006 after
  T003 and T005; T007 any time after T001; T008 after T003.
- **Foundational (T009–T043)**: after Setup; blocks every story. Harness T009 → T010 → T011 →
  T012 → T013. JSONC T014 → T015. Reader T016 → T017 (needs T006, T015). Canaries T018–T032 after
  T017 (and T008), in parallel with each other and with T033–T043. Resolver T033 → T034 (after
  T017). Extension T035 → T036 → T037 → T038 → T039 → T040 (after T034); T041 after T040;
  replacement T042 → T043 (after T040 and T013).
- **US1 (T044–T060)**: after Foundational. T044 → T045 → T046 → T047 → T048 → T049 → T050 → T051 →
  T052 → T053 → T055 → T056 → T057 → T058 → T060; T054 after T053; T059 after T058.
- **US2 (T061–T074)**: after US1 (its integration targets build packages through the layout).
  T061 → T062 → T063 → T064; T065, T066 after T064; T067 → T068; T069 after T068; T070 → T071 →
  T072 → T073 → T074.
- **US3 (T075–T079)**: after US1. T075 → T076 → T077 → T078 → T079.
- **US4 (T080–T085)**: after US1 and US2 (member comparison extends T064); T084's O case needs US3.
  T080 → T081 → T082 → T083 → T084 → T085.
- **US5 (T086–T091)**: after US1; T086's `w1` case needs US4. T086 → T087 → T088 → T089 → T090 →
  T091.
- **US6 (T092–T097)**: after US1. T092 → T093 → T094 → T095 → T096 → T097.
- **US7 (T098–T102)**: after US2. T098 → T099 → T100 → T101 → T102.
- **US8 (T103–T105)**: after US1–US5 (the consumer gets the final layout and peers). T103 → T104
  → T105.
- **US9 (T106–T107)**: after US2.
- **Scale (T108–T112)**: after US5 and US6 (the count covers the final actions). T108 → T109;
  T110 any time after T006; T111 after T109 and T110; T112 after T111 and T060.
- **Polish (T113–T120)**: after all stories and Scale; T113, T114 after T105; T115 after T112;
  T116, T117 after T115; T118 → T119 → T120.
- **POST-0, POST-1, POST-2**: last, in that order.

### Story completion order

Foundational → US1 → US2 → US3 → US4 → US5 → US6 → US7 → US8 → US9 → Scale → Polish. US3 and US6
may move before US2 (they need only US1), between tasks, because they edit the same `.bzl` files.

### Within each story

- The test task runs red and is recorded before its implementation task.
- A canary follows the implementation of the access it pins.
- Each checkpoint re-runs root `bazel test //...` before the next phase.

### Parallel opportunities

Only tasks that edit none of the files named in "Parallel marker":

- Setup: T003 and T004; T007 alongside T003–T006.
- Canaries T018–T032 (after T017), T041 (after T040), T054 (after T053), T059 (after T058),
  T065, T066 (after T064), T069 (after T068); merge their `bun/tests/canary/npm/BUILD.bazel`
  lines last.
- T110 (scale generator) alongside any story phase after T006.

Not parallel because their red or implementation edits a guarded file: every mutation task (T050,
T051, T053, T055, T056, T057, T064, T072, T073, T074, T077, T101, T106) and every implementation
task.

---

## Parallel Example: Foundational canaries

```text
Task T018: bun/tests/canary/npm/c_ver.test.ts
Task T020: bun/tests/canary/npm/c_wskey.test.ts
Task T023: bun/tests/canary/npm/c_keypath.test.ts
Task T029: bun/tests/canary/npm/c_peers.test.ts
(all after T017, alongside T033–T043)
```

## Parallel Example: User Story 1

```text
Task T054: bun/tests/canary/npm/c_td.test.ts (after T053), alongside T055–T058
Task T059: bun/tests/canary/npm/c_winname.test.ts (after T058), alongside T060
```

## Parallel Example: User Story 2

```text
Task T065: bun/tests/canary/npm/c_overrides.test.ts (after T064)
Task T066: bun/tests/canary/npm/c_catalog.test.ts (after T064), alongside T067–T068
Task T069: bun/tests/canary/npm/c_patched.test.ts (after T068), alongside T070–T074
```

## Parallel Example: Scale

```text
Task T110: bun/tests/npm/scale/generate.ts (after T006), alongside any story phase
```

---

## Implementation Strategy

### MVP (User Story 1)

1. Setup (T001–T008), Foundational (T009–T043).
2. US1 (T044–T060).
3. Validate: `bazel test //...` on Linux, `bazel run //bun/tests/npm/fixtures/jsx:render`. Not
   releasable alone: US2 (verified fetch failures), US3 (platform packages), US5 (peers beyond
   the provided case) and the consumer module (US8) are mandatory, and macOS and Windows are
   unverified until POST-1.

### Incremental delivery

1. Foundational → offline harness, reader with canaries, resolver core, generated targets,
   verified replacements.
2. US1 → strict store, guard, libraries, JSX proof, archives, no lifecycle scripts.
3. US2 → evaluation errors, manifest comparison, unsupported entries, integrity, laziness,
   reproducibility.
4. US3 → platform selection. US4 → workspaces. US5 → full peer semantics and uniqueness.
5. US6 → executables. US7 → registries and credentials. US8 → consumer module. US9 → several
   lockfiles.
6. Scale → bounds. Polish → CI, documentation, checks. POST-0–POST-2.

---

## Notes

- [P] tasks = different files, no dependency on an incomplete task, no edit of a guarded file.
- [Story] label maps a task to its user story for traceability.
- Verify each test fails for the expected reason before implementing (FR-030).
- Stop at any checkpoint to validate the stories so far.

---

## Phase 14: Convergence

- [X] T121 Make packages whose `bun.lock` integrity uses `sha256` or `sha384` fetch: Bun 1.4.2 writes every integrity as unpadded base64 followed by `==` (C-INTEGRITY), and Bazel 9.2.0's `download_and_extract` rejects such `sha256-…==` and `sha384-…==` values with "Checksum error … Invalid base64" (reproduced 2026-10-21 on Linux with a `file://` archive; `sha512` and correctly padded `sha256` pass). Red first: a Bazel-in-Bazel case in `bun/tests/integration/` that fetches the `alg_sha256` and `alg_sha384` packages from the loopback registry without `replace_package` and builds a target needing them. Then re-pad the base64 to the algorithm's digest length in `bun/private/npm_extension.bzl` before the value reaches `npm_package_repository`'s `integrity`, keeping the lockfile's digest unchanged. Record per FR-009 and Constitution III (partial)
- [X] T122 Implement the stale-link check that research "Decisions during implementation" (2026-10-21, R6) records and no task covers: before Bun starts, `bun/private/launcher.js` compares every entry of every `node_modules` directory in the target's copy tree with the declared link set and fails with an English error naming the extra entry and telling the user to run `bazel clean`. Red first: a test that reproduces the stale link left by T051's mutation (an edge from `phantom-user` to `b`, then reverted) and expects that error; today the phantom import loads after the revert. Record per FR-013, US1-7 and plan: research R6 decision (missing)
- [X] T123 Rewrite `bun/tests/integration/source_node_modules.test.ts` to the G9 correction recorded in research "Decisions during implementation" (2026-10-21) instead of T055's text: with the source `node_modules` not ignored, the default and `--spawn_strategy=local` runs fail with the guard's error naming the file under it; with `ignore_directories(["**/node_modules"])`, both fail with Bun's module-not-found error. The test currently asserts the guard's error for all four runs, so root `bazel test //...` fails. Then do T055's mutation and record, mark T055 done, and apply the same split to T091's optional-peer case. Record per US1-7, US5-2, Edge Cases (source-tree `node_modules`) and plan: G9 (contradicts)
- [X] T124 Make the replacement check gate the use of a replaced archive, as T043 states ("the instance tree depends on the stamp"): today `npm_package_tree` in `bun/private/npm_package.bzl` copies the extracted replacement without depending on `:check`, so only targets that also carry the stamp in runfiles or `DefaultInfo` fail on a wrong archive. Red first: an analysis test that the instance tree's copy action has the stamp among its inputs. Record per FR-026 and T043 (partial)

## Phase 15: Convergence

- [X] T125 CRITICAL: Remove or inventory the `bun.lock` reads that research Part 3 does not list: `_entry` in `bun/private/lockfile.bzl` reads slot 1 of a `file:` entry as its info object and slots 1 and 2 of a tarball-URL entry as info and integrity, with no `# L<n>` marker, no Part 3 row and no canary, and T116 reported no mismatch. These kinds are unsupported (FR-010), so drop the reads (the entry keeps empty `info` and `integrity`) unless a reader branch needs them; otherwise add Part 3 rows and canaries with recorded reds. Red first: a `lockfile_test.bzl` case asserting a `file:` and a tarball entry read with empty dependencies and integrity. Then re-run T116's comparison and record it per Constitution V, FR-001, FR-024 and SC-007 (contradicts)
- [X] T126 Reconcile the documents with the G9 correction that T123 tested: when `ignore_directories(["**/node_modules"])` covers a source-tree `node_modules`, the import fails with Bun's module-not-found error, not the guard's. The spec Edge Case, `contracts/public-api.md` ("ignored or not, it stays reachable … fails the load guard") and the data-model test map rows ("guard error either way") still state the guard's error for both cases, and `_FILES_DOC` in `bun/private/run.bzl` says the directory "stays reachable" in both cases. Record a spec Revision 6 restating that Edge Case, then align the contract, the test map and `_FILES_DOC`; root `bazel test //...` passes. Record per Edge Cases (source-tree `node_modules`) and plan: G9 (contradicts)
- [X] T127 Pin the `configVersion = 0` Edge Case that `_FILES_DOC` in `bun/private/run.bzl` claims ("a lockfile written for Bun's hoisted installs gets this layout too") and T117 lists as uncovered: a `lockfile_test.bzl` case showing that a lockfile with `"configVersion": 0` reads the same as with 1, and a phantom spawn case on that lockfile failing as US1-7; otherwise narrow the documentation to what is tested. Record per Edge Cases (hoisted lockfile) and Constitution II (partial)
- [X] T128 Pin `aix` → `@platforms//os:aix`, which the spec Edge Case and `contracts/public-api.md` state: the only `aix` fixture (`nomatch-aix-ppc64`) also has `cpu` `ppc64`, which no constraint matches, so no test shows the `aix` mapping in `_OS` of `bun/private/npm_repositories.bzl` selects anything. Add an analysis case on an `aix` platform in `bun/tests/platforms/BUILD.bazel` with an optional package whose `os` is `aix` and whose `cpu` has a constraint. Record per Edge Cases (`os`/`cpu` values) and FR-016 (partial)
- [X] T129 Align `npm.replace_package`'s scope with its documentation: `_npm_extension_impl` in `bun/private/npm_extension.bzl` applies a root replacement to the lockfiles of every module, as rules_js does (research G3), but the tag's `doc` and `contracts/public-api.md` say "every lockfile of the root module"; no test covers a non-root module's lockfile. Add that case to `bun/tests/integration/replace.test.ts` (or `multi.test.ts`) and correct the documentation to the tested behavior. Record per FR-026 and plan: G3 (contradicts)

## Phase 16: Convergence

- [X] T130 CRITICAL: Back or narrow the claim "empty directories are not carried" in the Package contents limitation of `specs/003-npm-dependencies/contracts/public-api.md`: no test covers an archive with an empty directory (the `npm` extension's `_NPM_DOC` in `bun/private/npm_extension.bzl` itself calls it unverified, "not expected to be carried"). Either add a fixture package whose archive holds an empty directory (packed by `bun/tests/npm/registry/pack.ts`, replaced in `npm_basic`) and a real run or analysis case in `bun/tests/npm/` showing the directory is absent from the store entry, recorded red first, then align `_NPM_DOC` and `_FILES_DOC` with the tested result; or restate the contract as unverified, matching `_NPM_DOC`. Record per Constitution II (contradicts)
- [X] T131 Make the CI comparison of US2-7 cover platform-restricted packages, where host-dependent generation would show: `mod-compare` in `.github/workflows/ci.yaml` compares only `e2e/smoke`, whose lockfile (`react`, `react-dom`, `scheduler`) has no `os`/`cpu` entry, and nothing uploads the `mod_output.txt` that `bun/tests/integration/reproducible.test.ts` writes, although its header says CI compares it. Add a package with `os`/`cpu`-restricted optional dependencies (for example `native` and its `native-*` packages) to the `fetch` inner workspace's lockfile, upload each OS's `reproducible_test` `mod_output.txt` from the root `test` job (`bazel-testlogs/bun/tests/integration/reproducible_test/test.outputs/`), have `mod-compare` run `compare_mod_output` on those three as well, and keep the test's header true. Record per US2-7, FR-008 and FR-027 (partial)
- [X] T132 Extend `bun/tests/integration/laziness.test.ts` to the peer part of SC-005: a target that needs one package with a resolved peer (for example `p`, whose peer `q` its dependent's workspace provides, with the optional peer `r` unprovided) causes archive requests for exactly that package, its dependencies and its resolved peer, and none for `r` or another version of `q`; add the packages and the target to the `fetch` inner workspace. Record per SC-005 (partial)
- [X] T133 Make `bun/tests/canary/npm/c_winname.test.ts` call `assertOffline(inner.log)` like every other Bazel-in-Bazel test: it runs only on Windows, where the loopback request log is the only evidence that the inner build used no external network. Record per FR-025 and the Integration tests convention (partial)

## Phase 17: Convergence

- [X] T134 Stop an `npm_bin` target of a platform-restricted optional package from crashing analysis: `_bin_record` in `bun/private/run.bzl` indexes `[...][0]` into the package's records, and on a platform the package's `os`/`cpu` does not match the selected instances are empty, so analysis fails with "index out of range"; `npm_bin` targets are not `manual`, so `bazel build //...` breaks. Red first: add a fixture optional dependency with a JS `bin` (packed by `bun/tests/npm/registry/pack.ts`) and an analysis case in `bun/tests/platforms/BUILD.bazel` building its bin target on a non-matching platform. Then give such bin targets `target_compatible_with` for the platforms the package matches (or fail with an English error naming the package and platform). Record per FR-016 and US6 (contradicts)
- [X] T135 Reject credentials embedded in `.npmrc` registry URLs: `read_npmrc` in `bun/private/npmrc.bzl` accepts `registry` and `@scope:registry` values such as `https://user:token@host/`, which then reach `npm_package_repository`'s `url` attribute and `canonical_id`. Red first: an `npmrc` test with userinfo in `registry` and in a scope registry. Then fail with an English error naming the key and the file, never echoing the credential. Record per FR-020 and US7 (contradicts)
- [X] T136 Tag a link `manual` when an unsupported package is reached only through the platform `select`: the hub's `unsupported` check in `bun/private/npm_repositories.bzl` looks at `link["closure"]` only, not at the instances of `link["select"]`, so such a link is buildable and `bazel build //...` fails. Red first: a fixture with an unsupported entry reachable only as a platform-restricted optional dependency and a test that `bazel build //...` of the hub passes and building the link fails with the FR-010 error. Then extend the check to every `select` branch. Record per FR-010 (partial)
- [X] T137 Namespace instance identities by hub: `_package_layout` in `bun/private/run.bzl` merges instances from every `dep` by `instance.id`, and IDs collide across hubs (several lockfiles, US9), so two different resolutions of one name@version silently collapse into one. Red first: a test combining two hubs where the same name@version resolves a dependency key to different versions, expecting the FR-017 uniqueness error. Then key instances and edges by hub, and validate equivalence before merging. Record per FR-017 and US9 (contradicts)
- [X] T138 Match `exclude_package_contents` patterns against archive names: `npm_package_repository` in `bun/private/npm_repositories.bzl` builds the `glob` exclude after `_make_addressable` renamed files, so a pattern naming a renamed file (e.g. one holding `:`) excludes nothing. Red first: a fixture case excluding a file that `_make_addressable` renames and asserting it is absent from the store entry. Then translate patterns to the renamed names (or exclude before renaming). Record per FR-033 (partial)
- [X] T139 Make the US5-4 conflict error name the differing versions: `_check_unique` in `bun/private/run.bzl` reports "resolves to {} and to {}" even when both resolve to the same version and only the edges (e.g. the peer's own peers) differ, so the message names one version twice. Red first: a case with two instances whose peer resolves to the same version through different instances, asserting the error names the differing peer versions. Record per FR-017 and US5-4 (partial)
- [X] T140 Fail evaluation when two entries of one name@version record different integrities and one is unsupported: the comparison in `_npm_extension_impl` of `bun/private/npm_extension.bzl` skips unsupported entries, so the mismatch passes. Red first: a lockfile case with one supported and one unsupported entry of the same name@version and different integrities, expecting an English error naming both entries and both values. Record per Edge Cases (entries of one package version with different URLs or integrities) (partial)
- [X] T141 Record the Windows behavior of C-WINNAME: `EXPECTED_WINDOWS` in `bun/tests/canary/npm/c_winname.test.ts` is `null`. Copy the repository to a directory under `C:\Users\revil\rbwin\`, run the canary with `C:\Users\revil\rbwin\tools\bazelisk.exe` (`USE_BAZEL_VERSION=9.2.0`) through `powershell.exe` from WSL, commit the observed expectation, and record the run in `tdd-log.md` as Windows (local, WSL interop). In the same session run `path_length_test` and report whether the ~382-character store paths work; if they fail, record a gap in research Part 1 and stop. Record per FR-036 and POST-1 (missing)
- [X] T142 Make the load guard compare paths case-insensitively on Windows (research G11, item 2): Windows file names are case-insensitive, and the copy-tree root the guard derives from the declared real paths and the path Bun loads may spell the output root in different case (`C:\users\…` and `C:\Users\…`), so `guard` in `bun/private/launcher.js` rejects declared files. Red first on Windows (local, WSL interop): `path_length_test` loading `deep` (T141, decision (a)) fails with the guard's "is not declared by this target". Then compile the guard's filter with the `i` flag on Windows only. Record per FR-013, research G11 and POST-1 (contradicts)
