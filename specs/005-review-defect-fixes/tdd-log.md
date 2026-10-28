# TDD Log: feature 005

FR-023: every fix is test-first. The test is written, run and seen failing before the fix, and
passes after it. Each row records one run: the task, the test target, the exact command, the
platform it ran on, the result, and an excerpt of the failure text (red) or the pass line (green).

| Task | Target | Command | Platform | Result | Excerpt |
|---|---|---|---|---|---|
| T004 | research E1 | `gh release download bun-v<v> -R oven-sh/bun -p SHASUMS256.txt`; `echo -n <hex> \| xxd -r -p \| base64` | Linux x64 (WSL) | match | 1.4.2 `linux-x64-musl` `sha256-SDXspZ1t…`, `linux-aarch64-musl` `sha256-cXYLbI6j…`; 1.4.4 `sha256-pajMxedN…`, `sha256-V/AbAqxx…`; `linux-x64` equal to `versions.bzl` |
| T005 | `//...` (root) | `bazel test //...` | Linux x64 (WSL) | baseline pass | Executed 278 out of 281 tests: 278 tests pass and 3 were skipped. |
| T005 | `//...` (`e2e/smoke`) | `(cd e2e/smoke && bazel test //...)` | Linux x64 (WSL) | baseline pass | Executed 0 out of 4 tests: 4 tests pass. |
| T010 | `//bun/tests/npm:npmrc` | `bazel test //bun/tests/npm:npmrc` | Linux x64 (WSL) | red | `Error: file '//bun/private:npmrc.bzl' does not contain symbol 'has_userinfo'` |
| T011 | `//bun/tests/integration:credentials_test` | `bazel test //bun/tests/integration:credentials_test --test_output=all` | Linux x64 (WSL) | red (a)–(d), (g), (h); green (e), (f) | (d) `the entries "a" and "b/a" of a@1.0.0 record different URL values, "…" and "http://u5er:t0ken-secret@127.0.0.1:…"`; (g) `dependencies "p": "https://u5er:t0ken-secret@host/p.tgz" is not in bun.lock`; (a) the inner build requested `/u5er:t0ken-secret@127.0.0.1:…/a/-/a-1.0.0.tgz` |
| T015 | `//bun/tests/npm:npmrc`, `//bun/tests/integration:credentials_test`, `//bun/tests/npm:all` | `bazel test //bun/tests/npm:npmrc //bun/tests/integration:credentials_test //bun/tests/npm:all` | Linux x64 (WSL) | green | Executed 2 out of 103 tests: 103 tests pass. |
