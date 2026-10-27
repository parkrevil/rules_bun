# Feature Specification: Upgrade the Pinned Bun to 1.4.4

**Feature Branch**: `003-npm-dependencies` (built on feature 003, delivered through PR #5)

**Created**: 2026-10-26

**Status**: Draft

**Input**: User description: "Upgrade the pinned Bun from 1.4.2 to 1.4.4 (released 2026-10-22,
https://github.com/oven-sh/bun/releases/tag/bun-v1.4.4), on top of feature 003 (branch
003-npm-dependencies, PR #5). Bun 1.4.2 runs git diff --no-index for bun patch --commit without
GIT_DIR, so git reads the .gitattributes of every directory above the patched folders; in an
unsandboxed bazel test (CI jobs manifest-only and windows-symlinks) that includes the symlinked
.gitattributes in Bazel execution root, git refuses it, and the C-PATCHED canary fails. Bun 1.4.4
sets GIT_DIR to the null device (oven-sh/bun commit e6f65f33c7, src/patch/lib.rs). Scope: the
default and development toolchain versions with each platform archive integrity taken from the
official release, the vendored archives of the Bazel-in-Bazel registry, every place that names Bun
1.4.2 behavior (docs, diagnostics, canaries, fixtures written by the pinned Bun such as bun.lock
files regenerated with write_lockfiles.ts and the scale fixture), and every upstream workaround: run
every canary (FR-028 and the bun.lock canaries) against 1.4.4 and, where one goes red, follow the
constitution (update the reader or the workaround with the documented or canary-pinned 1.4.4
behavior, or remove a workaround 1.4.4 no longer needs). No new public API. Done when root bazel
test //... and e2e/smoke bazel test //... pass, and PR #5 CI passes on Linux, macOS and Windows
including the unsandboxed jobs."

## Clarifications

### Session 2026-10-26

- Q: Should Bun 1.4.2 stay among the versions the ruleset knows, or be removed? → A: Keep 1.4.2
  and add 1.4.4; tests and canaries run against 1.4.4 only (FR-003).

### Session 2026-10-27

- Q: 1.4.4 writes and honors `libc`; read it (new public libc constraint) or leave it unread? → A:
  Read it in this feature, with a public libc constraint (constitution v2.3.0; FR-011–FR-014).
- Q: `unresolved` and `./<name>/<dep>` keys (research G1, G2)? → A: a follow-up feature.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The ruleset's own tests pass unsandboxed (Priority: P1)

A maintainer runs the ruleset's test suite without a sandbox, as the CI jobs `manifest-only` and
`windows-symlinks` do. With Bun 1.4.2 the C-PATCHED canary fails there: `bun patch --commit` runs
`git diff --no-index` without `GIT_DIR`, git reads the `.gitattributes` of every directory above the
patched folders, meets the symlinked `.gitattributes` in Bazel's execution root and refuses it. With
the pinned Bun at 1.4.4, which sets `GIT_DIR` to the null device for that call (oven-sh/bun commit
e6f65f33c7, `src/patch/lib.rs`), the canary and the rest of the suite pass in every CI job.

**Why this priority**: This is the defect that motivates the upgrade; PR #5 cannot merge while CI
is red.

**Independent Test**: Run the root suite with `--spawn_strategy=local` and without runfiles trees
(the `manifest-only` job's flags) on Linux, and the `windows-symlinks` job on Windows; C-PATCHED
passes in both.

**Acceptance Scenarios**:

1. **Given** the pinned Bun is 1.4.4, **When** the `manifest-only` CI job runs the root suite,
   **Then** C-PATCHED and every other test pass.
2. **Given** the pinned Bun is 1.4.4, **When** the `windows-symlinks` CI job runs, **Then**
   C-PATCHED and every other test pass.
3. **Given** the pinned Bun is 1.4.4, **When** the sandboxed `test` job runs on Linux, macOS and
   Windows, **Then** every test passes, as it did with 1.4.2.

---

### User Story 2 - A consumer gets Bun 1.4.4 without supplying integrity (Priority: P1)

A consumer writes `bun.toolchain(bun_version = "1.4.4")` in `MODULE.bazel` without an `integrity`
attribute. The ruleset knows the integrity of every platform archive of 1.4.4, downloads the exact
archive for each platform the consumer uses, verifies it and registers the toolchain. The ruleset's
documentation and examples name 1.4.4 as the version to use.

**Why this priority**: A pinned version the ruleset does not know forces every consumer to look up
five checksums by hand (constitution III).

**Independent Test**: `e2e/smoke`, which consumes the ruleset as a consumer would, requests 1.4.4
without integrity and its version test asserts the registered Bun reports `1.4.4`.

**Acceptance Scenarios**:

1. **Given** a consumer requests Bun 1.4.4 without integrity, **When** the toolchain is fetched on
   linux-x64, darwin-aarch64 or windows-x64 (the platforms CI runs), **Then** the archive is
   verified against the integrity taken from the release's official `SHASUMS256.txt` and the Bun it
   contains reports version `1.4.4`. For linux-aarch64 and darwin-x64, only the archive's
   integrity is verified (`bazel fetch`); nothing runs that Bun.
2. **Given** an archive whose content does not match the recorded integrity, **When** it is
   fetched, **Then** the fetch fails (unchanged behavior).

---

### User Story 3 - Every claim about Bun behavior is true of the pinned Bun (Priority: P2)

Every canary that pins upstream behavior the ruleset relies on or works around (the FR-028 canaries
of features 001 and 002 and the `bun.lock` canaries of feature 003) runs against 1.4.4. Each
docstring, diagnostic, comment and fixture that names Bun 1.4.2 behavior names 1.4.4 instead and is
true of 1.4.4. Fixtures the pinned Bun writes (the npm fixture `bun.lock` files written by
`write_lockfiles.ts`, the scale fixture, and any other recorded output of the pinned Bun) are
regenerated with 1.4.4. Where 1.4.4 behaves differently, the reader or the workaround is updated
to the documented or canary-pinned 1.4.4 behavior, and a workaround 1.4.4 no longer needs is
removed together with its canary.

**Why this priority**: Constitution II and V: a reliance on undocumented output is allowed only
while a canary pins it against the pinned Bun; after the upgrade, pins against 1.4.2 no longer
evidence anything.

**Independent Test**: Each canary passes against 1.4.4 (or is resolved per FR-006) and each
`bun.lock` canary, when its red mode is enabled, fails naming the reader or workaround, as before. A search of the repository outside `specs/` finds no
statement of Bun behavior that names 1.4.2.

**Acceptance Scenarios**:

1. **Given** a canary whose pinned behavior is unchanged in 1.4.4, **When** it runs, **Then** it
   passes, and its red mode still fails with the reader or workaround named.
2. **Given** a canary that goes red against 1.4.4, **When** the change is handed back, **Then**
   the reader or workaround it guards is updated to the 1.4.4 behavior (recorded in `research.md`
   with its evidence), or removed when 1.4.4 fixed the upstream defect, and the canary is updated
   or removed with it.
3. **Given** a fixture written by the pinned Bun, **When** it is regenerated with 1.4.4, **Then**
   its content is exactly what 1.4.4 wrote, with nothing rewritten by hand, and the tests that read
   it pass.
4. **Given** a lockfile with an unsupported `lockfileVersion`, **When** the build reads it,
   **Then** the diagnostic tells the user to run `bun install` with Bun 1.4.4.

---

### User Story 4 - Bazel-in-Bazel tests stay offline (Priority: P2)

The integration tests that run Bazel inside Bazel fetch Bun from the vendored archives of the
loopback registry, never from the network. After the upgrade, those vendored archives are the 1.4.4
release archives, verified with the same integrity as the toolchain, and the nested workspaces
request 1.4.4.

**Why this priority**: Without matching vendored archives the integration tests either fail or
reach the network, which the `network-denied` job forbids.

**Independent Test**: The integration suite passes in the `network-denied` CI job.

**Acceptance Scenarios**:

1. **Given** the vendored archives and nested workspaces name 1.4.4, **When** the integration
   tests run with network access denied, **Then** they pass.

### Edge Cases

- A consumer that still requests `bun_version = "1.4.2"` without integrity: the ruleset still knows
  1.4.2 and fetches it with the recorded integrity (FR-003); no test fetches it (research G3).
- A canary of an upstream defect that 1.4.4 fixed passes trivially or goes red in the "fixed"
  direction: the workaround it guards is removed, not left in place unguarded.
- A fixture regenerated with 1.4.4 differs from the 1.4.2 one only in fields the readers do not
  read: the regenerated content is committed as written; no reader change is needed.
- A 1.4.4 output field that the readers rely on and that is neither documented nor pinned: work
  stops and the gap is reported (constitution V), instead of relying on it unpinned.
- One platform archive of 1.4.4 is missing from the official release or from `SHASUMS256.txt`:
  work stops and the gap is reported; no integrity is computed from a local download.
- Strings that contain `1.4.2` but are unrelated to Bun (for example `bazel_skylib` 1.4.2 in the
  vendored registry and lock files, or version strings used as plain data in the semver tests) are
  left unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The ruleset MUST know Bun 1.4.4 for linux-x64, linux-aarch64, darwin-x64,
  darwin-aarch64 and windows-x64, with each archive's integrity taken from the official 1.4.4
  release's `SHASUMS256.txt`.
- **FR-002**: The ruleset's development toolchain, `e2e/smoke`, the vendored Bun archives of the
  Bazel-in-Bazel registry and every nested test workspace MUST use Bun 1.4.4.
- **FR-003**: Bun 1.4.2 MUST stay among the versions the ruleset knows, next to 1.4.4, with the
  integrity values feature 001 recorded from 1.4.2's `SHASUMS256.txt`, unchanged (constitution
  VII). The tests and canaries run against 1.4.4 only; no test fetches 1.4.2 after the upgrade
  (research G3), so the ruleset claims only that the entry is present and unchanged.
- **FR-004**: Every docstring, `doc =` string, diagnostic (`fail()` message, progress message, test
  failure message), comment and example outside `specs/` that names Bun 1.4.2 behavior or tells
  the user to use Bun 1.4.2 MUST name 1.4.4 and MUST be true of 1.4.4.
- **FR-005**: Every FR-028 canary and every `bun.lock` canary MUST run against Bun 1.4.4 and pass,
  or be resolved per FR-006. Each `bun.lock` canary's red mode (`RULES_BUN_CANARY_RED`) MUST still
  fail, naming the reader or workaround it guards; the FR-028 canaries have no red mode.
- **FR-006**: Where a canary goes red against 1.4.4, the reader or workaround it guards MUST be
  updated to the documented or canary-pinned 1.4.4 behavior; a workaround that 1.4.4 no longer
  needs MUST be removed together with its canary. Each such change MUST be recorded in the
  feature's `research.md` with its evidence and covered by a test (constitution II, V).
- **FR-007**: Every fixture produced by the pinned Bun (the npm fixture projects and their
  `bun.lock` files written by `write_lockfiles.ts`, the scale fixture, and any other recorded
  output of the pinned Bun) MUST be regenerated with Bun 1.4.4 and committed as Bun wrote it, with
  one exception: the `dependency_conflict` fixture is the lockfile 1.4.4 writes with one entry line
  removed, so that the check for a dependency with two resolutions has a lockfile to reject, and
  says so (research R12).
- **FR-008**: The change MUST add no public API other than the libc constraint of FR-011
  (constitution I, v2.3.0) and MUST NOT change the behavior of any public rule, macro, extension
  tag or generated target except where FR-006 or FR-013 requires it.
- **FR-009**: The test that fails with 1.4.2 in unsandboxed runs (C-PATCHED) MUST pass in the
  `manifest-only` and `windows-symlinks` CI jobs without a test-side workaround for the
  `.gitattributes` symlink.
- **FR-010**: Strings containing `1.4.2` that do not refer to Bun MUST be left unchanged.
- **FR-011**: The ruleset MUST provide the public constraint `//bun/platforms/libc:libc` with the
  values `:unconstrained` (its `default_constraint_value`), `:glibc` and `:musl`, laid out as
  rules_js's `@aspect_rules_js//platforms/libc` (research R11).
- **FR-012**: The lockfile reader MUST read each package entry's `libc` in the form Bun 1.4.4
  writes it, as it reads `os` and `cpu`. Reading it is approved by the user (2026-10-27,
  constitution V) and MUST be pinned by a canary (C-LIBC) with a red mode.
- **FR-013**: A package entry with `libc` MUST be linked for a target platform exactly when npm's
  rule (`npm-install-checks` `checkPlatform`) accepts it with the platform's libc: on Linux with
  `:glibc` or `:musl`, when the list accepts that value (including `!` negation and `any`); on a
  non-Linux OS, never, since npm defines libc only on Linux. On Linux with `:unconstrained`, it
  MUST be linked, as before this feature, because the platform does not say which libc it has.
- **FR-014**: The documentation of the npm extension MUST say how a consumer sets the libc of a
  platform (`constraint_values = ["@rules_bun//bun/platforms/libc:glibc"]`) and what
  `:unconstrained` does.

### Key Entities

- **Known Bun version**: a Bun release the ruleset can fetch without consumer-supplied integrity;
  holds one integrity per supported platform archive.
- **Canary**: a test that pins an upstream behavior the ruleset relies on or works around, against
  the pinned Bun, and fails naming the reader or workaround when that behavior changes.
- **Pinned-Bun fixture**: a committed file whose content the pinned Bun wrote and the tests read as
  ground truth.
- **Vendored archive**: a copy of a Bun release archive the Bazel-in-Bazel registry serves offline.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The root suite and the `e2e/smoke` suite pass locally, with zero failing or skipped
  tests attributable to the upgrade.
- **SC-002**: Every job of PR #5's CI run passes on Linux, macOS and Windows, including
  `manifest-only`, `windows-symlinks`, `network-denied` and `windows-without-bash`.
- **SC-003**: 100% of the FR-028 and `bun.lock` canaries run against 1.4.4; each one either passes
  or has been resolved per FR-006, and none is disabled.
- **SC-004**: Outside `specs/`, zero statements of Bun behavior or Bun usage instructions name
  1.4.2, except the 1.4.2 entry FR-003 keeps among the known versions.
- **SC-005**: A consumer requesting Bun 1.4.4 needs zero integrity values of their own.
- **SC-006**: For a lockfile with glibc and musl variants of one package, a target built for a
  Linux platform with `:glibc` links only the glibc variant, with `:musl` only the musl one, with
  `:unconstrained` both, and for a macOS or Windows platform neither; each case is covered by a
  test.

## Assumptions

- Bun 1.4.4 was released on 2026-10-22 with archives for all five supported platforms and an
  official `SHASUMS256.txt`.
- Bun 1.4.4 contains oven-sh/bun commit e6f65f33c7, which sets `GIT_DIR` to the null device for the
  `git diff --no-index` that `bun patch --commit` runs; C-PATCHED confirms it in the unsandboxed CI
  jobs.
- The `bun.lock` format 1.4.4 writes is the one the readers support (`lockfileVersion` unchanged);
  the `bun.lock` canaries confirm or refute it.
- The work is committed on branch `003-npm-dependencies` so that PR #5's CI exercises it; this
  spec's directory is independent of the branch name.
- The 1.4.3 release is not added; only 1.4.4 is introduced.
- The change touches `bun/`, `e2e/` and `MODULE.bazel`, so it goes through the speckit workflow
  (AGENTS.md).
