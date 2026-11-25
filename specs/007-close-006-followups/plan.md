# Implementation Plan: Close Feature 006's Follow-ups

**Branch**: `007-close-006-followups` (from `main` at `1bff1cf`) | **Date**: 2026-11-24 |
**Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/007-close-006-followups/spec.md`

## Summary

US1/US2: the `npm` extension stops rewriting the root `package.json`'s overrides into the JSON shape
`bun.lock` is written in. It carries over the `package.json` side of Bun 1.4.4's `OverrideMap` and
the whole selector parser into a new `bun/private/bun_override_map.bzl`, builds the same rule set
the lockfile loader of feature 006 already builds from `bun.lock`, and compares the two with Bun's
`OverrideMap::changed`, as the pinned Bun's frozen install does (research R1–R3). Every form of
FR-001 to FR-005 then follows from Bun's functions, and planning found two more forms that `main`
compares otherwise (BC-7: one selector parser for both fields; BC-8: a flat rule folded into a
group as `"."`), added to the spec. The root's catalogs are read where Bun reads them (Package.rs
L3418–L3440) and only their string entries (R4). Sixteen corpus projects, one per Bun branch, are
run red on `main`'s comparison first (R7); the C-OVERRIDES and C-CATALOG canaries gain the forms now relied on
(R8).

US3: the cause of `source_node_modules_test`'s Windows failure is not in the ruleset, Bun, or the
test: Bazel 9.2.0's Windows test wrapper drops the output still in its pipe when a test exits, and
the inner `//:source_test` writes all of its output just before it exits. Bazel fixed it in
bazelbuild/bazel#32203 (in 8.9.0, 10.0.0rc4, and `release-9.4.0`), not in any 9.x release yet
(R10). A Bazel-in-Bazel reproduction with the ruleset's `bun_test` is recorded failing on Windows;
the fix pins the integration tests' dev-only inner Bazel to 9.4.0. Until 9.4.0 is released, FR-016
holds US3 at the reproduction and the report.

## Technical Context

**Language/Version**: Starlark on Bazel 9.2.0 (`bazel_compatibility = [">=9.2.0"]`, `.bazelversion`);
TypeScript run by Bun 1.4.4 (conformance test, canaries, corpus writer, integration tests); Bun 1.4.2
as the second oracle only

**Primary Dependencies**: no `bazel_dep` change. Specification: oven-sh/bun at `bun-v1.4.4`
(`OverrideMap.rs`, `override_selector.rs`, `bun.lock.rs`, `Package.rs`, `CatalogMap.rs`,
`dependency.rs`) under the user's approval of 2026-11-24 (spec, research Part 1). US3: Bazel's
`tools/test/windows/tw.cc` at 9.2.0 and bazelbuild/bazel#32203; the dev-only `integration_bazel_*`
`http_file`s move to 9.4.0 once released

**Storage**: N/A

**Testing**: skylib `unittest` (`bun/tests/npm/bun_override_map_test.bzl` NEW, `compare_test.bzl`,
`bun_package_test.bzl`); the conformance `bun_test` and its 1.4.2 variant fed by
`@npm_fixture_results`; the canaries `c_overrides_test` and `c_catalog_test`; `citations_test`; Bazel-in-Bazel
`test_output_test` (NEW) and `source_node_modules_test`; `e2e/smoke`; CI on `ubuntu-latest`,
`macos-latest`, `windows-latest`

**Target Platform**: as `main` (linux-x64, linux-aarch64 glibc/musl, darwin-x64, darwin-aarch64,
windows-x64); CI runners as above

**Project Type**: Bazel ruleset (library)

**Performance Goals**: no new bound; the comparison is linear in the number of rules and catalog
entries; `scale_test`'s bound (R13 of feature 006) keeps holding

**Constraints**: Bun's functions, not shapes (P1); pinned Bun as oracle (P2); no public API change
(P4, constitution I); no retry, `flaky` or weakened assertion (FR-015); a cause in Bazel with no
supported avoidance stops US3 (FR-016, constitution V); shell-free (VI); English; test-first
(`tdd-log.md`: every corpus project red before the change, the reproduction red before the fix)

**Scale/Scope**: ~600–800 lines of Starlark in `bun_override_map.bzl` (selector parser, both
`OverrideMap` sides, `changed`/`sort`), with three helpers moved from `bun_lockfile.bzl` and its `_dependency` moved to
`bun_install_types.bzl` as `new_dependency`;
`bun_package.bzl` (`root_catalogs`), new `bun_catalog_map.bzl` (`catalog_parse_append` and the
three `CatalogMap` helpers moved from `bun_lockfile.bzl`, research R5),
`workspaces.bzl` (`compare_manifests`), `overrides.bzl` deleted, `npm_extension.bzl` (docs);
15 corpus projects (16 planned; research D2) and their 1.4.4 (and where possible 1.4.2) lockfiles; two canaries extended (C-OVERRIDES, C-CATALOG); one
new integration test and inner workspace; `update.ts`, `MODULE.bazel`'s integration region and
`bun/tests/integration/registry/` regenerated for 9.4.0

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Public API Boundary | No rule, attribute, tag, generated target or `.bzl` symbol changes; new code in `bun/private/`, tests in `bun/tests/` ([contracts/public-api.md](contracts/public-api.md)) | PASS |
| II. Tested Claims | Each BC-1…BC-8 has a corpus project, red before and 0 differences after, on the three CI runners; stale variants in `compare_test.bzl`; docs claim only those forms and name the runners (R11); US3's claim rests on the reproduction's measured runs | PASS |
| III. Pinned, Verified Downloads | US1/US2 add no download; the 9.4.0 inner Bazel is a dev-only `http_file` with the release's `.sha256` integrity, generated by `update.ts` as today | PASS |
| IV. Minimum Dependency Versions | No `bazel_dep` change; `bazel_compatibility`, `.bazelversion` and `e2e/smoke` stay at 9.2.0 | PASS |
| V. Supported APIs Only | Bun's source for forms bun.com does not describe, under the user's approval of 2026-11-24, recorded per form (research Part 1); no new `bun.lock` field is read, and the forms now relied on are added to C-OVERRIDES and C-CATALOG with their red modes (FR-011); US3 adopts Bazel's own fix in a release instead of working around it, and stops if none is released (FR-016) | PASS |
| VI. Shell-Free Actions | No new action; tests are `bun_test` and skylib `unittest` | PASS |
| VII. Releases Come From Tags | No release step; no rules_bun version is published, so BC-1…BC-8 change no released behavior | PASS |

No violation. Post-design re-check (after Phase 1): unchanged. The inner Bazel's move to 9.4.0
trades the integration tests' minimum-version coverage for a test log that keeps its end; the
minimum stays covered by `e2e/smoke` and the BCR presubmit (research R10).

## Project Structure

### Documentation (this feature)

```text
specs/007-close-006-followups/
├── plan.md              # This file
├── research.md          # Phase 0: sources, approval per form, R1–R11, planning findings
├── data-model.md        # Phase 1: selector, OverrideMap, CatalogMap as carried over; corpus; repro
├── quickstart.md        # Phase 1: validation runs V1–V9
├── contracts/
│   └── public-api.md    # what consumers observe (evaluation per form, errors, docs)
├── tdd-log.md           # implementation: each red before its change
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
bun/private/
├── bun_override_map.bzl      # NEW  override_selector.rs; OverrideMap.rs: parse_append (package.json),
│                             #      put_lockfile_rule/push_scoped (moved), changed, sort, $<name>
├── bun_catalog_map.bzl       # NEW  CatalogMap.rs: catalog_parse_append; catalog_find, catalogs_resolve_range,
│                             #      catalog_strip_reference (moved from bun_lockfile.bzl; no load cycle, R5)
├── bun_lockfile.bzl          # _parse_overrides and the lockfile's catalogs load the moved helpers
├── bun_install_types.bzl     # new_dependency (resolver_hooks.rs), moved from bun_lockfile.bzl's _dependency
├── bun_package.bzl           # root_catalogs (Package.rs L3418–L3440)
├── workspaces.bzl            # compare_manifests: rule sets and Bun's catalogs; manifest_catalogs removed
├── overrides.bzl             # DELETED
├── npm_extension.bzl         # translate_lock doc, _NPM_DOC (R11)
└── BUILD.bazel               # bzl_library targets (gazelle)

bun/tests/
├── npm/
│   ├── bun_override_map_test.bzl          # NEW, replaces overrides_test.bzl
│   ├── compare_test.bzl, bun_package_test.bzl
│   ├── fixtures/conformance_override_*/, conformance_resolution_*/, conformance_catalog_*/   # NEW (R7)
│   ├── registry/write_lockfiles.ts        # the 15 projects and their checks
│   └── conformance/
│       ├── bun_1_4_2/<project>/           # NEW where Bun 1.4.2 writes them
│       ├── not_applicable_1_4_2.ts        # the others, with reasons
│       └── citations.test.ts              # MODULES += bun_override_map, bun_catalog_map, bun_package
├── canary/npm/c_overrides.test.ts         # new cases (R8)
├── canary/npm/c_catalog.test.ts           # three new tests with red modes (R8, FR-011)
└── integration/
    ├── test_output.test.ts                # NEW reproduction (R10)
    ├── workspaces/test_output/            # NEW inner workspace
    ├── BUILD.bazel                        # test_output_test
    └── registry/update.ts, modules/, archives.bzl   # BAZEL_VERSION 9.4.0, regenerated

MODULE.bazel                  # integration region regenerated (integration_bazel_* 9.4.0)
.github/workflows/ci.yaml     # temporary --runs_per_test=30 step for SC-003, removed before merge
```

**Structure Decision**: existing layout (constitution I); the carry-over follows feature 006 R1, one
Starlark file per Bun source file with each function citing its lines, so `citations_test` covers
FR-008.

## Phases after this plan

1. **US1/US2 red**: the 15 corpus projects (research D2) written by the pinned Bun (and Bun 1.4.2), on `main`'s
   comparison; the conformance test fails on each (V1); `tdd-log.md` rows. The new unit tests are
   written against stubs and seen failing.
2. **US1/US2 green**: selector parser → `package.json` side of `OverrideMap` → `changed`/`sort` →
   catalogs → `compare_manifests` → docs; canary; V3–V5.
3. **US3**: reproduction test and inner workspace; red on Windows CI (V6, a push the user approves);
   if Bazel 9.4.0 is released, `update.ts` to 9.4.0 and V7; else stop per FR-016 and report.
4. Gates (V8, V9) and the PR with the BC table, the 1.4.2 list, and US3's outcome.

## Decisions taken in planning

- **BC-7, BC-8, BC-6's second half** (research Part 3): forms found in the cited functions, which
  `main` compares otherwise; added to the spec's Behavior Changes and FR-009 before any change
  (FR-012), each with a corpus project.
- **R3 literal equality**: Bun's semantic npm-range equality is not carried over; `main` compares
  literals everywhere, so nothing changes; listed as a follow-up.
- **US3 fix**: the integration tests' inner Bazel goes to 9.4.0 (not `.bazelversion`, not 10.0.0rc);
  gated on 9.4.0's release (FR-016).

## Complexity Tracking

No constitution violation to justify.
