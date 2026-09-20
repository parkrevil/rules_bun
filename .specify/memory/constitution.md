# rules_bun Constitution

## Core Principles

### I. Public API Boundary

The public API is `bun/*.bzl` and `//bun/toolchain:execution_type`. Implementation MUST live in
`bun/private/`, tests in `bun/tests/` and `e2e/smoke/`. Anything outside the public API MAY change
in any release, so it MUST NOT be documented as usable by consumers.

### II. Tested Claims

Every behavior change MUST add or update a test in `bun/tests/` or `e2e/smoke/`. Documentation,
specs, and reports MUST claim only behavior a test covers, and MUST name the platforms the test
actually ran on. Behavior that no test covers is reported as unverified, never as working.

### III. Pinned, Verified Downloads

Repository rules MUST download an exact version and verify it with an `integrity` value taken from
the upstream checksum file. They MUST NOT detect, probe, or run host-installed tools, and build
actions MUST run only tools that come from a registered toolchain. This is what makes a build
reproducible on a machine that is not the author's.

### IV. Minimum Dependency Versions

Minimal version selection turns every `bazel_dep` version into a requirement on consumers.
A `bazel_dep` without `dev_dependency = True` MUST declare the lowest version the ruleset works
with, and MUST be raised only when a change needs the newer version. `e2e/smoke` consumes the
ruleset with exactly those declared versions and MUST keep passing.

### V. Supported APIs Only

Rules MUST follow bazel.build documentation and the patterns of bazelbuild and bazel-contrib
rulesets, and the source URLs MUST be recorded in the feature's `research.md`. Deprecated APIs are
forbidden. Every API MUST be used as its documentation specifies; undocumented behavior MUST NOT be
relied on. Feature detection for an API that every Bazel version in `bazel_compatibility` provides
is forbidden. When no supported API does the job, work stops and the gap is reported instead of
worked around.

### VI. Shell-Free Actions and Tests

Rules MUST run tools with `ctx.actions.run` and `Args`. `ctx.actions.run_shell`, generated shell
scripts, and shell test launchers are forbidden, because Bash is absent on Windows, a supported
platform. Tests that need a launcher MUST use a purpose-made rule from bazel-skylib.

## Governance

This constitution governs every change in this repository, including changes made outside the Spec
Kit workflow. `AGENTS.md` holds the workflow; this file holds the rules the workflow enforces.

Amendments MUST go through `speckit-constitution` and carry a version bump: MAJOR for removing or
redefining a principle, MINOR for adding one or materially expanding guidance, PATCH for
clarifications. Every plan records its Constitution Check, `speckit-analyze` treats a conflict with
a MUST principle as critical, and such a conflict blocks the change until either the change or this
constitution is amended.

**Version**: 1.0.0 | **Ratified**: 2026-09-20 | **Last Amended**: 2026-09-20
