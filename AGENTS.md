# Project
rules_bun exposes a downloaded Bun release as a Bazel toolchain. A rule declares
`BUN_TOOLCHAIN_TYPE` from `//bun:defs.bzl` and reads `ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo`;
registering a toolchain is the consuming module's job.

Follow the official documentation — bazel.build for Bazel, bun.com for Bun — and the official
rulesets of bazelbuild and bazel-contrib as the reference, with `bazel-contrib/rules-template` as
the structural baseline. Where they define a way, use it instead of designing one.

# Rules
- Read and follow `.specify/memory/constitution.md` before changing anything.
- English for everything in the repository: the diagnostics a build prints (`fail()`,
  `progress_message`, test failure messages), commit messages, docstrings, `doc =` strings, and
  `specs/`. The ruleset is for every Bazel user, not one language community.
- A change under `bun/`, `e2e/`, or `MODULE.bazel` goes through
  `specify workflow run speckit -i spec="<description>"`. Answering a gate is the user's.
- Before handing back a change: in the root, `bazel run //:gazelle`, `prek run --all-files`,
  `bazel test //...`; in `e2e/smoke/`, `bazel test //...`. Report a failure, do not widen the task
  to fix it.
