# Quickstart: validating npm dependencies

Prerequisites: Bazel 9.2.0 (Bazelisk reads `.bazelversion`), a checkout of this branch, network for
the first fetch of the outer build (the inner Bazel-in-Bazel builds use only loopback). Contracts:
[contracts/public-api.md](contracts/public-api.md); entities and the test map:
[data-model.md](data-model.md).

## Consumer setup (what SC-001 counts)

`MODULE.bazel`:

```starlark
npm = use_extension("@rules_bun//bun:extensions.bzl", "npm")
npm.translate_lock(bun_lock = "//:bun.lock")
use_repo(npm, "npm")
```

`BUILD.bazel` of each workspace package:

```starlark
load("@npm//:defs.bzl", "npm_link_all_packages")
load("@rules_bun//bun:defs.bzl", "bun_test")

npm_link_all_packages()

bun_test(
    name = "render_test",
    srcs = ["render.test.tsx"],
    deps = [":node_modules/react", ":node_modules/react-dom"],
)
```

`REPO.bazel`: `ignore_directories(["**/node_modules"])`.

## Scenarios

| # | Command (directory) | Expected |
|---|---|---|
| 1 | `bazel test //...` (root) | all tests pass, including the JSX proof, layout, peers, workspaces, platforms, bins, canaries and the integration tests |
| 2 | `bazel test //bun/tests/integration:integration_tests` (root) | the Bazel-in-Bazel tests pass; on Linux under `block-network`, elsewhere with every inner request in the loopback log |
| 3 | `bazel test //...` (`e2e/smoke`) | the JSX `bun_test` passes |
| 4 | `bazel run //jsx:render` (`e2e/smoke`) | prints the rendered markup, exits 0 |
| 5 | `git grep -n 'bun/private' -- e2e` (root) | prints nothing |
| 6 | `bazel mod show_extension @rules_bun//bun:extensions.bzl%npm`, then `bazel mod show_repo` for each listed repository (`e2e/smoke`, each OS; and `//bun/tests/integration:reproducible_test`'s `show_extension.txt` and `show_repo.txt`, each OS) | identical output on Linux, macOS, Windows; `MODULE.bazel.lock` has no `npm` extension entry |
| 7 | `bazel fetch //...` then `bazel test //... --nosandbox_default_allow_network` (root and `e2e/smoke`, Linux) | pass |
| 8 | the same as 1 and 3 on Windows CI, with Bazel's defaults and again with `--windows_enable_symlinks` | pass both ways |
| 9 | Windows CI: build the npm test targets with `--output_base=A`, then with `--output_base=B`, both with one `--disk_cache` and `--execution_log_json_file` | every action consuming a store link is a cache hit in the second log |
| 10 | `bazel test //bun/tests/canary/npm:canaries` with one fixture access altered | the canary fails with its English message (record in tdd-log.md) |

Results are recorded per OS; macOS and Windows only from CI.
