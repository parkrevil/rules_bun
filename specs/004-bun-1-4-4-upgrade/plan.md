# Implementation Plan: Upgrade the Pinned Bun to 1.4.4

**Branch**: `003-npm-dependencies` (planned on `004-bun-1-4-4-upgrade`; implemented and committed on
`003-npm-dependencies` so PR #5's CI runs it, spec Assumptions) | **Date**: 2026-10-26 |
**Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/004-bun-1-4-4-upgrade/spec.md`

**Status**: implemented on 2026-10-27, Linux x64 only; CI on macOS and Windows not yet run. G4 is
resolved by R11 (libc read, public constraint, constitution v2.3.0), G5 by R12, G6 by R13. G1, G2
stay reported for the next feature.

## Summary

Add Bun 1.4.4 to `TOOL_VERSIONS` next to 1.4.2, with the five platform integrities converted from
the release's `SHASUMS256.txt` (research R1, R2), and make 1.4.4 the version the development
toolchain, `e2e/smoke`, every nested Bazel-in-Bazel workspace and the vendored archives of the
loopback registry use (R4). 1.4.4 contains oven-sh/bun `e6f65f33c7`, which runs `bun patch
--commit`'s `git diff --no-index` with `GIT_DIR` set to the null device (R3), so C-PATCHED passes in
the unsandboxed CI jobs with no test-side workaround (FR-009). Then run every FR-028 canary and every
`bun.lock` canary against 1.4.4 and resolve each red one by constitution II and V (R6); the source of
1.4.4 predicts exactly one red: C-TD, because 1.4.4 now writes an empty `trustedDependencies` (R5).
Regenerate every fixture the pinned Bun wrote with the existing scripts, committed as written (R8),
and rewrite every statement of Bun behavior that names 1.4.2 so it names 1.4.4 and is true of it
(R9). No public symbol is added or changed (contract).

## Technical Context

**Language/Version**: Starlark on Bazel 9.2.0 (`bazel_compatibility = [">=9.2.0"]`); JavaScript and
TypeScript run by Bun 1.4.4 (launcher, test helpers, canaries, fixture scripts)

**Primary Dependencies**: no change to any `bazel_dep`. Dev-only `http_file` repositories for the
five Bun 1.4.4 release archives replace the 1.4.2 ones (written by `update.ts`, R4)

**Storage**: N/A

**Testing**: existing suites only: skylib `unittest` (`versions_test` gains the FR-003 check that
1.4.2 and 1.4.4 are both known), `bun_test` real runs, FR-028 canaries (`bun/tests/canary/`),
`bun.lock` canaries (`bun/tests/canary/npm/`, red mode `RULES_BUN_CANARY_RED=1`), Bazel-in-Bazel
integration tests, `e2e/smoke` (`version_test` expects `1.4.4`), CI jobs `test`, `network-denied`,
`manifest-only`, `windows-symlinks`, `windows-without-bash`, `output-root-with-space`,
`windows-disk-cache`, `coverage`, `mod-compare`

**Target Platform**: linux-x64, linux-aarch64, darwin-x64, darwin-aarch64, windows-x64; CI on
ubuntu-latest, macos-latest, windows-latest

**Project Type**: Bazel ruleset (library)

**Performance Goals**: SC-010 of feature 003 stays within its bounds with the regenerated scale
fixture (re-measured only if `scale_test` fails)

**Constraints**: integrities only from the official `SHASUMS256.txt` (III; spec Edge Cases);
fixtures exactly as Bun 1.4.4 wrote them (FR-007); no new lockfile access (FR-008, research G1, G2);
non-Bun `1.4.2` strings unchanged (FR-010); English everywhere

**Scale/Scope**: about 45 files: `versions.bzl`, `MODULE.bazel` (dev toolchain and five
`http_file`s), `archives.bzl`, `update.ts`, nine nested `MODULE.bazel` files, `e2e/smoke`
(`MODULE.bazel`, `BUILD.bazel`, `bun.lock`), eleven files with Bun-behavior statements (R9), C-TD
and its `BUILD` target, the run-test archive, and the regenerated fixtures (about 25 `bun.lock`
files, the npm fixture archives, the scale fixture, two inline lockfiles)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public API Boundary | No symbol added, removed or renamed (contract). The changes are an entry in `bun/private/versions.bzl`, doc strings and diagnostics. | Pass |
| II. Tested Claims | Each changed statement is covered: 1.4.4 fetch and version by `e2e/smoke` `version_test` and the nested workspaces; both known versions by `versions_test`; every canary run against 1.4.4; the C-TD resolution recorded with its evidence (R6). Claims of platforms name the CI jobs that actually ran (quickstart Q7). The 1.4.2 entry is no longer fetched by any test; research G3 reports it. | Pass |
| III. Pinned, Verified Downloads | Integrity converted from `SHASUMS256.txt` of tag `bun-v1.4.4`, not from a local download (R1). The vendored archives are fetched by `http_file` with the same integrity. | Pass |
| IV. Minimum Dependency Versions | No `bazel_dep` changes. | Pass |
| V. Supported APIs Only | The readers rely on no new key (G1, G2 reported instead of worked around). Every remaining reliance on undocumented Bun output keeps a canary run against 1.4.4; the C-TD reliance becomes documented behavior (`docs/pm/lifecycle`) and its canary goes (R6). Sources in research Part 4. | Pass |
| VI. Shell-Free Actions | No action or launcher change. | Pass |
| VII. Releases Come From Tags | No `version` in `MODULE.bazel`; the version-bump decision for the release that ships this is the user's. 1.4.2 stays known (FR-003), so no consumer build breaks. | Pass |

Post-design re-check (after Phase 1): unchanged, all pass. Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/004-bun-1-4-4-upgrade/
├── plan.md              # This file
├── research.md          # Phase 0: decisions R1–R10, gaps G1–G3, evidence, sources
├── data-model.md        # Phase 1: known version, vendored archive, canary, fixture, statement
├── quickstart.md        # Phase 1: validation scenarios Q1–Q7
├── contracts/
│   └── public-api.md    # Phase 1: public API unchanged; user-visible text that changes
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root, on `003-npm-dependencies`)

```text
MODULE.bazel                                   # bun_dev.toolchain 1.4.4; integration_bun-* http_file (update.ts region)
bun/
├── extensions.bzl                             # example bun_version
├── private/
│   ├── versions.bzl                           # + "1.4.4" (R1, R2)
│   ├── extensions.bzl, providers.bzl, toolchain.bzl   # examples of a version string
│   ├── lockfile.bzl                           # FR-007 diagnostic names 1.4.4
│   ├── run.bzl, launcher.js                   # Bun-behavior statements (R7, R9); trustedDependencies sentence (R6)
│   ├── check_integrity.js, npm_extension.bzl, workspaces.bzl   # Bun-behavior statements (R9)
└── tests/
    ├── versions_test.bzl                      # both versions known (FR-003)
    ├── canary/c13_regexp_limit.test.ts        # header names 1.4.4
    ├── canary/npm/                            # headers; C-TD removed if red as predicted (R6)
    ├── integration/
    │   ├── registry/{archives.bzl,update.ts}  # vendored 1.4.4 archives (R4)
    │   ├── workspaces/*/MODULE.bazel          # nine nested workspaces request 1.4.4
    │   ├── credentials.test.ts, registries.test.ts   # inline lockfiles regenerated (R8)
    │   └── lockfile_errors.test.ts            # expects the 1.4.4 diagnostic
    ├── npm/
    │   ├── registry/{archives,pack.ts,write_lockfiles.ts}   # rerun (R8)
    │   ├── fixtures/*/bun.lock                # regenerated (R8)
    │   ├── scale/{bun.lock,package.json}      # regenerated by generate.ts (R8)
    │   └── workspaces/, workspaces_test.bzl   # statements name 1.4.4
    └── run/
        ├── args/args.test.ts                  # expected message names 1.4.4 (R7)
        ├── isolation/registry/*.tgz           # re-packed by 1.4.4 (R8)
        └── protocol/coverage/chdir.test.ts    # statement names 1.4.4
e2e/smoke/
├── MODULE.bazel                               # bun_version 1.4.4
├── BUILD.bazel                                # expected_version 1.4.4
└── bun.lock                                   # re-saved by 1.4.4 (R8)
```

**Structure Decision**: no new file or directory. Every edit is in a file the inventory above names;
regenerated files come only from the scripts that already own them (`pack.ts`,
`write_lockfiles.ts`, `scale/generate.ts`, `update.ts`) or from `bun install` / `bun pm pack` run
by Bun 1.4.4 (R8).

## Implementation Order

1. Work on `003-npm-dependencies`, where `specs/004-bun-1-4-4-upgrade/` already is (R10).
2. `versions.bzl` + `versions_test` (FR-001, FR-003), then the dev toolchain and `e2e/smoke`
   version (FR-002); `bazel test //bun/tests:versions` and `e2e/smoke` `version_test`.
3. Canaries first, before any fixture changes, so their result is against unchanged fixtures:
   run `//bun/tests/canary/...` with 1.4.4, sandboxed and with the `manifest-only` flags; record
   each result in research Part 3; resolve red ones (R6).
4. Fixtures (R8) in dependency order: run-test archive and `pack.ts` → `write_lockfiles.ts` →
   `scale/generate.ts` → inline lockfiles → `e2e/smoke/bun.lock`.
5. `update.ts` fix and rerun (R4); nested workspaces to 1.4.4.
6. Statements (R7, R9): verify the R7 behaviors against 1.4.4 first, then edit text.
7. Gates (AGENTS.md): root `bazel run //:gazelle`, `prek run --all-files`, `bazel test //...`;
   `e2e/smoke` `bazel test //...`; the repository search of SC-004 (quickstart Q6); push and
   watch PR #5 CI (Q7).

## Complexity Tracking

No violations.
