# Quickstart: Validating Feature 006

**Feature**: `006-bun-conformant-resolution` | **Spec**: [spec.md](spec.md) | **Contracts**: [contracts/](contracts/)

Prerequisites: a checkout of branch `006-bun-conformant-resolution`, Bazel per `.bazelversion`.
No network is needed by any test (the registry is loopback); fetching Bun 1.4.2 for Q4 needs it
once, as any toolchain fetch does.

## Q1. Conformance with Bun 1.4.4 (US1, US2, SC-001)

```sh
bazel test //bun/tests/npm/conformance:conformance_test --test_output=errors
```

Expected: PASS, with the test log listing every project compared (all of `bun/tests/npm/fixtures/`,
the `conformance_*` corpus, `scale` and `scale/platform`, `bun/tests/integration/workspaces/*`,
`bun/tests/npm/conformance/bun_1_4_2/*`, `bun/tests/npm/conformance/accepted/*`, `e2e/smoke`), the
not-applicable projects (`stale_link` and `bun/tests/npm/conformance/refused/*`, each of which both
Bun and the ruleset must refuse) with their reasons, the exclusions `ID-1`, `ID-2`, `ID-3`, `ID-4` by name, and `0 differences`.
ID-5 and ID-6 exclude nothing (no compared lockfile reaches them; spec "Intentional Differences").
Every BC-1…BC-16 difference recorded red in `tdd-log.md` is gone.

## Q2. Red mode (FR-011, SC-003)

```sh
bazel test //bun/tests/npm/conformance:conformance_test --test_env=RULES_BUN_CONFORMANCE_RED=1 --test_output=errors
```

Expected: FAIL, naming the project, the dependent, the dependency and both bindings
([contracts/conformance-graph.md](contracts/conformance-graph.md), "Failure text").

## Q3. Behavior changes were differences before (SC-003)

On `main` plus only the new test, corpus and canaries (the first commits of the branch), Q1 fails
once per BC of [contracts/public-api.md](contracts/public-api.md); `tdd-log.md` records each failure
text. After the carry-over, Q1 passes.

## Q4. Bun 1.4.2 (US5, SC-002)

```sh
bazel test //bun/tests/npm/conformance:conformance_1_4_2_test \
  --platforms=//bun/tests/npm/conformance:host_bun_1_4_2 \
  --extra_execution_platforms=//bun/tests/npm/conformance:host_bun_1_4_2 --test_output=errors
```

Bazel runs a test on an execution platform with the target platform's constraints, so the platform
is also given as an execution platform.

Expected: PASS, listing the 1.4.2 lockfiles compared and the corpus projects 1.4.2 cannot write with
the reason. A "Bun 1.4.2 links this lockfile differently from Bun 1.4.4" failure is the spec's stop
condition: report it to the user; do not change either side to pass.

## Q5. Canaries (US4)

```sh
bazel test //bun/tests/canary/npm/...
bazel test //bun/tests/canary/npm/... --test_env=RULES_BUN_CANARY_RED=1   # each new canary fails
```

## Q6. Traceability (US3, SC-004)

Every `def` of `bun/private/bun_*.bzl` and `bun/private/resolve.bzl`, and the resolver functions
of `bun/private/platforms.bzl` (`ONLY.platforms` in `citations.test.ts`), has a docstring line
`Bun: <file> L<a>–L<b> @ bun-v1.4.4` naming a file of research Part 1; in `resolve.bzl` and
`platforms.bzl` a function may instead state that it is the adapter (research R3, R4). A function
may cite more than one range, so the citations outnumber the `def`s. Research Part 2 maps each
function to its citations and lists each step not carried over.

```sh
bazel test //bun/tests/npm/conformance:citations_test --test_output=all
bazel test //bun/tests/npm/conformance:citations_test --test_env=RULES_BUN_CITATIONS_RED=1 --test_output=errors   # fails naming _red_mode
```

Expected: PASS, with `204 functions checked in 7 modules` in the log.

## Q7. Public surface unchanged (SC-005)

Compare `bazel query 'kind(".*", @npm//...)'`-style target lists of every root hub, and
`bazel mod show_extension @rules_bun//bun:extensions.bzl%npm`, on `main` and on the branch: names
of `:node_modules/...` targets are equal for every project without a BC; differences are only those
the BCs list.

## Q8. Completion gates (FR-018, SC-006)

```sh
bazel run //:gazelle
prek run --all-files
bazel test //...
bazel test //... --noenable_runfiles --spawn_strategy=local   # the unsandboxed run CI makes
(cd e2e/smoke && bazel test //...)
```

Then the PR's CI on `ubuntu-latest`, `macos-latest`, `windows-latest` (and the Q4 step on each);
documentation names only the runner labels that ran.

## Q9. Performance (research R13)

```sh
bazel test //bun/tests/integration:scale_test --test_output=all   # on main and on the branch
```

Expected: PASS (evaluation ≤ 10,000 ms, unchanged bound); both printed times go into the PR.
