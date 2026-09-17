# Project
rules_bun is a set of Bazel rules for integrating Bun.

# Rules
- Spec first: rule behavior and public API changes go through `/speckit-specify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-analyze` → `/speckit-implement`.
- One feature = one branch, named after its `specs/` directory.
- Public API lives in `bun/*.bzl`; everything else in `bun/private/`.
- Non-dev `bazel_dep` declares the lowest version that works, not the latest.
- Fetch external artifacts by exact version with an integrity from the official checksums. Never detect installed tools.
- Follow the official Bazel documentation and the patterns of official rulesets; cite what you followed. No deprecated APIs.
- No workarounds. If no supported API exists, stop and report.
- Claim only what CI tests.
- Before finishing: `bazel run //:gazelle`, `prek run --all-files`, `bazel test //...` in the root and in `e2e/smoke/`.
- After implementation: `/speckit-converge` for spec compliance, then `/codex:adversarial-review` for the approach.
