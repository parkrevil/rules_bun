# Quickstart: Validating the Bun 1.4.4 Upgrade

Run on `003-npm-dependencies` after implementation. `B` is the development toolchain's Bun:
`$(bazel info output_base)/external/+bun+bun_linux-x64/bun`.

## Prerequisites

- Bazel 9.2.0 (`.bazelversion`), network for the first fetch.
- For Q7: push access to PR #5.

## Q1: The toolchain is 1.4.4 and verified (US2, FR-001)

```sh
bazel test //bun/tests:versions
"$B" --version                     # 1.4.4
cd e2e/smoke && bazel test //:version_test
```

Expected: both tests pass; `bun --version` prints `1.4.4`. The integrities in `versions.bzl` equal
research R1.

## Q2: Every canary against 1.4.4 (US3, FR-005, FR-006)

```sh
bazel test //bun/tests/canary/... --nocache_test_results
bazel test //bun/tests/canary/npm/... --test_env=RULES_BUN_CANARY_RED=1 --nocache_test_results
```

Expected: the first passes (C-TD is gone if it went red as research R6 predicts; Windows-only
canaries are skipped on Linux); the second fails every `bun.lock` canary with a message naming its
reader. Each result is recorded in research Part 3 (E7).

## Q3: Unsandboxed run, as `manifest-only` (US1, FR-009)

```sh
bazel test //... --noenable_runfiles --spawn_strategy=local --nocache_test_results
```

Expected: all pass, C-PATCHED included, with no change to C-PATCHED or CI.

## Q4: Fixtures are what 1.4.4 wrote (FR-007)

Rerun each writer of research R8 with `B`; then:

```sh
git status --short          # no change: the writers serve on FIXTURE_PORT (research R13)
bazel test //bun/tests/npm/...
```

The writers' loopback registry listens on a random port and Bun writes full URLs, so a rerun
rewrites the port in every lockfile URL (research G6). Every other byte is unchanged: the committed
fixtures are what 1.4.4 writes.

## Q5: Bazel-in-Bazel offline (US4)

```sh
bazel fetch //...
bazel test //bun/tests/integration:integration_tests --nosandbox_default_allow_network
```

Expected: pass; the loopback log shows the five `bun-v1.4.4` archive paths and no external request.

## Q6: Full gates and the 1.4.2 search (SC-001, SC-004)

```sh
bazel run //:gazelle && prek run --all-files && bazel test //...
(cd e2e/smoke && bazel test //...)
git grep -n '1\.4\.2' -- . ':!specs'
```

Expected: all pass; the search finds only the `versions.bzl` 1.4.2 entry and the non-Bun strings
research R9 lists.

## Q7: CI (SC-002)

Push to `003-npm-dependencies`; every job of PR #5's CI passes on Linux, macOS and Windows,
including `manifest-only`, `windows-symlinks`, `network-denied` and `windows-without-bash`. Record
the run URL and the platforms in the PR description; claim nothing for a job that did not run.

## After the final gate

Done by the session that runs the workflow, not by the implement step: commit the work on
`003-npm-dependencies` as Conventional Commits, push it to update PR #5, watch every CI job on
Linux, macOS and Windows (SC-002, including `manifest-only`, `windows-symlinks`,
`network-denied`, `windows-without-bash`, `coverage`, `output-root-with-space`,
`windows-disk-cache`, `mod-compare`), fix only failures this feature caused, and record the run URL
and the jobs that passed in the PR #5 description, claiming nothing for a job that did not run.
