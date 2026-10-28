# Implementation Plan: The Ruleset's Design Principles, Held Everywhere

**Branch**: `005-review-defect-fixes` (from `main` at `aca8c13`) | **Date**: 2026-10-28 |
**Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-review-defect-fixes/spec.md`

## Summary

Seven principles (P1–P7), each applied to every place it governs; the audit tables are research
Part 3. P1: an npm package instance is its content, so cross-hub deduplication compares integrity,
source and exclusion policy and fails naming the first difference (R1), and a URL holding user
information is rejected from `bun.lock` as from `.npmrc`, before any diagnostic can print it (R2).
P2: one platform table (`bun/private/platforms.bzl`) drives Bun toolchain registration and npm
package selection; it adds Bun's official musl archives with integrity from `SHASUMS256.txt`
(R5), follows npm-install-checks `checkList` (`any`), and a private rules_bun toolchain type
constrained to Windows replaces the direct hermetic-launcher toolchain requests, so Linux and macOS
builds resolve and fetch nothing of hermetic-launcher (R6). P3: canaries C17 (Bun drops a leading
`--`) and C18 (Bun runs an extensionless JavaScript bin), and C1 fails instead of passing
vacuously (R3). P4: the package repository decides from the file whether a `bin` is a JavaScript
program for Node or Bun (source extension or `node`/`bun` shebang); `npm_bin` fails analysis with
the true reason otherwise (R4). P5: in `bun.toolchain` the root's integrity wins per platform,
non-root conflicts fail and keys and values are validated; two `npm` tag values gain validation
(R8). P6: `BUILD`/`BUILD.bazel` are renamed in any case (R7). P7: `bun_toolchain` leaves the
public API; the documentation states only tested facts with CI's runner labels (R9).

## Technical Context

**Language/Version**: Starlark on Bazel 9.2.0 (`bazel_compatibility = [">=9.2.0"]`); JavaScript and
TypeScript run by Bun 1.4.4 (launcher, canaries, tests, fixture scripts)

**Primary Dependencies**: no `bazel_dep` change. hermetic_launcher 0.0.16 is used through its
documented helpers and `finalize-stub` command line (research R6). No new dev repository.

**Storage**: N/A

**Testing**: skylib `unittest`/`analysistest` (`toolchain_test`, `target_toolchain_test`,
`versions_test`, `bun/tests/npm/*_test.bzl`, `run_test`), `bun_test` canaries
(`bun/tests/canary/`), Bazel-in-Bazel integration tests with the loopback registry
(`bun/tests/integration/`), `e2e/smoke`; CI jobs `test`, `network-denied`, `manifest-only`,
`coverage`, `output-root-with-space`, `windows-without-bash`, `windows-symlinks`,
`windows-disk-cache`, `mod-compare`, `prek`

**Target Platform**: linux-x64, linux-aarch64 (glibc and, new, musl), darwin-x64, darwin-aarch64,
windows-x64; CI runners `ubuntu-latest`, `macos-latest`, `windows-latest`

**Project Type**: Bazel ruleset (library)

**Performance Goals**: no regression of feature 003 SC-010 (2,000-package evaluation under 1 s);
R4 reads only bin files whose path has no source extension, and only when the package is fetched

**Constraints**: test-first for every fix (FR-023); integrity only from `SHASUMS256.txt` (III);
no public API added beyond the two musl platform keys (FR-024); every Bun behavior relied on is
documented or canaried (V); shell-free actions (VI); English everywhere

**Scale/Scope**: about 30 source and doc files in `bun/`, one new `.bzl` (`platforms.bzl`), one
new package (`bun/private/windows_launcher`), `MODULE.bazel` (one registration), two new canaries,
new and extended tests in about 15 test files, one re-packed fixture archive and its lockfiles

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public API Boundary | Removes `bun_toolchain` from `bun/extensions.bzl` (never released, VII). Adds the musl values of `bun_repositories.platform` and of `bun.toolchain.integrity` keys (FR-024). The windows-launcher toolchain type, `platforms.bzl`, `NpmPackageTreeInfo` and the new `NpmInstanceInfo` fields are in `bun/private/` and undocumented for consumers. The names of `@<name>_toolchains` targets change; only `:all` is documented (contract). | Pass |
| II. Tested Claims | Each fix has a test that fails first (FR-023, tasks). Platform statements name the CI runner labels and jobs that ran the covering tests (R9), checked against the PR's run (quickstart Q12). musl is claimed for resolution and integrity only; running it on musl is reported unverified (R5). | Pass |
| III. Pinned, Verified Downloads | musl integrities converted from the official `SHASUMS256.txt` (E1). R1 keeps every applicable integrity check; R2 keeps credentials with Bazel's downloader. No host tool is probed; npm bins run only with the toolchain's Bun (R4). | Pass |
| IV. Minimum Dependency Versions | No `bazel_dep` changes. | Pass |
| V. Supported APIs Only | Optional toolchains, toolchain transition, toolchain registration order and `module_ctx.modules` order as bazel.build documents them (Part 1). hermetic-launcher (approved 2026-10-01) through its README's helpers and CLI only. New Bun reliances pinned by C17 and C18. Sources recorded in research Part 1. | Pass |
| VI. Shell-Free Actions; Launchers | The Windows stub is still a hermetic-launcher stub, compiled with `ctx.actions.run`; the Linux and macOS shell launcher is unchanged. | Pass |
| VII. Releases Come From Tags | No `version` in `MODULE.bazel`. Removing `bun_toolchain` breaks no published version (FR-019). The bin `manual` tag (D1) changes `bazel build //...` for consumers of an unreleased ruleset; the release notes name it. | Pass |

Post-design re-check (after Phase 1): unchanged, all pass. Decisions D1–D3 (research Part 5) were
approved by the user at the plan gate (2026-10-28); none conflicts with a MUST principle. Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/005-review-defect-fixes/
├── plan.md              # This file
├── research.md          # Phase 0: sources, decisions R1–R9, audits A1–A7, Bun register, D1–D3, evidence
├── data-model.md        # Phase 1: identity, bin decision, platform table, toolchain request, launcher toolchain, canaries
├── quickstart.md        # Phase 1: validation scenarios Q1–Q12
├── contracts/
│   └── public-api.md    # Phase 1: public API and user-visible text that change
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
MODULE.bazel                                    # register_toolchains("//bun/private/windows_launcher:all") (R6)
bun/
├── extensions.bzl                              # export bun and npm only (R9)
├── defs.bzl                                    # platform statement (R9)
├── platforms/libc/BUILD.bazel                  # comment: also selects the Bun (R5)
└── private/
    ├── platforms.bzl                           # NEW: NPM_OS, NPM_CPU, NPM_LIBC, BUN_ARCHIVES, constraint sets (R5)
    ├── versions.bzl                            # + linux-x64-musl, linux-aarch64-musl for 1.4.2, 1.4.4 (R5)
    ├── toolchains_repo.bzl                     # toolchains from the table, explicit libc (R5)
    ├── repositories.bzl                        # platform values from the table (R5)
    ├── extensions.bzl                          # root wins, conflicts, key/value validation (R8)
    ├── npmrc.bzl                               # has_userinfo public (R2)
    ├── npm_extension.bzl                       # user-info rejection, identity data, bins to repos, tag validation, docs (R1, R2, R4, R8, R9)
    ├── npm_repositories.bzl                    # check_list, case-insensitive BUILD, bin decision, manual bins (R4, R5, R7)
    ├── npm_package.bzl                         # NpmPackageTreeInfo; npm_instance identity and bins (R1, R4)
    ├── providers.bzl                           # NpmPackageTreeInfo; NpmInstanceInfo fields (R1, R4)
    ├── run.bzl                                 # identity in _equivalent/_check_unique, _check_bin, launcher toolchain, docs (R1, R4, R6, R9)
    ├── windows_launcher.bzl                    # NEW: windows_launcher_toolchain rule (R6)
    ├── windows_launcher/BUILD.bazel            # NEW: toolchain_type, toolchain (R6)
    └── BUILD.bazel                             # bzl_library targets (gazelle)
bun/tests/
├── toolchain_test.bzl, target_toolchain_test.bzl   # musl/glibc/unconstrained on both CPUs (US4)
├── versions_test.bzl                           # musl keys known for every version (FR-005)
├── platforms/BUILD.bazel                       # linux_aarch64_{glibc,musl} platforms
├── run_test.bzl                                # no-stub failures with the new type (US8-2)
├── canary/{c1_preserve_symlinks,c17_leading_dashdash,c18_extensionless_bin}.test.ts, BUILD.bazel  # R3
├── npm/{platforms_test,libc_test,uniqueness_test,bins_test,glob_test,npmrc_test,layout_test}.bzl   # R1, R4, R5, R7, R9
├── npm/registry/{pack.ts,write_lockfiles.ts}, archives (build-files, new extensionless-bin fixture)  # R4, R7
└── integration/
    ├── credentials.test.ts                     # bun.lock user info (US3)
    ├── multi.test.ts, workspaces/multi_*       # identity mismatches across hubs (US2)
    ├── toolchain_tags.test.ts, workspaces/toolchain_tags/   # NEW: root wins, conflict, unknown key (US5)
    ├── launcher_fetch.test.ts                  # NEW: no stub request for a Linux/macOS build (US8)
    ├── lockfile_errors.test.ts                 # tag validation (R8)
    ├── bins.test.ts                            # extensionless bin through npm_bin and generated target (US1)
    └── replace.test.ts                         # archive not visible → Bazel's visibility error (R9)
e2e/smoke/                                      # unchanged sources; must pass (bun.toolchain still works)
```

**Structure Decision**: two new private files (`platforms.bzl`, `windows_launcher.bzl`) and one
private package (`bun/private/windows_launcher`), because a `toolchain_type` and its `toolchain()`
need a package that `register_toolchains` can name with `:all` without registering anything else.
Every other change is in an existing file. Regenerated fixtures come only from `pack.ts` and
`write_lockfiles.ts` run with Bun 1.4.4.

## Implementation Order

`tasks.md` runs `check_list` (US6) and R6 (US8) after US1–US5 rather than in step 3, because they
share files with those stories; the dependencies below are unchanged.

Each step is test-first (FR-023): write the test, run it, record the red, fix, record the green
in `tdd-log.md`.

1. Branch: `005-review-defect-fixes` exists from `main` at `aca8c13`; commit the spec artifacts.
2. P1: R2 (`npmrc_test`, `credentials.test.ts`: `bun.lock` URL, resolution URL, duplicate entry,
   `.npmrc`), then R1 (`uniqueness_test` for each property; `multi` integration workspaces).
3. P2: `platforms.bzl` with unchanged behavior (existing suites green), then `check_list`
   (`platforms_test`), then musl (`versions_test`, `toolchain_test`, `target_toolchain_test`,
   `bazel fetch` of both musl repositories), then R6 (`launcher_fetch.test.ts` red, then the
   launcher toolchain; `run_test` no-stub cases; Windows verified in CI).
4. P3: C17, C18 (green against 1.4.4 and red under `RULES_BUN_CANARY_RED=1` or by an altered
   expectation, as feature 004's canaries); C1.
5. P4: extensionless-bin fixture archive and lockfile; `bins_test`, `bins.test.ts` red; R4.
6. P5: `toolchain_tags` integration workspace (root wins, non-root conflict, unknown key, bad
   value), `lockfile_errors.test.ts` for the `npm` validations; R8.
7. P6: re-pack `build-files` with the case variants; `glob_test`/layout case red; R7.
8. P7: remove `bun_toolchain`; layout case for resolution scope; `replace` visibility case; rewrite
   the docs (R9).
9. Gates (AGENTS.md): root `bazel run //:gazelle`, `prek run --all-files`, `bazel test //...`,
   `bazel test //... --noenable_runfiles --spawn_strategy=local --nocache_test_results`;
   `e2e/smoke` `bazel test //...`; push, open one PR, watch CI on all jobs (quickstart Q12); then
   finalize the platform statements against that run.

## Complexity Tracking

No violations.
