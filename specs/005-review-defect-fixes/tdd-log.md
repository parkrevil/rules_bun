# TDD Log: feature 005

FR-023: every fix is test-first. The test is written, run and seen failing before the fix, and
passes after it. Each row records one run: the task, the test target, the exact command, the
platform it ran on, the result, and an excerpt of the failure text (red) or the pass line (green).

| Task | Target | Command | Platform | Result | Excerpt |
|---|---|---|---|---|---|
| T004 | research E1 | `gh release download bun-v<v> -R oven-sh/bun -p SHASUMS256.txt`; `echo -n <hex> \| xxd -r -p \| base64` | Linux x64 (WSL) | match | 1.4.2 `linux-x64-musl` `sha256-SDXspZ1t…`, `linux-aarch64-musl` `sha256-cXYLbI6j…`; 1.4.4 `sha256-pajMxedN…`, `sha256-V/AbAqxx…`; `linux-x64` equal to `versions.bzl` |
| T005 | `//...` (root) | `bazel test //...` | Linux x64 (WSL) | baseline pass | Executed 278 out of 281 tests: 278 tests pass and 3 were skipped. |
| T005 | `//...` (`e2e/smoke`) | `(cd e2e/smoke && bazel test //...)` | Linux x64 (WSL) | baseline pass | Executed 0 out of 4 tests: 4 tests pass. |
