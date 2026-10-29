# Implementation Plan: Link What the Pinned Bun Links, by Construction and by Test

**Branch**: `006-bun-conformant-resolution` (from `main` at `c485a75`) | **Date**: 2026-10-29 |
**Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/006-bun-conformant-resolution/spec.md`

## Summary

The resolver from `bun.lock` to linked packages is rebuilt as a carry-over of Bun 1.4.4's own
pipeline, stage by stage and in Bun's order (research Part 2, R1, R2): the text-lockfile loader
(one package per `name@resolution`, per-dependency resolutions with row evidence, `unresolved`,
`./<name>/` keys, version-based peers), `Lockfile::resolve` (the hoister that rebinds peers),
`clean`, and the isolated linker's `build_store` (DFS with transitive peers, then dedupe into store
entries). Five new private files mirror Bun's files, each function citing its Bun lines;
`resolve.bzl` becomes the adapter to today's output, so generated targets keep their names (R4).
Target platforms are handled by building the store per platform class, with Bun's own `is_disabled`
(R3); npm ranges by carrying over Bun's semver (R5). A differential conformance test runs the pinned
Bun's isolated install offline against the loopback registry for every fixture, the scale fixture,
the integration lockfiles and a new edge-case corpus, reads the linked graph from Bun's documented
`node_modules/.bun` layout, and requires it to equal the ruleset's graph for the host's platform
class, compared by partition refinement so entry counts and peer contexts count (R6–R9, R11). A
second run uses Bun 1.4.2 as the oracle through a dev-only registered toolchain and also checks that
1.4.2 and 1.4.4 agree, since the ruleset cannot tell them apart from a lockfile (R10). Planning
found three differences beyond the spec's five (BC-6 per-key instances, BC-7 non-optional platform
packages, BC-8 unfetched entries' dependencies) and one Intentional Difference (ID-3 no hoisting);
the user approved all of them at the plan gate on 2026-10-29, so the Behavior Changes are BC-1…BC-8.

## Technical Context

**Language/Version**: Starlark on Bazel 9.2.0 (`bazel_compatibility = [">=9.2.0"]`); TypeScript run
by Bun 1.4.4 (conformance test, canaries, fixture writers); Bun 1.4.2 as the second oracle only

**Primary Dependencies**: no `bazel_dep` change. Specification: oven-sh/bun at `bun-v1.4.4`
(`src/install`, `src/install_types`, `src/semver`), with the user's approval of 2026-10-29
(research Part 1). New dev-only repositories: the Bun 1.4.2 archives through the ruleset's own
`bun.toolchain` tag (R10)

**Storage**: N/A

**Testing**: skylib `unittest` (`bun/tests/npm/*_test.bzl`, new `bun_semver_test.bzl` with cases from
Bun's `test/cli/install/semver.test.ts`); the conformance `bun_test` (`bun/tests/npm/conformance/`)
fed by `@npm_fixture_results`; `bun_test` canaries (`bun/tests/canary/npm`); Bazel-in-Bazel
integration tests (`bun/tests/integration/`, `scale_test`); `e2e/smoke`; CI jobs as on `main`, plus
the 1.4.2 conformance step on each OS

**Target Platform**: linux-x64, linux-aarch64 (glibc, musl), darwin-x64, darwin-aarch64, windows-x64;
CI runners `ubuntu-latest`, `macos-latest`, `windows-latest`

**Project Type**: Bazel ruleset (library)

**Performance Goals**: `scale_test`'s existing bound holds (extension evaluation of 2,000 packages
≤ 10,000 ms); times on `main` and branch reported (R13)

**Constraints**: Bun's structure, not fixture-fitting (P1); no public API change (P4, constitution
I); every `bun.lock` access canaried (V); oracle Bun only from a registered toolchain, no network
(III); shell-free (VI); Starlark has no `while` or recursion (bounded loops, R1); English everywhere;
test-first: each BC recorded as a conformance difference before the fix (`tdd-log.md`)

**Scale/Scope**: about 4–5k lines of Starlark replacing `resolve.bzl`'s 455 (five new
`bun/private/bun_*.bzl`), `lockfile.bzl` (new accesses), `npm_extension.bzl` (`_NPM_DOC`),
`fixture_results.bzl`; a new `bun/tests/npm/conformance/` package; ~11 corpus projects and their
archives; ~6 new canaries; `MODULE.bazel` (dev-only 1.4.2 toolchain and its registration);
`.github/workflows/ci.yaml` (1.4.2 step)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Public API Boundary | No rule, attribute, tag or documented target name changes; instance repos (`<name>__…`) are documented as non-public; new code in `bun/private/`, tests in `bun/tests/` ([contracts/public-api.md](contracts/public-api.md)) | PASS |
| II. Tested Claims | Every BC has a conformance difference before and none after; `_NPM_DOC` states only covered behavior and names the CI runner labels that ran; the 1.4.2 run is reported per platform where it ran | PASS |
| III. Pinned, Verified Downloads | The 1.4.4 oracle is the test's own Bun (registered target toolchain); 1.4.2 is fetched by the ruleset's repository rule with `versions.bzl`'s integrity and run as a registered dev-only toolchain selected by a dev platform (R10); the registry is loopback; no host tool | PASS |
| IV. Minimum Dependency Versions | No `bazel_dep` change | PASS |
| V. Supported APIs Only | Bun's source is the specification for what bun.com does not document, under the user's approval of 2026-10-29, each field with a canary and red mode (Part 4); the oracle reads the layout bun.com documents (DOC-ISO); Bazel APIs used as documented (toolchain order, `parents`, `target_compatible_with`, `module_ctx.read`); a 1.4.2/1.4.4 disagreement stops work instead of being worked around | PASS |
| VI. Shell-Free Actions | No new action; tests are `bun_test` | PASS |
| VII. Releases Come From Tags | No release step. No rules_bun version is published (`.bcr/metadata.template.json` lists none; the only tag, `v0.0.0-test`, is not a release tag), so BC-1…BC-8 change no released behavior and need no migration failure; each is a correction toward what the pinned Bun links, listed for the first release's notes (as feature 005 FR-019 read VII) | PASS |

No violation. Post-design re-check (after Phase 1): unchanged — the design adds only dev-only module
usage and private files; D1–D3 are spec questions, not constitution conflicts.

## Project Structure

### Documentation (this feature)

```text
specs/006-bun-conformant-resolution/
├── plan.md              # This file
├── research.md          # Phase 0: Bun's pipeline, decisions R1–R14, field inventory, D1–D3
├── data-model.md        # Phase 1: Bun's lockfile/tree/store model as carried over
├── quickstart.md        # Phase 1: validation runs Q1–Q9
├── contracts/
│   ├── public-api.md         # what consumers observe (BC-1…BC-8)
│   └── conformance-graph.md  # graph JSON, oracle procedure, test interface
├── tdd-log.md           # implementation: each BC's difference before the fix
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
bun/private/
├── bun_semver.bzl            # NEW  src/semver (versions, npm ranges, satisfies)
├── bun_install_types.bzl     # NEW  resolver_hooks Behavior/Libc, Meta.is_disabled, DepSorter
├── bun_lockfile.bzl          # NEW  bun.lock.rs loader, lockfile.rs resolve/clean/dedupe, reachable.rs
├── bun_tree.bzl              # NEW  Tree.rs hoisting, bind_served_peers, filters; pruned_workspaces.rs
├── bun_isolated_store.bzl    # NEW  isolated_install.rs contained_folders, build_store
├── resolve.bzl               # REWRITTEN as the adapter: platform classes → instances/links/members
├── lockfile.bzl              # JSONC + checks; accesses L23–L30
├── npm_extension.bzl         # _NPM_DOC: Bun's rules, Intentional Differences, CI labels
└── platforms.bzl             # platform tuples for classes (R3)

bun/tests/
├── npm/
│   ├── conformance/          # NEW  BUILD.bazel, conformance.test.ts, oracle.ts, graph.ts,
│   │   │                     #      1.4.2 toolchain()/constraint/platform, conformance_1_4_2 test
│   │   └── bun_1_4_2/<project>/bun.lock   # NEW lockfiles Bun 1.4.2 wrote
│   ├── fixtures/conformance_*/            # NEW edge-case corpus (R11)
│   ├── registry/write_lockfiles.ts        # corpus projects, --bun-1-4-2
│   ├── registry/pack.ts, archives/        # new archives (e.g. opt-user@1.0.0)
│   ├── fixture_results.bzl                # also emits per-class graphs (contract)
│   ├── bun_semver_test.bzl                # NEW
│   ├── resolve_test.bzl, lockfile_test.bzl, …  # updated where they asserted non-Bun behavior (R14)
│   └── fixtures/missing_peer/…            # asserts BC-5
└── canary/npm/c_unresolved, c_unlinked, c_bundled, c_pkgext, c_wsversion, c_roworder (.test.ts)

MODULE.bazel                  # dev-only bun_1_4_2 toolchain + registration before @bun_toolchains
.github/workflows/ci.yaml     # 1.4.2 conformance step on every OS
```

**Structure Decision**: existing layout (constitution I). The carry-over is split by Bun source
file (R1) so each Starlark file is reviewed against one Bun file; tests stay under `bun/tests/npm/`
next to the fixtures they read.

## Phases after this plan

1. Conformance test, oracle, corpus, canaries and the ruleset-side graph export, on `main`'s
   resolver: Q1 must fail exactly with BC-1…BC-8 (and any further difference, added to the spec
   before it is fixed); recorded in `tdd-log.md`.
2. Carry-over in Bun's order: semver → install types → loader → resolve/hoist → clean → store →
   adapter; each step unit-tested and cited.
3. Q1–Q9 green; docs; PR with the BC table and measured times.

## Decisions of the user (research Part 6), answered 2026-10-29

- **D1** (answered: approved): **ID-3 No hoisting** (`node_modules/.bun/node_modules` and the root
  fallback are not reproduced) is in the spec's Intentional Differences.
- **D2** (answered: approved): **BC-6** (one package per `name@version`, bound by Bun's row
  evidence) and **BC-7** (non-optional dependencies of another platform not carried) are in Behavior
  Changes.
- **D3** (answered: list it): following the dependencies of unfetched entries (R4) is **BC-8**.

## Complexity Tracking

| Choice | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Carrying over Bun's hoister and `clean`, not only the loader and the store | S4/S6 rewrite peer resolutions the store reads; skipping them is the fixture-fitting P1 forbids | Loader + store only: peers bound by the hoister would differ silently |
| One store per platform class | A disabled package can change peer bindings and dedupe (S7, S8) | Conditional edges on one store (today's `_closure`): wrong in exactly those cases |
| Starlark semver | Version-based peers and shared versions compare ranges (S3, S5) | Exact-version `semver.bzl` cannot; no bazelbuild/bazel-contrib semver exists |
| Dev-only 1.4.2 toolchain via a dev platform | Constitution III: the oracle Bun must come from a registered toolchain | Running the 1.4.2 binary as plain test data: not a registered toolchain |
