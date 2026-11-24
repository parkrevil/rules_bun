---

description: "Task list for feature 007: close feature 006's follow-ups"
---

# Tasks: Close Feature 006's Follow-ups

**Input**: Design documents from `specs/007-close-006-followups/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/public-api.md,
quickstart.md

**Tests**: required. The input asks for each form to be "shown failing first" and for US3 to be
fixed "test first"; spec FR-009, FR-014 and the plan's constraint (`tdd-log.md`: every corpus
project red before the change, the reproduction red before the fix). New Starlark functions have
their unit tests written and seen failing first.

**Organization**: Phase 2 writes the 15 corpus projects of research R7 (16 planned; research Part 6 D2) and runs them red on
`main`'s comparison before any `bun/private/` change (research R7 "Test-first order"). Then US1
(overrides and resolutions), US2 (catalogs), US3 (Windows test output), and Polish. Paths are
relative to the repository root.

**Conventions used in every task**:

- Work and commit on branch `007-close-006-followups` (from `main` at `1bff1cf`). One PR at the end
  (T052). Pushing and opening or updating the PR need the user's approval each time (T040, T052).
- `B` is the development toolchain's Bun:
  `B="$(bazel info output_base)/external/+bun+bun_linux-x64/bun"`; `B142` is Bun 1.4.2:
  `B142="$(bazel info output_base)/external/+bun+bun_1_4_2_linux-x64/bun"`.
- `SRC` is `/tmp/bun007-src/bun-v1.4.4/`, `SRC142` is `/tmp/bun007-src/bun-v1.4.2/` (T002): Bun's
  source at the tag, read only, never built or run.
- "Cite" means: the function's docstring holds the line
  `Bun: <path under oven-sh/bun> L<a>–L<b> @ bun-v1.4.4` (for example
  `Bun: src/install/lockfile/override_selector.rs L54–L68 @ bun-v1.4.4`), one per Bun range it
  carries over, each range re-read in `SRC` before it is written. The line ranges in these tasks are
  research Part 1/R1/R2's; where `SRC` shows other bounds, cite `SRC`'s and note it in research
  Part 5.
- "Carry over" means: the Starlark function has the structure of the cited Bun function (same
  steps, same order, same names where Starlark allows), as feature 006 did. Nothing is fitted to a
  fixture's output (P1). Starlark has no `while` and no recursion: a Bun loop is a `for` over
  `range(_LIMIT)` (`_LIMIT = 1 << 30`) that ends without an error when exhausted.
- A rule Bun skips "with a warning" is skipped silently: no error, no print (spec FR-001).
- "Record red" / "record green" means: append to `specs/007-close-006-followups/tdd-log.md` one
  row with the task ID, the test target, the exact command, the platform it ran on, the result and
  a short excerpt of the failure text (red) or the pass line (green). A red that fails for a reason
  other than the one under test (a typo, a missing load) does not count: fix the test and re-run.
- Fixture lockfiles are produced only by `bun/tests/npm/registry/write_lockfiles.ts`, run with `$B`
  (or `$B142` with `--bun-1-4-2`) from the repository root. Never edit a Bun-written `bun.lock` by
  hand.
- Downloads go into a new, empty directory under `/tmp/bun007-*`, never next to a script.
- "Stop and report" means: change nothing more for that item and tell the user what was observed.
- A conformance difference no BC of the spec explains, or a lockfile Bun writes otherwise than
  research R2's "Lockfile writes" column says, is a new finding: stop and report; after the user
  approves it, add it to spec "Behavior Changes" and `contracts/public-api.md` as the next `BC-n`
  (or correct research R2) before anything fixes it (spec FR-012).
- Every diagnostic, `doc =` string, docstring, comment and commit message is in English. Errors
  `compare_manifests` returns start with the file name; `npm_extension.bzl` L331–L333 prefixes
  `rules_bun: `. The remedy text is exactly ``run `bun install` and commit bun.lock``, except for a non-object
  `overrides` or `resolutions`, which Bun refuses to install: research R6 gives that wording.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US3)

---

## Phase 1: Setup

**Purpose**: Branch, Bun's source at the tags, the TDD log, a green baseline.

- [X] T001 Confirm `git branch --show-current` prints `007-close-006-followups`,
  `git merge-base HEAD main` is `1bff1cf`, and `git status --short` shows only
  `specs/007-close-006-followups/`; commit that directory as
  `docs: specify feature 007, close feature 006's follow-ups`
- [X] T002 Fetch, into the new empty directories `/tmp/bun007-src/bun-v1.4.4/` and
  `/tmp/bun007-src/bun-v1.4.2/`, from `https://raw.githubusercontent.com/oven-sh/bun/<tag>/`, the
  files `src/install/lockfile/OverrideMap.rs`, `src/install/lockfile/override_selector.rs`,
  `src/install/lockfile/bun.lock.rs`, `src/install/lockfile/Package.rs`,
  `src/install/lockfile/CatalogMap.rs`, `src/install/dependency.rs` and
  `src/install_types/resolver_hooks.rs`, keeping their paths; check `wc -l` gives 1,452 lines for
  `SRC/src/install/lockfile/OverrideMap.rs` and 165 for `override_selector.rs` (research Part 1),
  else stop and report
- [X] T003 Create `specs/007-close-006-followups/tdd-log.md`: title `# TDD Log: Feature 007`, one
  paragraph stating the rule (every corpus project red on `main`'s comparison before the change,
  every new function's unit test red before the function, the US3 reproduction red before the fix;
  a red for another reason does not count), and the table header
  `| Task | Target | Command | Platform | Result | Excerpt |`
- [X] T004 Baseline on `main`'s code: run `bazel test //...` in the root and in `e2e/smoke/`,
  `bazel test //bun/tests/integration:scale_test --test_output=all` (note the extension evaluation
  time it prints), and save `bazel mod show_extension @rules_bun//bun:extensions.bzl%npm` to
  `/tmp/bun007-show_extension-main.txt`; record each as a green row in
  `specs/007-close-006-followups/tdd-log.md`. A failure: stop and report

---

## Phase 2: Foundational — the corpus, red on `main`'s comparison

**Purpose**: research R7's 15 corpus projects, written by the pinned Bun (and Bun 1.4.2), each
seen failing the conformance test on `main`'s comparison (FR-009, FR-010, SC-001, quickstart V1,
V2). Each project's `check` asserts what Bun wrote, research R2's "Lockfile writes" column; each
project whose written `overrides` holds a scoped rule (a parent or a target range) also asserts
`lock.lockfileVersion === 3` (spec Edge Cases). All five definition tasks edit one file, so they
run in order.

**⚠️ CRITICAL**: `git diff main -- bun/private` MUST be empty until T014 is recorded.

- [X] T005 Add to `PROJECTS` in `bun/tests/npm/registry/write_lockfiles.ts`, after
  `conformance_override_root_ref`, under a comment `// Feature 007, research R7: forms Bun skips with
  a warning (BC-1).`, three projects, each with `dependencies: { a: "1.0.0", q: "1.0.0" }` and
  `check` asserting `lock.overrides === undefined` (no rule written) and that `a`'s `b` and the
  root's `q` stay at 1.0.0 (`slot0(lock, "b") === "b@1.0.0"`, `slot0(lock, "q") === "q@1.0.0"`):
  `conformance_override_ignored_values` with
  `overrides: { b: 2, q: true, x: null, y: ["2.0.0"], z: "", c: "-" }` (OverrideMap.rs L867–L880,
  L1257–L1275); `conformance_override_child_values` with
  `overrides: { a: { b: 2, q: true, x: null, y: ["2.0.0"], z: "", c: "-" } }` (L906–L916,
  L1257–L1275); `conformance_resolution_ignored_values` with the same object as
  `conformance_override_ignored_values` under `resolutions` (L982–L992, L1257–L1275). If Bun writes
  an `overrides` key holding `{}` instead of none, assert that instead and note it in research R2
- [X] T006 Add to `bun/tests/npm/registry/write_lockfiles.ts`, each with
  `dependencies: { a: "1.0.0" }`: `conformance_override_skipped_keys` with
  `overrides: { "": "2.0.0", "@s": "2.0.0", "b@": "2.0.0", "a>b>c": "2.0.0", "a//b": "2.0.0",
  "a/**": "2.0.0", "a/b/c": "2.0.0", q: "patch:q@1.0.0#patches/q.patch" }` and `dependencies` also
  holding `q: "1.0.0"`, check: no `overrides` written, `b` and `q` at 1.0.0 (L853–L860,
  L1152–L1190, L1031–L1042; override_selector.rs L48–L50, L90–L92, L108–L165);
  `conformance_resolution_skipped_keys` with the same object under `resolutions`, the same
  `dependencies` and the same check (L969–L976, L1152–L1190, L1031–L1042);
  `conformance_override_comments` with
  `overrides: { "//": "top comment", "// note": "x", a: { "//": "child comment", b: "2.0.0" } }`,
  check: `JSON.stringify(lock.overrides) === '{"a":{"b":"2.0.0"}}'` and `a`'s `b` is b@2.0.0
  (L206–L209, L862–L864, L894–L896); (`conformance_resolution_comments` was removed in T012: `main` passes it, research Part 6 D2)
- [X] T007 Add to `bun/tests/npm/registry/write_lockfiles.ts`, each with
  `dependencies: { a: "1.0.0" }`: `conformance_override_dot_only` with
  `overrides: { b: { ".": "2.0.0" } }`, check `'{"b":"2.0.0"}'` (L918–L927, `is_flat` L1045);
  `conformance_override_flat_and_scoped` with `overrides: { a: "1.0.0", "a>b": "2.0.0" }`, check
  `'{"a":{".":"1.0.0","b":"2.0.0"}}'` (BC-8, bun.lock.rs L1311–L1458);
  `conformance_override_target_range` with `overrides: { "b@^1.0.0": "2.0.0" }`, check
  `'{"b@^1.0.0":{".":"2.0.0"}}'` (BC-3, L1044–L1068); each also asserts `a`'s `b` is b@2.0.0
- [X] T008 Add to `bun/tests/npm/registry/write_lockfiles.ts`: `conformance_resolution_globs` with
  `dependencies: { a: "1.0.0", q: "1.0.0" }`, `resolutions: { "**/q": "2.0.0", "a/**/b": "2.0.0" }`,
  check: `lock.overrides` deep-equals `{ q: "2.0.0", a: { b: "2.0.0" } }` (BC-5, override_selector.rs
  L108–L165); `conformance_override_selectors` with
  `dependencies: { a: "1.0.0", q: "1.0.0", "p-user": "1.0.0" }`,
  `overrides: { "a/b": "2.0.0", "q@>=1.0.0": "2.0.0", "q@npm:^1.0.0": "2.0.0", "p-user > p": "1.0.0", "p-user> p": "1.0.0" }`,
  check: deep-equals `{ a: { b: "2.0.0" }, "q@>=1.0.0": { ".": "2.0.0" }, "q@^1.0.0": { ".": "2.0.0" }, "p-user > p": "1.0.0", "p-user": { p: "1.0.0" } }`
  (research Part 6 D1)
  (BC-7, override_selector.rs L41–L47, L54–L98); `conformance_resolution_pnpm` with
  `dependencies: { a: "1.0.0" }`, `resolutions: { "a>b": "2.0.0" }`, check deep-equals
  `{ a: { b: "2.0.0" } }` (BC-7). Compare with deep equality (key order of Bun's writer is not
  asserted)
- [X] T009 Add to `bun/tests/npm/registry/write_lockfiles.ts`, under a comment naming FR-007 and
  Package.rs L3418–L3440: `conformance_catalog_top_and_nested` with
  `workspaces: { packages: [], catalog: { b: "2.0.0" } }`, top-level
  `catalog: { b: "1.0.0", q: "2.0.0" }` and `catalogs: { g: { q: "1.0.0" } }`,
  `dependencies: { b: "catalog:" }`, check: `lock.catalog` deep-equals `{ b: "2.0.0" }`,
  `lock.catalogs === undefined`, `b` is b@2.0.0 (US2-1); `conformance_catalog_no_workspaces` with
  top-level `catalog: { b: "2.0.0" }`, `dependencies: { a: "1.0.0" }`, no `workspaces`, check:
  `lock.catalog === undefined` and `a`'s `b` is b@1.0.0 (US2-2); `conformance_catalog_non_string`
  with `workspaces: { packages: [], catalog: { b: "2.0.0", q: 1 } }`,
  `dependencies: { b: "catalog:" }`, check: `lock.catalog` deep-equals `{ b: "2.0.0" }` (BC-6,
  CatalogMap.rs L356–L358)
- [X] T010 Write the 15 projects: `$B bun/tests/npm/registry/write_lockfiles.ts` followed by the 15
  project names of T005–T009; every `check` must pass. A `check` that fails, or a `bun install` that
  refuses a project, is a finding (stop and report; research R2 or R7 is then wrong). Then
  `bazel run //:gazelle`, and confirm each `bun/tests/npm/fixtures/conformance_<name>/` holds
  `BUILD.bazel`, `package.json`, `bun.lock`
- [X] T011 Write the 1.4.2 lockfiles: `$B142 bun/tests/npm/registry/write_lockfiles.ts --bun-1-4-2`
  followed by the 15 project names. Each project Bun 1.4.2 writes and installs lands in
  `bun/tests/npm/conformance/bun_1_4_2/<name>/`; for each it cannot, add an entry to
  `NOT_APPLICABLE_1_4_2` in `bun/tests/npm/conformance/not_applicable_1_4_2.ts` quoting the error
  Bun 1.4.2 printed and the line of `SRC142` it comes from, in the style of the existing entries
  (FR-010)
- [X] T012 Red: with `git diff main -- bun/private` empty, run
  `bazel test //bun/tests/npm/conformance:conformance_test --test_output=errors`. Expected: FAIL
  with exactly one difference per new project, each `<project>: the ruleset fails (…), Bun installs
  the lockfile`, and none on any other project. Record one red row per project in
  `specs/007-close-006-followups/tdd-log.md` with the error excerpt. A new project that passes:
  stop and report. Note in each multi-form project's row (`conformance_override_ignored_values`,
  `_child_values`, `conformance_resolution_ignored_values`, `conformance_override_skipped_keys`,
  `conformance_resolution_skipped_keys`, `conformance_override_selectors`, `conformance_resolution_globs`) which form `main`'s error names;
  the forms it hides get their own red in T017
- [X] T013 Red, Bun 1.4.2: run `bazel test //bun/tests/npm/conformance:conformance_1_4_2_test
  --platforms=//bun/tests/npm/conformance:host_bun_1_4_2
  --extra_execution_platforms=//bun/tests/npm/conformance:host_bun_1_4_2 --test_output=errors`;
  expected: the same differences for the projects T011 wrote, and every not-applicable one listed
  as such; record. A "Bun 1.4.2 links this lockfile differently from Bun 1.4.4" failure is feature
  006's stop condition: stop and report
- [X] T014 Commit `bun/tests/npm/registry/write_lockfiles.ts`, `bun/tests/npm/fixtures/conformance_*`
  (the 15 new), `bun/tests/npm/conformance/bun_1_4_2/`, `not_applicable_1_4_2.ts` and
  `tdd-log.md` as `test: add feature 007's corpus projects, red on main's comparison`

**Checkpoint**: every form of BC-1…BC-8 is a red row on `main`'s comparison.

---

## Phase 3: User Story 1 — Overrides and resolutions the pinned Bun installs pass evaluation (Priority: P1) 🎯 MVP

**Goal**: the root `package.json`'s `overrides`/`resolutions` are parsed into rules as the pinned
Bun parses them and compared with the lockfile's rules by `OverrideMap::changed` (research R1–R3,
R5, R6); `overrides.bzl` is removed.

**Independent Test**: the conformance test reports 0 differences on the 12 US1 projects of T005–T008
(quickstart V3); `//bun/tests/npm:compare` fails every stale variant with the remedy (V4);
`//bun/tests/npm:bun_override_map` passes; C-OVERRIDES passes and fails in red mode (V5).

### Tests for User Story 1 (write first, see them fail) ⚠️

- [X] T015 [US1] Create `bun/private/bun_override_map.bzl` with a module docstring (the carry-over
  of `override_selector.rs` and both sides of `OverrideMap.rs`, research R1, R5) and stubs that
  return `None` (not `fail()`, which in a skylib `unittest` aborts analysis instead of failing the
  test) for `parse_selector(key)` and
  `override_map_parse_append(manifest, file, members)` and `override_map_changed(declared, recorded)`,
  each docstring already citing its Bun lines (T019, T021, T022); add its `bzl_library` with
  `bazel run //:gazelle` in `bun/private/BUILD.bazel`
- [X] T016 [P] [US1] Write `bun/tests/npm/bun_override_map_test.bzl` with
  `bun_override_map_test_suite(name)` and register `bun_override_map_test_suite(name = "bun_override_map")`
  in `bun/tests/npm/BUILD.bazel`. Cases, each expectation read from `SRC` before it is written:
  (a) `parse_selector` → `struct(parent, target)` of `struct(name, range)` or an error kind of
  `SELECTOR_ERROR` (override_selector.rs L17–L23) for `"b"`, `"@s/b"`, `"b@^1.0.0"`,
  `"b@npm:^1.0.0"` (range `^1.0.0`), `"a>b"`, `"a > b"` (the flat target `"a > b"`, research Part 6 D1), `"a> b"`, `"a@^1.0.0>b"`, `"q@>=1.0.0"` (no
  delimiter), `"a@>=1>b"`, `"a/b"`, `"**/b"`, `"a/**/b"`, `"**/a/**/b"`, `"@s/a/b"`, and the errors
  `""`, `"@s"`, `"b@"`, `"a>b>c"`, `"a/b/c"`, `"a//b"`, `"a/**"`; (b) `override_map_parse_append`
  on one manifest per row of research R2's table, asserting the resulting `map` (name → value
  literal) and `scoped` (parent name and range literal, target name, target range literal, value
  literal), including `overrides` winning over `resolutions`, a later rule replacing an earlier
  one with the same selector, and a non-object `overrides` or `resolutions` returning an error that
  names the file and the field; (c) every case of `bun/tests/npm/overrides_test.bzl` (its `$<name>`
  references to the root, to members, to nothing, to disagreeing members, and its fixture
  projects), rewritten to rules; (d) `override_map_changed`: equal maps built in different orders
  → `None`; a different count of flat or scoped rules, and an equal count with one differing
  literal → the first differing pair in `sort` order. Run
  `bazel test //bun/tests/npm:bun_override_map --test_output=errors`: red (the stubs); record red
- [X] T017 [US1] In `bun/tests/npm/compare_test.bzl` add `override_forms_test`: one inline case per
  form below, each a root `package.json` with `dependencies: {"a": "1.0.0", "q": "1.0.0"}` and a
  lockfile built like `_plain_lock` whose root workspace holds the same dependencies and whose
  `overrides` is the given one (none = no key), expecting `compare_manifests(...).error == None`:
  `{"overrides": {"b": 2}}`, `{"b": true}`, `{"b": None}`, `{"b": ["2.0.0"]}`,
  `{"a": {"b": 2}}` (each → none); the same non-string under `resolutions` (→ none);
  `""` and `"-"` values in both fields at both levels (→ none); `{"": "2.0.0"}` in both fields
  (→ none); `{"q": "patch:q@1.0.0#patches/q.patch"}` (→ none); keys `"@s"`, `"b@"`, `"a//b"`,
  `"a/**"`, `"a>b>c"`, `"a/b/c"`, each in both fields (→ none); `{"//": "x", "// y": "z", "a": {"//": "x", "b": "2.0.0"}}`
  (→ `{"a": {"b": "2.0.0"}}`); `{"b": {".": "2.0.0"}}` (→ `{"b": "2.0.0"}`);
  `{"b@^1.0.0": "2.0.0"}` (→ `{"b@^1.0.0": {".": "2.0.0"}}`); `resolutions`
  `{"**/q": "2.0.0"}` (→ `{"q": "2.0.0"}`) and `{"a/**/b": "2.0.0"}` (→ `{"a": {"b": "2.0.0"}}`);
  `overrides` `{"a/b": "2.0.0"}` (→ `{"a": {"b": "2.0.0"}}`) and `{"**/b": "2.0.0"}`
  (→ `{"b": "2.0.0"}`); `resolutions` `{"a>b": "2.0.0"}` (→ `{"a": {"b": "2.0.0"}}`);
  `{"a > b": "2.0.0"}` (→ `{"a > b": "2.0.0"}`, research Part 6 D1); `{"a> b": "2.0.0"}` (→ `{"a": {"b": "2.0.0"}}`); `{"q@>=1.0.0": "2.0.0"}`
  (→ `{"q@>=1.0.0": {".": "2.0.0"}}`); `{"a@>=1>b": "2.0.0"}` (→ `{"a@>=1": {"b": "2.0.0"}}`);
  `{"q@npm:^1.0.0": "2.0.0"}` (→ `{"q@^1.0.0": {".": "2.0.0"}}`);
  `{"a": "1.0.0", "a>b": "2.0.0"}` (→ `{"a": {".": "1.0.0", "b": "2.0.0"}}`); and, passing on
  `main` too, `{"a": {".": "1.0.0", "b": "2.0.0"}}`, `{"q@^1.0.0": {".": "2.0.0"}}` and
  `resolutions` `{"**/a/**/b": "2.0.0"}` (→ `{"a": {"b": "2.0.0"}}`) and `{"//": "x", "// y": "z", "b": "2.0.0"}` (→ `{"b": "2.0.0"}`, research Part 6 D2). Add the 12 US1 corpus
  projects to `_equal_test_impl`'s list. Run `bazel test //bun/tests/npm:compare --test_output=errors`
  on `main`'s comparison: red, one failure per form except the three marked; record one red row per
  form (this is each form's own red, T012)
- [X] T018 [US1] In `bun/tests/npm/compare_test.bzl` add `override_stale_test` (US1-7, SC-002,
  FR-006): for each of the 12 US1 corpus projects, an `edit` that changes one rule Bun applies
  (`"2.0.0"` → `"1.0.0"` for a project that has one; for a project whose rules Bun all skips, a
  new rule `"b": "2.0.0"` added to the field it uses), expecting an error that contains
  `./package.json`, the field, the rule as `[<parent>[@<range>]>]<target>[@<range>]` and
  ``run `bun install` and commit bun.lock``; plus `"overrides": "x"` and `"resolutions": []`,
  expecting research R6's error, which names the file and the field. Run
  `bazel test //bun/tests/npm:compare --test_output=errors`; the rule-naming assertions are red on
  `main` (its messages differ); record

### Implementation for User Story 1

- [X] T019 [US1] Carry over `override_selector.rs` into `bun/private/bun_override_map.bzl`:
  `SELECTOR_ERROR` (L17–L23); `parse_package_segment` (L25–L52: `is_bare_scope` L25–L27, inlined, and the function L29–L52), moved from `bun_lockfile.bzl`'s
  `_parse_package_segment` (L222–L241) with its body and re-cited; `parse_selector` (L54–L68);
  `_pnpm_delimiter` (L72–L82, a `>` after ` `, `|`, `@` or `:` is no delimiter); the pnpm split
  with trimmed segments (L84–L98); `_parse_yarn_path` (L108–L165, `**` segments dropped, errors as
  L17–L23). Move `_dependency` (resolver_hooks.rs L517–L528) from `bun/private/bun_lockfile.bzl`
  to `bun/private/bun_install_types.bzl` as `new_dependency`, and update its callers;
  `bun_override_map.bzl` MUST NOT load `bun_lockfile.bzl` (which loads it). Run
  `bazel test //bun/tests/npm:bun_override_map --test_output=errors`: the `parse_selector` cases
  green; record
- [X] T020 [US1] Move to `bun/private/bun_override_map.bzl`: `_lockfile_range`, split into the two Bun
  functions it carries over, `_is_selector_range` (OverrideMap.rs L1081–L1087) and `lockfile_range`
  (L1089–L1115), each re-cited, and `_put_lockfile_rule` as `put_lockfile_rule` (L671–L737), with
  its scoped insertion split out as `push_scoped` (L644–L668) for T021 to share; `bun_lockfile.bzl`'s
  `_parse_overrides` loads `parse_package_segment` and `put_lockfile_rule`. Add to
  `bun/private/bun_lockfile.bzl` `lockfile_overrides(rows, file)`: a fresh
  `struct(map = {}, scoped = [], scoped_names = {})` filled by `_parse_overrides`, returned as
  `struct(value, error)` (cite bun.lock.rs L1934–L2035). Run `bazel test //bun/tests/npm/... --keep_going`:
  the same pass/fail set as before T020
  (a move: the targets red on purpose since T012 and T016–T018 stay red, every other stays green);
  record both lists
- [X] T021 [US1] Carry over the `package.json` side of `OverrideMap.rs` into
  `bun/private/bun_override_map.bzl`, following data-model.md "How one `package.json` entry becomes
  rules" step by step: `_is_comment_key` (L206–L209); `override_map_parse_append(manifest, file,
  members)` (`parse_append` L802–L838 with `Field::of` L166–L170, the refusal `not_an_object`
  L1140–L1150 as research R6's error `<file>: "<field>" expects a map of package names to versions, which Bun
  requires; make it an object`); `_parse_from_overrides` (L841–L955); `_parse_from_resolutions`
  (L959–L995); `_parse_string_rule` (L997–L1020); `_put_rule` (L1022–L1069, via `push_scoped`);
  `_is_selector_range` (from T020); `_parse_parent` (L1192–L1206); `_parse_range` (L1208–L1245);
  `_parse_override_value` (L1248–L1371, `dependency_parse` of `bun_install_types.bzl` for
  `Dependency::parse`), with `_reference`, `_root_declared` and `_declared` moved from
  `bun/private/overrides.bzl` with their citations (L1278–L1335, L1405–L1452; L1286–L1297;
  L1373–L1380). Returns `struct(value = struct(map, scoped, scoped_names), error)`, the struct
  `lockfile_overrides` returns. Run `bazel test //bun/tests/npm:bun_override_map
  --test_output=errors`: the parse cases green; record
- [X] T022 [US1] Carry over `sort` (L553–L579) as `_sort` and `changed` (L503–L551) as
  `override_map_changed(declared, recorded)` in `bun/private/bun_override_map.bzl`, with research
  R3's literal equality (parent name and range literal, target name and range literal, value
  literal). Where Bun returns only `true`, it returns the subject research R6 needs: the first
  unequal pair of the two sorted lists, or the first rule only one side holds, as
  `struct(rule, declared, recorded)` (`rule` the text `[<parent>[@<range>]>]<target>[@<range>]`,
  each value a literal or `None`); `None` when unchanged. Run
  `bazel test //bun/tests/npm:bun_override_map --test_output=errors`: all green; record
- [X] T023 [US1] In `bun/private/workspaces.bzl` `compare_manifests`, replace the
  `normalize_overrides` block (L346–L351) and the `overrides.bzl` load: parse the root with
  `override_map_parse_append(root.value, root.file, [member values])` (an error is returned as is),
  the lockfile's `overrides` with `lockfile_overrides(lockfile.overrides, <lockfile label>)` (add a
  `lock_file` parameter if `read_lockfile`'s value does not carry its label, and pass it from
  `bun/private/npm_extension.bzl` L331 and `bun/tests/npm/compare_test.bzl` `_compare`), and turn
  `override_map_changed`'s subject into the contract's messages:
  `<file>: <field> "<rule>" is <value>, but bun.lock records <value>; …`,
  `<file>: <field> "<rule>": <value> is not in bun.lock; …`,
  `<file>: bun.lock records <field> "<rule>": <value>, which the file does not declare; …`, with
  `<field>` the one `Field::of` picked. Run `bazel test //bun/tests/npm:compare --test_output=errors`:
  T017 and T018 green; record
- [X] T024 [US1] Delete `bun/private/overrides.bzl` and `bun/tests/npm/overrides_test.bzl`, the
  `bzl_library(name = "overrides")` and its `":overrides"` dependency in `bun/private/BUILD.bazel`,
  and `overrides_test_suite` in `bun/tests/npm/BUILD.bazel`; first list, in the commit message,
  each case of `overrides_test.bzl` and the case of `bun_override_map_test.bzl` that took it over
  (T016 c). Run `bazel run //:gazelle`; `rtk grep -rn "overrides.bzl\|normalize_overrides\|_FORMS"
  bun e2e` prints nothing
- [X] T025 [P] [US1] In `bun/tests/npm/conformance/citations.test.ts` add `"bun_override_map"` to
  `MODULES`; add `//bun/private:bun_override_map.bzl` to `citations_test`'s `data` in
  `bun/tests/npm/conformance/BUILD.bazel` and `bun_override_map.bzl` to `exports_files` in
  `bun/private/BUILD.bazel`. Run `bazel test //bun/tests/npm/conformance:citations_test
  --test_output=errors`: green, `bun_override_map` among the modules; record
- [X] T026 [P] [US1] Extend `CASES` in `bun/tests/canary/npm/c_overrides.test.ts` (research R8),
  each expected value the lockfile form research R2 gives: `"b@^1.0.0": "2.0.0"` →
  `{"b@^1.0.0": {".": "2.0.0"}}`; `{b: {".": "2.0.0"}}` → `{b: "2.0.0"}`;
  `{a: "1.0.0", "a>b": "2.0.0"}` → `{a: {".": "1.0.0", b: "2.0.0"}}`; `resolutions`
  `{"**/b": "2.0.0"}` → `{b: "2.0.0"}` and `{"a/**/b": "2.0.0"}` → `{a: {b: "2.0.0"}}`;
  `overrides` `{"a/b": "2.0.0"}`, `{"a> b": "2.0.0"}` → `{a: {b: "2.0.0"}}`; `{"a > b": "2.0.0"}` → `{"a > b": "2.0.0"}` (research Part 6 D1);
  `{"b@>=1.0.0": "2.0.0"}` → `{"b@>=1.0.0": {".": "2.0.0"}}`; `{"b@npm:^1.0.0": "2.0.0"}` →
  `{"b@^1.0.0": {".": "2.0.0"}}`; `resolutions` `{"a>b": "2.0.0"}` → `{a: {b: "2.0.0"}}`; and one
  case per skipped form (a non-string, `""`, `"-"`, an empty key, a `patch:` value, a `"//"` key,
  and the selector errors `"@s"`, `"b@"`, `"a//b"`, `"a/**"`, `"a>b>c"`, `"a/b/c"`), each in both
  `overrides` and `resolutions` at the top and, for the values and `"//"`, also under `a` in
  `overrides`, placed next to the applied rule `b: "2.0.0"`, → `{b: "2.0.0"}`. Compare with deep
  equality (`Bun.deepEquals`), not `JSON.stringify`: key order is not asserted (T008). Extend the red-mode regex so every new case's target `b` becomes
  `c`; set `READER` to `"override_map_parse_append and override_map_changed in
  bun/private/bun_override_map.bzl, and _parse_overrides in bun/private/bun_lockfile.bzl"` and
  rewrite the header comment (no `normalize_overrides`). Run
  `bazel test //bun/tests/canary/npm:c_overrides_test --test_output=errors` (green) and with
  `--test_env=RULES_BUN_CANARY_RED=1` (every case fails naming C-OVERRIDES); record both
- [X] T027 [US1] Green: `bazel test //bun/tests/npm/conformance:conformance_test
  --test_output=errors` and the 1.4.2 command of T013: the 12 US1 projects compared with 0
  differences (the 3 catalog projects still differ until US2); record green per project. A
  difference on any other project: stop and report
- [X] T028 [US1] Commit as `fix: compare package.json overrides with bun.lock as Bun 1.4.4 does
  (BC-1, BC-2, BC-3, BC-4, BC-5, BC-7, BC-8)`, with `tdd-log.md`

**Checkpoint**: US1 complete; every override and resolution form of the input passes evaluation,
and stale ones fail.

---

## Phase 4: User Story 2 — The catalogs compared are the ones Bun reads (Priority: P1)

**Goal**: the root's catalogs are read where Bun reads them (Package.rs L3418–L3440), only their
string entries, and both the catalog comparison and `catalog:` resolution use that reading
(FR-007, research R4).

**Independent Test**: the conformance test reports 0 differences on the 3 catalog projects of T009;
`//bun/tests/npm:compare` and `//bun/tests/npm:bun_package` pass (quickstart V3–V5).

### Tests for User Story 2 (write first, see them fail) ⚠️

- [X] T029 [P] [US2] Add a stub `root_catalogs(manifest, file)` that returns `None` (as T015's stubs) to
  `bun/private/bun_package.bzl` (docstring citing Package.rs L3418–L3440), and to
  `bun/tests/npm/bun_package_test.bzl` a `root_catalogs` test, each case asserting `default`
  (name → literal) and `groups` (group → name → literal): `workspaces` an object with `catalog`,
  next to a top-level `catalog` and `catalogs` → only the `workspaces` one; `workspaces` an object
  with only `catalogs` → only that; `workspaces` an object with neither → the top level's;
  `workspaces` an array with a top-level `catalog` → the top level's (US2-3); `"workspaces": null`
  → the top level's (research R4's Starlark note); no `workspaces` → none; a non-string entry →
  skipped (BC-6); `catalogs.default` → group `"default"`. Run
  `bazel test //bun/tests/npm:bun_package --test_output=errors`: red; record
- [X] T030 [US2] In `bun/tests/npm/compare_test.bzl`: add the 3 catalog corpus projects to
  `_equal_test_impl`'s list; add `catalog_where_test` with inline cases for US2-1, US2-2, US2-3 and
  BC-6 expecting no error, and one with no `workspaces`, a top-level `catalog: {"b": "2.0.0"}` and
  `dependencies: {"b": "catalog:"}` expecting an error containing `names no entry of the default
  catalog` (spec Edge Cases, BC-6; red on `main`, which reads that top-level catalog); add, for each catalog project, a stale variant (one catalog entry's
  value changed after the install) expecting an error with ``run `bun install` and commit
  bun.lock`` (`catalogs_test`, `catalog_missing_test` and `resolve_catalog_test` are rewritten in
  T033, with the code they test). Run `bazel test //bun/tests/npm:compare
  --test_output=errors` on `main`'s catalog code: red for US2-1, US2-2 and BC-6; record

### Implementation for User Story 2

- [X] T031 [US2] Create `bun/private/bun_catalog_map.bzl` (research R5), loading only
  `bun_install_types.bzl` and `bun_semver.bzl`, with `catalog_parse_append(catalogs, obj, file)`:
  `CatalogMap::parse_append` (CatalogMap.rs L285–L342) with `parse_append_group` (L344–L396),
  filling the `struct(default, groups)` `_parse_catalog` fills, skipping entries whose value is not
  a string (L356–L358), keeping the `catalog`/`catalogs.default` conflict (L310–L339) and
  "Duplicate catalog" (L382–L385) as errors, returning `struct(found_any, error)`. Move into
  it from `bun_lockfile.bzl`, with their bodies and citations: `_catalog_find` as `catalog_find`,
  `catalogs_resolve_range`, and `_strip_reference` as `catalog_strip_reference`; `bun_lockfile.bzl`
  and `bun_tree.bzl` load them from there, and `_parse_catalog` (bun.lock.rs) stays in
  `bun_lockfile.bzl`. Add its `bzl_library` with `bazel run //:gazelle`. Run
  `bazel test //bun/tests/npm/... --keep_going`: the same pass/fail set as before T031; record
- [X] T032 [US2] Replace the stub `root_catalogs(manifest, file)` in `bun/private/bun_package.bzl`
  with the carry-over of Package.rs L3418–L3440 (data-model.md "Which catalogs the root has";
  `"workspaces" in manifest`, not `!= None`), returning `struct(value = struct(default, groups),
  error)`; `bun_package.bzl` loads `catalog_parse_append` from `bun_catalog_map.bzl`, never
  `bun_lockfile.bzl`, so there is no load cycle (`bun_lockfile.bzl` → `bun_override_map.bzl` →
  `bun_package.bzl` → `bun_catalog_map.bzl`). Run
  `bazel test //bun/tests/npm:bun_package --test_output=errors`: green; record
- [X] T033 [US2] In `bun/private/workspaces.bzl`: `compare_manifests` reads the root's catalogs with
  `root_catalogs`, compares `default` with `lockfile.catalog` (what `catalog`) and each group with
  `lockfile.catalogs` (what `catalogs`) by literal through `_difference` on `{name: literal}` maps;
  `resolve_catalog(name, spec, catalogs)` looks the reference up with `catalog_find` (`bun_catalog_map.bzl`) and returns
  the entry's literal, its error text unchanged; delete `manifest_catalogs`. Rewrite
  `catalogs_test`, `catalog_missing_test` and `resolve_catalog_test` in
  `bun/tests/npm/compare_test.bzl` for the catalogs value `root_catalogs` returns, keeping each
  case's expectation. Run `bazel test //bun/tests/npm:compare --test_output=errors`: green; record
- [X] T034 [P] [US2] In `bun/tests/npm/conformance/citations.test.ts` add `"bun_package"` and
  `"bun_catalog_map"` to `MODULES`; add `//bun/private:bun_package.bzl` and
  `//bun/private:bun_catalog_map.bzl` to `citations_test`'s `data`, and both files to
  `exports_files` in `bun/private/BUILD.bazel`. Run the citations test:
  green; record
- [X] T035 [P] [US2] In `bun/tests/canary/npm/c_catalog.test.ts` (FR-011, research R8) set
  `READER` to name `root_catalogs in bun/private/bun_package.bzl, catalog_parse_append in
  bun/private/bun_catalog_map.bzl and _parse_catalog in bun/private/bun_lockfile.bzl` instead of
  `compare_manifests`, and add three tests, each asserting the `catalog` and `catalogs` Bun writes,
  each with a red mode (`red({ files })`) that makes Bun write otherwise: (a) a `workspaces` object
  with `catalog: { b: "2.0.0" }` next to a top-level `catalog: { b: "1.0.0", q: "2.0.0" }` and
  `catalogs: { g: { q: "1.0.0" } }`, `dependencies: { b: "catalog:" }` → `catalog`
  `{ b: "2.0.0" }`, no `catalogs` (red: the `workspaces` object's `catalog` key renamed, so Bun
  reads the top level); (b) a top-level `catalog: { b: "2.0.0" }`, no `workspaces`,
  `dependencies: { b: "1.0.0" }` → no `catalog` (red: `"workspaces": []` added, so Bun reads the
  top level); (c) a `workspaces` object with `catalog: { b: "2.0.0", q: 1 }`,
  `dependencies: { b: "catalog:" }` → `catalog` `{ b: "2.0.0" }` (red: `1` made `"1.0.0"`, so Bun
  writes `q`; it writes every catalog entry, bun.lock.rs L580–L610). Run `bazel test
  //bun/tests/canary/npm:c_catalog_test --test_output=errors` green and with
  `--test_env=RULES_BUN_CANARY_RED=1` (every test fails naming C-CATALOG); record both
- [X] T036 [US2] Green: the conformance test and the 1.4.2 command of T013: all 15 new projects
  compared with 0 differences, every other project as before; record green per catalog project.
  Commit as `fix: read the root's catalogs where Bun 1.4.4 reads them (BC-6)`, with `tdd-log.md`

**Checkpoint**: US1 and US2 complete; quickstart V1–V5 hold.

---

## Phase 5: User Story 3 — The source `node_modules` test is deterministic on Windows (Priority: P2)

**Goal**: reproduce research R10's cause (Bazel 9.2.0's Windows test wrapper drops a test's output
still in its pipe) with the ruleset's `bun_test`, red on Windows, then remove it by moving the
integration tests' dev-only inner Bazel to 9.4.0, or stop per FR-016 if 9.4.0 is not released.

**Independent Test**: `//bun/tests/integration:test_output_test` fails 30 of 30 runs on the Windows
`output-root-with-space` job with inner Bazel 9.2.0, and with 9.4.0 it and
`source_node_modules_test` pass 60 of 60 (quickstart V6, V7; SC-003).

### Tests for User Story 3 (write first, see them fail) ⚠️

- [X] T037 [P] [US3] Create the inner workspace `bun/tests/integration/workspaces/test_output/`:
  `MODULE.bazel` as `bun/tests/integration/workspaces/toolchain/MODULE.bazel`; `out.test.ts` that
  writes `process.env.SIZE` bytes (one `process.stdout.write` of a repeated line), then the line
  `process.env.MARKER`, then fails one `expect`; `BUILD.bazel` with 8 `bun_test` targets `out_1` …
  `out_8`, each `srcs = ["out.test.ts"]`, `env = {"MARKER": "rules_bun marker <i>", "SIZE":
  "524288"}`. No `bun.lock` and no `npm` extension (so `bun/tests/npm/fixture_results.bzl` does not
  read it)
- [X] T038 [US3] Write `bun/tests/integration/test_output.test.ts` (header comment: research R10,
  FR-014): `new Inner("test_output")`, `inner.run(["test", "//:all", "--test_output=errors"])`,
  expect a non-zero exit code and that `stdout + stderr` contains each of the 8 markers (print the
  missing ones), `assertOffline(inner.log)`, timeout `INNER_TIMEOUT`; add `test_output_test` to
  `bun/tests/integration/BUILD.bazel` with `size = "enormous"`, `tags = ["requires-network"]`,
  `deps = [":inner", "//bun/tests/support:spawn"]`, as `source_node_modules_test`. Run
  `bazel test //bun/tests/integration:test_output_test --test_output=errors` on Linux: green (the
  race is in the Windows wrapper only); record
- [X] T039 [US3] Add to the `output-root-with-space` job of `.github/workflows/ci.yaml`, after its
  `bazel test //...` step, the temporary step `- if: ${{ !cancelled() && matrix.folder == '.' }}` (so it runs although
  the job's `bazel test //...` step fails on the red `test_output_test`) / `run: bazel
  --output_user_root="C:/bazel root" test //bun/tests/integration:test_output_test
  --runs_per_test=30 --test_output=errors`, with a comment `# Temporary (feature 007 SC-003):
  removed before merge.`; commit as `test: reproduce the Windows test wrapper's lost output
  (research R10)`
- [ ] T040 [US3] Ask the user to approve pushing the branch and opening the PR as a draft (title
  `Close feature 006's follow-ups`); after approval push and open it. From the CI run, record in
  `tdd-log.md` the run URL and, per runner, the result of `test_output_test`: expected 30 of 30 FAIL
  on Windows `output-root-with-space` (each naming a missing marker) and PASS on `ubuntu-latest` and
  `macos-latest`. If fewer than 30 of 30 fail, raise the target count and `SIZE` in
  `bun/tests/integration/workspaces/test_output/BUILD.bazel` (16 targets, 2 MiB), push (approved
  above for this branch) and re-run, recording each measured rate
- [ ] T041 [US3] Add to research.md Part 5 an entry `E5` with the reproduction's measured result
  and run URL (FR-013); commit

### Implementation for User Story 3

- [ ] T042 [US3] Gate (FR-016): run `gh release view 9.4.0 --repo bazelbuild/bazel`. Released: go
  to T043. Not released: revert the commits of T037–T039 on the branch (`git revert`; the
  reproduction is not merged red), leave `bun/tests/integration/source_node_modules.test.ts` and its
  BUILD target unchanged (no retry, no `flaky`), record the stop in `tdd-log.md` with the red run's
  URL, write the PR-body section "US3" (cause: Bazel 9.2.0's `tw.exe` drops the pipe's tail,
  bazelbuild/bazel#32203; fix pending Bazel 9.4.0; reproduction red in <run URL>, commit <hash>),
  stop and report to the user, and skip T043–T046
- [ ] T043 [US3] Set `BAZEL_VERSION = "9.4.0"` in `bun/tests/integration/registry/update.ts` and run
  `$B bun/tests/integration/registry/update.ts` (network). Review the diff: the region of
  `MODULE.bazel` between `# BEGIN integration archives` and `# END integration archives`
  (`integration_bazel_*` URLs of release 9.4.0, each `integrity` equal to the release's `.sha256`
  file, checked for `integration_bazel_windows_x86_64` by fetching it into a new empty
  `/tmp/bun007-sha/`), `bun/tests/integration/registry/modules/`, `bazel_registry.json` and
  `archives.bzl`; `.bazelversion`, `bazel_compatibility` and `e2e/smoke/` are unchanged. Run
  `bazel test //bun/tests/integration/...` on Linux: green; record
- [ ] T044 [US3] Change the temporary step of T039 to run
  `//bun/tests/integration:test_output_test //bun/tests/integration:source_node_modules_test` with
  `--runs_per_test=30`; commit as `test: run the integration tests' inner builds on Bazel 9.4.0
  (research R10)`; push (approved in T040). Record: 60 of 60 PASS on Windows
  `output-root-with-space` (SC-003), with the run URL; `git diff main --
  bun/tests/integration/source_node_modules.test.ts` is empty. A failure: stop and report
- [ ] T045 [US3] Remove the temporary step from `.github/workflows/ci.yaml`; commit as
  `ci: remove feature 007's repeated-runs step`
- [ ] T046 [US3] Add to research.md Part 5 an entry `E6` with T044's run URL and counts; commit

**Checkpoint**: US3 complete (fixed, or stopped per FR-016 with the evidence in the PR body).

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: documentation (FR-018), public surface (FR-017), gates (FR-019), the PR.

- [X] T047 [P] Rewrite `translate_lock`'s `doc` (`bun/private/npm_extension.bzl` L10–L40) and
  `_NPM_DOC` per research R11: overrides read as Bun reads them (both fields' key forms; the rules
  Bun skips with a warning are skipped: a non-string, `""` or `"-"` value, an empty key, a `patch:`
  value, a `"//"` key, a key Bun's selector parser rejects, deeper nesting); catalogs read where Bun
  reads them, only string entries; a non-object `overrides` or `resolutions` refused. Each sentence
  names its tests (`//bun/tests/npm/conformance:conformance_test`, `//bun/tests/npm:compare`,
  `//bun/tests/npm:bun_override_map`, `//bun/tests/npm:bun_package`) and the runners
  `ubuntu-latest`, `macos-latest`, `windows-latest`. Remove "when the root `package.json` uses an
  override form rules_bun does not compare"
- [X] T048 [P] Run `rtk grep -rn "cannot compare with bun.lock\|normalize_overrides\|manifest_catalogs\|overrides\.bzl\|_catalog_find\|_strip_reference"
  bun e2e README.md`: nothing printed; fix any hit
- [X] T049 Public surface (quickstart V8): `git diff main --stat -- bun/*.bzl bun/toolchain
  bun/platforms` prints nothing, and `bazel mod show_extension @rules_bun//bun:extensions.bzl%npm`
  equals `/tmp/bun007-show_extension-main.txt` (T004); record
- [X] T050 `bazel test //bun/tests/integration:scale_test --test_output=all`: passes; record the
  evaluation time next to T004's
- [ ] T051 Gates (FR-019, quickstart V9): in the root `bazel run //:gazelle`,
  `prek run --all-files`, `bazel test //...`; in `e2e/smoke/` `bazel test //...`; record each. A
  failure: report it with its output, do not widen the task (AGENTS.md)
- [ ] T052 Commit the remaining changes as `docs: state the override and catalog forms evaluation
  reads (FR-018)`; ask the user to approve pushing and marking the PR ready. PR body: the BC-1…BC-8
  table (form, corpus project, red row, green row), the 1.4.2 not-applicable list with reasons,
  US3's outcome (T044 or T042), and "Known differences not fixed": research R3's literal range
  equality. After the run, record its ID in `tdd-log.md`; every job on `ubuntu-latest`,
  `macos-latest` and `windows-latest` must pass, else report the failing job's log, keep the PR a draft, and take that runner out of the
  documentation's claim (T047, FR-018) until its job passes (SC-005)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup; BLOCKS US1 and US2 (their red rows must exist on
  `main`'s comparison before any `bun/private/` change).
- **US1 (Phase 3)**: after Phase 2.
- **US2 (Phase 4)**: after Phase 2; after US1 in this plan, because both edit
  `bun/private/workspaces.bzl` `compare_manifests`, `bun/tests/npm/compare_test.bzl`,
  `citations.test.ts` and the BUILD files. US2's red (T030) is valid after US1: US1 leaves the
  catalog code as on `main`.
- **US3 (Phase 5)**: after Phase 1 only; its push (T040) carries US1/US2 if done, so do it after
  T036 to have one CI run serve both. T043–T046 depend on the T042 gate.
- **Polish (Phase 6)**: after US1, US2, and US3 (done or stopped).

### Within Each User Story

- Tests written and recorded red before implementation.
- US1: T015 → T016/T017 → T018 → T019 → T020 → T021 → T022 → T023 → T024 → T025/T026 → T027 → T028.
- US2: T029/T030 → T031 → T032 → T033 → T034/T035 → T036.
- US3: T037 → T038 → T039 → T040 → T041 → T042 → (T043 → T044 → T045 → T046).

### Parallel Opportunities

- T016 (`bun_override_map_test.bzl`) with T017 (`compare_test.bzl`).
- T025 (citations) with T026 (canary).
- T029 (`bun_package.bzl`, `bun_package_test.bzl`) alongside US1's tasks, which touch neither file.
- T034 (citations) with T035 (canary).
- T037 (inner workspace) can be written while US1/US2 run.
- T047 (docs) with T048 (grep).

---

## Parallel Example: User Story 1

```bash
# After T015, write both red suites together:
Task: "T016 bun_override_map_test.bzl: parse_selector, parse_append, changed cases"
Task: "T017 compare_test.bzl override_forms_test: one inline case per form"

# After T024:
Task: "T025 citations.test.ts MODULES += bun_override_map"
Task: "T026 c_overrides.test.ts: new cases and red-mode regex"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1 and Phase 2: the 15 projects red on `main`.
2. Phase 3: US1. **Stop and validate**: quickstart V3 (12 US1 projects, 0 differences), V4, V5.

### Incremental Delivery

1. US1 → consumers with any override form Bun 1.4.4 installs evaluate.
2. US2 → catalogs read where Bun reads them.
3. US3 → Windows integration logs keep their end, or the stop is reported (FR-016).
4. Polish → docs, gates, one PR.

---

## Notes

- [P] tasks touch different files and depend on no incomplete task.
- Commit after each task group as the tasks state.
- US3's push (T040) and the PR (T052) wait for the user's approval.
- The 30-run CI step is evidence for SC-003 only and is removed before merge (T045, or by the
  revert of T042).
