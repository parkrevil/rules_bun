---

description: "Task list for feature 005: the ruleset's design principles, held everywhere"
---

# Tasks: The Ruleset's Design Principles, Held Everywhere

**Input**: Design documents from `specs/005-review-defect-fixes/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/public-api.md,
quickstart.md

**Tests**: required. FR-023: every fix is test-first; the test is written, run and seen failing
before the fix, and passes after it. Each story phase therefore starts with its tests.

**Organization**: Tasks are grouped by user story (spec US1–US9). P1 stories run in the plan's
implementation order (US3, US2, US4, US1), then P2 (US7, US5, US6), then P3 (US8, US9). Paths are
relative to the repository root.

**Conventions used in every task**:

- Work and commit on branch `005-review-defect-fixes` (from `main` at `aca8c13`). One PR at the
  end (T086).
- `B` is the development toolchain's Bun:
  `B="$(bazel info output_base)/external/+bun+bun_linux-x64/bun"`.
- "Record red" / "record green" means: append to `specs/005-review-defect-fixes/tdd-log.md` one
  row with the task ID, the test target, the exact command, the platform it ran on, the result
  and a short excerpt of the failure text (red) or the pass line (green). A red that fails for a
  reason other than the defect (a typo, a missing load) does not count: fix the test and re-run.
- Fixture archives are produced only by `bun/tests/npm/registry/pack.ts` and fixture lockfiles only
  by `bun/tests/npm/registry/write_lockfiles.ts`, both run with `$B` from the repository root
  (feature 004 R8 procedure). Never edit a `.tgz` or a `bun.lock` by hand.
- Downloads go into a new, empty directory under `/tmp/bun005-*`, never next to a script; no
  integrity is ever computed from a downloaded archive (constitution III).
- "Stop and report" means: change nothing more for that item and tell the user what was observed.
- Every diagnostic, `doc =` string, docstring, comment and commit message is in English.
- Every diagnostic that this feature adds starts with `rules_bun: ` or `<label>: ` as the
  surrounding code does, and never contains URL user information: URLs reach a diagnostic only
  after FR-002's check has rejected every URL holding it (a URL is a location, P1).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US9)

---

## Phase 1: Setup

**Purpose**: Branch, user decisions, evidence the plan rests on, a green baseline.

- [X] T001 Confirm `git branch --show-current` prints `005-review-defect-fixes`, `git merge-base
  HEAD main` is `aca8c13`, and `git status --short` shows only `specs/005-review-defect-fixes/`;
  commit that directory as `docs: specify feature 005, the ruleset's design principles` (plan
  step 1)
- [X] T002 Check that research Part 5 records the user's approval of D1 (every generated bin target
  `manual`), D2 (FR-007 and SC-007 read as "no hermetic-launcher stub repository is fetched") and
  D3 (C1 stays Windows-compatible unless the PR's Windows jobs cannot create a link), given at the
  plan gate on 2026-10-28. T041 (D1), T063–T068 (D2) and T087 (D3) depend on it
- [X] T003 [P] Create `specs/005-review-defect-fixes/tdd-log.md` with a title, one paragraph
  stating FR-023, and a table with the columns `Task`, `Target`, `Command`, `Platform`, `Result`,
  `Excerpt`
- [X] T004 [P] Re-verify research E1: in a new empty `/tmp/bun005-shasums-1.4.2/` and
  `/tmp/bun005-shasums-1.4.4/`, download only `SHASUMS256.txt` of `bun-v1.4.2` and `bun-v1.4.4`
  (`gh release download bun-v<v> -R oven-sh/bun -p SHASUMS256.txt`); for the lines of
  `bun-linux-x64-musl.zip`, `bun-linux-aarch64-musl.zip` and `bun-linux-x64.zip` compute
  `echo -n <hex> | xxd -r -p | base64`; confirm the musl values equal research E1 and the
  `linux-x64` values equal those in `bun/private/versions.bzl`. On any difference or missing line,
  stop and report
- [X] T005 [P] Baseline: run `bazel test //...` in the root and in `e2e/smoke/` and record the
  result in `tdd-log.md` as the baseline; if anything fails, stop and report (AGENTS.md: do not
  widen the task)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The one platform table (FR-004, research R5) with behavior unchanged, so US4 and US6
change one place.

**⚠️ CRITICAL**: US4 and US6 cannot start until this phase is complete.

- [X] T006 Create `bun/private/platforms.bzl` holding: `NPM_OS` and `NPM_CPU` moved verbatim from
  `bun/private/npm_repositories.bzl` (npm `os` → `@platforms//os:<v>`: aix, android,
  darwin→macos, freebsd, linux, netbsd, openbsd, win32→windows; npm `cpu` →
  `@platforms//cpu:<v>`: arm, arm64→aarch64, ia32→x86_32, riscv64, s390x, x64→x86_64);
  `NPM_LIBC` (`glibc`, `musl` → `Label("//bun/platforms/libc:<v>")`); `BUN_ARCHIVES` with today's
  five archives as `struct(os, cpu, libc)` in npm vocabulary (`linux-x64` linux/x64/glibc,
  `linux-aarch64` linux/arm64/glibc, `darwin-x64`, `darwin-aarch64`, `windows-x64` with
  `libc = None`); and `archive_constraint_sets(archive)` returning, for now, today's single
  `[os, cpu]` constraint list per archive. Module docstring names research R5
- [X] T007 In `bun/private/npm_repositories.bzl`, load `NPM_OS`, `NPM_CPU`, `NPM_LIBC` from
  `//bun/private:platforms.bzl`, delete the local copies, and derive `_settings` and the hub's
  `config_setting`s from them (same names, same constraints)
- [X] T008 In `bun/private/toolchains_repo.bzl` and `bun/private/repositories.bzl`, derive the
  platform list and each toolchain's constraints from `BUN_ARCHIVES` and
  `archive_constraint_sets`; `_ATTRS.platform` `values` becomes `sorted(BUN_ARCHIVES)`. The
  generated `@<name>_toolchains` BUILD file must be byte-identical to today's (compare
  `cat $(bazel info output_base)/external/+bun+bun_toolchains/BUILD.bazel` before and after)
- [X] T009 Run `bazel run //:gazelle` (adds the `bzl_library` for `platforms.bzl` in
  `bun/private/BUILD.bazel`), then `bazel test //bun/tests:all //bun/tests/npm:all`; all pass
  unchanged. Commit as `refactor: derive platforms from one table`

**Checkpoint**: one table, no behavior change.

---

## Phase 3: User Story 3 - Credentials in a lockfile URL are rejected and never printed (Priority: P1) 🎯 MVP

**Goal**: No URL holding user information is accepted from `bun.lock` or `.npmrc`; no diagnostic
or repository attribute holds it (FR-002, research R2, data-model "URL check").

**Independent Test**: `bazel test //bun/tests/npm:npmrc //bun/tests/integration:credentials_test`
(quickstart Q1); failure texts hold no user, token or URL.

### Tests for User Story 3 (write first, see red)

- [X] T010 [P] [US3] In `bun/tests/npm/npmrc_test.bzl`, add unit cases for `has_userinfo(url)`
  loaded from `//bun/private:npmrc.bzl`: true for `https://user:token@host/x`,
  `https://@host/x` (empty user information, spec Edge Cases), `https://user@host`,
  `git+https://user:token@host/r.git`; false for `https://host/a@1.0.0.tgz` (`@` after `/`),
  `https://host?x=a@b`, `https://host#a@b`, `https://host:8080/x`. Run
  `bazel test //bun/tests/npm:npmrc`; record red (symbol not exported)
- [X] T011 [P] [US3] In `bun/tests/integration/credentials.test.ts`, add inner-workspace cases,
  each asserting evaluation fails, the output names the `bun.lock` label and the lockfile entry
  key, contains `--credential_helper` and `.netrc`, and contains neither the user, the token
  (use the distinctive strings `u5er` and `t0ken-secret`) nor the URL: (a) an npm entry whose
  slot 1 URL is `http://u5er:t0ken-secret@127.0.0.1:<port>/...`; (b) a `tarball` entry whose
  resolution holds that user information; (c) a `git+https://u5er:t0ken-secret@host/r.git`
  entry (unsupported kind); (d) a lockfile with two entries of one `name@version` whose URLs
  differ, one holding user information (the duplicate-entry diagnostic must not print it). Add
  (e) and (f): an `.npmrc` `registry=` and `@scope:registry=` with user information, failing as
  today (existing behavior, now covered; FR-002, US3-2). Add (g) and (h): a dependency spec
  `https://u5er:t0ken-secret@host/p.tgz` in a workspace `package.json` and the same spec only in
  `bun.lock` `workspaces` (so `compare_manifests` would report the difference); each fails with the
  user-information error naming the file and the dependency, without the spec. Write each lockfile inline in the test as
  the file already does. Run `bazel test //bun/tests/integration:credentials_test`; record red for
  (a)–(d) and green for (e)–(f)

### Implementation for User Story 3

- [X] T012 [US3] In `bun/private/npmrc.bzl`, rename `_has_userinfo` to the module-level public
  function `has_userinfo(url)` (the authority, after `://` and before the first `/`, `?` or `#`,
  holds `@`; without `://` the whole string up to `/`, `?` or `#` is the authority), with a
  docstring; `read_npmrc` uses it unchanged
- [X] T013 [US3] In `bun/private/npm_extension.bzl` `_translate`, before `first_entries` and every
  other check that may print a URL, iterate every `packages` entry of the lockfile and call
  `has_userinfo` on slot 1 of an npm entry and on the slot 0 resolution of a `tarball` entry and of
  every unsupported entry whose resolution is a URL (read the slot layout from
  `bun/private/lockfile.bzl`). On a match, `fail()` with exactly: `rules_bun: <bun_lock label>:
  the packages entry "<key>" records a URL that holds user information (credentials before an @);
  give credentials through Bazel's downloader (--credential_helper or .netrc) instead`. Print
  neither the URL nor slot 0. Apply the same check, before `compare_manifests`, to every dependency
  spec of every workspace `package.json` and of `bun.lock` `workspaces` (`bun/private/workspaces.bzl`),
  failing with `rules_bun: <file>: the dependency "<name>" is a URL that holds user information ...`
  without printing the spec
- [X] T014 [US3] In the `translate_lock` doc of `bun/private/npm_extension.bzl`, extend the
  credentials sentence: a URL holding user information is rejected from `bun.lock` as from
  `.npmrc`; credentials come only from Bazel's downloader
- [X] T015 [US3] Run `bazel test //bun/tests/npm:npmrc //bun/tests/integration:credentials_test
  //bun/tests/npm:all`; record green; commit as `fix: reject credentials in bun.lock URLs`

**Checkpoint**: US3 holds; SC-004 covered.

---

## Phase 4: User Story 2 - Every package archive stays verified when several lockfiles share it (Priority: P1)

**Goal**: Instances from two hubs are carried once only when integrity, source and exclusion
policy are equal and every edge matches; otherwise analysis fails naming the package version,
both lockfiles and the first differing property with both values (FR-001, research R1,
data-model "Content identity").

**Independent Test**: `bazel test //bun/tests/npm:uniqueness //bun/tests/integration:multi_test`
(quickstart Q2).

### Tests for User Story 2 (write first, see red)

- [X] T016 [US2] Add Bazel-in-Bazel workspaces under `bun/tests/integration/workspaces/`, each
  with two `npm.translate_lock` hubs and one `bun_binary` that depends on the shared package from
  both hubs, modeled on `multi_root/` and `multi_dep/`:
  `multi_integrity/` (one `name@version`, two different archives of it served under two loopback
  registry paths, each lockfile recording its own archive's integrity, so both downloads verify
  and only R1's analysis check can fail; produce the variant archive with `pack.ts` from a copy of
  the package directory that differs in one file),
  `multi_source/` (same archive and integrity, two different URLs: two registry paths as
  `workspaces/registries/` does),
  `multi_exclude/` (same lockfile in both hubs, one hub with `exclude_package_contents` for the
  package),
  `multi_nointegrity/` (one hub's entry records no integrity),
  and `multi_alike/` (identical identity). Register the new files in
  `bun/tests/integration/BUILD.bazel` `workspace_files` if the glob does not already cover them
- [X] T017 [US2] In `bun/tests/integration/multi.test.ts`, add cases: `multi_alike` builds and
  runs with one `.store/<name>@<version>` entry; `multi_integrity` fails naming
  `<name>@<version>`, both hub names with their `bun.lock` labels, `integrity` and both integrity
  values;
  `multi_source` fails naming `source` and both URLs; `multi_exclude` fails naming `exclusion
  policy` and both pattern lists; `multi_nointegrity` fails with `bun.lock records no integrity`
  (research R1 edge case). Run `bazel test //bun/tests/integration:multi_test`; record red for
  integrity, source and exclusion (today the build succeeds)

### Implementation for User Story 2

- [X] T018 [US2] In `bun/private/providers.bzl`, add to `NpmInstanceInfo` the fields `integrity`
  (padded integrity string), `source` (download URL, or the `replace_package` label text),
  `exclude` (sorted, de-duplicated list of exclusion patterns), `hub` (the hub name the
  `npm.translate_lock` tag gives) and `lockfile` (the hub's `bun.lock` label text), the last two for
  diagnostics, each documented
- [X] T019 [US2] In `bun/private/npm_package.bzl`, add the attributes `integrity`
  (`attr.string`), `source` (`attr.string`), `exclude` (`attr.string_list`) and `lockfile`
  (`attr.string`) to `npm_instance` and put them into `NpmInstanceInfo`
- [X] T020 [US2] In `bun/private/npm_extension.bzl` (hub data) and the hub BUILD generation in
  `bun/private/npm_repositories.bzl`, write per `ok` instance: `integrity =
  padded_integrity(entry.integrity)`, `source = package_url(...)` or the replacement's
  `_label_text(...)`, `exclude = sorted(set(exclude_package_contents.get("*", []) +
  exclude_package_contents.get(<name>, [])))`, `lockfile = str(tag.bun_lock)`
- [X] T021 [US2] In `bun/tests/npm/uniqueness_test.bzl`, add analysis tests that build
  `npm_instance` targets directly (as the file's existing helpers do) over one tree with
  different `lockfile` values and: equal identity → one store entry (`_hubs_alike_impl` style);
  different `integrity` → failure messages `["x@1.0.0", "<lockfile A>", "<lockfile B>",
  "integrity", "<value A>", "<value B>"]`; different `source`; different `exclude`; and
  identity equal but an edge different → the existing dependency message. Register them in the
  suite. Run `bazel test //bun/tests/npm:uniqueness`; record red (the instances are merged)
- [X] T022 [US2] In `bun/private/run.bzl`, make `_equivalent` compare `integrity`, `source`,
  `exclude` before the edges, and make `_check_unique` fail, before it reports any dependency
  difference, with: `<label>: the npm package <name>@<version> comes from the hubs <hub A>
  (<lockfile A>) and <hub B> (<lockfile B>) with different <property>: <value A> and <value B>;
  one instance per package version is carried only when both hubs describe the same content`, `<property>` being the
  first difference in the order `integrity`, `source`, `exclusion policy`
- [X] T023 [US2] In `_NPM_DOC` of `bun/private/npm_extension.bzl`, state for several lockfiles:
  a package version is carried once only when both lockfiles record equal integrity, source and
  exclusion policy and its dependencies resolve alike; otherwise analysis fails naming the
  difference
- [X] T024 [US2] Run `bazel test //bun/tests/npm:uniqueness //bun/tests/integration:multi_test
  //bun/tests/npm:all`; record green; commit as `fix: compare content identity across npm hubs`

**Checkpoint**: US2 holds; SC-005 covered.

---

## Phase 5: User Story 4 - A musl platform gets the musl Bun (Priority: P1)

**Goal**: Bun's official musl archives are known for 1.4.2 and 1.4.4 and resolve for
`:musl` platforms on both CPUs, as execution and target toolchain; `:glibc` and `:unconstrained`
keep glibc (FR-005, research R5, data-model "Platform table", "Known version").

**Independent Test**: `bazel test //bun/tests:selection //bun/tests:target_selection
//bun/tests:versions`, then `bazel fetch` of both musl repositories (quickstart Q4).

### Tests for User Story 4 (write first, see red)

- [X] T025 [P] [US4] In `bun/tests/platforms/BUILD.bazel`, add `linux_aarch64_glibc` and
  `linux_aarch64_musl` platforms modeled on `linux_x64_glibc` and `linux_x64_musl`
- [X] T026 [P] [US4] In `bun/tests/versions_test.bzl`, assert that every version in
  `TOOL_VERSIONS` has exactly the keys `linux-x64`, `linux-aarch64`, `linux-x64-musl`,
  `linux-aarch64-musl`, `darwin-x64`, `darwin-aarch64`, `windows-x64` (data-model invariant);
  run `bazel test //bun/tests:versions`; record red
- [X] T027 [US4] In `bun/tests/toolchain_test.bzl` (execution toolchain) and
  `bun/tests/target_toolchain_test.bzl` (target toolchain), add cases: `linux_x64_musl` →
  `bun_linux-x64-musl`, `linux_aarch64_musl` → `bun_linux-aarch64-musl`, `linux_x64_glibc` and
  `linux_x64` → `bun_linux-x64`, `linux_aarch64_glibc` and `linux_aarch64` →
  `bun_linux-aarch64`, asserting the Bun file's repository name; run `bazel test
  //bun/tests:selection //bun/tests:target_selection`; record red for the musl cases

### Implementation for User Story 4

- [X] T028 [US4] In `bun/private/versions.bzl`, add for `1.4.2`: `"linux-x64-musl":
  "sha256-SDXspZ1tpw9GdPVkL25Fncrat3NpWy7Zki0TEFeYl0I="`, `"linux-aarch64-musl":
  "sha256-cXYLbI6jBiO4GkkHy4FdSOLqJm8uc+dRU0pEoGB5UN8="`; for `1.4.4`: `"linux-x64-musl":
  "sha256-pajMxedNy4g/6XTxJae9s7QeUZXtG4cOc/F+/9PrKy0="`, `"linux-aarch64-musl":
  "sha256-V/AbAqxxE8Yck18o84wuq4SePJcNqyH4tkCoex72UAk="` (research E1, re-verified in T004)
- [X] T029 [US4] In `bun/private/platforms.bzl`, add `linux-x64-musl` (linux, x64, musl) and
  `linux-aarch64-musl` (linux, arm64, musl) to `BUN_ARCHIVES`, and make
  `archive_constraint_sets` return `[os, cpu, :glibc]` and `[os, cpu, :unconstrained]` for a
  glibc archive, `[os, cpu, :musl]` for a musl archive, `[os, cpu]` otherwise
- [X] T030 [US4] In `bun/private/toolchains_repo.bzl`, declare one execution and one target
  `toolchain()` per constraint set, named `<archive>_toolchain` / `<archive>_target_toolchain` for
  non-Linux and musl archives and `<archive>_<libc>_toolchain` / `<archive>_<libc>_target_toolchain`
  (`libc` `glibc` or `unconstrained`) for glibc archives (research R5)
- [X] T031 [US4] In `bun/private/repositories.bzl`, update the `_ATTRS.platform` doc to list the
  seven values and state that a musl archive serves `@rules_bun//bun/platforms/libc:musl`;
  `bun_register_toolchains` creates `<name>_linux-x64-musl` and `<name>_linux-aarch64-musl`
  (contracts/public-api.md). Add both repositories to the `use_repo(bun_dev, ...)` call in
  `MODULE.bazel`
- [X] T032 [P] [US4] In `bun/platforms/libc/BUILD.bazel`, extend the comment: the libc
  constraint also selects the Bun archive (musl for `:musl`, glibc for `:glibc` and
  `:unconstrained`)
- [X] T033 [US4] Run `bazel test //bun/tests:selection //bun/tests:target_selection
  //bun/tests:versions`, then `bazel fetch @bun_linux-x64-musl//... @bun_linux-aarch64-musl//...`
  (both verify the integrity; on a mismatch stop and report); record green and the fetch output;
  run `bazel test //...`; commit as `feat: select the musl Bun for musl platforms`

**Checkpoint**: US4 holds; SC-006 covered. musl is verified by resolution and integrity only.

---

## Phase 6: User Story 1 - A package executable that Bun can run is runnable (Priority: P1)

**Goal**: A bin is runnable when its path has a source extension or its first line is a `#!`
line naming `node` or `bun`; the package repository decides from the file; `npm_bin` fails with
the true reason otherwise; every generated bin target is `manual` (FR-012, FR-013, research R4,
D1, data-model "Bin decision").

**Independent Test**: `bazel test //bun/tests/canary:c18_extensionless_bin_test
//bun/tests/npm:bins //bun/tests/integration:bins_test` (quickstart Q5, Q6).

### Tests for User Story 1 (write first, see red)

- [X] T034 [P] [US1] Create `bun/tests/canary/c18_extensionless_bin.test.ts`: under a new
  `mkdtempSync(join(process.env.TEST_TMPDIR!, "c18-"))`, write `tsc` (no extension; first line
  `#!/usr/bin/env node`; `require("./lib.js")` of a sibling `lib.js` that prints
  `JSON.stringify(process.argv.slice(2))`) and `esm` (no extension; `#!/usr/bin/env node`;
  `import` of a sibling `lib.mjs`); run each with `Bun.spawnSync([process.execPath,
  "--no-env-file", "--no-install", <absolute path>, "a"])`; assert stdout `["a"]`, empty stderr,
  exit 0. On any difference, fail with a message naming "rules_bun runs an npm bin file without a
  source extension with Bun (FR-012, bun/private/npm_repositories.bzl)". Under
  `RULES_BUN_CANARY_RED=1` alter the expected output so the canary fails (the convention of
  `bun/tests/canary/npm/support.ts`). Add `bun_test(name = "c18_extensionless_bin_test", ...)` to
  `bun/tests/canary/BUILD.bazel`. Record green, and red with `--test_env=RULES_BUN_CANARY_RED=1`
- [X] T035 [P] [US1] Add fixture package `bun/tests/npm/registry/packages/node-bin@1.0.0/` with
  `package.json` `bin` entries `tsc` → `bin/tsc` (extensionless, `#!/usr/bin/env node`, CommonJS,
  `require("../lib/tsc.js")`, prints `tsc ` + its arguments), `envs` → `bin/envs`
  (`#!/usr/bin/env -S node --no-warnings`), `abs` → `bin/abs` (`#!/usr/local/bin/node`), `bunbin`
  → `bin/bunbin` (`#!/usr/bin/env bun`), `sh` → `bin/sh` (`#!/bin/sh`), `noline` →
  `bin/noline` (JavaScript without a `#!` line); pack it with `pack.ts`; add a fixture project
  `bins_node` to `write_lockfiles.ts` that depends on `node-bin` and write its lockfile; register
  the hub `npm_bins_node` in `MODULE.bazel` (dev) next to the other fixture hubs and add it to
  `use_repo`
- [X] T036 [US1] In `bun/tests/npm/bins_test.bzl`, add analysis tests: `npm_bin` for `tsc`,
  `envs`, `abs`, `bunbin` of `node-bin` analyzes (launcher action present); `sh` fails with
  `the bin entry "sh" of the npm package node-bin@1.0.0 is the file bin/sh, which is not a
  JavaScript program for Node or Bun: it has none of the extensions`; `noline` fails the same
  way; the `nonjs-bin` fixture fails the same way; the `dirbin` fixture fails with `it is a
  directory`; a bin excluded by `exclude_package_contents` fails with `the package holds no such
  file`. Run `bazel test //bun/tests/npm:bins`; record red
- [X] T037 [US1] In `bun/tests/integration/bins.test.ts` and `workspaces/bins/`, add cases:
  `bazel run` of an `npm_bin` for `node-bin`'s `tsc` and of the generated
  `:node_modules/node-bin/bin/tsc` with arguments `x -- y` print `tsc x -- y` and exit 0;
  `bazel build` of the `sh` bin fails with the FR-012 text; `bazel build //...` of the workspace
  succeeds and builds no bin target (D1). Vendor the `node-bin` archive in the loopback registry
  as the workspace does for its other packages. Run `bazel test
  //bun/tests/integration:bins_test`; record red

### Implementation for User Story 1

- [X] T038 [US1] In `bun/private/providers.bzl`, add the private provider
  `NpmPackageTreeInfo(bins)` (`bins`: dict bin path → `""` when runnable or the reason) and the
  field `bins` to `NpmInstanceInfo`
- [X] T039 [US1] In `bun/private/npm_repositories.bzl` `npm_package_repository`, add `bins =
  attr.string_list` (the entry's bin paths, normalized as `npm_bin.path`); after extraction and
  renaming, decide each path: runnable when it ends in one of `SOURCE_EXTENSIONS`; else read the
  file through its safe name (renamed files included) and runnable when its first line starts
  with `#!` and its first word's basename is `node` or `bun`, or is `env` and the first following
  word that neither starts with `-` nor contains `=` has basename `node` or `bun`; otherwise the
  reason `the package holds no such file` (absent or excluded), `it is a directory`, or `it has
  none of the extensions <SOURCE_EXTENSIONS joined by ", "> and its first line is no #! line
  naming node or bun`. Write the dict as the `bins` attribute of the `:tree` target. Read only
  bin files without a source extension (plan Performance Goals)
- [X] T040 [US1] In `bun/private/npm_package.bzl`, give `npm_package_tree` the attribute `bins`
  (`attr.string_dict`) and return `NpmPackageTreeInfo(bins = ...)`; `npm_instance` copies it from
  its `tree` into `NpmInstanceInfo.bins`
- [X] T041 [US1] In `bun/private/npm_extension.bzl`, delete `_runnable` and the `runnable` slot of
  the hub's bin data, pass each entry's bin paths to its `npm_package_repository` as `bins`, and
  in the hub BUILD generation (`bun/private/npm_repositories.bzl`) tag every generated
  `:node_modules/<package>/bin/<bin>` target `manual` (D1)
- [X] T042 [US1] In `bun/private/run.bzl`, rewrite `_check_bin` to look up the bin path in
  `NpmInstanceInfo.bins` and fail analysis with `<label>: the bin entry "<entry>" of the npm
  package <name>@<version> is the file <path>, which is not a JavaScript program for Node or Bun:
  <reason>` when the reason is non-empty; remove the false "Bun runs only JavaScript and
  TypeScript files" text
- [X] T043 [US1] Update the bin text of `_NPM_DOC` in `bun/private/npm_extension.bzl` and of the
  `npm_bin` doc in `bun/private/run.bzl`: a bin runs with the toolchain's Bun when it has a source
  extension or its first line is a `#!` line naming `node` or `bun` (npm's bin convention);
  any other bin fails analysis with the reason; every generated bin target is `manual`, so
  `bazel build //...` builds none unless used or requested; reference canary C18
- [X] T044 [US1] Run `bazel test //bun/tests/canary:c18_extensionless_bin_test
  //bun/tests/npm:bins //bun/tests/integration:bins_test //bun/tests/npm:all`; record green; run
  `bazel test //...`; commit as `fix: run npm bins that are JavaScript programs for Node or Bun`

**Checkpoint**: US1 holds; SC-003 covered (an extensionless node-shebang bin runs with zero
configuration).

---

## Phase 7: User Story 7 - Every workaround is pinned and every canary asserts (Priority: P2)

**Goal**: C17 pins Bun dropping a leading `--`; C1 never passes without asserting and checks the
child's exit status (FR-009, FR-010, research R3, data-model "Canaries").

**Independent Test**: `bazel test //bun/tests/canary:all` (quickstart Q5).

### Tests for User Story 7 (the canaries are the tests)

- [X] T045 [P] [US7] Create `bun/tests/canary/c17_leading_dashdash.test.ts`: write a script under
  a new `TEST_TMPDIR` directory printing `JSON.stringify(process.argv.slice(2))`; run
  `Bun.spawnSync([process.execPath, "--no-env-file", <absolute script>, "--", "x"])`; assert
  stdout `["x"]` and exit 0, and in a second case that `[<script>, "a", "--", "b"]` prints
  `["a","--","b"]`. On a difference, fail naming "the launcher's refusal of a leading `--`
  (bun/private/launcher.js, bun_binary doc)". Under `RULES_BUN_CANARY_RED=1` alter the expectation.
  Add `bun_test(name = "c17_leading_dashdash_test", ...)` to `bun/tests/canary/BUILD.bazel`.
  Record green, and red with `--test_env=RULES_BUN_CANARY_RED=1`
- [X] T046 [US7] In `bun/tests/canary/c1_preserve_symlinks.test.ts`, replace the early return on a
  `symlinkSync` failure with `throw new Error("C1 cannot assert: this runner cannot create a
  symbolic link: " + <error message>)`, and assert `result.exitCode === 0` with stdout and stderr
  in the failure message before comparing the output. Show red twice by uncommitted local edits,
  then revert each: (a) make the link path already exist so `symlinkSync` throws; (b) make the
  child script `process.exit(3)`; record both reds and the green

### Implementation for User Story 7

- [X] T047 [US7] In `bun/private/launcher.js` (the leading-`--` check) and the `bun_binary` doc in
  `bun/private/run.bzl`, reference canary C17 as the pin of the Bun behavior the refusal works
  around
- [X] T048 [US7] Run `bazel test //bun/tests/canary:all`; record green; commit as
  `test: pin Bun's leading -- and make C1 assert`

**Checkpoint**: US7 holds; SC-008 covered (D3 settled from the PR's Windows jobs in T087).

---

## Phase 8: User Story 5 - Toolchain requests from several modules resolve predictably (Priority: P2)

**Goal**: The root's integrity wins per platform; non-root conflicts fail; keys, values and
`bun_version` are validated naming module and tag; `npm.translate_lock` `name` and
`workspace_target_name` are validated (FR-015, FR-016, research R8, data-model "Toolchain
request").

**Independent Test**: `bazel test //bun/tests/integration:toolchain_tags_test
//bun/tests/integration:lockfile_errors_test` (quickstart Q7).

### Tests for User Story 5 (write first, see red)

- [X] T049 [US5] Create the workspace `bun/tests/integration/workspaces/toolchain_tags/` with a
  root `MODULE.bazel` and two local modules `dep_a/` and `dep_b/` (each with `MODULE.bazel`,
  reached through `bazel_dep` + `local_path_override`), each calling `bun.toolchain(bun_version =
  "1.4.4", integrity = {...})`; the test writes each case's `MODULE.bazel` contents
- [X] T050 [US5] Create `bun/tests/integration/toolchain_tags.test.ts` and its `bun_test` target
  `toolchain_tags_test` in `bun/tests/integration/BUILD.bazel` (modeled on `lockfile_errors_test`)
  with cases, each using the key of the host's platform (`linux-x64`, `darwin-aarch64` or
  `windows-x64`, so the archive is actually fetched): (a) root gives the correct value, `dep_a` a
  different well-formed SRI → `bazel build` of a `bun_binary` succeeds (the root's value is used
  and verifies); (a2) root gives a wrong well-formed SRI, `dep_a` the correct one → the fetch fails
  with Bazel's checksum error (the root's value wins, it is not ignored); (b) `dep_a` and
  `dep_b` give different `linux-x64` values, root none → evaluation fails naming `dep_a@`,
  `dep_b@`, `1.4.4` and `linux-x64`; (c) key `linux_x64` → fails naming the module, the key and
  the seven known keys; (d) value `abc` → fails naming the module and the key and the accepted
  forms `sha256-`/`sha384-`/`sha512-`; (e) two root tags for `1.4.4` with different platforms →
  both values apply (merged); (e2) two root tags for `1.4.4` with different values for one platform
  → fails naming the root module, the version and the platform; (e3) root gives no value for the
  host key, `dep_a` and `dep_b` give the same correct one → succeeds with it; (f) `bun_version =
  "x"` → fails naming the module; (g) an unknown version `9.9.9` with integrity for the glibc keys
  only → a glibc build analyzes (its fetch is not attempted offline), and `bazel fetch` of the
  musl repository fails with the "pass the integrity" diagnostic naming the musl key. Run; record
  red for the cases that fail today
- [X] T051 [P] [US5] In `bun/tests/integration/lockfile_errors.test.ts`, add cases:
  `npm.translate_lock(name = "bad name", ...)` and `workspace_target_name = "a:b"` each fail
  naming the module, `translate_lock` and the value. Run `bazel test
  //bun/tests/integration:lockfile_errors_test`; record red

### Implementation for User Story 5

- [X] T052 [US5] In `bun/private/extensions.bzl`, iterate `module_ctx.modules` (root first,
  BZ-modctx); per tag validate `bun_version` with `version_key` (error names `<module
  name>@<version>` and the tag), each integrity key against `BUN_ARCHIVES` (error names module,
  key and `sorted(BUN_ARCHIVES)`), each value as `sha256-`, `sha384-` or `sha512-` followed by
  base64 (error names module and key, not the value's bytes beyond the prefix); collect per name,
  version and platform every value with its module; the root's value wins (two different root
  values fail naming the root module); with no root value, two different non-root values fail
  naming both modules, the version and the platform; merge values of several tags per platform;
  the highest version per name is selected as today
- [X] T053 [US5] Update the `integrity` attribute doc in `bun/private/extensions.bzl`: the seven
  keys, root precedence per platform, the conflict failure
- [X] T054 [US5] In `bun/private/npm_extension.bzl`, validate `translate_lock.name` as an apparent
  repository name (letters, digits, `_`, `-`, `.`, starting with a letter) and
  `workspace_target_name` as a target name (BZ-labels), each failing with `rules_bun: module
  <module>: npm.translate_lock: <attribute> "<value>" is not a valid <repository|target> name`
- [X] T055 [US5] Run `bazel test //bun/tests/integration:toolchain_tags_test
  //bun/tests/integration:lockfile_errors_test`; record green; run `(cd e2e/smoke && bazel test
  //...)`; commit as `fix: give the root module's toolchain integrity precedence`

**Checkpoint**: US5 holds.

---

## Phase 9: User Story 6 - npm's platform and file-name rules hold (Priority: P2)

**Goal**: `os`/`cpu` follow npm-install-checks `checkList`; any case of `BUILD`/`BUILD.bazel`
is renamed (FR-006, FR-017, research R5, R7).

**Independent Test**: `bazel test //bun/tests/npm:platforms //bun/tests/npm:libc
//bun/tests/npm/...` (quickstart Q3, Q9).

### Tests for User Story 6 (write first, see red)

- [X] T056 [P] [US6] In `bun/tests/npm/platforms_test.bzl`, add unit cases of
  `check_list(value, values)` loaded from `//bun/private:platforms.bzl`, each with npm-install-
  checks' result (research E3): `("linux", ["any"])` true; `("linux", ["linux"])` true;
  `("darwin", ["linux"])` false; `("linux", ["!linux"])` false; `("darwin", ["!linux"])` true;
  `("darwin", ["linux", "!win32"])` false; `("linux", [])` true; `("linux", ["any", "!linux"])`
  false; `("darwin", ["any", "!linux"])` false; `(None, ["linux"])` false; `(None, ["!linux"])`
  true; `(None, ["any"])` true. Run `bazel test //bun/tests/npm:platforms`; record red
- [X] T057 [US6] Add fixture package `bun/tests/npm/registry/packages/any-platform@1.0.0/`
  with `"os": ["any"]` and `"cpu": ["any"]`, pack it, add it to a new `write_lockfiles.ts` project
  `any_platform`, register hub `npm_any_platform` in `MODULE.bazel` (dev) and `use_repo`, and add a
  `platforms_test.bzl` case that the package is linked for `linux_x64`, `darwin_aarch64` and
  `windows_x64`. Record red
- [X] T058 [P] [US6] Add to `bun/tests/npm/registry/packages/build-files@1.0.0/` the files
  `lower/build`, `lower/build.bazel`, `mixed/Build`, `mixed/Build.bazel` (each a one-line
  JavaScript module exporting its own path); re-pack with `pack.ts`; rewrite every lockfile that
  holds `build-files` with `write_lockfiles.ts`; in `bun/tests/npm/glob_test.bzl` (or the
  `build-files` case of `bun/tests/npm/layout_test.bzl`), assert the four files are in the
  package's tree under their original paths and that a program reading `lower/build` reads its
  content, and assert the rename itself, which fails on a case-sensitive Linux file system before
  the fix: each of the four files is stored under its safe name in the package repository and the
  repository's path map maps its original path to that safe name. On macOS and Windows a
  case-insensitive file system then also proves they stay in one Bazel package. Record red. If `bun/tests` has a test of the rename-collision diagnostic, add a
  `BUILD` + `build` case; otherwise record in `tdd-log.md` that the unchanged diagnostic covers it

### Implementation for User Story 6

- [X] T059 [US6] In `bun/private/platforms.bzl`, add `check_list(value, values)`, a transcription
  of npm-install-checks `checkList` (v9.0.0, `fcba600c2e4d`): a sole `any` → true; a `!v` equal to
  `value` → false; else true when a positive entry equals `value` or every entry is negated;
  `None` equals no entry. Cite the source in the docstring
- [X] T060 [US6] In `bun/private/npm_repositories.bzl`, replace `_matches` with `check_list` for
  `os` and `cpu`; keep `libc_matches` unchanged
- [X] T061 [US6] In `bun/private/npm_repositories.bzl` `_make_addressable`, rename a file when
  `name.lower()` is `build` or `build.bazel`, as `BUILD` is renamed today (directories are not
  renamed); update the `BUILD` sentence of `_NPM_DOC` in `bun/private/npm_extension.bzl`
  ("`BUILD` and `BUILD.bazel` in any case")
- [X] T062 [US6] Run `bazel test //bun/tests/npm/...`; record green; commit as `fix: follow npm's
  checkList and rename BUILD files in any case`

**Checkpoint**: US6 holds.

---

## Phase 10: User Story 8 - Linux and macOS builds do not fetch the Windows launcher (Priority: P3)

**Goal**: A private toolchain type constrained to Windows replaces the direct hermetic-launcher
toolchain requests, so nothing of hermetic-launcher is resolved or fetched for Linux and macOS
(FR-007, research R6, D2, data-model "Windows launcher toolchain").

**Independent Test**: `bazel test //bun/tests/integration:launcher_fetch_test` on Linux and macOS;
Windows CI keeps the `.exe` stub (quickstart Q8).

### Tests for User Story 8 (write first, see red)

- [X] T063 [US8] Create the workspace `bun/tests/integration/workspaces/launcher_fetch/` with one
  `bun_binary` and one `bun_test`, and `bun/tests/integration/launcher_fetch.test.ts` with target
  `launcher_fetch_test` in `bun/tests/integration/BUILD.bazel` (`target_compatible_with` not
  Windows, via `select` on `@platforms//os:windows` → `@platforms//:incompatible`): run the inner
  `bazel test //...` with an empty repository cache and assert the loopback registry log
  (`inner.log`, `bun/tests/integration/support/inner.ts`) holds no request whose path contains
  `runfiles-stub-` or `finalize-stub-`. Run; record red (research E4)
- [X] T064 [P] [US8] In `bun/tests/run_test.bzl`, make the `no_stub` cases expect a failure naming
  the hermetic-launcher toolchain type that did not resolve and the target platform under the new
  type; add a case for a Windows target with the rules_bun launcher toolchain whose `template` is
  `None`. Adjust `bun/tests/platforms/BUILD.bazel` `no_stub` if needed. Run `bazel test
  //bun/tests:all`; record the result (red where the message changes)

### Implementation for User Story 8

- [X] T065 [US8] Create `bun/private/windows_launcher.bzl` with the rule
  `windows_launcher_toolchain`: requests hermetic-launcher's template and finalizer toolchain types
  as optional (`config_common.toolchain_type(..., mandatory = False)`) and returns
  `platform_common.ToolchainInfo(template = <File or None>, finalizer = <File or None>)`
- [X] T066 [US8] Create `bun/private/windows_launcher/BUILD.bazel` with `toolchain_type(name =
  "toolchain_type", visibility = ["//visibility:public"])`, a `windows_launcher_toolchain` target
  and `toolchain(name = "windows_launcher", toolchain = ..., toolchain_type = ":toolchain_type",
  target_compatible_with = ["@platforms//os:windows"])`; add
  `register_toolchains("//bun/private/windows_launcher:all")` to `MODULE.bazel` (not
  `dev_dependency`)
- [X] T067 [US8] In `bun/private/run.bzl`, replace the hermetic-launcher toolchain requests of
  `bun_binary`, `bun_test` and `npm_bin` with `config_common.toolchain_type(
  "//bun/private/windows_launcher:toolchain_type", mandatory = False)`; on a Windows target, build
  the embedded arguments with hermetic-launcher's `launcher.args_from_entrypoint`,
  `append_runfile` and `append_embedded_arg`, and run the finalizer with `ctx.actions.run(
  executable = finalizer, inputs = [template], outputs = [stub], arguments = ["--template",
  template.path, "-o", stub.path, "--transform", <indices>, "--", <args>], toolchain =
  "//bun/private/windows_launcher:toolchain_type")`; a missing toolchain, template or finalizer
  fails analysis naming the hermetic-launcher type that did not resolve and the target platform
- [X] T068 [US8] Run `bazel run //:gazelle`, `bazel test //bun/tests:all
  //bun/tests/integration:launcher_fetch_test`; record green; run `bazel test //...` and
  `(cd e2e/smoke && bazel test //...)`; commit as `fix: resolve the Windows launcher only for
  Windows targets`. Windows behavior is verified by the PR's Windows jobs (T086)

**Checkpoint**: US8 holds on Linux; SC-007 covered.

---

## Phase 11: User Story 9 - Documentation and public API state only what is true (Priority: P3)

**Goal**: `bun/extensions.bzl` exports `bun` and `npm` only; docs state JSX's source, the
`node_modules` resolution scope, `replace_package` visibility and one consistent platform text with
CI runner labels (FR-019–FR-022, research R9).

**Independent Test**: quickstart Q10.

### Tests for User Story 9 (write first, see red)

- [ ] T069 [P] [US9] Add a resolution-scope case: a subpackage `bun/tests/npm/fixtures/basic/sub/`
  with a `bun_test` whose source imports a package from `//bun/tests/npm/fixtures/basic:node_modules/<pkg>`
  (passes), and a sibling package `bun/tests/npm/fixtures/scope_sibling/` with a `bun_binary`
  depending on the same `:node_modules/<pkg>` plus a `bun_test` that spawns it (data dependency)
  and asserts a non-zero exit and Bun's `Cannot find package` text. Record red if the failing case
  passes unexpectedly; otherwise record it as a characterization of today's behavior
- [ ] T069a [P] [US9] Add a Bazel-in-Bazel case (in `bun/tests/integration/toolchain_tags.test.ts`
  of T050, its own inner workspace) whose `MODULE.bazel` or a `.bzl` file loads `bun_toolchain`
  from `@rules_bun//bun:extensions.bzl`; assert evaluation fails with Bazel's error that the file
  does not contain `bun_toolchain`, and that loading `bun` and `npm` still works (FR-019,
  constitution II). Run it; record red (today the load succeeds)
- [ ] T070 [P] [US9] In `bun/tests/integration/replace.test.ts` and `workspaces/replace/`, add a
  case whose `replace_package` archive has no `exports_files(..., visibility =
  ["//visibility:public"])`; assert the build fails with Bazel's visibility error naming the
  archive label. Run `bazel test //bun/tests/integration:replace_test`; record the result

### Implementation for User Story 9

- [ ] T071 [US9] In `bun/extensions.bzl`, remove the `bun_toolchain` export and keep `bun` and
  `npm` (the tag class stays in `bun/private/extensions.bzl`); `grep -rn bun_toolchain bun e2e`
  shows no public use. No migration message: no version is published (FR-019)
- [ ] T072 [US9] In `bun/private/run.bzl` `_FILES_DOC`, replace "rules_bun does not provide react"
  with "JSX needs the `react` package; a consumer gets it from its `bun.lock` through the `npm`
  extension (`:node_modules/react` in `deps`)"
- [ ] T073 [US9] In `bun/private/npm_extension.bzl` `_NPM_DOC`, state: `:node_modules/<package>`
  resolves only for files in and below the package that calls `npm_link_all_packages` (as rules_js
  documents); a `replace_package` archive must be visible to the generated repository
  (`exports_files([...], visibility = ["//visibility:public"])`)
- [ ] T074 [US9] Write the platform statement once in `bun/private/run.bzl` naming CI's runner
  labels and jobs from `.github/workflows/ci.yaml`: root and `e2e/smoke` suites on
  `ubuntu-latest`, `macos-latest`, `windows-latest` (job `test`); `--noenable_runfiles` without a
  sandbox and coverage on `ubuntu-latest` (`manifest-only`, `coverage`); Windows without Bash, with
  symbolic links and with an output root holding a space on `windows-latest`; `network-denied`,
  `windows-disk-cache` and `mod-compare` as `ci.yaml` defines them; musl resolved and
  integrity-verified, not run. Remove image names (`ubuntu-24.04`, `macos-26-arm64`,
  `windows-2025-vs2026`) and "Linux (WSL) only"; make `bun/defs.bzl` and `_NPM_DOC` in
  `bun/private/npm_extension.bzl` reference it and say only what differs. Re-read `ci.yaml` first;
  if a job or label differs from this list, follow `ci.yaml`
- [ ] T075 [US9] Run `bazel test //bun/tests/npm:all //bun/tests/integration:replace_test
  //bun/tests/integration:toolchain_tags_test` (T069a's case green), `(cd e2e/smoke && bazel test //...)`;
  record green; commit as `docs: state only tested facts and export bun and npm only`

**Checkpoint**: all stories hold.

---

## Phase 12: Polish & Cross-Cutting Concerns

**Purpose**: Audits, gates, CI, delivery.

- [ ] T076 Re-run the audits A1–A7 of research Part 3 against the changed code; for any place
  whose result changed or that the implementation found, update its row in
  `specs/005-review-defect-fixes/research.md` (SC-009); a new defect found is fixed test-first
  under the same principle, or stopped and reported if it widens the scope
- [ ] T077 [P] Update research Part 4 (Bun behaviors) so C17 and C18 rows name their test files;
  confirm every Bun flag or behavior used in `bun/private/launcher.js` and `launcher.sh.tpl` has a
  row (FR-009, FR-011)
- [ ] T078 [P] Confirm FR-024: `git diff main -- bun/*.bzl bun/toolchain bun/platforms` adds no
  public symbol, rule, attribute or target besides the two musl platform values; confirm
  `contracts/public-api.md` matches what changed
- [ ] T079 [P] Measure no regression of feature 003 SC-010: `bazel test
  //bun/tests/integration:scale_test` passes (2,000-package evaluation under 1 s)
- [ ] T080 Root gate: `bazel run //:gazelle` (commit any change)
- [ ] T081 Root gate: `prek run --all-files`
- [ ] T082 Root gate: `bazel test //...`
- [ ] T083 Root gate: `bazel test //... --noenable_runfiles --spawn_strategy=local
  --nocache_test_results`
- [ ] T084 `e2e/smoke` gate: `(cd e2e/smoke && bazel test //...)`
- [ ] T085 Review `tdd-log.md`: every test task of Phases 3–11 has a red (or a stated
  characterization) and a green row (FR-023, SC-002). Report any gate failure to the user with
  its output; do not widen the task (AGENTS.md)
- [ ] T086 Push `005-review-defect-fixes`, open one PR against `main` whose body lists the
  principles P1–P7, each reviewed defect (1)–(12) with its test, decisions D1–D3, the bin
  `manual` change for release notes (constitution VII), and "musl not run on a musl system"; watch
  `gh pr checks --watch` until every job passes on `ubuntu-latest`, `macos-latest`,
  `windows-latest`. Report a failing job with its log
- [ ] T087 From the PR's run: settle D3 (if C1 failed on Windows because no link can be made,
  give `c1_preserve_symlinks_test` in `bun/tests/canary/BUILD.bazel` `target_compatible_with =
  select({"@platforms//os:windows": ["@platforms//:incompatible"], "//conditions:default": []})`
  and record C1 as unasserted on Windows in research Part 4); check every platform statement of
  T074 against the jobs that ran; commit and push any change and re-watch CI (quickstart Q12)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none. T002 blocks T041 (D1), T063–T068 (D2), T087 (D3).
- **Foundational (Phase 2)**: after T001; blocks US4 (Phase 5) and US6 (Phase 9) and US5's key
  validation (T052 loads `BUN_ARCHIVES`).
- **US3 (Phase 3)**: after Setup; independent of Phase 2. Runs before US2 because R2's check must
  run before every diagnostic that prints a URL, including R1's `source` value.
- **US2 (Phase 4)**: after US3 (shares `npm_extension.bzl`; its failure text prints sources).
- **US4 (Phase 5)**: after Phase 2.
- **US1 (Phase 6)**: after US2 (both edit `providers.bzl`, `npm_package.bzl`, `run.bzl`,
  `npm_extension.bzl`); T034 (C18) can start any time.
- **US7 (Phase 7)**: independent; T045 and T046 can start any time after Setup.
- **US5 (Phase 8)**: after Phase 2 and US4 (the seven keys); T051 after US3 (shares
  `npm_extension.bzl`).
- **US6 (Phase 9)**: after Phase 2 and US1 (both edit `npm_repositories.bzl`; R4 reads renamed
  files through their safe name).
- **US8 (Phase 10)**: after US1 (both edit `run.bzl`).
- **US9 (Phase 11)**: after every other story (it rewrites the docs they touched).
- **Polish (Phase 12)**: after all stories.

### Within Each User Story

- Tests first, red recorded, then implementation, then green recorded, then commit.
- Providers before rules that return them; repository rules before the hub that uses them.

### Parallel Opportunities

- Setup: T003, T004, T005.
- US3: T010 and T011.
- US4: T025, T026, T032.
- US1: T034 and T035 (then T036, T037).
- US7: T045 alongside any other phase (new file); T046 alongside any phase that does not edit the
  canary BUILD file at the same moment.
- US5: T051 alongside T049–T050.
- US6: T056 and T058 (T057 edits `platforms_test.bzl` after T056).
- US9: T069, T070.
- Polish: T077, T078, T079.

---

## Parallel Example: User Story 1

```text
Task: "T034 [US1] Create bun/tests/canary/c18_extensionless_bin.test.ts and its bun_test target"
Task: "T035 [US1] Add fixture package node-bin@1.0.0, pack it, write the bins_node lockfile"
# then, sequentially:
Task: "T036 [US1] Analysis tests in bun/tests/npm/bins_test.bzl"
Task: "T037 [US1] Bazel-in-Bazel cases in bun/tests/integration/bins.test.ts"
```

## Parallel Example: User Story 6

```text
Task: "T056 [US6] check_list unit cases in bun/tests/npm/platforms_test.bzl"
Task: "T058 [US6] build-files case variants, re-pack, glob/layout assertions"
```

---

## Implementation Strategy

### MVP First (User Story 3)

1. Phase 1 Setup (including the D1–D3 gate).
2. Phase 3 US3: credentials rejected and never printed, the security defect.
3. Stop and validate with quickstart Q1.

### Incremental Delivery

1. Setup + Foundational → table in place, nothing changed.
2. US3 → US2 → US4 → US1 (all P1), one commit each, each validated by its quickstart row.
3. US7 → US5 → US6 (P2).
4. US8 → US9 (P3).
5. Polish: audits, gates, one PR, CI on all three runners, D3 settled.

### Notes

- [P] tasks touch different files and depend on nothing incomplete.
- Every commit leaves `bazel test //...` green.
- Stop at any checkpoint to validate the story on its own.
