# Quickstart: validating this feature

Prerequisites: the repository checkout, Bazel via `.bazelversion` (9.2.0), and network access for
the Bun download. Windows and macOS results come from CI; a local run covers Linux x86_64 only.

## 1. Root module

```bash
bazel run //:gazelle
bazel test //...
```

Expected: the build files are already up to date, and every test passes, including
`//bun/tests:hardening_test`, which now runs through `diff_test`.

## 2. Consumer module

```bash
cd e2e/smoke
bazel test //...
```

Expected: `//:smoke_test` runs and passes. Before this feature the same command exited 4 with
`ERROR: No test targets were found, yet testing was requested`.

## 3. The hardening check is non-vacuous (FR-005)

Temporarily drop the hardening flags the probe passes to the child Bun — in
`bun/private/hardening.bzl`, return an empty list from `hardening_args` — then:

```bash
bazel test //bun/tests:hardening_test
```

Expected: the test **fails**, and the diff shows `{"poisoned":true,"port":"9999"}` against the
expected `{"poisoned":false,"port":null}`. Restore `hardening_args` afterwards; this check is a
manual experiment, not a committed test.

## 4. No fallback remains (SC-004)

```bash
grep -rn "hasattr" bun/
```

Expected: no matches.

## 5. Every platform

```bash
gh run list --workflow=ci.yaml --limit 1
```

Expected once the branch is pushed: all six `test` jobs (ubuntu, macos, windows × root,
`e2e/smoke`) and the `prek` job report success.
