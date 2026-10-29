# Feature Specification: Link What the Pinned Bun Links, by Construction and by Test

**Feature Branch**: `006-bun-conformant-resolution`

**Created**: 2026-10-29

**Status**: Draft

**Input**: User description: "Redesign how rules_bun binds npm dependencies from bun.lock, so it
links exactly what the pinned Bun links, by construction and by test, instead of by case-by-case
rules. The user decided this on 2026-10-29 after the earlier feature-006 attempt (G1 \"unresolved\",
G2 \"./<name>/<dep>\" keys) kept surfacing further mismatches (optional or peer dependencies without
a key failing the build where Bun leaves them unlinked; a registry package's dependency on a
workspace member not linked; a peer nothing provides failing the build). Root cause:
bun/private/resolve.bzl (and the walks in lockfile.bzl, workspaces.bzl, npm_extension.bzl) were
written in feature 003 by fitting rules to fixture outputs, not by carrying over Bun's algorithm,
so differences surface only where someone looks. Design: (1) Bun's text-lockfile loader at tag
bun-v1.4.4 (oven-sh/bun, src/install, the bun.lock reader and the code that turns lockfile keys
and dependencies into package IDs and resolutions, and the isolated linker that lays out
node_modules) is the specification, since bun.com documents only the format's outline
(constitution V; the user approves reading every bun.lock field and key form that this algorithm
reads, each pinned by a canary with a red mode). The resolver is rebuilt as a carry-over of that
algorithm, with the same structure, each function citing the Bun source lines it follows. (2) A
differential conformance test makes the pinned Bun the oracle: for every npm fixture project and a
corpus of edge-case projects (workspaces named like aliased packages, unresolved optionals,
optional and peer dependencies without a key, registry packages depending on workspace members,
peers nothing provides, nested and hoisted keys, overrides, catalogs), the pinned Bun's isolated
install (bun.com docs install/isolated) is run offline against the loopback registry, its linked
dependency graph is recorded, and the ruleset's resolution of the same lockfile must equal it; any
difference fails the test. Platform-specific optional packages are compared for the host platform;
documented intentional differences (no lifecycle scripts; selection by Bazel target platform) are
listed explicitly and are the only exceptions. (3) Lockfiles written by Bun 1.4.2, still a known
version, keep resolving as Bun 1.4.2's own install links them, checked the same way where 1.4.2 is
available. (4) No public API changes; the generated targets keep their names; behavior changes
only where the ruleset differed from Bun, each listed. Prior research to reuse (Bun 1.4.4 source
lines for unresolved, ./<name>/<dep>, unlinked workspaces, missing keys, and an audit of key
walks): /tmp/claude-1000/-home-revil-projects-rules-bun/acf65d17-aa18-4312-9b49-89b675aee735/scratchpad/006-prior/research.md.
Done when the conformance test covers every fixture and the edge-case corpus with zero
differences, root bazel test //..., the unsandboxed run, e2e/smoke bazel test //..., prek, and PR
CI on Linux, macOS and Windows pass. Work on a branch from main and deliver it as one PR."

**Approval (user, 2026-10-29)**: the user approves reading every `bun.lock` field and key form
that Bun 1.4.4's text-lockfile loader and isolated linker read, on the condition that each is
pinned by a canary with a red mode (constitution V). This supersedes the narrower approval of
2026-10-26 (feature 004 research G1/G2), which covered `unresolved` and `./<name>/<dep>` only.
`research.md` records the approval, each field and key form it covers, and the evidence.

**Supersedes**: the earlier feature-006 attempt (`006-unresolved-workspace-keys`, never merged).
Its research (Bun 1.4.4 source lines for `unresolved`, `./<name>/<dep>`, unlinked workspaces,
missing keys, and its audit of key walks) is input to this feature's `research.md`, re-checked
against the source, not taken over unverified.

## Design Principles

### P1. Bun's algorithm is the specification

How a `bun.lock` becomes a linked dependency graph is defined by the pinned Bun's source at its
release tag: the text-lockfile loader that turns keys and dependency lists into packages and
resolutions, and the isolated linker that turns those into `node_modules` links. The ruleset's
resolver is a carry-over of that algorithm with the same structure: each step of the ruleset's
resolution corresponds to a step of Bun's, and names the Bun source lines it follows. Nothing is
inferred from fixture outputs.

### P2. The pinned Bun is the oracle

Conformance is shown by running the pinned Bun, not by reasoning about it. For every project the
ruleset's tests resolve, the pinned Bun installs the same lockfile and the two linked dependency
graphs must be equal. A difference is a failing test, never a reviewer's discovery.

### P3. Differences are listed, or they are defects

The ruleset differs from Bun only where this spec lists a difference on purpose (Intentional
Differences below). Every other difference is a defect, whether or not a consumer has reported it.

### P4. The public surface does not move

No rule, attribute, module-extension tag or generated target name changes. What changes is which
packages are linked, and only where the ruleset linked something other than what Bun links; each
such change is listed (Behavior Changes below).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A consumer's build links what `bun install` links (Priority: P1)

A consumer with a `bun.lock` written by the pinned Bun builds with rules_bun. For the root, every
workspace and every package, the dependencies the program can resolve at run time are exactly the
ones the pinned Bun's isolated install links for that lockfile on the same platform: the same
packages, at the same versions, with the same peer bindings, and nothing more. This holds for the
layouts the earlier attempt and its follow-ups found broken: an optional dependency Bun left
unresolved, a workspace named like a package the root aliases, an optional or peer dependency with
no key, a registry package depending on a workspace member, and a peer nothing provides.

**Why this priority**: a Bazel build that links a different graph than `bun install` runs a
different program, silently. This is the reason the ruleset exists.

**Independent Test**: for each project of the edge-case corpus, the conformance test (US2) passes;
before the change it reports the difference for each layout listed in Behavior Changes.

**Acceptance Scenarios**:

1. **Given** a package whose optional dependency the lockfile lists under `unresolved` while another
   package of that name is in the tree, **When** the consumer builds, **Then** that package has no
   link of that name, as the pinned Bun links none.
2. **Given** the root depends on `lib@npm:other` and a workspace is named `lib`, **When** the
   consumer builds, **Then** the workspace `lib` links the dependencies the pinned Bun links for it
   (keyed `./lib/<dep>` in the lockfile), never `other`'s.
3. **Given** an optional or peer dependency of the root or a workspace for which the lockfile has no
   key, **When** the consumer builds, **Then** the build succeeds and that dependency is not linked.
4. **Given** a registry package that depends on a workspace member, **When** the consumer builds,
   **Then** that package links the workspace member, as the pinned Bun links it.
5. **Given** a package whose non-optional peer nothing in the tree provides, **When** the consumer
   builds, **Then** the build succeeds and that peer is not linked, as the pinned Bun leaves it.
6. **Given** any existing fixture project whose resolution already equals Bun's, **When** it is
   resolved after the change, **Then** the generated targets and their links are unchanged.

---

### User Story 2 - Maintainers learn of any difference from a failing test (Priority: P1)

A maintainer changes the resolver, upgrades the pinned Bun, or adds a fixture. A conformance test
runs the pinned Bun's isolated install offline against the loopback registry for every npm fixture
project and every edge-case project, records the graph Bun linked, and compares it with the
ruleset's resolution of the same lockfile. Any difference fails the test with the project, the
dependent, the dependency name and both sides' bindings.

**Why this priority**: without it, conformance is a claim; with it, every future difference
surfaces in CI rather than in a consumer's build. It is also how US1 is verified.

**Independent Test**: the conformance test passes on the branch; injecting a single wrong binding
into the ruleset's resolution (its red mode) makes it fail and name that binding.

**Acceptance Scenarios**:

1. **Given** every npm fixture project and the edge-case corpus, **When** the conformance test
   runs, **Then** it compares each one and reports zero differences.
2. **Given** a project where the ruleset links one dependency differently from Bun, **When** the
   test runs, **Then** it fails naming the project, the dependent, the dependency and both
   bindings.
3. **Given** a project with platform-specific optional packages, **When** the test runs, **Then**
   it compares the bindings for the host platform, with the ruleset resolving for a target platform
   equal to the host.
4. **Given** an npm fixture project added later, **When** the test runs, **Then** it is compared
   without the test being edited, or the test fails because a project is not covered.
5. **Given** a difference that is one of the listed Intentional Differences, **When** the test
   runs, **Then** it is excluded by name of that difference, and nothing else is excluded.

---

### User Story 3 - Each step of the resolver can be traced to Bun's source (Priority: P2)

A maintainer reading the resolver can find, for each function, the Bun source lines at the pinned
tag that it carries over, and can check one against the other. When the pinned Bun is upgraded,
the maintainer diffs Bun's cited lines between tags to find what the resolver must follow.

**Why this priority**: it is what makes conformance hold by construction, not only for the projects
the corpus happens to contain.

**Independent Test**: review: every function of the rebuilt resolver cites Bun source lines at
`bun-v1.4.4`; `research.md` maps each Bun step to the ruleset function that carries it over, and
lists each Bun step deliberately not carried over with its reason.

**Acceptance Scenarios**:

1. **Given** the rebuilt resolver, **When** each function is inspected, **Then** it names the Bun
   file, tag and line range it follows.
2. **Given** `research.md`, **When** it is read, **Then** every step of Bun's loader and isolated
   linker that affects which package a dependency links is mapped to a ruleset function or listed as
   not carried over with the reason (for example, lifecycle scripts).

---

### User Story 4 - Every `bun.lock` form the resolver reads is pinned by a canary (Priority: P2)

A maintainer upgrading Bun learns from a failing canary, not from a consumer, that Bun changed how
it writes a field or key form the resolver reads.

**Why this priority**: constitution V allows reading a field the format's documentation does not
describe only with a canary that fails when the pinned Bun's output changes.

**Independent Test**: each canary passes with the pinned Bun and fails in its red mode, naming the
reader it protects.

**Acceptance Scenarios**:

1. **Given** a field or key form the resolver reads that no existing canary pins (at least
   `unresolved` and the `./<name>/<dep>` key), **When** the canaries run, **Then** a canary asserts
   the form the pinned Bun writes and names the reader it protects.
2. **Given** a canary's red mode, **When** it runs, **Then** it fails.

---

### User Story 5 - A consumer on Bun 1.4.2 keeps the links 1.4.2 gives (Priority: P3)

A consumer whose `bun.lock` was written by Bun 1.4.2, still a version rules_bun knows, updates
rules_bun. Their build links what Bun 1.4.2's own isolated install links for that lockfile.

**Why this priority**: 1.4.2 is a known version, but no longer the pinned one; a lockfile it wrote
must keep resolving as Bun 1.4.2 links it. No rules_bun version is published, so the Behavior
Changes are not release-visible breaks under constitution VII (plan, Constitution Check).

**Independent Test**: the conformance test runs with Bun 1.4.2 as the oracle on lockfiles Bun 1.4.2
writes for the corpus projects it can install, and reports zero differences.

**Acceptance Scenarios**:

1. **Given** a corpus project's lockfile written by Bun 1.4.2, **When** the 1.4.2 conformance run
   compares it, **Then** the ruleset's resolution equals Bun 1.4.2's isolated install.
2. **Given** a corpus project Bun 1.4.2 cannot write or install (for example an unlinked workspace,
   which 1.4.2's loader rejects), **When** the 1.4.2 run lists its projects, **Then** that project is
   listed as not applicable with the reason, not silently skipped.

### Edge Cases

- A lockfile Bun 1.4.4 refuses to load (for example a `packages` key equal to a workspace's name
  holding a `file:` folder, "Duplicate package path"): the ruleset fails the build with a
  diagnostic naming the file and the key, as Bun fails; it never links a graph for a lockfile Bun
  does not install.
- A value of a field the resolver reads that is malformed (for example `unresolved` not a list of
  strings): the build fails naming the `bun.lock` label, the entry and the field, in English,
  without printing values the reader has not checked.
- A name listed under `unresolved` that is no optional dependency of the entry: ignored, as Bun's
  loader ignores it.
- A key no walk of Bun's loader reaches (for example a `./<name>/…` key for a linked workspace):
  loaded and never bound, as Bun does; not an error.
- A scoped workspace named like an aliased package (`@scope/lib`): its keys start `./@scope/lib/`.
- A peer that some package provides only through an `unresolved` optional edge: the peer binds as
  Bun binds it.
- A package that appears in Bun's store more than once because its peers bind differently: the
  ruleset has the same number of instances with the same peer bindings.
- Platform-specific optional packages that do not match the host: excluded on both sides for the
  host comparison; selection for other target platforms stays by Bazel target platform (an
  Intentional Difference) and keeps its existing tests.
- A lockfile Bun 1.4.2 writes that the 1.4.4 loader links differently from 1.4.2: the ruleset cannot
  follow both from the lockfile alone; work stops and the user is told (constitution V), rather than
  either result being chosen silently.
- Windows: keys are lockfile strings, never file system paths; `./` in a key never reaches a path.
- The conformance test runs Bun in a test action: Bun comes from the registered toolchain and the
  registry is the loopback registry; no network and no host-installed tool is used (constitution
  III).

## Requirements *(mandatory)*

### Functional Requirements

**Specification and carry-over (P1)**

- **FR-001**: `research.md` MUST identify, at tag `bun-v1.4.4` of oven-sh/bun under `src/install`,
  the code that reads `bun.lock`, turns its keys and dependency lists into packages and
  resolutions, and lays out `node_modules` in the isolated linker, with file URLs and line ranges.
- **FR-002**: The ruleset's resolution from `bun.lock` to a linked graph MUST be rebuilt as a
  carry-over of that code with the same structure: each function MUST cite the Bun file, tag and
  line range it follows, and each step of Bun's that affects a binding MUST be either carried over
  or listed in `research.md` as not carried over, with its reason.
- **FR-003**: The resolver MUST decide from the lockfile and the `package.json` fields the ruleset
  already reads, never from a registry or the host.
- **FR-004**: A lockfile the pinned Bun refuses to load MUST fail the build during module extension
  evaluation with a diagnostic in English that names the `bun.lock` label and the key or field, and
  states the remedy where Bun's message does (for example "run `bun install`").

**Fields and key forms read (constitution V)**

- **FR-005**: Every `bun.lock` field and key form the carried-over algorithm reads MUST be listed in
  `research.md` with the Bun source lines that write and read it, evidence from a lockfile the
  pinned Bun wrote, and the approval of 2026-10-29.
- **FR-006**: Each listed field or key form that no existing canary pins MUST get a canary in
  `bun/tests/canary/npm` that runs the pinned Bun through the existing canary support, asserts the
  form the reader relies on, names the reader it protects, and has a red mode that makes it fail.

**Differential conformance test (P2)**

- **FR-007**: A conformance test MUST, for each project, run the pinned Bun's isolated install
  (bun.com/docs/install/isolated) offline against the loopback registry, extract the linked
  dependency graph from what it installed, and compare it with the ruleset's resolution of the same
  lockfile; any difference MUST fail the test.
- **FR-008**: The linked dependency graph MUST consist of: for the root and each workspace, each
  linked dependency name and the package entry or workspace it links to; for each package entry
  (a package at a version with its peer bindings), each linked dependency name and the entry it
  links to. Two graphs are equal when they have the same entries and the same links.
- **FR-009**: The test MUST cover every npm fixture project under `bun/tests/npm/fixtures` and an
  edge-case corpus with at least one project for each of: a workspace named like a package the root
  aliases (unscoped and scoped); an optional dependency listed under `unresolved` (in a package and
  in a workspace); an optional and a peer dependency without a key (root and workspace); a registry
  package depending on a workspace member; a peer nothing provides (non-optional and optional);
  nested and hoisted keys; overrides; catalogs. A fixture project not covered MUST fail the test.
- **FR-010**: Platform-specific optional packages MUST be compared for the host platform, the
  ruleset resolving for a target platform equal to the host.
- **FR-011**: Exclusions MUST be exactly the Intentional Differences listed in this spec, each named
  in the test; the test MUST have a red mode that injects one difference and fails.
- **FR-012**: A failure MUST name the project, the dependent, the dependency name and both bindings.

**Bun 1.4.2 (US5)**

- **FR-013**: The conformance test MUST also run with Bun 1.4.2, fetched with the integrity
  `bun/private/versions.bzl` records, as the oracle, on lockfiles Bun 1.4.2 writes for the corpus
  projects it can install; projects 1.4.2 cannot write or install MUST be listed with the reason.
  On every platform where the 1.4.2 run executes, it MUST report zero differences.

**Public surface and behavior changes (P4)**

- **FR-014**: The public API (constitution I) MUST NOT change: rules, attributes, module-extension
  tags and the names of generated targets stay as they are on `main`.
- **FR-015**: Every change in what a consumer's build links MUST be one where the ruleset differed
  from the pinned Bun; each MUST be listed in Behavior Changes below with a test that failed before
  the change. For a project with no such difference, generated targets and links MUST equal
  `main`'s.
- **FR-016**: Existing tests that assert behavior Bun does not have (for example the `missing_peer`
  fixture's failure) MUST be changed to assert Bun's behavior, and each such change MUST be listed.

**Documentation and delivery**

- **FR-017**: Documentation MUST state only what the tests cover and name the CI runner labels where
  they ran (constitution II), and MUST list the Intentional Differences. Feature 004's research G1
  and G2 are marked resolved by this feature.
- **FR-018**: The change is delivered as one PR from branch `006-bun-conformant-resolution`; it is
  done when the conformance test covers every fixture and the corpus with zero differences, and
  root `bazel test //...`, the unsandboxed run, `e2e/smoke` `bazel test //...`,
  `prek run --all-files` and PR CI on Linux, macOS and Windows pass.

### Intentional Differences

The only differences between the ruleset and the pinned Bun's isolated install that the
conformance test excludes:

- **ID-1 No lifecycle scripts**: the ruleset runs no `preinstall`, `install` or `postinstall`
  scripts; files those scripts would create are not compared, and the oracle install runs with
  scripts disabled.
- **ID-2 Selection by target platform**: platform-specific optional packages are selected for the
  Bazel target platform, not the host; the conformance test therefore compares only with target
  equal to host.

### Behavior Changes

Expected, each confirmed by the conformance test before the change and listed again in the PR with
the test that shows it:

- **BC-1**: an optional dependency listed under `unresolved` is no longer linked to another package
  of its name.
- **BC-2**: a workspace named like a package the root aliases links its own dependencies
  (`./<name>/<dep>`), not the root's or the aliased package's.
- **BC-3**: an optional or peer dependency of the root or a workspace without a key no longer fails
  the build; it is not linked.
- **BC-4**: a registry package's dependency on a workspace member is linked to that member.
- **BC-5**: a peer nothing provides no longer fails the build; it is not linked.

Any further difference the conformance test finds is added here before it is fixed.

### Key Entities

- **Linked dependency graph**: the entries (root, workspaces, package entries) and the links between
  them that an install produces; the unit compared between the ruleset and Bun.
- **Package entry**: a package at a version together with the peer bindings that make Bun store it
  separately; corresponds to one store entry of Bun's isolated install and one instance of the
  ruleset.
- **Binding**: the entry a dependency name of an entry links to, or none.
- **Edge-case corpus**: projects written for the conformance test, each for a layout FR-009 names,
  whose lockfiles the pinned Bun writes.
- **Intentional Difference**: a listed, named exception to equality; the only kind of exclusion.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The conformance test compares 100% of npm fixture projects and every corpus project
  and reports 0 differences with Bun 1.4.4 on Linux, macOS and Windows CI.
- **SC-002**: The 1.4.2 conformance run reports 0 differences for every project it applies to, on
  each platform where it runs.
- **SC-003**: Each Behavior Change has a conformance difference recorded before the change (TDD log)
  that is gone after it; the conformance test and each new canary fail in red mode.
- **SC-004**: 100% of the rebuilt resolver's functions cite Bun source lines; `research.md` maps
  every binding-relevant Bun step, with 0 unaccounted.
- **SC-005**: 0 public API changes: every generated target name and every public symbol on `main`
  exists unchanged on the branch.
- **SC-006**: The completion gates of FR-018 pass, locally and in every job of the PR's CI run on
  Linux, macOS and Windows.

## Assumptions

- The pinned Bun is 1.4.4, the version the fixture writers, canaries and conformance test run.
- "Linked graph" compares package entries including peer bindings (store-entry identity), not only
  `name@version` per link, because two copies of a package with different peers are different
  programs; this is the reading of "links exactly what the pinned Bun links".
- The oracle runs in the test each time (Bun from the registered toolchain, offline, loopback
  registry), so it cannot go stale; lockfiles of the corpus are written by the pinned Bun and
  committed, as the existing fixtures are.
- Bun 1.4.2 is "available" wherever its archive in `versions.bzl` can be fetched as a test-only
  toolchain; it is fetched for the 1.4.2 run only (this reverses feature 004 G3's "no test downloads
  1.4.2" for that run). Lockfiles 1.4.2 writes have no `unresolved` and no unlinked workspace, as
  1.4.2's loader rejects the latter.
- The earlier attempt's research is a starting point; every line number it cites is re-read at the
  tag before it is relied on.
- `bin` links, `.bin` directories and file contents are out of the graph comparison; existing tests
  keep covering them.
