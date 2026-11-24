# Quickstart: Validating Feature 007

**Feature**: `007-close-006-followups` | **Spec**: [spec.md](spec.md) | **Contract**:
[contracts/public-api.md](contracts/public-api.md) | **Research**: [research.md](research.md)

Prerequisites: a checkout of branch `007-close-006-followups`, Bazel per `.bazelversion`. No test
needs network (the registry is loopback). Writing corpus lockfiles (V2) runs the pinned Bun by hand,
as `bun/tests/npm/registry/write_lockfiles.ts` documents.

## V1. Red first (FR-009, SC-001)

With the corpus projects of research R7 added and `bun/private/` as on `main`:

```sh
bazel test //bun/tests/npm/conformance:conformance_test --test_output=errors
```

Expected: FAIL, with one difference per new project, each the ruleset's evaluation error (for
example `conformance_override_target_range: the ruleset fails (…overrides "b@^1.0.0"…), Bun
installs the lockfile`) and none on any other project. Each is a `tdd-log.md` row.

## V2. Lockfiles the pinned Bun writes (FR-009, FR-010)

```sh
"$(bazel info output_base)/external/+bun+bun_linux-x64/bun" bun/tests/npm/registry/write_lockfiles.ts <project>...
"$(bazel info output_base)/external/+bun+bun_1_4_2_linux-x64/bun" bun/tests/npm/registry/write_lockfiles.ts --bun-1-4-2 <project>...
```

Expected: each project's `check` passes (the `overrides`/`catalog`/`catalogs` written are those of
research R2/R7); for 1.4.2, the lockfile is written or the project goes into
`NOT_APPLICABLE_1_4_2` with the reason 1.4.2 printed.

## V3. Green (US1, US2, SC-001)

```sh
bazel test //bun/tests/npm/conformance:conformance_test --test_output=errors
bazel test //bun/tests/npm/conformance:conformance_1_4_2_test \
  --platforms=//bun/tests/npm/conformance:host_bun_1_4_2 \
  --extra_execution_platforms=//bun/tests/npm/conformance:host_bun_1_4_2 --test_output=errors
```

Expected: PASS, `0 differences`, every new project listed as compared (1.4.4) or as compared or
not applicable (1.4.2). A "Bun 1.4.2 links this lockfile differently from Bun 1.4.4" failure is
feature 006's stop condition: report it, change neither side.

## V4. Stale lockfiles still fail (US1-7, SC-002, FR-006)

```sh
bazel test //bun/tests/npm:compare --test_output=errors
```

Expected: PASS; for each R7 project the variant with a rule changed after `bun install` fails with
"run `bun install` and commit bun.lock".

## V5. Units, canary, citations (FR-008, FR-011)

```sh
bazel test //bun/tests/npm:bun_override_map //bun/tests/npm:bun_package --test_output=errors
bazel test //bun/tests/canary/npm:c_overrides_test
bazel test //bun/tests/canary/npm:c_overrides_test --test_env=RULES_BUN_CANARY_RED=1   # must fail
bazel test //bun/tests/canary/npm:c_catalog_test
bazel test //bun/tests/canary/npm:c_catalog_test --test_env=RULES_BUN_CANARY_RED=1      # must fail
bazel test //bun/tests/npm/conformance:citations_test --test_output=errors
```

Expected: units and canaries PASS, the red canaries FAIL naming C-OVERRIDES and C-CATALOG,
citations PASS with `bun_override_map`, `bun_catalog_map` and `bun_package` in its modules. `:bun_override_map` is the new suite of
`bun_override_map_test.bzl`, replacing `:overrides`.

## V6. Windows: the cause reproduced (US3, FR-013, FR-014)

On the Windows CI job `output-root-with-space`, with the inner Bazel at 9.2.0 (a push: the user's
approval):

```sh
bazel --output_user_root="C:/bazel root" test //bun/tests/integration:test_output_test --runs_per_test=30 --test_output=errors
```

Expected: 30 of 30 FAIL, each naming a marker missing from the inner output; PASS on the Linux and
macOS jobs. Recorded in `tdd-log.md` with the run URL.

## V7. Windows: fixed (US3, SC-003)

With the inner Bazel at 9.4.0 (research R10; only once 9.4.0 is released, else US3 stops per
FR-016):

```sh
bazel --output_user_root="C:/bazel root" test //bun/tests/integration:test_output_test //bun/tests/integration:source_node_modules_test --runs_per_test=30 --test_output=errors
```

Expected: 60 of 60 PASS, `source_node_modules_test`'s assertions unchanged (`git diff main --
bun/tests/integration/source_node_modules.test.ts` empty). The `--runs_per_test=30` step is
removed from the workflow before merge.

## V8. Public surface unchanged (FR-017, SC-004)

```sh
git diff main --stat -- bun/*.bzl bun/toolchain bun/platforms
bazel mod show_extension @rules_bun//bun:extensions.bzl%npm
```

Expected: no change to `bun/*.bzl` or the toolchain and platform packages; the extension's tag
classes and attributes as on `main`.

## V9. Completion gates (FR-019, SC-005)

```sh
bazel run //:gazelle
prek run --all-files
bazel test //...
(cd e2e/smoke && bazel test //...)
```

Then every job of the PR's CI on `ubuntu-latest`, `macos-latest`, `windows-latest`; documentation
names only the runner labels that ran.
