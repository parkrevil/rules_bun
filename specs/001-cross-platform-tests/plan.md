# Implementation Plan: Tests that run on every supported platform

**Branch**: `001-cross-platform-tests` | **Date**: 2026-09-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-cross-platform-tests/spec.md`

## Summary

Make every check in the repository executable on Linux, macOS, and Windows, and remove the one
remaining fallback for an unsupported Bazel version.

`//bun/tests:hardening_test` becomes a macro: a probe rule runs Bun through `ctx.actions.run`, Bun
spawns a child process in the hostile directory and reports what leaked as JSON, `write_file`
writes the expected JSON, and `diff_test` compares them — no shell anywhere. `e2e/smoke` gains
`build_test`, which gives its `bazel test //...` a target to run. The two `hasattr` guards around
`repository_ctx.repo_metadata` are deleted.

## Technical Context

**Language/Version**: Starlark for Bazel 9.2.0 (`bazel_compatibility = [">=9.2.0"]`); JavaScript run
by Bun 1.4.2

**Primary Dependencies**: `bazel_skylib` 1.9.2 (`diff_test`, `write_file`, `build_test`) as a dev
dependency in the root module, newly as a dev dependency in `e2e/smoke`

**Storage**: N/A

**Testing**: `bazel test //...` in the root module and in `e2e/smoke`

**Target Platform**: Linux x86_64, macOS arm64, Windows x86_64 (the CI matrix); the BCR presubmit
adds debian11 and ubuntu2204

**Project Type**: Bazel ruleset

**Performance Goals**: N/A

**Constraints**: No Bash anywhere in the test path; no change to the public API, the pinned Bun
version, or the hardening flags

**Scale/Scope**: Three source areas — `bun/tests/`, `bun/private/` + `bun/repositories.bzl`, and
`e2e/smoke/`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution v1.0.0. The feature exists to restore compliance, so every principle is a gate here.

| Principle | Gate | Verdict |
|-----------|------|---------|
| I. Public API Boundary | No change to `bun/*.bzl` or `//bun/toolchain:execution_type`; test code stays in `bun/tests/` and `e2e/smoke/` | PASS — `bun/private/paths.bzl` is deleted, which is implementation, not public API |
| II. Tested Claims | Every behavior change is covered by a test, and platform claims name where the test ran | PASS — the changes are tests; `hardening_test` and `smoke_test` run on all three CI platforms, Windows only via CI |
| III. Pinned, Verified Downloads | No change to fetching; the probe runs Bun from the registered toolchain | PASS |
| IV. Minimum Dependency Versions | `e2e/smoke` must not raise the minimums it validates | PASS — `bazel_skylib` is added as a dev dependency and its own deps (`platforms` 0.0.10, `rules_license` 1.0.0) are below what Bazel 9.2.0 resolves anyway; see research.md (c) |
| V. Supported APIs Only | Documented, non-deprecated APIs only; sources in research.md; no feature detection for APIs Bazel 9.2.0 has | PASS — rules out a relative `--cwd`, and removes both `hasattr` guards |
| VI. Shell-Free Actions and Tests | No `run_shell`, no generated shell script, no shell launcher | PASS — `ctx.actions.run` for the probe, skylib rules for the launchers |

Re-check after Phase 1 design: unchanged, all PASS.

## Project Structure

### Documentation (this feature)

```text
specs/001-cross-platform-tests/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── quickstart.md        # Phase 1 output
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

`data-model.md` and `contracts/` are not produced: the feature adds no entities and changes no
interface the ruleset exposes (FR-007).

### Source Code (repository root)

```text
bun/
├── repositories.bzl          # drop the hasattr guard
├── private/
│   ├── toolchains_repo.bzl   # drop the hasattr guard
│   ├── paths.bzl             # deleted with the runfiles launcher it served
│   └── BUILD.bazel           # gazelle drops the paths bzl_library
└── tests/
    ├── hardening_test.bzl    # probe rule + macro, no shell
    └── BUILD.bazel           # unchanged: hardening_test(name = "hardening_test")

e2e/smoke/
├── MODULE.bazel              # add bazel_skylib as a dev dependency
├── MODULE.bazel.lock         # regenerated
└── BUILD.bazel               # add build_test over :verify
```

**Structure Decision**: The existing layout is kept. Public API (`bun/*.bzl`), implementation
(`bun/private/`), and tests (`bun/tests/`, `e2e/smoke/`) stay where the constitution puts them.
