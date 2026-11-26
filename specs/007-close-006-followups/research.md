# Research: Close Feature 006's Follow-ups

**Feature**: `007-close-006-followups` | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

Every Bun line range below was re-read at tag `bun-v1.4.4` on 2026-11-24: the files were fetched
from `raw.githubusercontent.com/oven-sh/bun/bun-v1.4.4/...` and are byte-identical to the copies
the spec was written from (Part 5, E1).

## Part 1: Sources and approval

| ID | Source | Used for |
|---|---|---|
| OVERRIDE | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/OverrideMap.rs (1,452 lines) | how a root `package.json`'s `overrides`/`resolutions` become rules (R1, R2), `changed` (R3) |
| SELECTOR | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/override_selector.rs (165 lines) | the key parser shared by both fields (R2, BC-7) |
| LOCK | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/bun.lock.rs | how the rules are written (`write_override_rules` L1311–L1458, `override_selector_key` L1274–L1287, `lockfileVersion` 3 L104, L180–L198) and read back (L1934–L2035, carried over by feature 006) |
| PKG | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/Package.rs | where the root's catalogs come from (L3418–L3440), the frozen-install diff (`overrides_changed` L1048–L1059, catalogs L1061–L1120) |
| CATALOG | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/CatalogMap.rs | `parse_append` L285–L342, `parse_append_group` L344–L396 |
| DEP | https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/dependency.rs | `Dependency::eql` L254–L258, `Version::eql` L745–L770 (R3) |
| DOC-OVR | https://bun.com/docs/pm/overrides | the forms bun.com documents (table below) |
| DOC-CAT | https://bun.com/docs/pm/catalogs | "`catalog` and `catalogs` also work at the top level of `package.json`" |
| TW | https://github.com/bazelbuild/bazel/blob/9.2.0/tools/test/windows/tw.cc, `tw.h`, `src/main/native/windows/util.h` | the Windows test wrapper of the Bazel the integration tests run (R10) |
| TW-FIX | https://github.com/bazelbuild/bazel/pull/32203, commit `e50ebd4a0a0b` (2026-11-03); cherry-picks #32383 (`release-9.4.0`), #32382 (10.0.0), #32417 (8.9.0) | the upstream fix (R10) |
| CI | PR #7's run 45040229326, job `output-root-with-space (.)`, id 137262794310 | the failure (R10) |

**Approval (constitution V)**: the user approved, in this feature's input (spec, "Approval",
2026-11-24), reading each `package.json` form of FR-001 to FR-006, and the catalog forms the input
names (FR-007), as the pinned Bun's source reads it, each pinned by a corpus project whose lockfile
the pinned Bun writes ("input approval" below). The forms found in planning (Part 3: BC-6's second
half, BC-7, BC-8) rest on the user's separate approval of 2026-11-24 at the analysis gate (spec,
"Approval of the forms found in planning"; "planning approval" below).

| Form | bun.com | Bun 1.4.4 lines |
|---|---|---|
| npm object form, `"."` child | DOC-OVR "scope a rule to one parent", "`"."` inside an object overrides `micromatch` itself" | OVERRIDE L893–L954 (`"."` L918–L927) |
| pnpm `>` form, parent with a range | DOC-OVR (same section) | SELECTOR L54–L98 |
| target with a range (`"semver@<7.5.2"`, `"terser@4": {".": …}`, `"foo@>=2.0.0"`) | DOC-OVR "Version-scoped overrides" | SELECTOR L29–L52, L72–L82; OVERRIDE L1044–L1068 |
| Yarn path form with `**` in `resolutions` | DOC-OVR "`resolutions` accepts Yarn's path form. Bun accepts `**`" | SELECTOR L108–L165 |
| `"-"` value, `"pkg@"` key (skipped with a warning) | DOC-OVR "Limitations" | OVERRIDE L1265–L1275; SELECTOR L48–L50 |
| deeper nesting ignored | DOC-OVR "Limitations" | OVERRIDE L902–L905, SELECTOR L90–L92, L144–L146 |
| `lockfileVersion` 3 for scoped rules | DOC-OVR "Limitations" | LOCK L104, L180–L198 |
| non-string value, `""` value, empty key, `patch:` value, selector errors | none: input approval | OVERRIDE L853–L860, L867–L880, L906–L916, L969–L976, L982–L992, L1031–L1042, L1152–L1190, L1257–L1264 |
| `"//"` comment keys | none: input approval | OVERRIDE L206–L209, L862–L864, L894–L896, L977–L979 |
| one selector parser for both fields (BC-7: Yarn paths in `overrides`, pnpm in `resolutions`, `npm:` range) | DOC-OVR shows each form in one field only: planning approval | OVERRIDE L997–L1020 (`parse_string_rule`); SELECTOR L54–L68, L41–L47 |
| flat rule folded into a group as `"."` (BC-8) | none: planning approval | LOCK L1311–L1458 (written); L1934–L2035 (read) |
| top-level `catalog`/`catalogs` only when `workspaces` exists and holds neither | DOC-CAT says only that they "also work"; the condition: input approval | PKG L3418–L3440, CATALOG L285–L342 |
| catalog entry that is not a string, skipped (BC-6, second half) | none: planning approval | CATALOG L356–L358 |

## Part 2: Decisions

### R1. Compare overrides as Bun does: parse both sides into rules, then `OverrideMap::changed`

- **Decision**: carry over the `package.json` side of Bun's `OverrideMap` (`parse_append`
  L802–L838, `parse_from_overrides` L841–L955, `parse_from_resolutions` L959–L995,
  `parse_string_rule` L997–L1020, `put_rule` L1022–L1069, `parse_parent` L1192–L1206,
  `parse_range` L1208–L1245, `parse_override_value` L1248–L1371, `is_comment_key` L206–L209) and
  the whole of `override_selector.rs`, producing the same `struct(map, scoped, scoped_names)` the
  lockfile loader builds (`bun_lockfile.bzl` `_parse_overrides`, feature 006), and compare the two
  with a carry-over of `OverrideMap::changed` (L503–L551) and `sort` (L553–L579). `overrides.bzl`'s
  `normalize_overrides`, which rewrites the manifest into the JSON shape the lockfile writes and
  errors on any shape it does not know, is removed.
- **Rationale**: this is how the pinned Bun decides that a lockfile is current (`Package::Diff`,
  PKG L1048–L1059): it parses `package.json` into an `OverrideMap`, loads the lockfile's into
  another, and compares rules, never JSON shapes. Every form of FR-001 to FR-005, BC-7 and BC-8
  then follows from the carried-over functions instead of from a table of shapes (P1). The
  lockfile side is already carried over and canaried.
- **Alternatives considered**: (a) extend `normalize_overrides` with each new shape, reproducing
  `write_override_rules`' grouping and `"."` folding: a second model of Bun's writer, the kind of
  shape table that produced the follow-ups; rejected (P1). (b) compare JSON after normalizing both
  sides: still needs the writer's folding rules; rejected.

### R2. The forms, as the carried-over parser reads them

Each row is a rule of `package.json` and the rule set both sides produce; "main" is what
`main`'s `normalize_overrides` does with it.

| Form | Bun reads | Lockfile writes | main |
|---|---|---|---|
| non-string value at the top (`overrides`) | skipped, "Invalid override value" (L870–L880) | nothing | error "cannot compare" |
| non-string value under a parent | skipped (L906–L916) | nothing | error |
| non-string value (`resolutions`) | skipped, "Invalid resolution value" (L982–L992) | nothing | error |
| `""` / `"-"` value, either field, either level | skipped (L1257–L1275) | nothing | compared, differs |
| empty key | skipped (L853–L860, L969–L976) | nothing | compared, differs |
| `patch:` value | skipped (L1031–L1042) | nothing | compared, differs |
| key the selector parser rejects (`"@s"`, `"b@"`, `"a//b"`, trailing `**`) | skipped, `warn_selector_error` (L1152–L1190) | nothing | compared, differs, or error |
| `"//"`-prefixed key, top or child | skipped (L862, L894, L977) | nothing | compared, differs |
| `{"q": {".": "1.2.3"}}` | flat `q` (L918–L927, `is_flat` L1045) | `"q": "1.2.3"` (no scoped rule) | kept as an object, differs |
| `{"a": {".": "1.0.0", "b": "2.0.0"}}` | flat `a` + scoped `a>b` | `{"a": {".": …, "b": …}}` (L1404–L1431) | passes (same JSON) |
| `"q@^1.0.0": "1.2.3"` | scoped, no parent, target range `^1.0.0` | `{"q@^1.0.0": {".": "1.2.3"}}` | stored as a string, differs |
| `{"q@^1.0.0": {".": "1.2.3"}}` | the same rule | the same | passes (same JSON) |
| `"**/q"` (`resolutions`) | flat `q`: `**` segments dropped (SELECTOR L118–L123) | `"q": …` | error |
| `"a/**/q"` (`resolutions`) | scoped `a>q` | `{"a": {"q": …}}` | error |
| `"**/a/**/q"` (`resolutions`) | scoped `a>q` | `{"a": {"q": …}}` | passes |
| BC-7: `"a/b"`, `"**/b"` in `overrides` | Yarn path (SELECTOR L67) | as in `resolutions` | flat key `"a/b"`, differs |
| BC-7: `"a>b"` in `resolutions` | pnpm (SELECTOR L64–L66) | `{"a": {"b": …}}` | flat key `"a>b"`, differs |
| BC-7: `"a > b"` | a `>` after a space is no delimiter (SELECTOR L77): one Yarn segment, the flat rule of the name `"a > b"` (corrected in implementation, Part 6 D1) | `"a > b": …` | names `"a "`, `" b"`, differs |
| BC-7: `"a> b"` | pnpm, segments trimmed (SELECTOR L85–L86) | `{"a": {"b": …}}` | names `"a"`, `" b"`, differs |
| BC-7: `"q@>=1.0.0"`, `"a@>=1>b"` | a `>` after `@`, `:`, a pipe or a space is no delimiter (SELECTOR L72–L82) | `{"q@>=1.0.0": {".": …}}` | split at the `>`, differs |
| BC-7: `"q@npm:^1.0.0"` | range `^1.0.0` (SELECTOR L41–L47) | `{"q@^1.0.0": {".": …}}` | differs |
| BC-8: `{"a": "1.0.0", "a>b": "2.0.0"}` | flat `a` + scoped `a>b` | `{"a": {".": "1.0.0", "b": "2.0.0"}}` | error (string then object) |
| a later rule with the same selector | replaces the earlier (`put_assume_capacity`, `push_scoped` L644–L668) | the last | merged by key |
| `$<name>` value | as today (feature 006 T177, T179; L1278–L1335) | the resolved specifier | unchanged |

`parse_override_value` and `parse_range` call `Dependency::parse`; a value or range it rejects, or
a range that is no selector range (`is_selector_range` L1081–L1087: an npm range for both, a
catalog only for a target, never a dist-tag), is skipped with a warning. The carry-over calls the
existing `dependency_parse` (`bun_install_types.bzl`).

`Field::of` (L166–L170): `overrides` wins whenever present; a value that is not an object is
refused (`not_an_object` L1140–L1150, an error, so Bun installs nothing), which evaluation keeps
refusing.

### R3. Rule equality: the literal

- **Decision**: two rules are equal when the parent's name and range literal, the target's name and
  range literal, and the value's literal are equal; the comparison is `OverrideMap::changed` with
  this equality (counts, then both sides sorted by `sort`, then pairwise).
- **Rationale**: `Dependency::eql` (DEP L254–L258) is name plus `Version::eql` (L745–L770), which
  for every tag compares the literal or a value parsed from it, and for npm ranges first the
  literal (L753–L759). Bun writes the value's literal as it parsed it (LOCK L1306, L1429, L1447),
  so for a lockfile written from the current `package.json` literal equality and `Version::eql`
  agree.
- **Not carried, listed as a follow-up**: `Version::eql`'s npm branch also accepts two different
  literals that parse to the same range (`npm().eql`, L758). A lockfile can keep such a literal only
  if `package.json` was edited to an equal range after the install. The pinned Bun's frozen install
  then passes and `bun install` keeps the recorded literal (D5), so the ruleset's error stays until
  the range is written as `bun.lock` records it. `main` compares literals in the dependency, catalog and
  override comparisons alike, so this is not a change; it needs `SemverQuery`'s group equality
  carried over and is outside this feature's input.

### R4. Catalogs: where Bun reads them, and which entries

- **Decision**: the root's catalogs are read by a carry-over of PKG L3418–L3440 and CATALOG
  `parse_append` (L285–L342) / `parse_append_group` (L344–L396): when the root has a `workspaces`
  field (any value), its object's `catalog` (into the default catalog) and `catalogs` (into named
  groups, `default` among them) are read, and `found_any` is set when either key exists; the top
  level's are read only when `workspaces` exists and `found_any` is false; without `workspaces`,
  none. Entries whose value is not a string are skipped (L356–L358). The result is the same
  `struct(default, groups)` the lockfile loader builds (`bun_lockfile.bzl` `_parse_catalog`);
  `compare_manifests` compares it with `bun.lock`'s `catalog`/`catalogs` and `resolve_catalog`
  looks `catalog:` references up in it.
- **Rationale**: FR-007 and P1. `main`'s `manifest_catalogs` merges the top level with the
  `workspaces` object and reads the top level without `workspaces` (US2 scenarios 1 and 2).
- **Kept as today**: the `catalog` and `catalogs.default` conflict (L310–L339) and "Duplicate
  catalog" (L382–L385) are errors in Bun, which then installs nothing; no lockfile reaches them.
  So is a `workspaces` that is neither an array nor an object, `null` among them (PKG L2863–L2879,
  `"workspaces" expects an array of strings`); "any value" above therefore matters only for
  arrays and objects, and C-CATALOG pins the refusal (review, 2026-11-25, research Part 6 D4).
- **Starlark note**: `json.decode` maps `null` to `None`, so "has `workspaces`" is
  `"workspaces" in manifest`, not `manifest.get("workspaces") != None`.

### R5. Where the code lives

- **Decision**:
  - NEW `bun/private/bun_override_map.bzl`: the carry-over of `override_selector.rs` and of
    `OverrideMap.rs` (both sides). `_parse_package_segment`, `_lockfile_range` and
    `_put_lockfile_rule` move here from `bun_lockfile.bzl`, so each Bun function has one
    carry-over; `bun_lockfile.bzl`'s `_parse_overrides` (bun.lock.rs) loads them. `_reference`,
    `_root_declared` and `_declared` move here from `overrides.bzl` with their citations.
    `bun_lockfile.bzl`'s `_dependency` (resolver_hooks.rs L517–L528) moves to
    `bun_install_types.bzl` as `new_dependency`, so `bun_override_map.bzl` and
    `bun_catalog_map.bzl` build dependencies without loading `bun_lockfile.bzl`.
  - `bun/private/bun_package.bzl`: `root_catalogs(manifest, file)` (PKG L3418–L3440).
  - NEW `bun/private/bun_catalog_map.bzl`: the carry-over of `CatalogMap.rs`:
    `catalog_parse_append` (`parse_append` L285–L342, `parse_append_group` L344–L396), and, moved
    from `bun_lockfile.bzl` with their bodies and citations, `catalog_find` (`_catalog_find`,
    L54–L115), `catalogs_resolve_range` (L195–L207) and `catalog_strip_reference`
    (`_strip_reference`, L209–L237). It loads only `bun_install_types.bzl` and `bun_semver.bzl`;
    `bun_lockfile.bzl`, `bun_tree.bzl` and `bun_package.bzl` load it. Kept in `bun_lockfile.bzl`,
    `catalog_parse_append` would close a load cycle: `bun_lockfile.bzl` → `bun_override_map.bzl` →
    `bun_package.bzl` (`package_dependencies`, for `$<name>` references) → `bun_lockfile.bzl`.
    `_parse_catalog` (bun.lock.rs L1727–L1795) stays in `bun_lockfile.bzl`.
  - `bun/private/workspaces.bzl`: `compare_manifests` calls the above; `manifest_catalogs` and the
    `overrides.bzl` load go. `overrides.bzl` is deleted.
  - `bun/tests/npm/conformance/citations.test.ts`: `MODULES` gains `bun_override_map`,
    `bun_catalog_map` and `bun_package`, so every new function cites its Bun lines (FR-008).
- **Rationale**: feature 006 R1 (one Starlark file per Bun source file, each function citing its
  lines); the citations test then covers FR-008 mechanically.
- **Alternatives considered**: the `package.json` side next to the lockfile side in
  `bun_lockfile.bzl`: that file carries `bun.lock.rs` and `lockfile.rs`, and would hold two Bun
  files more.

### R6. Errors

- A difference names the file, the field the file uses (`overrides` or `resolutions`), the rule as
  `<parent>[@<range>]><target>[@<range>]` (or `<target>[@<range>]` without a parent), both values,
  and "run `bun install` and commit bun.lock" (FR-006), as `_difference` does for the other maps.
  Order: Bun's `sort` order (L553–L579), so the first difference is stable.
- `overrides`/`resolutions` that is not an object keeps failing, in one wording: Bun's refusal
  (`not_an_object`, L1140–L1150) and a remedy that can work, since Bun refuses to install such a
  project: `<file>: "<field>" expects a map of package names to versions, which Bun requires; make it
  an object`. It does not say to run `bun install`.
- The message "has a form rules_bun cannot compare with bun.lock" disappears: every form Bun reads
  is compared and every form it skips is skipped.

### R7. Corpus projects (FR-009, FR-010)

Each is written by `bun/tests/npm/registry/write_lockfiles.ts` with the pinned Bun against the
loopback registry; its `check` asserts the `overrides`, `catalog` or `catalogs` Bun wrote (the
"Lockfile writes" column of R2). They use the existing archives (`a@1.0.0` → `b@^1.0.0`, `b@1.0.0`,
`b@2.0.0`, `q@1.0.0`, `q@2.0.0`, `p-user`, `p`), so each rule that applies changes what is linked
and the graph comparison checks it. One project per Bun branch, so the red run shows each branch
failing on `main` (FR-009); a project may hold several forms of one branch.

| Project | Forms | Spec |
|---|---|---|
| `conformance_override_ignored_values` | non-string (number, boolean, `null`, array), `""`, `"-"` at the top level of `overrides` | US1-1, US1-2, FR-001 |
| `conformance_override_child_values` | the same under a parent's object | US1-1, US1-2, FR-001 |
| `conformance_resolution_ignored_values` | non-string, `""`, `"-"` in `resolutions` | US1-1, US1-2, FR-001 |
| `conformance_override_skipped_keys` | empty key, `"@s"`, `"b@"`, the selector errors `"a>b>c"`, `"a//b"`, `"a/**"`, `"a/b/c"`, `patch:` value | FR-001 (further) |
| `conformance_resolution_skipped_keys` | the same keys and value in `resolutions` | FR-001 (further), spec Edge Cases |
| `conformance_override_comments` | `"//"` keys at the top and in a parent's object; a key that is only `"//"` | US1-5, FR-004 |
| `conformance_override_dot_only` | `{"b": {".": "2.0.0"}}` | US1-3, FR-002 |
| `conformance_override_flat_and_scoped` | `{"a": "1.0.0", "a>b": "2.0.0"}` | BC-8 |
| `conformance_override_target_range` | `"b@^1.0.0": "2.0.0"` | US1-4, FR-003 |
| `conformance_resolution_globs` | `"**/q"`, `"a/**/b"` | US1-6, FR-005 |
| `conformance_override_selectors` | `"a/b"`, `"q@>=1.0.0"`, `"q@npm:^1.0.0"`, `"p-user > p"` in `overrides` | BC-7 |
| `conformance_resolution_pnpm` | `"a>b"` in `resolutions` | BC-7 |
| `conformance_catalog_top_and_nested` | `workspaces` object with `catalog`; top-level `catalog` and `catalogs` too | US2-1, FR-007 |
| `conformance_catalog_no_workspaces` | top-level `catalog`, no `workspaces`, no reference | US2-2, FR-007 |
| `conformance_catalog_non_string` | a catalog entry whose value is not a string | BC-6 |

US2 scenario 3 (`workspaces` array, top-level `catalog`) and `"//"` keys in `resolutions` (Part 6 D2)
pass on `main` and stay unit tests (`compare_test.bzl`). Each project then runs in the Bun 1.4.2 run, or is listed in
`NOT_APPLICABLE_1_4_2` with the reason 1.4.2 shows (FR-010), as feature 006 did; the writer is run
with `--bun-1-4-2` per project during implementation, where the reason is observed, not assumed.

**Test-first order**: the projects are added on `main`'s comparison first; the conformance test
must fail on each with the evaluation error (feature 006 T160: its ruleset side runs the
extension's evaluation checks), recorded in `tdd-log.md` before any `bun/private/` change.

### R8. Canary (FR-011)

`bun/tests/canary/npm/c_overrides.test.ts` gains a case per new lockfile form the comparison now
relies on the loader reading: `{"q@^1.0.0": {".": …}}` from a target with a range, the `"."`-only
object written flat, the flat rule folded into a group (BC-8), `"**/q"` written flat, `"a/**/q"`
written nested, the BC-7 keys, and each skipped form (the values, `"//"` keys and the selector errors `"@s"`,
`"b@"`, `"a//b"`, `"a/**"`, `"a>b>c"`, `"a/b/c"`) written as nothing, in both `overrides` and
`resolutions`. Cases compare by deep equality, since Bun's key order is not what the reader relies
on. Its red mode is the
existing one (the rule retargeted). `READER` names `bun_override_map.bzl` and `_parse_overrides`.
No `bun.lock` field is read for the first time, so no new canary file.

`bun/tests/canary/npm/c_catalog.test.ts` (C-CATALOG) gains three tests for what the catalog
comparison now relies on Bun doing when it writes `bun.lock` from `package.json` (FR-011): the top
level ignored when the `workspaces` object holds `catalog` or `catalogs`; the top level not read
without `workspaces`; a non-string entry skipped. Each has a red mode that makes Bun write
otherwise (the `workspaces` object's `catalog` key renamed; `"workspaces": []` added; the
non-string entry made a string), and `READER` names `root_catalogs`, `catalog_parse_append` and
`_parse_catalog`.

### R9. Unit tests

- NEW `bun/tests/npm/bun_override_map_test.bzl`: `parse_selector` (each SELECTOR branch and error),
  `parse_from_overrides`/`parse_from_resolutions` per OVERRIDE branch, `changed`. It takes over
  `overrides_test.bzl`'s cases, rewritten to rules instead of normalized JSON, and replaces it.
- `bun/tests/npm/compare_test.bzl`: the catalog cases of US2 (all three scenarios, BC-6) and, for
  each corpus project of R7, a variant with one rule's value changed after the install that must
  fail with "run `bun install` and commit bun.lock" (US1-7, SC-002).
- `bun/tests/npm/bun_package_test.bzl`: `root_catalogs` per branch of PKG L3418–L3440.

### R10. The Windows failure of `source_node_modules_test` (US3)

**Cause**: Bazel 9.2.0's Windows test wrapper drops a test's output that is still in its pipe when
the test exits. `tw.exe` runs the test with its stdout and stderr on a pipe; a thread (`TeeImpl`,
TW L77–L104, `MainFunc` L1497–L1509) copies the pipe to the test log. `RunSubprocess`
(L1511–L1547) waits for the test process and returns; the `Tee` is then destroyed without waiting
for the thread (`Tee` has an empty virtual destructor, `tw.h` L105–L113), and `TeeImpl`'s
`AutoHandle` members close the pipe and the log handles (`util.h` L43–L47) while the thread may not
have read what the test wrote last. The exit code is unaffected. The ruleset, the launcher and Bun
are not involved: the inner test failed as it must and its output was lost after it exited.

**Evidence**:
- CI (E3): in the failing attempt ("ignored, local strategy"), the inner Bazel printed
  `FAIL: //:source_test (Exit 1)` and an empty `Test output for //:source_test` section, while the
  two other inner tests of the same invocation printed their whole logs, and the outer assertion
  failed only on `Cannot find package 'b'`. The inner tests ran together in 0.4 s while the outer
  job had 4 actions running. `source_test` fails while loading its test file, so (inferred, not
  measured) its whole output is written at the end of a run of a few hundred milliseconds, the
  window the race needs; the reproduction (below) measures the race without relying on this.
- Upstream (TW-FIX): bazelbuild/bazel#32203 describes the same mechanism ("Once the test process
  had exited, the wrapper destroyed the `Tee` without waiting for this thread … Output that was
  still in the pipe was lost, but the exit code of the test was unaffected") and adds
  `TeeImpl::~TeeImpl`, which waits for the thread. Released in 8.9.0 (2026-11-19) and 10.0.0rc4;
  cherry-picked to `release-9.4.0` (#32383; milestone "9.4.0 release blockers" due 2026-12-07); not
  in 9.2.0, 9.3.0 or 9.3.3 (each tag's `tw.cc` re-read, E4).
- Exposure: the inner Bazel is the dev-only `integration_bazel_*` 9.2.0 (`MODULE.bazel`,
  `bun/tests/integration/registry/update.ts` `BAZEL_VERSION`). Five integration tests assert on
  inner test logs (`launcher_fetch`, `laziness`, `multi`, `stale_link`, `source_node_modules`); each
  can fail the same way on Windows.

**Reproduction (FR-014)**: NEW `//bun/tests/integration:test_output_test` with an inner workspace
`bun/tests/integration/workspaces/test_output/`: several `bun_test` targets that each write a large
output (hundreds of KiB, so the pipe holds a full buffer when the test exits) ending in a marker
line, then fail; the outer test runs `bazel test //:all --test_output=errors` and asserts every
marker is in the inner Bazel's output. It uses the ruleset's `bun_test`, so it also states what a
consumer's failing `bun_test` shows. Expected: fails on Windows with inner Bazel 9.2.0 in every
run of 30 (`--runs_per_test=30` on the Windows CI job, recorded in `tdd-log.md`; upstream saw the
log "cut off about 4 KB in"), passes on Linux and macOS, and passes on Windows with a Bazel that
has #32203. If 30 of 30 do not fail, the output size and target count are raised until they do,
and the measured rate is recorded.

**Fix (FR-015)**: pin the integration tests' inner Bazel to 9.4.0, the first 9.x release with
#32203: `update.ts` `BAZEL_VERSION = "9.4.0"`, rerun to regenerate the `integration_bazel_*`
`http_file`s (integrity from the release's `.sha256`, constitution III) and the local registry.
`.bazelversion` (the root's own Bazel, 9.2.0) and `e2e/smoke` stay at the minimum version
`bazel_compatibility` declares: the root's own Windows test logs can lose their end too, but no
test of the root asserts on its own log, and the exit codes are unaffected. Cost: the integration
tests' inner builds no longer run the minimum version, which `e2e/smoke` and the BCR presubmit
still run.

**Gate (FR-016)**: no Bazel ≥ 9.2.0 release with #32203 exists on 2026-11-24 (10.0.0 is a release
candidate), and no Bazel flag avoids the race (`--test_output=streamed` and `test.xml` go through
the same thread). If 9.4.0 is not released when US1 and US2 are done, US3 stops there: the cause,
the evidence and the reproduction's red run are reported in the PR body, the reproduction test is
not merged red, and `source_node_modules_test` is left unchanged (no retry, no `flaky`).

**Alternatives considered**: reading the inner test's `test.xml` or the junit file Bun writes to
`XML_OUTPUT_FILE` instead of the printed log: `test.xml` is written from the same thread's copy,
and moving five tests to a second channel works around a Bazel defect (constitution V); a delay in
the launcher before it exits: narrows the window without removing it (FR-015); `--local_test_jobs=1`
in the inner builds: the same; Bazel 10.0.0rc4 for the inner builds: a prerelease and a major
version step for a fix 9.4.0 carries.

**SC-003**: after the fix, `source_node_modules_test` with `--runs_per_test=30` on the Windows
`output-root-with-space` job, once on the PR (a temporary step, removed before merge), 30 of 30
passing.

### R11. Documentation (FR-018)

`translate_lock`'s `doc` (`npm_extension.bzl` L10–L40) and `_NPM_DOC` list what evaluation
compares. They change to: overrides read as Bun reads them (both fields' key forms; the rules Bun
skips with a warning are skipped: a non-string, `""` or `"-"` value, an empty key, a `patch:`
value, a `"//"` key, a key Bun's selector parser rejects, deeper nesting); catalogs read where Bun
reads them and only string entries; the refusal of a non-object `overrides`. Each sentence names
the tests that cover it and the CI runners they ran on (`ubuntu-latest`, `macos-latest`,
`windows-latest`). "when the root `package.json` uses an override form rules_bun does not compare"
is removed.

## Part 3: Differences found in planning

Reading the cited functions found forms the input does not name, each one `main` compares
otherwise and the pinned Bun parses and records; they are added to the spec as BC-7 and BC-8 and
as BC-6's second half (FR-012) and covered by R7's projects:

- BC-7: `parse_string_rule` (OVERRIDE L997–L1020) calls `parse_selector` for a string rule of
  either field, so `overrides` takes Yarn paths and `resolutions` takes pnpm keys; the pnpm
  delimiter skips a `>` after `@`, `:`, `|` or a space, and segments are trimmed; a segment's
  `npm:` range drops the prefix. bun.com documents `"foo@>=2.0.0"`, which `main` splits.
- BC-8: with scoped rules present, a flat rule of a name that is also an unranged group's name is
  written as the group's `"."` (LOCK L1366–L1431).
- BC-6, second half: `parse_append_group` skips non-string entries silently.

Not fixed, listed as follow-ups: R3's literal equality, and the catalog entries Bun's frozen install
skips (D5).

## Part 4: Not changed

- The lockfile loader's reading of `overrides` and `catalogs` (feature 006) is unchanged but for the
  move of three helpers (R5).
- Bun 1.4.2: its lockfiles for the new projects are compared as feature 006 does (FR-010).
- `bazel_compatibility` (`>=9.2.0`), `.bazelversion`, `e2e/smoke`.

## Part 5: Evidence log

- **E1** (2026-11-24): `OverrideMap.rs`, `override_selector.rs`, `bun.lock.rs`, `Package.rs`,
  `CatalogMap.rs` fetched at `bun-v1.4.4` and compared with `cmp` to the copies the spec was
  written from: identical. Every line range in this file and in spec.md was read in the fetched
  copy; `put_rule` is L1022–L1069 (the spec's L1071 included the closing braces; corrected).
  Re-read after the analysis of `tasks.md` (2026-11-24): `is_selector_range` is L1081–L1087 and
  `lockfile_range` L1089–L1115, two functions (feature 006's `_lockfile_range` cites both as
  L1081–L1116); PKG's reading of the catalogs is L3418–L3440 (L3417 is blank); `not_an_object` is
  L1140–L1150; it prints `"<field>" expects a map of package names to versions`.
- **E2** (2026-11-24): bun.com `pm/overrides.md` and `pm/catalogs.md` fetched; the quotes in Part 1
  are from them.
- **E3** (2026-11-24): `gh run view 45040229326 --job 137262794310 --log`: lines 315–390 of the job
  log hold the failing attempt; the outer assertion's `Received` string shows
  `==================== Test output for //:source_test:\n====…====` with nothing between and
  `FAIL: //:source_test (Exit 1)`; the two other inner tests' logs are whole; the retry passed
  ("FLAKY, failed in 1 out of 2").
- **E4** (2026-11-24): `tw.cc` at Bazel tags 9.2.0, 9.3.0, 9.3.3 has no `TeeImpl::~TeeImpl`; at
  8.9.0, 10.0.0rc4, `release-9.4.0` and `master` it has (`master` L1516–L1532). `RunSubprocess` is
  identical on 9.2.0 and `master`. No tag `9.4.*` exists yet.

## Part 6: Findings and decisions during implementation

- **D1** (2026-11-24, T010; decided by the lead under the user's delegation): the pinned Bun wrote
  `conformance_override_selectors`' `"p-user > p": "1.0.0"` as the flat rule
  `"p-user > p": "1.0.0"`, not as `{"p-user": {"p": "1.0.0"}}` as R2 said. The cited function
  explains it: `pnpm_delimiter` (SELECTOR L72–L82) skips a `>` that follows a space, so the key is
  one Yarn path segment and `parse_package_segment` keeps the whole key as the name. R2's row was a
  misreading of SELECTOR L77, not a form outside BC-7 (whitespace around `>`, read as the pinned
  Bun's source reads it, under the planning approval), so R2 is corrected and no BC is added. The
  project keeps `"p-user > p"` and gains `"p-user> p"`, whose `>` is a delimiter and whose segments
  are trimmed (L85–L86), so both branches are pinned. The expectations of `"a > b"` in T016, T017
  and T026 follow the corrected row: the flat rule `"a > b"`.
- **D2** (2026-11-24, T012; decided by the lead under the user's delegation): R7's
  `conformance_resolution_comments` (`"resolutions": {"//": "comment", "b": "2.0.0"}`) passed the
  conformance test on `main`'s comparison: `normalize_overrides` splits a `resolutions` key with
  `split_key`, which reads `"//"` as three empty segments, and ignores it as a chain deeper than one
  parent. The form is therefore not one `main` fails on; FR-009 keeps such a form as a unit test, so
  the project is removed from the corpus (15 projects, 12 for US1) and `override_forms_test`
  (T017) holds `"//"` keys in `resolutions` among the cases passing on `main` too.
- **D3** (2026-11-25, T033; corrected 2026-11-25, T054): `compare_manifests` compares each named
  catalog of `catalogs` with `bun.lock`'s as one JSON object, as `main` does. T033 read this as
  making the order of its entries count, since Bun sorts each catalog before it writes `bun.lock`
  (LOCK L580–L583), and listed it as a follow-up. That was wrong: `json.encode` writes a dict's keys
  in sorted order, as bazel.build documents it (https://bazel.build/rules/lib/core/json: "A dict is
  encoded as a JSON object, in lexicographical key order"; seen on Bazel 9.2.0, 2026-11-25:
  `json.encode({"b": "1", "a": "2"})` is `{"a":"2","b":"1"}`), so `_difference` does not depend on entry order. `catalog_where_test`'s
  case `D3` pins it: a `workspaces` object listing `catalogs: {"g": {"q": …, "b": …}}` against a
  lockfile listing `{"g": {"b": …, "q": …}}` passes, and with one value changed its error prints
  the declared catalog as `{"b":"2.0.0","q":"1.0.0"}`, sorted. D3 is no follow-up (FR-007).
- **D4** (2026-11-25, the workflow's Claude review; decided by the lead under the user's
  delegation): of its five findings,
  1. the `translate_lock` doc naming the three CI runners stays: it states what holds at merge,
     and T052 makes the PR ready only once every job on those runners has passed;
  2. the inner test of `test_output_test` failed with `expect(process.env.MARKER).toBe("")`,
     which printed the marker again in Bun's `Received:` line, so a log that lost the marker line
     could still hold the marker; it now fails with `expect(size).toBe(0)`, and the outer test's
     name says what it checks ("holds", not "ends with") (T058);
  3. `test_output_test` failing on Windows with the inner Bazel 9.2.0 is the reproduction that
     T040–T042 run and T053 removes; no change;
  4. no canary pinned two of R4's cases against Bun. C-CATALOG gains a `workspaces` object holding
     only `catalogs` (only its catalogs are written) and a `workspaces` of `null`, which Bun 1.4.4
     refuses with `"workspaces" expects an array of strings` and installs nothing for
     (PKG L2863–L2879). The ruleset's `translate_lock` doc said "(of any value)"; it now says "an
     array or object (Bun installs nothing for any other value)", and R4 and
     `root_catalogs_test`'s comment say so; `root_catalogs` is unchanged (T057);
  5. D3 cited an observation where bazel.build documents `json.encode`'s key order; it cites both
     now (T059).

  The Codex review did not run: the Codex usage limit was reached until 2026-11-28 (T061).
- **D5** (2026-11-25, a second review run on Claude Fable 5.2 in place of the Codex review;
  decided by the lead under the user's delegation): it found no defect in the carried-over logic
  (each function checked against its cited lines, and 47 differential runs against Bun 1.4.4 agreed).
  Of its four findings:
  1. the `translate_lock` doc and `bun_override_map.bzl` said overrides are "compared as Bun's
     frozen install compares them"; R3 compares literals. Run by the lead with Bun 1.4.4: `^2.0.0`
     recorded and `^2.0` declared, `bun install --frozen-lockfile` exits 0 ("no changes") and
     `bun install` leaves `bun.lock` as it was, so the ruleset's error survives its own remedy.
     `main` compares literals too, and the fix is R3's follow-up (`Version::eql`'s npm group
     equality), a BC outside this feature's input; both texts now say what is compared and how to
     write such a range (T063);
  2. a catalog entry that `bun.lock` lacks fails, though Bun's frozen install skips one no
     workspace uses (PKG L1107–L1118, "skipped 1 catalog entry not in bun.lock"); `bun install`
     writes it, so the remedy works. As on `main`; the doc says so and it is a follow-up (T063);
  3. the top level's catalogs under a `workspaces` that holds neither key were pinned only in red:
     C-CATALOG gains a workspaces array and an object holding neither, green (T062);
  4. forms the unit tests read from Bun's source had no canary: C-OVERRIDES gains a parent or
     target range that is no selector range, a parent object with such a range, an alias target
     range, a later flat and a later scoped rule replacing an earlier one, child keys carrying a
     parent under an object, and a `patch:` value under a parent; Bun wrote each as the unit
     tests expect (T062).
- **D6** (2026-11-26, T040; decided by the lead under the user's delegation): the reproduction's first
  CI run (https://github.com/parkrevil/rules_bun/actions/runs/45814656477) did not reproduce R10's race: on Windows `output-root-with-space` with the inner
  Bazel 9.2.0, `test_output_test` passed 30 of 30. Its check was weaker than R10 needs. The race
  drops what is still in the pipe when the test exits, the tail of the log, but the marker was not
  the tail: Bun writes the failure report and its summary after it. T040's remedy is applied with two
  changes. The targets go from 8 to 16. `SIZE` stays 512 KiB, since the inner Bazel prints no log
  over `--experimental_ui_max_stdouterr_bytes` (1 MiB), which 2 MiB exceeds. Each target's log
  section must also end in Bun's last line (`Ran 1 test across 1 file.`), so a lost tail fails the
  test. A mutation that exits one target before Bun's summary fails it locally (`tdd-log.md`).
  If the next 30 runs still pass, R10's cause stays unproven by reproduction (FR-013), and US3 stops
  with that reported (FR-016).
