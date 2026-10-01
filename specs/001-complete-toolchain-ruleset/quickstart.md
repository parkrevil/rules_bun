# Quickstart: Validate the Feature

Prerequisites: Bazelisk, network access to GitHub releases and the BCR, `prek`. Local runs are
Linux only; macOS and Windows are validated by the `CI` workflow (`.github/workflows/ci.yaml`),
and are reported as unverified until a named CI run succeeds.

## 1. Consumer module (US1, FR-001, FR-002)

```sh
(cd e2e/smoke && bazel test //...)
```

Expected: the `diff_test` and the auto-exec-groups analysistest run and pass. Before the feature: exit code 4,
"No test targets were found".

Mismatch check: change the literal version in `e2e/smoke/BUILD.bazel` to `0.0.0`; the test fails
and prints the `failure_message`. Revert.

## 2. Root module (US2–US4)

From the repository root:

```sh
bazel run //:gazelle
prek run --all-files
bazel test //...
```

Expected: all pass. The test list includes the per-platform selection tests (R5), the exec
configuration test (R6), both `BUN_BIN` tests (R7), `versions_test`, `semver`, and
`//tools:preset.update_test`; it no longer includes `hardening_*` or `cross_*`.

## 3. Static checks (SC-003, SC-004)

```sh
git grep -n run_shell -- bun e2e          # no output
git grep -n 'is_executable = True' -- bun e2e   # no output
git grep -n hasattr -- bun                 # no output
git grep -n stripPrefix -- bun             # no output
git grep -n 'toolchain = BUN_TOOLCHAIN_TYPE' -- bun e2e   # defs.bzl docstring and e2e/smoke/verify.bzl
```

## 4. Selection tests can fail (US3 acceptance 1)

Swap the `compatible_with` of two entries in `PLATFORMS` (`bun/private/toolchains_repo.bzl`
after this feature; `bun/private/platforms.bzl` before task T019) and
run `bazel test //bun/tests/...`; the tests for those two platforms fail. Revert.

## 5. Cross-platform

Push the branch and open a pull request; the `CI` workflow runs step 1 and step 2's
`bazel test //...` on `ubuntu-latest`, `macos-latest` and `windows-latest`. Record the run ID and
per-OS results in `tdd-log.md`.

## References

- Public API: [contracts/public-api.md](contracts/public-api.md)
- Fixtures and records: [data-model.md](data-model.md)
- Decisions and sources: [research.md](research.md)
