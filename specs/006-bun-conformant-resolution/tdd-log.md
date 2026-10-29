# TDD Log: Feature 006

Test-first (plan Constraints, SC-003): every Behavior Change is first recorded here as a
conformance difference on `main`'s resolver, every canary and every new Starlark module's unit test
is seen failing before the code it checks is written, and each is then recorded passing. A red that
fails for a reason other than the one under test (a typo, a missing load) does not count.

| Task | Target | Command | Platform | Result | Excerpt |
|---|---|---|---|---|---|
| T005 | `//...` (root) | `bazel test //...` | Linux x64 (WSL) | baseline green on `main`'s resolver | `Executed 317 out of 320 tests: 317 tests pass and 3 were skipped.` |
| T005 | `//...` (`e2e/smoke`) | `cd e2e/smoke && bazel test //...` | Linux x64 (WSL) | baseline green | `Executed 0 out of 4 tests: 4 tests pass.` (cached) |
| T005 | `//bun/tests/integration:scale_test` | `bazel test //bun/tests/integration:scale_test --test_output=all` | Linux x64 (WSL) | baseline green; evaluation time on `main` | `extension evaluation: -120 ms (bazel mod deps median with the tag 5402 ms [8036, 5402, 3424], without 5522 ms [12290, 5522, 2689])` |
| T008 | `//bun/tests/npm/conformance:graph` | `bazel test //bun/tests/npm/conformance:graph --test_output=errors` | Linux x64 (WSL) | red: `conformance_graphs` not written (stub returns `[]`) | `In test _error_test_impl ...: Expected "{"error": "bun.lock: broken"}", but got "[]"`; `Error in fail: no class holds ("linux", "x64", "glibc")` |
| T009 | `//bun/tests/npm/conformance:graph` | `bazel test //bun/tests/npm/conformance:graph --test_output=errors` | Linux x64 (WSL) | green | `Executed 6 out of 6 tests: 6 tests pass.` |
| T011 | `//bun/tests/npm/...` | `bazel run //:gazelle && bazel test //bun/tests/npm/...` | Linux x64 (WSL) | green; no suite fails on the corpus (resolution errors are carried into `graphs.json`, e.g. `conformance_unbound`: BC-3) | `Executed 0 out of 157 tests: 157 tests pass.` |
| T012 | `//bun/tests/npm/conformance:graph_test_ts` | `bazel test //bun/tests/npm/conformance:graph_test_ts --test_output=errors` | Linux x64 (WSL) | red: `compare` not written (stub throws) | `error: compare is not written yet` (8 of 8 fail) |
| T017 | `//bun/tests/npm/conformance:graph_test_ts` | `bazel test //bun/tests/npm/conformance:graph_test_ts --test_output=errors` | Linux x64 (WSL) | green | 9 of 9 pass |
| T017 | `//bun/tests/npm/conformance:conformance_test` | `bazel test //bun/tests/npm/conformance:conformance_test --test_output=errors` (on `main`'s resolver) | Linux x64 (WSL) | red, Q3: 12 of 59 projects differ | see the rows below |
| T017 | BC-1 | same run | Linux x64 (WSL) | red | `conformance_unresolved: the root links "b" to b@1.0.0, Bun links it to no link` |
| T017 | BC-2 | same run | Linux x64 (WSL) | red | `conformance_alias_workspace: workspace "packages/lib" links "b" to b@1.0.0, Bun links it to b@2.0.0` |
| T017 | BC-3 | same run | Linux x64 (WSL) | red | `conformance_unbound: the ruleset fails (…: the workspace "" declares "r", which bun.lock lists no entry for; …), Bun installs the lockfile` |
| T017 | BC-4 | same run | Linux x64 (WSL) | red | `conformance_registry_to_workspace: member-user@1.0.0 links "member-lib" to no link, Bun links it to workspace "packages/member-lib"` |
| T017 | BC-5 | same run | Linux x64 (WSL) | red | `conformance_unprovided_peer: peer-unprovided@1.0.0 is 2 entries in the ruleset, Bun installs it as 1` (`missing_peer` shows no graph difference: the ruleset's missing-peer status fails analysis, which the graph does not carry; reported) |
| T017 | BC-6 | same run | Linux x64 (WSL) | red | `dependency_conflict: x@1.0.0 links "b" to b@2.0.0, Bun links it to b@1.0.0`; `conformance_nested: x@1.0.0 (b → b@1.0.0) is 2 entries in the ruleset, Bun installs it as 1`; `basic`: the same as `conformance_nested` |
| T017 | BC-7 | same run | Linux x64 (WSL) | red | `conformance_platform: the root links "nomatch-aix-ppc64" to nomatch-aix-ppc64@1.0.0, Bun links it to no link` |
| T017 | BC-8 | same run | Linux x64 (WSL) | no difference | `unsupported` passes: none of its unfetched entries has dependencies (reported) |
| T017 | no BC (reported) | same run | Linux x64 (WSL) | red | `conformance_peer_contexts: p@1.0.0 (q → q@1.0.0) links "r" to no link, Bun links it to r@1.0.0`; `integration/workspaces/fetch`: the same |
| T017 | no BC (reported) | same run | Linux x64 (WSL) | red | `conformance_bundled: bundler@1.0.0 links "b" to b@1.0.0, Bun links it to no link` |
| T018 | `//bun/tests/npm/conformance:conformance_test` red mode | `bazel test //bun/tests/npm/conformance:conformance_test --test_env=RULES_BUN_CONFORMANCE_RED=1 --test_output=errors` | Linux x64 (WSL) | red as intended (on `workspace`, since `basic` shows BC-6) | `red mode: the root's "a" redirected to b@1.0.0`; `workspace: the root links "a" to b@1.0.0, Bun links it to a@1.0.0 (b → b@1.0.0)` |
| T070 | deviation from T018 | — | — | red mode kept on `workspace`, not T018's `basic` | T017 found `basic` showing BC-6 (`conformance_nested`'s difference), so its red could be confused with a BC difference (FR-011); `workspace` shows no BC. T018's second Q2 run after T051 uses `workspace` |
| T069 | BC-8 (`conformance_unfetched`) | `bazel test //bun/tests/npm/conformance:conformance_test --test_output=errors` (on `main`'s resolver) | Linux x64 (WSL) | red, 13 of 60 projects differ (T017's 12 and this one) | `conformance_unfetched: a@1.0.0 links "b" to no link, Bun links it to b@1.0.0` |
