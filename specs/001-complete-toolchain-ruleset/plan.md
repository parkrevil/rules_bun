# Implementation Plan: Complete the Bun Toolchain Ruleset

**Branch**: `001-complete-toolchain-ruleset` | **Date**: 2026-09-29 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-complete-toolchain-ruleset/spec.md`

## Summary

Make `rules_bun` a complete, shell-free Bun toolchain ruleset aligned with
`bazel-contrib/rules-template@cb8787e` and the bazel.build toolchain, extension and repository-rule
pages, developed test-first. Concretely: give `e2e/smoke` a `diff_test` that checks the version
Bun reports from a toolchain-run action (R1) and an analysistest that requires `toolchain =`
(R2); delete the unreachable hardening helper and its shell
test (R3); drop the `hasattr` guards (R4) and deprecated `stripPrefix` (R9); move implementation
into `bun/private/` (R10); replace target-platform `cross_*` tests with
`analysistest`s that vary the execution platform (R5); build `bun` in the exec configuration (R6);
return `TemplateVariableInfo` with `BUN_BIN` (R7); and close the file-level divergences recorded in
[research.md](research.md) Part 2 (R8).

## Technical Context

**Language/Version**: Starlark on Bazel 9.2.0 (`bazel_compatibility = [">=9.2.0"]`)

**Primary Dependencies**: non-dev `platforms` 1.0.0, `package_metadata` 0.0.6 (unchanged);
dev `bazel_skylib` 1.9.2 (root and, new, `e2e/smoke`), `bazel_lib`, `gazelle`,
`bazel_skylib_gazelle_plugin`, `bazelrc-preset.bzl`

**Storage**: N/A

**Testing**: bazel-skylib `unittest`/`analysistest` (root), `diff_test` + `write_file`
(`e2e/smoke`), `//tools:preset.update_test`

**Target Platform**: execution platforms linux-x64, linux-aarch64, darwin-x64, darwin-aarch64,
windows-x64; CI on ubuntu-latest, macos-latest, windows-latest

**Project Type**: Bazel ruleset (library)

**Performance Goals**: N/A

**Constraints**: no `run_shell`, no authored scripts or launchers (VI); no feature detection (V);
no raise of non-dev `bazel_dep` versions (IV); English everywhere, diagnostics included (AGENTS.md);
test-first with recorded red/green (FR-009)

**Scale/Scope**: ~15 Starlark/BUILD files; public API unchanged except additions in
[contracts/public-api.md](contracts/public-api.md)

No NEEDS CLARIFICATION remains; research.md resolves every open point.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Pre-research | Post-design | Evidence |
|---|---|---|---|
| I. Public API boundary | FAIL (implementation in `bun/*.bzl`) → fixed by R10 | PASS | R10 moves implementation to `bun/private/` and re-exports; additions to `bun_toolchain` (exec cfg, `TemplateVariableInfo`) and a docstring; fixtures in `bun/tests/`, `e2e/smoke/`; no new public target. |
| II. Tested claims | PASS | PASS | Every behavior change has a test: R1, R2 (presence of `toolchain =` under `--incompatible_auto_exec_groups`), R5–R7, versions test. Claims no test covers are reported as such: the `toolchain =` value (R2) and genrule inputs (R7). Platforms are reported per actual run. |
| III. Pinned, verified downloads | PASS | PASS | Download path unchanged; versions test adds coverage of `TOOL_VERSIONS`. |
| IV. Minimum dependency versions | PASS | PASS | No non-dev `bazel_dep` changes; `e2e/smoke` adds only a dev `bazel_skylib`. |
| V. Supported APIs only | FAIL (existing `hasattr`, deprecated `stripPrefix`) → fixed by R4, R9 | PASS | Every API in R1–R10 is documented and sourced; no canonical-repo-name or output-dir-name reliance (R5, R6); undocumented genrule inputs are not asserted (R7 gap). |
| VI. Shell-free actions and tests | FAIL (existing `hardening_test`) → fixed by R3 | PASS | R3 deletes the only `run_shell` and authored launcher; `diff_test` launchers are skylib's; the R7 genrule is `manual` and only analyzed. |
| VII. Releases from tags | PASS | PASS | No `version`, no release changes; `cfg = "exec"` is not breaking (R6). |

All pre-research failures are the defects this feature exists to fix; no violation remains after
design, so Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/001-complete-toolchain-ruleset/
├── spec.md
├── plan.md              # this file
├── research.md          # decisions R1–R8, divergence register
├── data-model.md        # providers, attributes, repositories, fixtures, records
├── quickstart.md        # validation commands
├── contracts/
│   └── public-api.md
├── checklists/requirements.md
├── tdd-log.md           # written during /speckit-implement (FR-009 records)
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
MODULE.bazel                         # dev use_repo adds bun_<platform> repos for R5
bun/
├── defs.bzl                         # docstring shows toolchain = BUN_TOOLCHAIN_TYPE
├── toolchain.bzl, repositories.bzl, extensions.bzl   # docstrings + re-exports only (R10)
├── private/
│   ├── BUILD.bazel                  # drop action/hardening/paths/platforms libraries
│   ├── toolchains_repo.bzl          # holds PLATFORMS; no hasattr
│   ├── toolchain.bzl                # new (R10): cfg = "exec"; TemplateVariableInfo(BUN_BIN)
│   ├── repositories.bzl             # new (R10): no hasattr; strip_prefix; PLATFORMS from toolchains_repo.bzl
│   ├── extensions.bzl               # new (R10): extension and tag class
│   ├── providers.bzl, semver.bzl, versions.bzl   # unchanged
│   └── (deleted) action.bzl, hardening.bzl, paths.bzl, platforms.bzl
└── tests/
    ├── BUILD.bazel                  # selection, exec-cfg, BUN_BIN, versions, semver tests
    ├── toolchain_test.bzl           # new: R5, R6, R7 fixtures and analysistests
    ├── versions_test.bzl            # new
    ├── semver_test.bzl              # unchanged
    ├── platforms/BUILD.bazel        # five literal platforms (not derived from PLATFORMS)
    └── (deleted) action_test.bzl, hardening_test.bzl, platform_transition.bzl
e2e/smoke/
├── MODULE.bazel                     # no module(); dev bazel_deps; + bazel_skylib
├── MODULE.bazel.lock                # refreshed
├── BUILD.bazel                      # write_file + diff_test + AEG analysistest
├── verify_test.bzl                  # new: analysistest with incompatible_auto_exec_groups
└── verify.bzl                       # toolchain = BUN_TOOLCHAIN_TYPE
(tools/ unchanged: research Part 2 row 45)
```

**Structure Decision**: Keep the baseline's layout (`bun/` ↔ `mylang/`, `bun/private/`,
`bun/tests/`, `bun/toolchain/`, `e2e/smoke/`, `tools/`). New test code goes in one
`toolchain_test.bzl` plus a baseline-named `versions_test.bzl`.

## Implementation Order

Dependencies drive the order; tasks.md is authoritative. Each step's red/green record goes to
`tdd-log.md`.

1. **Setup, foundational** — record the starting state; five literal test platforms; dev
   `use_repo` of the platform repositories.
2. **US1 / R1–R2** — e2e AEG analysistest (red: "Please set the toolchain parameter"), then
   `toolchain =`; e2e `diff_test` (red by mutation, literal `0.0.0`); `defs.bzl` docstring.
3. **US3 / R5, R6** — per-execution-platform selection tests (red by mutation of `PLATFORMS` in
   `bun/private/platforms.bzl`, where it lives at this step); exec-cfg test, then `cfg = "exec"`.
   Must land before step 4.
4. **US2 / R3** — delete hardening helper, `cross_*`, `with_platform`, `platform_transition`
   (deletion record).
5. **US4 refactors / R4, R9, R10, R8** — remove `hasattr`, `strip_prefix`, move implementation to
   `bun/private/`, move `PLATFORMS`, align e2e `MODULE.bazel` (refactor records).
6. **US4 / R7** — `BUN_BIN` value and genrule tests (red: `$(BUN_BIN) not defined`), then
   `TemplateVariableInfo`; `versions_test` (red by mutation); divergence register.
7. Hand-back checks from AGENTS.md; adversarial review; push; record CI per OS.

## Risks

- **Windows host**: `BUN_BIN` expansion in `cmd_bat` (backslash paths, per the genrule page) and
  running on a Windows host (`bun.exe`, `.bat` launchers) are verified only by Windows CI.
- **diff_test message on Windows (R1)**: `failure_message` must avoid `( ) ! % ^ & | < >`.
- **Reported gaps**: genrule inputs from a toolchain type (R7) and the `toolchain =` value (R2).
- **Test-first for existing behavior (R1, R5, versions test)**: these tests guard behavior that
  already works, so their red is a recorded, reverted mutation, as the spec's edge case requires.
- **CI cost (R5)**: analysis fetches all five Bun archives on every job.

## Complexity Tracking

None.
