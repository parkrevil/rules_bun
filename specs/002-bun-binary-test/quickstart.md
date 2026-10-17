# Quickstart: validating `bun_binary` and `bun_test`

Contracts: [contracts/public-api.md](contracts/public-api.md). Fixtures and what each covers:
[data-model.md](data-model.md) "Test fixtures"; canaries: data-model.md "Upstream canaries"
(FR-028). Every gap is decided (research.md Part 1, G1–G15), and G-impl-1 is resolved by spec
Revision 13. Spec Revisions 10–13 are carried in research.md Part 1 "Plan for spec Revision 10"
through "Plan for spec Revision 13". Rows 2a, 2b, 10 and 13 verify G-impl-1's resolution: they
fail with the stub on Linux and are expected to pass with the shell launcher (plan step 11).

## Prerequisites

- Bazelisk; `.bazelversion` selects Bazel 9.2.0. No host Bun is needed or used.
- Linux and macOS: `bash` and the utilities the Bash runfiles library calls, which running a
  target needs (contract, "Launching").
- Local runs: Linux. macOS and Windows: CI only; report them as unverified until CI passes there.

## Root module

| # | Command (repository root) | Expected |
|---|---|---|
| 1 | `bazel test //...` | all pass, including feature 001's suites unchanged, every `bun_test`, the load-guard spawn tests (including `--isolate`, the 10,000-file set, the 22,000-file set failing with the declared-file-count error, and fail closed), the non-zero-exit, standard-input, `BUN_OPTIONS`, transpiler-cache, spaces-in-paths, leading-`--` rejection, allowlist, describe-label filter, filter-without-match, filter × shards rejection, empty-shard, `bun_test` working-directory (the copy-tree root, holding no file; Revision 11), coverage `.dat` spawn test, the coverage spawn test whose test changes its working directory (exit 1, English error naming an `SF:` value, no `.dat`; G15), the command-line-length spawn test, the canaries C1, C2, C4 (the runtime `--config <path>` / `-c <path>` command) and C13 (C7 and C16 are incompatible off Windows), and the analysis failures (including a directory in `data`) |
| 2 | `bazel test //... --noenable_runfiles` | same result with a manifest only, including the manifest-escaping check of the spaces-in-paths test (US4-2, SC-003) |
| 2a | `bazel run --noenable_runfiles //bun/tests/run/app:main -- extra` | exit 0 (FR-024; G-impl-1 resolved, Revision 13) |
| 2b | `bazel test //bun/tests/run:skeleton_test --noenable_runfiles --spawn_strategy=local --nocache_test_results` | passes: no staged tree, the shell launcher resolves through the manifest (G-impl-1, Revision 13) |
| 2c | `bazel build //bun/tests/run/app:main && head -n1 bazel-bin/bun/tests/run/app/main` | prints `#!/usr/bin/env bash`: the Linux executable is the shell launcher (Revision 13) |
| 3 | `bazel run //bun/tests/run/app:main -- extra` | exit 0 |
| 4 | same as 3 with `extra` changed | non-zero exit, message names the wrong argument |
| 4a | `bazel run //bun/tests/run/args:echo -- -- x` | exit 1, English error naming the leading `--` (Revision 10) |
| 5 | `RULES_BUN_INHERITED=set RULES_BUN_BOTH=inherited bazel test //bun/tests/run/protocol/env:env_inherit_set_test` | passes (FR-014, inherited and set, and inherited over declared) |
| 6 | `bazel coverage --combined_report=lcov //bun/tests/run/protocol/coverage:coverage_test`, then `bazel run //bun/tests/run/protocol/coverage:coverage_check -- bazel-out/_coverage/_coverage_report.dat` | the check exits 0: the merged report names a source file by its workspace path (FR-016a, G7) |
| 7 | `bazel run //:gazelle && prek run --all-files` | no changes, no failures (AGENTS.md) |
| 7a | `bazel mod graph` | `platforms` resolves to 1.1.0, the version `MODULE.bazel` declares |

## Consumer module

| # | Command (`e2e/smoke/`, no `.bazelrc`) | Expected |
|---|---|---|
| 8 | `bazel test //...` | passes, including the consumer `bun_test` (US5-1), which asserts that the root `bunfig.toml` (preload of `smoke_preload.ts` setting a global) and the root `.env`, declared by no target, take no effect (Revision 12); the result is recorded for Linux, and a failure is reported as a gap, not worked around |
| 9 | `bazel run //app:main` | exit 0 (US5-2) |
| 10 | `bazel test //... --noenable_runfiles`, then `bazel run --noenable_runfiles //app:main` | both pass (FR-024) |
| 11 | `git grep -n 'bun/private' -- e2e` (root) | prints nothing; output kept in the hand-back record (US5-3) |

## CI

| # | Job | Expected |
|---|---|---|
| 12 | matrix ubuntu/macos/windows × root/e2e: `bazel test //...`, the `bazel run` step and the `env_inherit` step | pass on 3 of 3 (SC-002), including the load-guard tests, the isolation greens (SC-006), the canaries on each OS (Revision 7, FR-028) and the `e2e/smoke` root `bunfig.toml`/`.env` assertion, whose result is recorded per OS (a failure is a gap; Revision 12); C7 and C16 run on Windows only |
| 13 | Linux, root and `e2e/smoke` with `--noenable_runfiles`: `bazel test //...` and the `bazel run` step | pass (SC-003, FR-024); the `bazel run` step is no longer an expected failure (G-impl-1, Revision 13) |
| 14 | Linux, `bazel coverage` and the checking program | pass (FR-016a) |
| 15 | Windows, root and `e2e/smoke` test sets and the `bazel run` step with `bazel --output_user_root="C:/bazel root"` | pass: runfiles paths contain a space (spec Edge Cases, Revision 9) |

Windows argument tests with quotes wait for a hermetic-launcher release that fixes #80 (G1).
macOS runs the shell launcher only in CI; its result is unverified until row 12 passes there.
