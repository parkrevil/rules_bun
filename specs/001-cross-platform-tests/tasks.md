# Tasks: Tests that run on every supported platform

**Input**: Design documents from `specs/001-cross-platform-tests/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[quickstart.md](./quickstart.md)

**Tests**: Mandatory here. Constitution II requires a test for every behavior change, and this
feature's deliverables are themselves tests, so each story's test lands together with the change it
covers.

**Organization**: One phase per user story. The stories touch disjoint files and can be done in any
order.

## Phase 1: User Story 1 - A consumer's platform is covered by the smoke check (Priority: P1)

**Goal**: `bazel test //...` in `e2e/smoke` runs a check instead of failing with "no test targets".

**Independent test**: In `e2e/smoke`, `bazel test //...` reports one executed test and exits 0.

- [ ] T001 [US1] Add `bazel_dep(name = "bazel_skylib", version = "1.9.2", dev_dependency = True)` to `e2e/smoke/MODULE.bazel`
- [ ] T002 [US1] Add `build_test(name = "smoke_test", targets = [":verify"])` and its `load("@bazel_skylib//rules:build_test.bzl", "build_test")` to `e2e/smoke/BUILD.bazel`
- [ ] T003 [US1] Run `bazel test //...` in `e2e/smoke` to regenerate `e2e/smoke/MODULE.bazel.lock`, confirm `//:smoke_test` passes, and confirm the `//...` pattern in `.bcr/presubmit.yml` now resolves to it (FR-002)

## Phase 2: User Story 2 - The hardening guarantee is checked on every supported platform (Priority: P2)

**Goal**: The hardening check runs without a shell, so Windows executes it too, and it still fails
when the protection is lost.

**Independent test**: `bazel test //bun/tests:hardening_test` passes with no `.sh` in the test
action graph, and fails when the hardening flags are emptied.

- [ ] T004 [US2] Replace the `run_shell` probe in `bun/tests/hardening_test.bzl` with a `ctx.actions.run` rule whose Bun process spawns a child Bun in the hostile directory via `Bun.spawnSync`'s `cwd` option and writes the child's JSON observation to the rule's output
- [ ] T005 [US2] In `bun/tests/hardening_test.bzl`, replace the `.sh` launcher with a `hardening_test` macro wiring the probe, `write_file(newline = "unix")` for the expected JSON, and `diff_test`, keeping `//bun/tests:hardening_test` as the test label and `bun/tests/BUILD.bazel` unchanged
- [ ] T006 [US2] Delete `bun/private/paths.bzl`, whose `runfiles_path` existed only for the removed launcher
- [ ] T007 [US2] Verify non-vacuity per [quickstart.md](./quickstart.md) §3: temporarily return `[]` from `hardening_args` in `bun/private/hardening.bzl`, confirm `//bun/tests:hardening_test` fails with `{"poisoned":true,"port":"9999"}`, then restore the file and verify the restore with `git diff --quiet bun/private/hardening.bzl`

## Phase 3: User Story 3 - The ruleset carries no fallback for unsupported Bazel versions (Priority: P3)

**Goal**: Repository rules return their reproducibility metadata directly.

**Independent test**: `grep -rn hasattr bun/` finds nothing and a toolchain still fetches.

- [ ] T008 [P] [US3] Remove the `hasattr(repository_ctx, "repo_metadata")` guard in `bun/repositories.bzl`, returning `repository_ctx.repo_metadata(reproducible = True)` directly
- [ ] T009 [P] [US3] Remove the same guard in `bun/private/toolchains_repo.bzl`
- [ ] T010 [US3] Refetch the toolchain repositories with `bazel build //...` in the root and confirm they fetch without error

## Phase 4: Polish

- [ ] T011 Run `bazel run //:gazelle` in the root so `bun/private/BUILD.bazel` drops the `paths` `bzl_library`
- [ ] T012 Run `prek run --all-files` in the root
- [ ] T013 Run `bazel test //...` in the root and in `e2e/smoke`, and report which platform the run covered
- [ ] T014 Report SC-001 as pending: the six CI jobs can only be observed after the branch is pushed

## Dependencies

- The three stories are independent: US1 touches `e2e/smoke/`, US2 touches `bun/tests/` and
  `bun/private/paths.bzl`, US3 touches `bun/repositories.bzl` and
  `bun/private/toolchains_repo.bzl`.
- Within US2: T004 → T005 → T007; T006 after T005.
- Phase 4 runs after every story, and T011 depends on T006.

## Parallel Opportunities

- T008 and T009 are separate files with no shared state.
- The three story phases can proceed in parallel if worked by separate agents.

## Implementation Strategy

MVP is User Story 1: it unblocks CI's `e2e/smoke` jobs on all three platforms and the BCR
presubmit. User Story 2 then unblocks the Windows root job. User Story 3 is a compliance cleanup
with no CI effect.
