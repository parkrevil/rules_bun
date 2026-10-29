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
