# Quickstart: Validating feature 005

Prerequisites: Bazel 9.2.0 via Bazelisk, network for the first fetch, the repository at the tip of
`005-review-defect-fixes`. Every scenario names the requirement it proves; expected results are
those of [contracts/public-api.md](contracts/public-api.md).

| # | Scenario | Command | Expected |
|---|---|---|---|
| Q1 | Credentials (US3, FR-002) | `bazel test //bun/tests/npm:npmrc //bun/tests/integration:credentials_test` | pass; failure texts hold no user, token or URL |
| Q2 | Content identity (US2, FR-001) | `bazel test //bun/tests/npm:uniqueness //bun/tests/integration:multi_test` | pass; integrity, source and exclusion differences each fail naming the property |
| Q3 | npm `checkList` (US6-1/2, FR-006) | `bazel test //bun/tests/npm:platforms //bun/tests/npm:libc` | pass, including `any` and `["any", "!linux"]` |
| Q4 | musl Bun (US4, FR-005) | `bazel test //bun/tests:selection //bun/tests:target_selection //bun/tests:versions` then `bazel fetch @bun_linux-x64-musl//... @bun_linux-aarch64-musl//...` | pass; both fetches verify the integrity |
| Q5 | Canaries (US7, FR-009/010/013) | `bazel test //bun/tests/canary:all` | C1, C17, C18 pass; C1 fails when a link cannot be made |
| Q6 | Bins (US1, FR-012) | `bazel test //bun/tests/npm:bins //bun/tests/integration:bins_test` | the extensionless node-shebang bin runs through `npm_bin` and the generated target; a `#!/bin/sh` bin fails analysis with the FR-012 reason |
| Q7 | Toolchain tags (US5, FR-015/016) | `bazel test //bun/tests/integration:toolchain_tags_test //bun/tests/integration:lockfile_errors_test` | root wins; non-root conflict, unknown key, bad value, bad `name` and `workspace_target_name` fail naming module and tag |
| Q8 | No launcher fetch (US8, FR-007) | `bazel test //bun/tests/integration:launcher_fetch_test` on Linux and macOS | the inner build of a `bun_binary` and a `bun_test` requests no `runfiles-stub-*` or `finalize-stub-*` file |
| Q9 | Case-insensitive `BUILD` (US6-3, FR-017) | `bazel test //bun/tests/npm/...` | the renamed files are in the tree under their original names |
| Q10 | API and docs (US9, FR-019–FR-022) | `bazel test //bun/tests/npm:layout //bun/tests/npm/fixtures/basic/sub/... //bun/tests/npm/fixtures/scope_sibling/... //bun/tests/integration:replace_test //bun/tests/integration:toolchain_tags_test`; `(cd e2e/smoke && bazel test //...)` | loading `bun_toolchain` fails, `bun` and `npm` load; resolution-scope and visibility cases pass; `bun.toolchain` still works |
| Q11 | Gates (AGENTS.md, SC-001) | `bazel run //:gazelle && prek run --all-files && bazel test //... && bazel test //... --noenable_runfiles --spawn_strategy=local --nocache_test_results`; `(cd e2e/smoke && bazel test //...)` | all pass |
| Q12 | CI (SC-001, FR-021) | push; `gh pr checks --watch` | every job passes on `ubuntu-latest`, `macos-latest`, `windows-latest`; the platform statements match the jobs that ran (D3 decided from the Windows jobs' C1 result) |

Each test of Q1–Q10 must also be shown red before its fix (FR-023); `tdd-log.md` records both
runs.
