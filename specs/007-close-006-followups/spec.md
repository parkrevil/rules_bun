# Feature Specification: Close Feature 006's Follow-ups

**Feature Branch**: `007-close-006-followups`

**Created**: 2026-11-24

**Status**: Draft

**Input**: User description: "Close feature 006's follow-ups (research Part 6 of
specs/006-bun-conformant-resolution, PR #7's \"Known differences not fixed\"). (1) The npm
extension's comparison of package.json with bun.lock must accept every form the pinned Bun 1.4.4
writes and installs, reading each as Bun's own source does (cited lines): override values Bun
ignores with a warning (a non-string, \"\", \"-\"); an override object whose only child is \".\"; a
top-level override target with a range (\"q@^1.0.0\"), which Bun records as {\".\": ...}; npm's
\"//\" comment keys, which Bun skips (OverrideMap.rs is_comment_key); resolutions globs \"**/q\" and
\"a/**/q\"; and a top-level catalog/catalogs, which Bun reads only when workspaces exists and holds
neither (Package.rs L3418-L3440). Each form gets a conformance corpus project the pinned Bun
writes, shown failing first. (2) Make //bun/tests/integration:source_node_modules_test
deterministic on Windows: it failed once on output-root-with-space (the load guard reported
node_modules\b\index.js not declared by @@//:phantom_test) and passed on retry; find the cause and
fix it, test first."

**Approval (user, 2026-11-24, this input)**: read each `package.json` form listed in FR-001 to
FR-006 as the pinned Bun's source reads it, each pinned against output the pinned Bun produces by a
corpus project. `research.md` records, per form, the bun.com page (or page bun.com links to) that
describes it, or, where none does, this approval with the evidence (constitution V).

**Approval of the forms found in planning (user, 2026-11-24, at the analysis gate)**: BC-6's second
half, BC-7 and BC-8 (research Part 3), read as the pinned Bun's source reads them, each pinned
against output the pinned Bun produces by a corpus project. FR-007's catalog forms are the ones the
input names (Package.rs L3418–L3440).

**Correction to the input (evidence: PR #7's CI run 45040229326, job `output-root-with-space (.)`,
id 137262794310)**: the attempt that failed is the case "ignored, local strategy" (`REPO.bazel`
ignores `**/node_modules`, `--spawn_strategy=local`). Its assertion failed because the test output
Bazel printed for the inner `//:source_test` was empty, so `Cannot find package 'b'` was missing.
The `node_modules\b\index.js is not declared by this target` lines that feature 006's research
Part 6 and PR #7 quote are the test's own `console.log` of the cases that passed ("not ignored").
The cause is therefore searched where the inner test's output goes missing, not in the load guard.

## Design Principles

Feature 006's principles hold unchanged: **P1** Bun's algorithm is the specification; **P2** the
pinned Bun (1.4.4) is the oracle; **P3** differences are listed, or they are defects; **P4** the
public surface does not move (`specs/006-bun-conformant-resolution/spec.md`, Design Principles).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Overrides and resolutions the pinned Bun installs pass evaluation (Priority: P1)

A consumer's root `package.json` holds an `overrides` or `resolutions` form the pinned Bun accepts:
a rule Bun skips with a warning, an object whose only child is `"."`, a top-level target with a
range, npm's `"//"` comment keys, or a `resolutions` key with `**` segments. The consumer runs
`bun install` with Bun 1.4.4, commits `bun.lock`, and builds with Bazel. Today module-extension
evaluation fails ("has a form rules_bun cannot compare with bun.lock", or "run `bun install` and
commit bun.lock") although the lockfile is current. After this feature, evaluation passes and the
build links what the pinned Bun links.

**Why this priority**: the consumer cannot build at all, on a lockfile the pinned Bun wrote and
installs; that is a defect under P3 that `main` has.

**Independent Test**: for each form, a corpus project whose lockfile the pinned Bun writes; the
conformance test fails on it before the change and reports 0 differences after.

**Acceptance Scenarios**:

1. **Given** an override whose value is a number, boolean, `null` or array, at the top level or as
   a child of a parent's object, **When** the extension evaluates the project, **Then** the rule is
   skipped as Bun skips it (OverrideMap.rs L867–L880, L906–L916) and evaluation passes.
2. **Given** an override or resolution whose value is `""` or `"-"`, **When** evaluated, **Then**
   the rule is skipped as Bun skips it (`parse_override_value`, L1248–L1275) and evaluation passes.
3. **Given** `"overrides": {"q": {".": "1.2.3"}}`, **When** evaluated, **Then** it is compared as the
   flat rule `"q": "1.2.3"` the lockfile records (`"."` child, L918–L927) and evaluation passes.
4. **Given** `"overrides": {"q@^1.0.0": "1.2.3"}`, **When** evaluated, **Then** it is compared as
   `{"q@^1.0.0": {".": "1.2.3"}}`, the form the lockfile records for a target with a range
   (`put_rule` L1022–L1069, `write_override_rules` bun.lock.rs L1311–L1458), and evaluation passes.
5. **Given** `"//"`-prefixed keys at the top level or inside a parent's object, **When** evaluated,
   **Then** they are skipped as Bun skips them (`is_comment_key`, L206–L209) and evaluation passes.
6. **Given** `"resolutions": {"**/q": "1.2.3"}` or `{"a/**/q": "1.2.3"}`, **When** evaluated,
   **Then** they are compared as `{"q": "1.2.3"}` and `{"a": {"q": "1.2.3"}}`, as Bun's Yarn path
   parser drops `**` segments (override_selector.rs L108–L123), and evaluation passes.
7. **Given** any of the projects above with a `package.json` rule changed after `bun install`,
   **When** evaluated, **Then** evaluation still fails with "run `bun install` and commit bun.lock".

---

### User Story 2 - The catalogs compared are the ones Bun reads (Priority: P1)

A consumer's root `package.json` has a top-level `catalog` or `catalogs`. Bun reads them only when
`workspaces` exists and holds neither `catalog` nor `catalogs` (Package.rs L3418–L3440; CatalogMap.rs
`parse_append` L285–L341 counts either key as found). Today the ruleset merges the top level with
`workspaces.catalog`/`workspaces.catalogs`, and reads the top level without `workspaces`, so
evaluation fails on lockfiles the pinned Bun writes and installs.

**Why this priority**: same as US1: a current lockfile fails evaluation, a defect `main` has.

**Independent Test**: one corpus project per case below that `main` fails, red then green in the
conformance test.

**Acceptance Scenarios**:

1. **Given** `workspaces` is an object holding `catalog` or `catalogs` and the top level holds a
   `catalog` or `catalogs` too, **When** evaluated, **Then** only the `workspaces` ones are compared
   and resolved through, and evaluation passes.
2. **Given** no `workspaces` field and a top-level `catalog` that no dependency references, **When**
   evaluated, **Then** no catalog is compared (the lockfile records none) and evaluation passes.
3. **Given** `workspaces` is an array and the top level holds `catalog`, **When** evaluated, **Then**
   the top-level catalog is read, as today.

---

### User Story 3 - The source `node_modules` test is deterministic on Windows (Priority: P2)

A maintainer's CI run on Windows passes or fails `//bun/tests/integration:source_node_modules_test`
by what the ruleset does, not by chance. Its first attempt in run 45040229326 failed because the
inner `//:source_test`'s output was missing from what the inner Bazel printed (see the correction
above); the retry passed.

**Why this priority**: a flaky test hides real failures and costs CI reruns, but no consumer build
is wrong because of it, unless the cause is in what the ruleset launches, which the research
decides.

**Independent Test**: a test that fails on the identified cause every time, recorded failing before
the fix; then repeated runs of `source_node_modules_test` on the Windows CI job with 0 failures.

**Acceptance Scenarios**:

1. **Given** the cause, **When** the reproducing test runs before the fix, **Then** it fails every
   run, on the platforms where the cause occurs.
2. **Given** the fix, **When** `source_node_modules_test` runs repeatedly on the Windows CI job,
   **Then** every run passes, and every case still asserts that `b` and `r` do not load.

---

### Edge Cases

- `package.json` holds both `overrides` and `resolutions`: only `overrides` is read, as today
  (bun.com pm/overrides).
- `overrides` is not an object: Bun refuses the project (`not_an_object`), so evaluation keeps
  failing.
- An object with `"."` and other children (`{"a": {".": "1.0.0", "b": "2.0.0"}}`): compared as Bun
  records both rules, the flat one for `a` and the scoped one under `a`.
- A `"."` child under a parent with a range (`{"q@^1.0.0": {".": "1.2.3"}}`): compared as the same
  rule as US1 scenario 4.
- Comment keys under a key Bun reads, and a key that is only `"//"`.
- `resolutions` keys Bun's selector parser rejects with a warning (a trailing `**`, an empty
  segment, a bare scope) and keys deeper than one parent (`a/b/c`): skipped, as Bun skips them.
- An override rule Bun skips for other reasons with a warning (an empty key, a `patch:` value): skipped
  likewise (FR-001).
- No `workspaces` field and a top-level `catalog` that a `dependencies` entry references as
  `catalog:`: Bun does not read that catalog (FR-007), so the reference names no catalog entry and
  evaluation fails with the error naming the missing entry (BC-6); `main`, which read the top
  level, passed it.
- A project in this feature's corpus that Bun 1.4.2 cannot write, or whose lockfile its own frozen
  install refuses: listed as not applicable to the 1.4.2 run with the observed reason, as feature
  006 listed `conformance_root_row`.
- A lockfile with a scoped rule is written as `lockfileVersion` 3 (bun.lock.rs L104, L180–L198);
  the ruleset already reads version 3 (`overrides_range`).

## Requirements *(mandatory)*

### Functional Requirements

Overrides and resolutions (US1):

- **FR-001**: Every `overrides` or `resolutions` rule the pinned Bun's parser skips with a warning
  MUST be skipped by the comparison: a non-string value at the top level or under a parent
  (L867–L880, L906–L916, L982–L992), a `""` or `"-"` value (L1248–L1275), an empty key (L853–L860,
  L969–L976), a `patch:` value (L1031–L1042), and a key Bun's selector parser rejects
  (`warn_selector_error`, L1152–L1190). The input names the first two; the others are the same
  branch of Bun's parser and are taken in so that "every form" holds.
- **FR-002**: An object whose children include `"."` MUST be compared as the rule Bun records for
  `"."` on the parent's own selector (L918–L927) plus the rules of its other children.
- **FR-003**: A top-level `overrides` key with a range (`"<name>@<range>"`) MUST be compared as the
  scoped rule Bun records, written in the lockfile as `{"<name>@<range>": {".": …}}`.
- **FR-004**: Keys starting with `//` MUST be skipped at both levels (L206–L209, L862, L894, L977).
- **FR-005**: A `resolutions` key MUST be read as Bun's Yarn path parser reads it, dropping `**`
  segments (`parse_yarn_path`, override_selector.rs L108ff.), so `**/q` is the flat rule for `q` and
  `a/**/q` the rule for `q` under `a`.
- **FR-006**: The comparison MUST still fail, naming the file and "run `bun install` and commit
  bun.lock", when a rule Bun reads differs from the lockfile's.

Catalogs (US2):

- **FR-007**: The root's catalogs MUST be read as Bun reads them (Package.rs L3418–L3440): those
  under `workspaces` when `workspaces` is an object holding `catalog` or `catalogs`; else the top
  level's when `workspaces` exists; else none. Both the comparison with the lockfile and the
  resolution of `catalog:` specifiers in the manifest comparison MUST use that reading.

Evidence and tests (US1, US2):

- **FR-008**: `research.md` MUST map each form of FR-001 to FR-007 to the Bun 1.4.4 lines that read
  it (tag `bun-v1.4.4` of oven-sh/bun), each re-read at the tag, and each changed function MUST cite
  them, as feature 006's carry-over does.
- **FR-009**: Each form that `main` fails on, among the forms named in the input, FR-001's further
  forms, and the forms of BC-6's second half, BC-7 and BC-8, MUST be reached by a conformance corpus project whose lockfile the
  pinned Bun writes; the conformance test MUST fail on it before the change (recorded in the TDD
  log) and report 0 differences after. Forms Bun reads with one check (for example the JSON types of a non-string
  value) MAY share one project. A form that passes on `main` too (research R7, T017) keeps a unit
  test instead.
- **FR-010**: Each new corpus project MUST also run in the Bun 1.4.2 conformance run, or be listed
  in its not-applicable list with the reason Bun 1.4.2 shows.
- **FR-011**: A form the ruleset newly relies on to do this, whether a `bun.lock` form it reads or a
  way the pinned Bun writes `package.json` into `bun.lock` (which catalogs, which catalog entries,
  which override rules), MUST be pinned by a canary with a red mode (constitution V, feature 006
  approval of 2026-10-29).
- **FR-012**: Each change in whether evaluation passes MUST be listed below as a Behavior Change
  before it is made.

Windows determinism (US3):

- **FR-013**: `research.md` MUST state the cause of the run 45040229326 failure with evidence (the
  CI log, and a reproduction), including where the inner `//:source_test`'s output was lost (the
  test's own process, the ruleset's launcher, Bun, or Bazel's test runner).
- **FR-014**: A test that fails on that cause every run MUST be recorded failing before the fix (TDD
  log). Where the cause is in what the ruleset launches, that test MUST exercise the ruleset's rules,
  since a consumer's failing test would lose its output the same way.
- **FR-015**: The fix MUST remove the cause. It MUST NOT retry, mark the test `flaky`, or drop or
  weaken an assertion of `source_node_modules_test`.
- **FR-016**: If the cause is in Bun or Bazel and no supported API avoids it, work MUST stop and the
  gap be reported with the evidence (constitution V).

Delivery:

- **FR-017**: The public API (constitution I) MUST NOT change; every generated target name stays.
- **FR-018**: Documentation and error messages that list the forms the comparison reads MUST be
  updated, and MUST claim only forms a test covers, naming the platforms it ran on.
- **FR-019**: The change is one PR from branch `007-close-006-followups`; before hand-back, in the
  root `bazel run //:gazelle`, `prek run --all-files`, `bazel test //...`, and in `e2e/smoke/`
  `bazel test //...` pass, as does every job of the PR's CI run on Linux, macOS and Windows.

### Behavior Changes

Each is a change from `main` in what a consumer's build does; in each, `main` fails evaluation on a
lockfile the pinned Bun writes and installs.

- **BC-1**: override and resolution rules Bun skips with a warning (FR-001) are skipped.
- **BC-2**: an override object with a `"."` child is compared as Bun records it (FR-002).
- **BC-3**: a top-level override target with a range is compared as `{".": …}` (FR-003).
- **BC-4**: `"//"` comment keys are skipped (FR-004).
- **BC-5**: `resolutions` keys with `**` segments are read as Bun reads them (FR-005).
- **BC-6**: a top-level `catalog`/`catalogs` is read only where Bun reads it (FR-007), and a catalog
  entry whose value is not a string is skipped, as Bun skips it (`parse_append_group`, CatalogMap.rs
  L356–L358; found in planning, research R4).

Found in planning by reading the cited functions at the tag (research R2); each is a form the pinned
Bun parses and records that `main` compares otherwise:

- **BC-7**: an `overrides` or `resolutions` key is read by Bun's one selector parser for both fields
  (`parse_selector`, override_selector.rs L54–L165): a Yarn path key (`"a/b"`, `"**/b"`) in
  `overrides`, a pnpm `>` key in `resolutions`, whitespace around `>`, a `>` after `@`, `:`, `|` or a
  space (`"foo@>=2.0.0"`, bun.com pm/overrides), and an `npm:` range in a selector (L41–L47).
- **BC-8**: a flat rule next to rules scoped under the same name (`{"a": "1.0.0", "a>b": "2.0.0"}`),
  which `bun.lock` writes as one object with a `"."` child (`write_override_rules`, bun.lock.rs
  L1311–L1458), is compared as the rules Bun records.

Any further difference the conformance test finds is added here before it is fixed.

### Key Entities

- **Override rule**: a `(parent selector?, target name, target range?, value)` that Bun's parser
  produces from one `overrides` or `resolutions` entry, or skips with a warning; the unit compared.
- **Catalog set**: the default catalog and named catalogs Bun reads from a root `package.json`.
- **Corpus project**: a project under the conformance corpus whose lockfile the pinned Bun writes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of the forms of FR-009 that `main` fails on have a corpus project that fails the conformance test before the change and passes it after
  (TDD log), with 0 differences from Bun 1.4.4 on Linux, macOS and Windows CI.
- **SC-002**: Each stale-lockfile variant of US1 scenario 7 still fails evaluation (0 false passes).
- **SC-003**: `source_node_modules_test` passes 30 of 30 runs on the Windows `output-root-with-space`
  CI job after the fix (a 10% failure rate would show in 30 runs with 96% probability); its
  reproducing test fails before the fix in every run. If work stops under FR-016 (Bazel 9.4.0 not
  released), SC-003 is met by the reproduction's red run on that job and the report, with its
  evidence (cause, upstream fix, run URL), in the PR body.
- **SC-004**: 0 public API changes: every generated target name and public symbol on `main` is
  unchanged.
- **SC-005**: The gates of FR-019 pass, locally and in every job of the PR's CI run.

## Assumptions

- The pinned Bun is 1.4.4; its source at tag `bun-v1.4.4` is the reference. Line numbers above were
  read at that tag on 2026-11-24 and are re-read before the plan relies on them.
- "Accept" means evaluation passes when `package.json` and `bun.lock` agree as Bun reads them, and
  still fails when they disagree; it does not mean skipping the comparison.
- The resolver already reads the lockfile's own `overrides` and `catalogs` as Bun does (feature
  006); this feature changes only how `package.json` is read for the comparison, unless the
  conformance test shows otherwise (then FR-012).
- The 30-run measure of SC-003 runs once on the PR, through `--runs_per_test`; it is evidence, not
  a permanent CI job.
- Feature 006's other follow-ups (none open besides these) and its Intentional Differences are
  unchanged.
