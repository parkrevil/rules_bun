# Project
rules_bun is a set of Bazel rules for integrating Bun.

# Rules
- Changes under `bun/` go through Spec Kit: `speckit-specify` → `speckit-plan` → `speckit-tasks` → `speckit-analyze` → `speckit-implement`, then repeat `speckit-converge` → `speckit-implement` until converge reports converged.
- Right after `speckit-specify`, create a branch named after its `specs/` directory. One feature per branch.
- Public API: `bun/*.bzl` and `//bun/toolchain:execution_type`. Implementation: `bun/private/`. Tests: `bun/tests/` and `e2e/smoke/`.
- Every behavior change adds a test. Claim only what tests cover, on the platforms they ran.
- Raise a `bazel_dep` minimum only when a change requires it; dev dependencies are exempt.
- Repository rules download an exact version with `integrity` from the upstream checksum file. Never use host-installed tools.
- Follow bazel.build docs and bazelbuild/bazel-contrib rulesets; record the URLs in the feature's `research.md`.
- Use only non-deprecated APIs available across `bazel_compatibility`; no fallbacks. If none exists, stop and report.
- Run tools with `ctx.actions.run` and `Args`, not `run_shell` or shell launchers.
- Before finishing: in the root, `bazel run //:gazelle`, `prek run --all-files`, `bazel test //...`; in `e2e/smoke/`, `bazel test //...`. Rerun after any change.
- Last, ask the user to run `/codex:adversarial-review --base main`.
