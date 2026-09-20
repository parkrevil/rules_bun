# Project
rules_bun is a set of Bazel rules for integrating Bun.

# Rules
- `.specify/memory/constitution.md` governs every change.
- Changes under `bun/` or `e2e/` go through Spec Kit: `speckit-specify` → `speckit-plan` → `speckit-tasks` → `speckit-analyze` → `speckit-implement`, then repeat `speckit-converge` → `speckit-implement` until converge reports converged.
- Right after `speckit-specify`, create a branch named after its `specs/` directory. One feature per branch.
- Then get an adversarial review from a subagent and from Codex, and fix what they confirm.
- Before finishing: in the root, `bazel run //:gazelle`, `prek run --all-files`, `bazel test //...`; in `e2e/smoke/`, `bazel test //...`.
