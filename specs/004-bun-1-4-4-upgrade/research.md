# Research: Upgrade the Pinned Bun to 1.4.4

**Feature**: `004-bun-1-4-4-upgrade` | **Date**: 2026-10-26 | **Spec**: [spec.md](spec.md)

Every source below was read on 2026-10-26. "Source" means the file at tag `bun-v1.4.4` (or
`bun-v1.4.2` where named) in oven-sh/bun, read through the GitHub API; "observed" means run with Bun
1.4.4 and is recorded in Part 3 at implementation. Static reading predicts; only a canary or an
observation decides (constitution II).

Part 1 holds the decisions R1–R10. Part 2 lists the gaps reported to the user. Part 3 is the
evidence log, with the canary results to be filled in at implementation. Part 4 lists the sources.

## Part 1: Decisions

### R1: Release archives and integrity (FR-001)

The release `bun-v1.4.4` was published 2026-10-22T10:11:32Z with all five archives the ruleset
supports and `SHASUMS256.txt` (plus `SHASUMS256.txt.asc`). Each integrity below is the
`SHASUMS256.txt` hex digest converted to SRI (`sha256-` + base64 of the bytes), the form
`versions.bzl` already uses; no archive was downloaded to compute it (E1).

| Platform | `SHASUMS256.txt` | SRI |
|---|---|---|
| linux-x64 | `bf8ccbfb2b0b80159e0f9a6d15c55317add8077534dbc6130a3edb52fccb395c` | `sha256-v4zL+ysLgBWeD5ptFcVTF63YB3U028YTCj7bUvzLOVw=` |
| linux-aarch64 | `baa6bb36f51d6e58561e02bbea825038a9df454f673d6d776e8bbf86f8c7850e` | `sha256-uqa7NvUdblhWHgK76oJQOKnfRU9nPW13bou/hvjHhQ4=` |
| darwin-x64 | `50a3491f73abc2fe81673171a85762d3bc2cc1680ccecadd983de99adf77977e` | `sha256-UKNJH3Orwv6BZzFxqFdi07wswWgMzsrdmD3pmt93l34=` |
| darwin-aarch64 | `c240d7f0ccb90c263a849fcdb09b7ee62630d921348ed6aafda86b9d577bc510` | `sha256-wkDX8My5DCY6hJ/NsJt+5iYw2SE0jtaq/ahrnVd7xRA=` |
| windows-x64 | `cd2c0fccc78f3ede1f50ca827a15f063eda13d4d150a3d0674f4f6e323d864a5` | `sha256-zSwPzMePPt4fUMqCehXwY+2hPU0VCj0GdPT24yPYZKU=` |

**Decision**: these five values, in `versions.bzl` under `"1.4.4"` and in the five
`integration_bun-*.zip` `http_file`s. Bazel's downloader verifies each archive against them on
first fetch; a mismatch fails the fetch (spec US2-2, unchanged behavior).

**Alternatives**: digests of locally downloaded archives (rejected: constitution III, spec Edge
Cases); the `-baseline` x64 archives (rejected: 1.4.2 uses the default builds; changing the build
flavor is out of scope).

### R2: Known versions (FR-003)

**Decision**: `TOOL_VERSIONS` keeps `"1.4.2"` and adds `"1.4.4"`; 1.4.3 is not added (spec
Assumptions). `versions_test` gains an assertion that both are known, so dropping 1.4.2 fails a
test. `bun.toolchain` has no default version (`bun_version` is mandatory), so "the default
version" of the user input is the version this repository's development toolchain and `e2e/smoke`
request.

**Alternatives**: replace 1.4.2 (rejected in spec Clarifications: a consumer pinning 1.4.2 without
integrity would stop building, constitution VII).

### R3: The upstream fix for C-PATCHED (FR-009)

Source `src/patch/lib.rs` line 1434 sets `GIT_DIR=<null device>` in the environment of the `git`
process `bun patch --commit` runs, with the comment "Without this, git inside a repository would
also read that repository's config and every .gitattributes above the two folders". The commit
`e6f65f33c72b367e978ad2ad75eb897c651cd0c0` is an ancestor of `bun-v1.4.4` (compare
`e6f65f33c7...bun-v1.4.4`: ahead, behind by 0) (E2). Its message also says, under `bun patch`:
"The project's own `.gitattributes`, `.git/info/attributes` or `.git/config` could change or empty
the patch. git runs without a repository."

**Decision**: no change to C-PATCHED or to any CI job; the `manifest-only` job (`--spawn_strategy=local`)
and the `windows-symlinks` job prove the fix (quickstart Q3, Q7). `bun patch --commit` still runs
`git`; the `windows-without-bash` job keeps Git's `cmd` directory on the test `PATH`.

### R4: Bazel-in-Bazel vendored archives (FR-002, US4)

`update.ts` writes `archives.bzl` and the marked `http_file` region of `MODULE.bazel`. It maps each
Bun archive URL to its integrity with a regular expression over every `"<platform>": "sha256-…"`
pair of `versions.bzl`, keyed to a hard-coded `bun-v1.4.2` URL. With two versions in
`TOOL_VERSIONS` the last pair per platform wins and is keyed to the wrong URL.

**Decision**: `update.ts` reads the integrities of the version the nested workspaces request
(1.4.4) from that version's block of `versions.bzl`, and builds the URL from the same version. The
nine nested `MODULE.bazel` files (`fetch`, `multi_root`, `replace`, `restricted`, `scale`,
`source_nm`, `stale_link`, `toolchain`, `winname`) request 1.4.4. Then `update.ts` is rerun with
network (it is the only writer of `archives.bzl` and the region); the diff must be the five Bun
URLs and integrities and nothing else, or the extra lines are reported (a registry module that
changed upstream would be a separate change).

**Alternatives**: edit `archives.bzl` and `MODULE.bazel` by hand (rejected: both are generated,
and the next `update.ts` run would disagree).

### R5: What 1.4.4 changes in `bun.lock` (static reading)

From the source of `src/install/lockfile/bun.lock.rs` at both tags and the commit message of
`e6f65f33c7` (E3, E4):

1. **`lockfileVersion`**: `version_to_write` is identical at both tags; `Version::from_int` still
   accepts 0–3 and `CURRENT` is 3. The FR-007 range (1, 2, 3) and C-VER / C-VER1 expectations hold.
2. **New optional keys, no version bump**: `"unresolved": [...]` next to `optionalPeers` (optional
   dependencies that could not be resolved, listed only when another package of that name is in
   the tree); `"hasInstallScript": true` in an npm entry's info object; `"./<name>/<dep>"`
   `packages` keys (dependencies of a workspace whose name the root gives to another package).
   The first two are declared in `bun.d.ts` (`packages/bun-types/bun.d.ts`, changed by the same
   commit). "A plain install doesn't rewrite a lockfile just to add the first two."
3. **Empty `trustedDependencies`**: 1.4.4 writes `"trustedDependencies": []` when the list is
   declared empty (comment: "A checkout without the workspace that declares `[]` must tell it from
   no list"); 1.4.2 has no such branch. bun.com `pm/lifecycle` already said "The lockfile records
   the list, even if it's empty."
4. **Resolution order**: "A fresh `bun install` writes the same `bun.lock` whichever response
   arrives first"; dependencies resolve in one fixed order. Fixture lockfiles may change in entry
   choice where ranges overlap; the regenerated files are the ground truth (R8).

**Consequence for the readers**: `hasInstallScript` is ignored by `read_lockfile` (it reads info
keys by name) and changes nothing, since no lifecycle script runs (FR-023 of feature 003).
`unresolved` and `./<name>/<dep>` are not read; see G1 and G2.

### R6: Canary expectations against 1.4.4 and how each red is resolved (FR-005, FR-006)

Expectation from R3, R5 and the upstream issue states (E5). Results are recorded in Part 3, E7.

| Canary | Pins | Expected with 1.4.4 | If red |
|---|---|---|---|
| C1 | relative imports resolve from the real path with `--preserve-symlinks` (oven-sh/bun#43689, open) | pass | revisit copy tree and guard; stop and report (a design change) |
| C2 | `CI=true` snapshot creates a header-only `.snap` (oven-sh/bun#44531, open) | pass | revisit FR-016b of feature 002 |
| C4 | `bun --config <path> <file>` runs `<path>` | pass | revisit the Windows first-process limitation |
| C7, C16 | Windows stub argument parsing and `BUN_OPTIONS` (hermetic-launcher, not Bun) | pass (independent of Bun) | revisit the documented Windows limitations |
| C13 | regular-expression limit 1,048,576 (oven-sh/bun PR #36757, open) | pass | `MAX_GUARD_PATTERN`, `run.bzl` limit text and the canary take the new limit the canary measures |
| C-VER, C-VER1 | `lockfileVersion` 2 / 3, 1 kept | pass (R5.1) | `SUPPORTED_VERSIONS` and the FR-007 diagnostic |
| C-WSKEY, C-WSNAME, C-WSDEPS, C-KEYPATH, C-SLOT0, C-URL1, C-URL2, C-INFO, C-INTEGRITY, C-INFODEPS, C-PEERS, C-OSCPU, C-BIN, C-OVERRIDES, C-CATALOG, C-ALIAS | the accesses L4–L22 | pass (no accessed key changed form, R5) | update the named reader to the canary-pinned 1.4.4 form |
| C-PATCHED | `patchedDependencies` keyed `name@version` | pass, now also unsandboxed (R3) | update `unsupported_reason` |
| C-TD | 1.4.2 writes no empty `trustedDependencies` | **red** in its first test (R5.3) | see below |
| C-WINNAME | Bazel's extractor on Windows names (Bazel, not Bun) | pass (independent of Bun) | — |

**C-TD decision (conditional on the observed red)**: feature 003 (research G4) documented that Bun
1.4.2 disagrees with bun.com and kept C-TD so the documentation could be revisited when Bun changed.
With 1.4.4 Bun and bun.com agree, so the documentation no longer states undocumented Bun behavior:
the clause "and Bun 1.4.2 writes no empty `trustedDependencies` to `bun.lock`" is removed from
`run.bzl`, and C-TD is removed with its `BUILD` target, as FR-006 requires for a workaround 1.4.4
no longer needs. The ruleset's own behavior ("No lifecycle script runs, whatever
`trustedDependencies` says") is unchanged and stays covered by `scripted.test.ts`. If C-TD passes
instead, the source reading was wrong: the canary stays, its text names 1.4.4, and the finding is
recorded here.

**Alternatives**: invert C-TD to pin that 1.4.4 writes `[]` (rejected: the ruleset reads neither
list, so the canary would guard no reader or workaround; behavior bun.com documents needs no
canary, constitution V).

**Outcome (E7)**: C-TD went red as predicted and was resolved as above. One canary the source
reading did not predict went red, C-OSCPU (1.4.4 writes `libc`); it is reported as G4, not
resolved. Every other canary passed.

A canary that goes red with a change the source did not predict is resolved by the "If red" column;
where that needs a new lockfile access or a design change, work stops and the gap is reported
(constitution V; spec Edge Cases).

### R7: Bun behavior the ruleset works around without a canary of its own

Three statements name 1.4.2 behavior that no FR-028 or `bun.lock` canary pins; each is checked
against 1.4.4 by a test that already exists or by an observation recorded in Part 3 before its
text is changed:

| Statement | Where | Covered by | Decision |
|---|---|---|---|
| Bun drops a `--` directly after the entry point | `launcher.js` (`fail`), `run.bzl` `bun_binary` doc, `args.test.ts` | `args.test.ts` asserts the ruleset's error, not Bun's drop | Observe `bun <entry> -- x` with 1.4.4 (E8). Still dropped: text names 1.4.4. Fixed: report to the user before removing the error, because removing it changes `bun_binary` behavior (FR-008) |
| Bun does not install a missing package under `bun test` | `run.bzl` `bun_test` doc | `run/isolation/install.test.ts` | Test passes with 1.4.4: text names 1.4.4. Fails: stop and report (auto-install changed in 1.4.4, R5 source "Auto-install reads `.npmrc` …") |
| Coverage `SF:` paths are relative to the working directory at exit | `run/protocol/coverage/chdir.test.ts` | that test (`coverage` CI job) | Passes: text names 1.4.4. Fails: update the coverage handling to the observed 1.4.4 form |

Workspace glob semantics (`workspaces.bzl`, `glob_cases.bzl`, `workspaces_test.bzl`) are pinned
by `glob_compare.test.ts`, which runs the pinned Bun on every case; its result decides the same way
as a canary.

**Outcome (E7, E8)**: `--` is still dropped, `install_test` and the coverage tests pass, so those
three statements name 1.4.4. `glob_compare_test` went red: 1.4.4 applies a negative pattern
wherever it stands in the list, which the static reading did not predict; the matcher and its
cases follow 1.4.4 (E7), and the `workspaces.bzl` and `workspaces_test.bzl` text says so.

### R8: Regenerating what the pinned Bun wrote (FR-007)

**Decision**: each file is regenerated by its existing writer, run with the Bun 1.4.4 binary of the
development toolchain (`$(bazel info output_base)/external/+bun+bun_linux-x64/bun`), and committed
as written; nothing is edited by hand except the two edits the writer itself makes (version1's
stamp, the removed state entry, both already in `write_lockfiles.ts`). Order:

1. `bun/tests/run/isolation/registry/rules-bun-fixture-pkg-1.0.0.tgz`: `bun pm pack` in its source
   folder (the test computes its integrity at run time).
2. `bun/tests/npm/registry/pack.ts`: the npm fixture archives (`bun pm pack`, except the three it
   writes itself). If the bytes are unchanged, nothing below changes because of them.
3. `bun/tests/npm/registry/write_lockfiles.ts` with no arguments: every fixture project and
   `bun.lock`, fresh installs against the loopback registry, with its own key assertions.
4. `bun/tests/npm/scale/generate.ts`: `bun.lock` and `package.json` of the scale fixture (the
   archives are written by the script with fixed bytes, not by Bun).
5. The inline lockfiles of `credentials.test.ts` and `registries.test.ts`: written by `bun install`
   of 1.4.4 for the test's `package.json` against the loopback registry, with the URL slots
   replaced by the test's `${urls.*}` placeholders as the existing text does; their comments name
   1.4.4.
6. `e2e/smoke/bun.lock`: re-saved by `bun install --lockfile-only` with 1.4.4 on the existing
   lockfile (public registry). A fresh install is not used, because it could move `scheduler`
   within `^0.27.0` to a version the root's checked-in react archives do not have; the re-save is
   what 1.4.4 writes for this project and passes `--frozen-lockfile`.

The `jsx` fixture's react archives come from the npm registry (`fetch_react.ts`), not from Bun,
and are not regenerated. Unit tests whose expectations read fixture content (`lockfile_test.bzl`,
`fixture_results.bzl`) are updated only where the regenerated content differs, to what 1.4.4 wrote.

**Alternatives**: keep the 1.4.2 fixtures (rejected: FR-007; the canaries and fixtures would
evidence 1.4.2, not the pinned Bun).

### R9: Statements that name 1.4.2 (FR-004, FR-010, SC-004)

Search on `003-npm-dependencies` outside `specs/` for `1.4.2` (E6). Changed to 1.4.4, each true of
1.4.4 by R6, R7 or R8:

- Versions requested: `MODULE.bazel` (dev toolchain, five `http_file` URLs via R4),
  `archives.bzl`, nine nested `MODULE.bazel`, `e2e/smoke/MODULE.bazel`,
  `e2e/smoke/BUILD.bazel` (`expected_version`), `update.ts`.
- Examples of a version string in docs: `bun/extensions.bzl` module docstring,
  `bun/private/extensions.bzl` (`bun_version` doc), `providers.bzl` (`version` field doc),
  `toolchain.bzl` (`bun_target_toolchain` example).
- Diagnostics: `lockfile.bzl` FR-007 message ("the versions Bun 1.4.4 writes: run `bun install` with
  Bun 1.4.4"), and the two expectations in `lockfile_errors.test.ts`; `launcher.js` guard-limit and
  `--` messages, and `args.test.ts`'s expectation (R7).
- Docs and comments of Bun behavior: `check_integrity.js`, `npm_extension.bzl` (`==` form,
  C-INTEGRITY), `run.bzl` (guard limit C13, `--` R7, `trustedDependencies` R6, auto-install R7),
  `workspaces.bzl`, `glob_cases.bzl`, `glob_compare.test.ts`, `workspaces_test.bzl` (R7 globs),
  `c13_regexp_limit.test.ts`, the headers of C-CATALOG, C-INTEGRITY, C-OVERRIDES, C-URL1, C-URL2,
  C-VER, C-VER1, `write_lockfiles.ts` (catalog comment), `fetch_algorithms.test.ts`,
  `credentials.test.ts`, `registries.test.ts`, `chdir.test.ts`.

Left unchanged (FR-010): `bazel_skylib` 1.4.2 in the vendored registry, `MODULE.bazel.lock` and
`e2e/smoke/MODULE.bazel.lock`; `rules_python` 1.4.2 in the vendored registry's `metadata.json`;
the version strings of `bun/tests/semver_test.bzl`, which are data. The `versions.bzl` 1.4.2 entry
stays (FR-003).

### R10: Branch

**Decision**: the spec says the work is committed on `003-npm-dependencies` so PR #5's CI runs it.
The workflow created `004-bun-1-4-4-upgrade` from `main`; it had no commits and was deleted after
the plan step, and this directory (untracked) moved with the checkout of `003-npm-dependencies`,
where the implementation commits go.

### R11: libc (G4, user decision 2026-10-27; FR-011–FR-014)

**Decision**: read `libc` and select by a public libc constraint.

- Constraint: `//bun/platforms/libc:libc` with `default_constraint_value = ":unconstrained"` and the
  values `:unconstrained`, `:glibc`, `:musl`, as rules_js's public `platforms/libc/BUILD.bazel`
  (aspect-build/rules_js, `@aspect_rules_js//platforms/libc`); `@platforms` has no libc constraint.
  Constitution I lists it (v2.3.0).
- Reading: `libc` is read where `os` and `cpu` are (`lockfile.bzl`, L15), with the same string-or-
  list handling; C-LIBC pins the form 1.4.4 writes (`"libc": "glibc"` / `"musl"` for a single-libc
  package) and has a red mode.
- Selection, npm's rule (npm/npm-install-checks `lib/index.js` `checkPlatform`): `libcOk =
  checkList(libc, target.libc)`, false when the environment has no libc, which npm defines only on
  Linux. So a restricted optional edge's condition becomes `[os, cpu, libc]`: on `@platforms//os:linux`
  with `:glibc` / `:musl` it holds when `checkList` accepts the value (`!` negation, `any`); on
  any other OS it never holds; on Linux with `:unconstrained` it holds, as before this feature,
  because Bazel cannot tell which libc an unconstrained platform has (rules_js links every libc
  variant on such a platform as well). The default therefore changes nothing for a consumer who
  does not set the constraint.
- C-OSCPU is changed to pin what 1.4.4 writes for `os`/`cpu` with `libc` beside them, no longer
  "`libc` is not written"; the statements in `npm_extension.bzl` and `platforms_test.bzl` are
  rewritten to the new behavior.
- Tests: analysis tests over the four platform cases of SC-006 (`bun/tests/platforms` gains Linux
  platforms with `:glibc` and `:musl`), using the `basic` fixture's glibc/musl variants.

### R12: A fixture for the dependency conflict (G5)

**Decision**: a fixture project `dependency_conflict` (`a`, `b`, `x@2.0.0`, `y`, `z`) whose lockfile
is the one Bun 1.4.4 writes with its `y/x/b` entry line removed, as the `missing_peer` project
removes one entry; `write_lockfiles.ts` asserts that the line existed and that x@1.0.0's `b` then
resolves to b@2.0.0 under `y` and b@1.0.0 under `z`. No Bun writes this lockfile; it exists so
that `uniqueness_dependency_test` keeps a lockfile the ruleset must reject (constitution II).

**Evidence (2026-10-27, Linux x64)**: for the `basic` dependencies and reduced sets, Bun 1.4.4
wrote `y/x/b` = b@1.0.0 or hoisted `x`, and ignored a `"y>x>b"` override. Bun 1.4.2 (archive
verified against the 1.4.2 entry of `versions.bzl`) wrote `z/x/b` = b@2.0.0 for the full `basic`
set, as the committed 1.4.2 lockfile has, but `y/x/b` = b@1.0.0 once `q2-user` was dropped, so
its output depends on the rest of the dependency set; running it would not give a fixture whose
shape a reader can predict.

### R13: Byte-reproducible fixture writers (G6)

**Decision**: `startRegistry` takes an optional `port` (default 0, a free port, as now), and
`write_lockfiles.ts` and `scale/generate.ts` pass one fixed loopback port, so a rerun writes the
same bytes and quickstart Q4 holds without "modulo the port". All their lockfiles are regenerated
once with that port, committed as written. A busy port makes the writer fail with Bun's error; the
writers are run by hand.

## Part 2: Gaps reported to the user (constitution V)

### G1: `"unresolved"` is not read

1.4.4 lists, under `"unresolved"`, an optional dependency that it left unbound because no version
fits, when another package of that name is in the tree. `resolve.bzl`'s `walk_key` binds an
optional dependency to the first key of that name on the walk, so for such a lockfile the ruleset
links the other package where Bun 1.4.4 links nothing. That is the binding 1.4.2 itself made ("an
older one binds by name as before"), so the ruleset's behavior does not change with this upgrade.
Reading the key is a new lockfile access, which needs the user's approval (feature 003, research
Part 4) and a canary, and would change resolution (FR-008). No fixture produces it.

### G2: `"./<name>/<dep>"` keys are not read

For a workspace whose name the root gives to another package (for example the root depends on
`lib@npm:other` and a workspace is named `lib`), 1.4.4 writes that workspace's dependencies under
`./lib/<dep>`. `_workspace_children` starts the walk at `[<name>]` and looks for `lib/<dep>`, then
`<dep>`, so it misses the entry and either binds the root-level `<dep>` or fails with "declares …,
which bun.lock lists no entry for". Handling it is a new access (approval, canary) and a resolver
change; out of scope here (FR-008). No fixture produces it.

**Decision (user, 2026-10-26)**: G1 and G2 are left out of this feature and become the next
feature, which reads both keys with the approval and canaries constitution V requires.

### G3: 1.4.2 is known but no longer fetched by a test

After the upgrade no test downloads the 1.4.2 archives: `versions_test` checks that the entry is
present and well formed, and its integrities are the ones feature 001 recorded from 1.4.2's
`SHASUMS256.txt`. The claim "a consumer pinning 1.4.2 keeps building" (FR-003) is therefore
covered by those two only; documentation must not claim more (constitution II).

### G4: 1.4.4 writes and honors `libc` (found at implementation, open)

C-OSCPU pins "`libc` is not written" (feature 003, G6: "a package with `"libc": ["glibc"]` gets
`{ "os": "linux", "cpu": "x64" }`, no `libc`", so "all `libc` variants for an OS and CPU are
included; that is the only behavior the lockfile allows"). 1.4.4 writes `"libc": "glibc"` or
`"libc": "musl"` for a package restricted to one libc, and on a glibc host no longer installs the
`-musl` variant (E7). **Resolved by R11** (user decision 2026-10-27). The reader ignores `libc`, so the ruleset still links every variant for the
target's OS and CPU; its behavior does not change with this upgrade, but the reason feature 003
documented no longer holds, and the ruleset now differs from what Bun 1.4.4 installs. The
regenerated `basic`, `restricted` and `workspace` lockfiles carry the new key. Resolving it is
the user's choice: reading `libc` (a new lockfile access with approval and a canary, and a
resolver change, FR-008), or keeping it unread and changing C-OSCPU to pin the 1.4.4 form with the
documentation saying why. C-OSCPU stays red until then.

### G5: the `basic` fixture no longer produces a dependency conflict (found at implementation, resolved by R12)

`uniqueness_dependency_test` (feature 003) expects the error for one package version whose
dependency resolves to different versions in one closure, made by `y/x` and `z/x` (both
x@1.0.0) whose `b` was b@2.0.0 at `y/b` and b@1.0.0 at the root. 1.4.4 resolves x@1.0.0's `b`
to b@1.0.0 in both places (it writes `y/x/b` rather than use `y/b`, R5.4), so the closure holds one
x@1.0.0 instance and the test fails for lack of the error. The ruleset's check is unchanged;
the fixture no longer exercises it. A replacement needs a fixture design decision (a lockfile
1.4.4 writes with such a conflict, if one exists, or a lockfile kept from an older Bun, which
FR-007 does not allow for these fixtures). The test stays red until then.

### G6: the fixture writers are not byte-reproducible (resolved by R13)

The loopback registry of `write_lockfiles.ts` and `scale/generate.ts` listens on a random port,
and Bun writes full URLs, so every rerun rewrites every URL of every fixture lockfile (E9); at
1.4.2 the committed ports already differed per file. The content is otherwise reproducible.
Quickstart Q4's "no change" holds only modulo the port; the files are committed as written
(FR-007).

## Part 3: Evidence log

Data in `/tmp/bun144`, separate from any script.

- **E1** (2026-10-26): `gh release view bun-v1.4.4 -R oven-sh/bun` lists the five archives and
  `SHASUMS256.txt`; `curl -sSL …/bun-v1.4.4/SHASUMS256.txt`; the SRI values of R1 by
  `echo -n <hex> | xxd -r -p | base64`.
- **E2** (2026-10-26): `gh api repos/oven-sh/bun/compare/e6f65f33c7...bun-v1.4.4` → `ahead`,
  `behind_by` 0; `src/patch/lib.rs` at `bun-v1.4.4`, line 1434, `GIT_DIR=` + `null_device!()`.
  `compare/bun-v1.4.2...bun-v1.4.4`: 684 commits.
- **E3** (2026-10-26): `src/install/lockfile/bun.lock.rs` at `bun-v1.4.2` and `bun-v1.4.4`:
  `version_to_write` identical (`diff` empty); `"trustedDependencies": [],` occurs 0 times at 1.4.2,
  once at 1.4.4; `unresolved` and `hasInstallScript` writers present at 1.4.4.
- **E4** (2026-10-26): commit message of `e6f65f33c7` (1,182 lines), sections "Behavior changes to
  sign off", "Resolution and lockfile", "`bun patch`", "Workspaces".
- **E5** (2026-10-26): oven-sh/bun#43689 open, #44531 open, PR #36757 open (not merged).
- **E6** (2026-10-26): `git grep -n '1\.4\.2' 003-npm-dependencies -- . ':!specs'` → the R9
  inventory.
Results below ran on 2026-10-26 on Linux x64 only (WSL2, `bun test v1.4.4 (38afee6c8)`); macOS
and Windows results come from CI and are recorded in the PR #5 description (constitution II).

- **E7** (canaries and behavior tests against 1.4.4, on the unchanged 1.4.2 fixtures):
  - `bazel test //bun/tests/canary/... --nocache_test_results` and the same with
    `--noenable_runfiles --spawn_strategy=local`: identical results. 22 pass (C1, C2, C4, C13,
    C-ALIAS, C-BIN, C-CATALOG, C-INFO, C-INFODEPS, C-INTEGRITY, C-KEYPATH, C-OVERRIDES, C-PATCHED,
    C-PEERS, C-SLOT0, C-URL1, C-URL2, C-VER, C-VER1, C-WSDEPS, C-WSKEY, C-WSNAME); 3 skipped as
    Windows-only (C7, C16, C-WINNAME); 2 red:
    - C-TD, first test ("an empty trustedDependencies is not written"), observed `[]`: as R6
      predicted. Resolved by R6 (canary, target and the `run.bzl` 1.4.2 clause removed);
      `bazel test //bun/tests/npm/fixtures/basic:scripted_test` passes.
    - **C-OSCPU, not predicted**: "info os and cpu (one value)", observed
      `{"os":"linux","cpu":"x64","libc":"glibc"}` for a package that declares `"libc": ["glibc"]`.
      Source: `bun.lock.rs` at `bun-v1.4.4` lines 1053–1059 write `"libc": "<name>"` when the
      package restricts itself to a single libc, and lines 2602–2603 read it back; at `bun-v1.4.2`
      the writer is commented out (lines 1170–1174, "libc (soon)"). Commit `9510e74152` (#44968):
      "glibc hosts stop installing `-musl` variants", "`libc` is honoured (#40057)". R5 missed
      it. Not resolved: see G4.
  - C-PATCHED alone, sandboxed and with `--noenable_runfiles --spawn_strategy=local`: pass with no
    edit to the canary or CI (R3 confirmed locally). `git grep -i gitattributes -- . ':!specs'`:
    no hit (FR-009).
  - Red mode, `bazel test //bun/tests/canary/npm/... --test_env=RULES_BUN_CANARY_RED=1
    --nocache_test_results`: all 20 `bun.lock` canaries that run on Linux fail with
    `rules_bun canary <ID>: Bun's bun.lock <access> changed: revisit <reader>`; C-WINNAME skipped.
  - R7: `//bun/tests/run/isolation:install_test`, `coverage_test`, `coverage_chdir_test`,
    `coverage_spawn_test` pass; the `coverage` job's two commands (`bazel coverage
    --combined_report=lcov …:coverage_test`, `bazel run …:coverage_check`) pass.
  - **`glob_compare_test` red, not predicted**, in case `negation_first`
    (`["!packages/excluded", "packages/*"]`): 1.4.4 lists `packages/a`, `packages/ab`,
    `packages/b`; the 1.4.2-order matcher also kept `packages/excluded`. Probes with
    `"$B" install --lockfile-only` in `/tmp/bun144-glob` (every directory with a `package.json`):

    | `workspaces` | 1.4.4 members |
    |---|---|
    | `["!packages/excluded","packages/*"]` | a, ab, b |
    | `["packages/*","!packages/a*","packages/a*"]` | b, excluded |
    | `["!packages/a*","packages/*","packages/ab"]` | ab, b, excluded |
    | `["packages/a","!packages/a"]`, `["!packages/a","packages/a"]`, `["packages/a","!packages/*"]` | a |
    | `["**","!packages/**"]` | other/c, tools/t1 (`packages` itself removed) |
    | `["packages/*","!./packages/excluded"]`, `["packages/*","!packages/excluded/"]` | a, ab, b |
    | `["packages/*","!packages/./excluded"]` | a, ab, b, excluded (not removed) |
    | `["packages/*","!/packages/a"]` | a, ab, b, excluded (not removed) |

    Upstream: commit `9510e74152` (#44968) item 10, "negated entries work in every spelling
    (`!./pkg`, `!pkg/`) and position, add no members" (#43401, #43400). Resolved (T017):
    `match_members` applies every negative pattern after all positive ones, to glob matches only;
    five cases added to `glob_cases.bzl` (`negation_then_glob`, `negation_globstar_dir`,
    `negation_dot_slash`, `negation_trailing_slash`, `negation_glob_of_path`) and
    `workspaces_test.bzl` updated; `glob_compare_test` passes all 29 cases. The last two rows are
    not followed: the matcher normalizes a `./` segment inside a pattern and a leading `/`, and no
    case covers them.
- **E8**: `/tmp/bun144-e8/main.js` printing `process.argv.slice(2)`; `"$B" /tmp/bun144-e8/main.js
  -- x` prints `["x"]`: 1.4.4 still drops the `--`, so the `bun_binary` error stays and names 1.4.4.
- **E9** (toolchain and fixtures):
  - R13 (2026-10-27): `startRegistry({ port })` (test "listens on the port it is given");
    `write_lockfiles.ts` and `scale/generate.ts` serve on `FIXTURE_PORT` 28761. After one
    regeneration of every project and the scale fixture, a second run of both left
    `git diff --name-only bun/tests/npm` empty. The text below describes the runs before R13.
  - R11 (2026-10-27): `restricted_test` (Bazel-in-Bazel) first failed with "no such package
    '@@rules_bun+//bun/platforms/libc'": the new package was not in `//bun:all_files`, the files
    the module ships; added. Gates after T046–T050, Linux x64: gazelle no change, `prek` passes,
    root `bazel test //...` 278 pass, 3 skipped (Windows-only), also with
    `--noenable_runfiles --spawn_strategy=local --nocache_test_results`; `e2e/smoke` 4 pass.
  - Workflow reviews (2026-10-27): Codex approved with no findings; the Claude review reported five
    low-severity gaps, all fixed: a libc-restricted bin had no test (the fixture package
    `bin-linux-x64-musl` with libc musl, and `restricted_test` builds its bin as incompatible on a
    `:glibc` platform and buildable on a `:musl` one, in an inner workspace using
    `@rules_bun//bun/platforms/libc`); the `_compatible` docstring and the `platforms_test`
    header named only `os`/`cpu`; `//bun/tests:versions` now asserts the 1.4.2 integrities equal
    feature 001's; the `dependency_conflict` fixture's BUILD file says its lockfile is edited.
    Gates again: `prek` passes, root 278 pass, 3 skipped (also unsandboxed), `e2e/smoke` 4 pass.
  - `"$B" --version` → `1.4.4` (after `bazel fetch --repo=@bun_linux-x64`);
    `bazel test //bun/tests:versions` 3 pass; `e2e/smoke` `bazel test //:version_test` pass.
    Neither `MODULE.bazel.lock` changed.
  - `bun pm pack` of `rules-bun-fixture-pkg` in `/tmp/bun144-pack`: byte-identical archive;
    `install_test` passes. `pack.ts`: no archive changed, SRIs unchanged.
  - `write_lockfiles.ts`: exit 0, its key assertions pass. `lockfileVersion`: version1, unsupported,
    restricted 1; overrides_object, overrides_gt, overrides_range, overrides_path, overrides_glob 3;
    every other project 2. `git diff --stat bun/tests/npm/fixtures/`: 25 files, 116+/116−. Every
    file changes the loopback port of its URLs (the registry listens on a random port each run).
    Changes beyond the port: `basic` (`native-linux-x64` gains `"libc": "glibc"`,
    `native-linux-x64-musl` `"libc": "musl"`, `scripted` `"hasInstallScript": true`, and the key
    `"z/x/b"` b@2.0.0 becomes `"y/x/b"` b@1.0.0: 1.4.4 resolves `x@1.0.0`'s `b` to b@1.0.0 under
    both `y` and `z`, R5.4), `restricted` (both `libc`), `workspace` (`native-linux-x64` `libc`).
  - `scale/generate.ts`: exit 0 (2000 packages, 5662 edges); `bun.lock` changes only the port,
    `package.json` unchanged.
  - Inline lockfiles: `"$B" install` of `workspaces/registries/package.json` against a loopback
    registry serving `@scope/s`, `a`, `b` writes, apart from the URL slots, exactly the lockfile
    both `credentials.test.ts` and `registries.test.ts` hold; only their comments changed. Both
    tests pass.
  - `e2e/smoke`: `"$B" install --lockfile-only` → "no changes"; `bun.lock` unchanged.
  - Resolver expectations: with the new `basic`, `resolve_test` expects `walk_key` `y/x/b` and
    `b` and the closure of `y` with both `b` versions; an inline map keeps the nearest-parent case
    the fixture no longer has. `uniqueness_dependency_test` fails: see G5.
  - Reproducibility (quickstart Q4): rerunning `bun pm pack`, `pack.ts`, `write_lockfiles.ts` and
    `scale/generate.ts` leaves every file identical except the loopback port in the lockfile URLs,
    so the writers are not byte-reproducible (as at 1.4.2: the committed ports already differed
    per file). See G6.
  - `update.ts`: exit 0. The kept diff is the five `bun-v1.4.4` URLs of `archives.bzl` and the
    five `integration_bun-*.zip` URLs and integrities of `MODULE.bazel`, equal to R1. Not kept:
    upstream versions the run added to registry `metadata.json` files (bazel_features 1.53.0,
    hermetic_launcher 0.0.17, pybind11_bazel 3.0.3, rules_cc 0.2.27, rules_python 2.4.3–2.4.5).
  - `bazel test //bun/tests/integration:integration_tests --nosandbox_default_allow_network
    --nocache_test_results`: 19 pass; each test's `assertOffline` found no path the loopback
    server does not serve.
  - Gates: `bazel run //:gazelle` no change; `prek run --all-files` pass; root `bazel test //...`
    and the same with `--noenable_runfiles --spawn_strategy=local --nocache_test_results`: 268
    pass, 3 skipped, 2 fail (C-OSCPU, `uniqueness_dependency_test`); `e2e/smoke` `bazel test //...`
    4 pass.

## Part 4: Sources

Bun:

- https://github.com/oven-sh/bun/releases/tag/bun-v1.4.4 — release, assets, `SHASUMS256.txt`
- https://github.com/oven-sh/bun/commit/e6f65f33c72b367e978ad2ad75eb897c651cd0c0 — `GIT_DIR`, lockfile keys, `bun patch` changes
- https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/patch/lib.rs — line 1434
- https://github.com/oven-sh/bun/blob/bun-v1.4.4/src/install/lockfile/bun.lock.rs — version stamp, `unresolved`, `hasInstallScript`, empty `trustedDependencies`
- https://github.com/oven-sh/bun/blob/bun-v1.4.2/src/install/lockfile/bun.lock.rs — the 1.4.2 writer, for comparison
- https://github.com/oven-sh/bun/blob/bun-v1.4.4/packages/bun-types/bun.d.ts — lockfile types with the new keys
- https://bun.com/docs/pm/lifecycle — "The lockfile records the list, even if it's empty"
- https://bun.com/docs/pm/lockfile — text lockfile
- https://github.com/oven-sh/bun/issues/43689, https://github.com/oven-sh/bun/issues/44531, https://github.com/oven-sh/bun/pull/36757 — open upstream issues behind C1, C2, C13

Bazel 9.2.0:

- https://bazel.build/versions/9.2.0/rules/lib/repo/http — `http_file(integrity)`
- https://bazel.build/versions/9.2.0/rules/lib/builtins/repository_ctx — `download_and_extract(integrity)`
- https://bazel.build/reference/command-line-reference — `--enable_runfiles`, `--spawn_strategy`, `--windows_enable_symlinks`, `--test_env`
