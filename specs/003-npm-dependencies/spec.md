# Feature Specification: npm Dependencies from `bun.lock`

**Feature Branch**: `003-npm-dependencies`

**Created**: 2026-10-18

**Status**: Draft (Revision 6)

**Input**: User description: "Add npm dependencies to rules_bun: a module extension reads a Bun text lockfile (bun.lock) and fetches every package it lists as a Bazel repository with the exact version and the integrity value the lockfile records, without running bun install or any host tool and without network access at build or test time beyond Bazel's own downloads, so bun_binary, bun_test and bun_library can import npm packages hermetically on Linux, macOS and Windows. Follow bazel.build documentation for module extensions and repository rules, the bun.com documentation of the bun.lock format, and how aspect-build/rules_js handles pnpm-lock.yaml (npm_translate_lock: per-package repositories, a node_modules layout linked into the output tree, lifecycle hooks off by default) as the reference; record every source in research.md. Cover: scoped packages, workspaces declared in the root package.json, optional and platform-specific dependencies (os/cpu fields) selected by Bazel platform, peer dependencies, packages with bin entries usable as tools, private registries and authentication via documented Bazel mechanisms, and a canary for every upstream reliance. Integrate with the existing per-target copy tree and load guard so imported packages are declared inputs and nothing outside the declared set loads. JSX through the react package must work end to end as the proof. Develop test-first; constitution v2.0.0 applies; everything in the repository is English."

**Revision 2 (2026-10-18, review of the first draft; user decisions under constitution v2.2.0)**:
(1) Peer dependencies: `bun.lock` does not record how peers resolve (observed: one entry for a
package that Bun installed as two store instances with different peers), so the ruleset resolves
peers itself by npm's documented `peerDependencies` semantics, not by reproducing Bun's layout or
store hash (FR-017, US5, US1-6). (2) Layout: the ruleset builds its own strict layout, not Bun's
isolated layout, because Bun's hoisted fallback and the visibility of the root `node_modules` let
packages reach undeclared root dependencies (observed); each package instance sees only its
declared dependencies and resolved peers through Node's documented `node_modules` lookup, with one
instance per package version per target on Linux, macOS and Windows (FR-003, US1-7, US4). The
claim that Bun's isolated installs reject phantom dependencies is removed. (3) npmjs entries record
an empty tarball URL; it is built with the pattern rules_js uses, and full URLs are used as recorded
(FR-009, FR-019). (4) FR-011 applies to the rules' build actions and to consumers' tests; FR-024
canaries may run the pinned Bun's installer against a loopback registry started inside the test.
(5) Module-evaluation and fetch failures are tested Bazel-in-Bazel with
bazel-contrib/rules_bazel_integration_test; credential tests use a loopback registry started by the
integration test, never by a repository rule (FR-025, FR-026, SC-006). (6) Consumer setup follows
rules_js: the extension creates repositories, and a macro loaded from `bun/*.bzl`, called in each
workspace package's `BUILD` file, creates the `:node_modules/<package>` targets (FR-012, SC-001).
(7) Generated targets are public API and their naming rules are documented (constitution I; FR-012,
FR-018). (8) Integrity is the one the registry published, as the lockfile records it (constitution
III; US2). (9) Only `bun.lock` fields the blog post does not describe are pinned by canaries; no
other undocumented behavior is relied on (constitution V; FR-001, FR-024). (10) Only `bin` entries
whose file has a JavaScript or TypeScript source extension become executable targets (FR-018,
US6). (11) No lifecycle script runs and nothing is printed at analysis; the documentation explains
trusted-dependency entries, and an absent `trustedDependencies` is told apart from an empty one
(FR-023). (12) Workspace glob patterns, negative globs, and adding or removing a member without
changing the root manifest are tested (FR-006, US4). (13) The extension is reproducible, so it
writes no `MODULE.bazel.lock` entry; US2-7 tests host independence of the generated repository set
(FR-008). (14) A source-tree `node_modules` has no effect only when `ignore_directories` covers it;
both cases are tested (Edge Cases). (15) Enterprise use: mirrors, credentials, several lockfiles and
non-root modules, dependency kinds per workspace package, `overrides` and catalogs, archive layouts,
packages that ship `BUILD` files, Windows-invalid file names, scale and content exclusion (US7, US9,
FR-019, FR-020, FR-032 to FR-037, SC-010). (16) `bun.lock` is JSONC and goes through a JSONC-to-JSON
step before decoding (FR-007). (17) Unmeasurable criteria are made measurable (US1-2, US3-3, SC-005,
SC-007).

**Revision 3 (2026-10-18, decided after review of Revision 2)**: (1) Layout: the strict symlinked
layout rules_js uses; it works with Bazel's defaults on Linux and macOS, and on Windows it requires
Bazel's documented `--windows_enable_symlinks`, without which the build fails with an English error
naming the flag; Windows CI and `e2e/smoke` set it (FR-003, FR-027, SC-002). (2) Peers follow npm
v7 and later: an unprovided non-optional peer resolves to the version the lockfile lists in the
dependent's workspace, and an unprovided optional peer is absent (FR-017, US5-2). (3) The hub
repository generates `defs.bzl` with the linking macro, loaded from `@<hub>//:defs.bzl` (FR-012,
SC-001, US1). (4) Canaries cover every lockfile access the reader makes, by key or by position,
including the URL and integrity slots (FR-024, SC-007). (5) Root real-run tests fetch fixture
archives in the repository through a `--downloader_config` rewrite; Bazel-in-Bazel inner builds use
no external network; `e2e/smoke` may use the public npm registry (FR-025, FR-026, SC-002). (6)
Credentials come only from `--credential_helper` and `.netrc`; a `.npmrc` passed as a label supplies
registry and scope mappings only (FR-020, US7). (7) A Windows-invalid file name fails at fetch with
Bazel's extraction error (FR-036). (8) The ruleset's rules never make a consumer's build or test
need a package manager or network access (FR-011). (9) SC-005 is measured by requests to a loopback
registry. (10) Workspace targets cover all four dependency kinds, and US4-6, US6-5, US7-6 and US9-3
state their outcomes (FR-012, FR-018, FR-032). (11) An undeclared import from an unignored
source-tree `node_modules` is rejected by the load guard (Edge Cases). (12) `{registry}` in FR-009
comes from the passed `.npmrc`, else the npm registry. (13) FR-003's "no instance MUST see" is now
"MUST NOT see".

**Revision 4 (2026-10-20, plan gaps G1–G4; technical decisions by the implementer)**: G1: Windows
needs no `--windows_enable_symlinks`; the layout uses directory junctions as research found, so the
Windows flag requirement of Revision 3 is withdrawn and SC-002 holds with Bazel's default settings
on every OS. G2: a Windows-invalid file name fails when the target is built, with Bazel's error,
documented. G3: root real-run tests use `npm.replace_package` (the rules_js `replace_packages`
pattern, here the `npm_replace_package` tag) with fixture archives checked into the repository, not
a `--downloader_config` rewrite. G4: Bun 1.4.2 writes no `trustedDependencies` to `bun.lock` for an
explicitly empty list, contrary to bun.com; the ruleset treats an absent and an empty list alike,
runs no lifecycle script either way (FR-023), documents the difference, and pins Bun's behavior with
a canary. Restated for these: FR-001, FR-003, FR-005, FR-023, FR-025, FR-026, FR-027, FR-036,
SC-001, SC-002, US1 and US8 (Independent Tests), two Edge Cases, and an Assumption. Revision 4
supersedes Revision 2 item (11) and Revision 3 items (1), (5) and (7).

**Revision 5 (2026-10-20, plan fixes A–M after two adversarial reviews; technical decisions by the
implementer)**: (1) A consumer's source-tree `node_modules` stays reachable through the execution
root even when `ignore_directories` covers it, so isolation is stated as what a package can load:
the load guard rejects every module outside the declared set, and a phantom import, an absent
optional peer or an uncarried platform package cannot load (US1-7, US4-6, US5-2, FR-003, an Edge
Case); the resolver's reads of `package.json` files outside the set are a documented limitation.
(2) Packages are extracted at fetch by Bazel's documented extraction API, so a file name Windows
cannot hold is handled by Bazel's extractor, which the ruleset does not promise to fail (FR-036, an
Edge Case). (3) Integration tests run on the ruleset's own `bun_test` with a pinned Bazel binary,
not on bazel-contrib/rules_bazel_integration_test, whose tests are `sh_test` targets (FR-025, an
Assumption). (4) Two entries of one package version whose dependencies resolve differently are
distinct instances, and a target needing two of them fails like US5-4 (FR-017, US5-4). (5) Two
entries of one package version with different URLs or integrities fail evaluation (an Edge Case).
(6) `aix` has a Bazel constraint; the Edge Case example is corrected. (7) US2-7 names the `bazel
mod` commands. Revision 5 supersedes Revision 2 item (5) and Revision 4's G2 statement.

**Revision 6 (2026-10-25, the G9 correction T123 tested; technical, by the implementer)**: a
source-tree `node_modules` that `ignore_directories` covers is not reachable through the execution
root, and an import of a package in it fails with Bun's module-not-found error; one that
`ignore_directories` does not cover is reachable, and the load guard rejects the import, naming the
file. Either way nothing in it loads (an Edge Case). Revision 6 supersedes the reachability
statement of Revision 5 item (1); its isolation statement stands.

## Sources checked while writing this specification

Each fact below was read at its source on 2026-10-18; research MUST re-read and record them.

- bun.com documents `bun.lock` only as a text lockfile that replaced `bun.lockb` as the default in
  Bun v1.2 (https://bun.com/docs/pm/lockfile), and points to a blog post for the format
  (https://bun.com/blog/bun-lock-text-lockfile). The blog post says the file is JSONC and shows one
  example with `lockfileVersion`, `workspaces` and `packages`; it defines no field, no entry shape,
  no integrity field and no compatibility rule. No bun.com page defines the schema.
- bun.com documents isolated installs (https://bun.com/docs/pm/isolated-installs): a
  `node_modules/.bun/<package>@<version>/node_modules/` store with one symlink per dependency; it is
  the default for new workspace projects (`configVersion = 1`), hoisting otherwise.
- bun.com documents lifecycle scripts (https://bun.com/docs/pm/lifecycle) as "arbitrary shell
  commands"; Bun runs them only for packages on an allow list: `trustedDependencies` in
  `package.json` or, when it is omitted, a built-in list of npm packages; "The lockfile records the
  list".
- rules_js v3.5.1 (`docs/pnpm.md`) defines one `npm_import` repository per package with the
  integrity the lockfile records, fetched lazily by Bazel's downloader; `npm_link_all_packages()`
  creates `:node_modules/<package>` targets per workspace package; it does not support "phantom"
  hoisting; lifecycle hooks run only for packages pnpm's `allowBuilds` / `onlyBuiltDependencies`
  allow, as build actions; private registries authenticate through Bazel's downloader, which takes
  a credential helper (https://bazel.build/reference/command-line-reference#flag--credential_helper).
- rules_js v3.5.1 source (Revision 3): `npm/private/npm_import.bzl` takes executables only from a
  package's `bin` field (a string or an object), not from `directories.bin`; `npm/extensions.bzl`
  creates one hub repository per `npm_translate_lock` tag under the tag's `name` and does not
  deconflict hub names. It also defines a root-module-only `npm_replace_package` tag
  (`package = "name@version"`, `replacement = <label>`) that replaces a package across the
  dependency graph (Revision 4, read on 2026-10-20).
- bazel.build documents `--windows_enable_symlinks` as a startup option: "If true, real symbolic
  links will be created on Windows instead of file copying. Requires Windows developer mode to be
  enabled and Windows 10 version 1703 or greater."
  (https://bazel.build/reference/command-line-reference)
- Feature 002 documents in `bun/private/run.bzl` that "JSX needs the `react` package, which
  rules_bun does not provide yet".

Observed on 2026-10-18 and recorded as decisions of Revision 2; research MUST reproduce each with
the pinned Bun or Bazel and record the evidence:

- `bun.lock` holds one entry for a package version that Bun installed as two store instances with
  different peer resolutions, so the lockfile does not record how peers resolve.
- Under Bun's installs a package can reach dependencies it does not declare, through Bun's hoisted
  fallback and the root `node_modules`.
- Entries for packages from the npm registry record an empty tarball URL.
- Starlark's `json.decode` rejects trailing commas, which JSONC allows.

Research MUST read and record, with the source URL, before the plan relies on it: npm's
documentation of `peerDependencies` and `peerDependenciesMeta` for npm v7 and later, and bun.com's
statement of how Bun installs peers; Node's documented lookup through `node_modules` folders and
bun.com's statement of how Bun resolves packages; bazel.build's `extension_metadata`,
`--downloader_config`, `--credential_helper`, `.netrc` handling for repository downloads and
`--windows_enable_symlinks`, and what else symlinks on Windows need; how a Bazel-in-Bazel inner
build gets its modules and toolchain from the outer build's repository cache or a local registry;
bun.com's documentation of workspaces, `overrides`/`resolutions` and catalogs; npm's documentation
of `.npmrc` registry and scope keys; and how rules_js builds tarball URLs, lays out its symlinked
package store, and handles archive top-level directories, packages that ship `BUILD` files, and
`exclude_package_contents`.

## User Scenarios & Testing *(mandatory)*

Actors:

- **Consumer**: a Bazel module that depends on `rules_bun`, keeps a `package.json` and a `bun.lock`
  written by Bun outside Bazel, and declares Bun targets that import npm packages.
- **Maintainer**: a person who changes `rules_bun` and must know, from test results alone, whether
  the change is correct on every supported platform.
- **Package registry**: the npm registry, or another registry the lockfile names, that serves
  package archives; it may require credentials or be reached through a mirror.
- **Registry (BCR)**: the Bazel Central Registry presubmit, which runs `e2e/smoke`.

Today a Bun target can import only files declared in the workspace. A source that imports an npm
package fails with Bun's module-not-found error, and JSX does not work because Bun's JSX transform
imports from the `react` package.

### User Story 1 - Import npm packages, proven by JSX with React (Priority: P1)

A consumer points the ruleset at their `bun.lock` in `MODULE.bazel`, loads the macro the hub
repository generates (`@<hub>//:defs.bzl`) and calls it in the `BUILD` file of each workspace
package, adds the npm packages a target uses to that target's dependencies, and the target's sources
import them by package name. A test written in TSX renders a React component and checks the markup.

**Why this priority**: It is the feature. JSX through `react` is the proof the user asked for, and
it exercises a real package with a dependency, a peer dependency and conditional exports.

**Independent Test**: In a module whose root `package.json` declares `react` and `react-dom` and
whose `bun.lock` was written by the Bun version the module pins, a `bun_test` with a TSX file
renders a component that calls a React hook with `react-dom/server` and asserts the HTML; a
`bun_binary` does the same and exits non-zero on a mismatch. Both run on Linux, macOS and Windows
(with Bazel's default settings on every OS, FR-003).

**Acceptance Scenarios**:

1. **Given** the module above, **When** `bazel test` runs the TSX test, **Then** it passes and the
   rendered markup equals the expected string.
2. **Given** the same component in a `bun_binary`, **When** CI runs it with `bazel run`, **Then** it
   exits zero; **and given** a variant of that program whose expected markup differs from what it
   renders, **When** a test spawns it, **Then** it exits non-zero and the test checks that exit.
3. **Given** a `bun_library` that depends on a package and a `bun_binary` or `bun_test` that depends
   on that library, **When** the program or test runs, **Then** the library's import of the package
   resolves.
4. **Given** a scoped package (`@scope/name`), **When** a target that depends on it imports it,
   **Then** the import resolves.
5. **Given** a package that the lockfile lists but the target does not depend on, directly or
   through a `bun_library` or another package, **When** the target's source imports it, **Then** the
   run fails with Bun's module-not-found error or the load guard's error naming the file.
6. **Given** two versions of one package in the lockfile, one used by the workspace and one by
   another package, **When** each is imported from its dependent, **Then** each dependent gets the
   version the lockfile resolves for it; **and given** a package with a peer dependency, **When** it
   is imported, **Then** its peer resolves as FR-017 defines.
7. **Given** a package whose code imports a package it does not declare as a dependency or peer (a
   "phantom" dependency), even when the workspace root declares that package, **When** that code
   runs, **Then** it cannot load that package, as in rules_js: the import fails with Bun's
   module-not-found error, or with the load guard's error when a copy is reachable outside the
   target's declared set (for example a source-tree `node_modules`, Revision 5).

---

### User Story 2 - Fetching is pinned, verified, lazy and offline after fetch (Priority: P1)

Every package the lockfile lists is a separate Bazel repository that Bazel's downloader fetches
with the exact version and the integrity value the registry published, as the lockfile records it.
Nothing runs `bun install`, a package manager or a host tool, and only packages a requested target
needs are fetched.

**Why this priority**: It is what constitution III requires of every download, and what makes the
result trustworthy and cacheable.

**Independent Test**: Bazel-in-Bazel integration tests (FR-025) with fixture archives or a loopback
registry check integrity failure, a missing integrity, an unreachable package no target needs, and
unsupported lockfile inputs. A Linux CI job fetches, then builds and tests with network access
denied to actions and tests. CI on Linux, macOS and Windows compares the generated repository set.

**Acceptance Scenarios**:

1. **Given** a lockfile whose integrity value does not match the archive the registry serves,
   **When** a target that needs the package is built, **Then** the fetch fails and the error names
   the package.
2. **Given** a lockfile entry with no integrity value (for example a git dependency), **When** a
   target that needs it is built, **Then** the build fails with an English error naming the package
   and the reason; targets that do not need it are unaffected.
3. **Given** a lockfile that lists a package whose archive cannot be downloaded, **When** a target
   that does not need that package is built and tested, **Then** it succeeds.
4. **Given** a completed fetch, **When** the same targets are built and tested with network access
   denied to actions and tests, **Then** they pass.
5. **Given** only a binary `bun.lockb`, a lockfile version the ruleset does not support, or a
   lockfile that does not parse as JSONC, **When** the module is evaluated, **Then** it fails with an
   English error that names the file and what to do.
6. **Given** a root or workspace `package.json` whose dependencies differ from what the lockfile
   records for it, after `catalog:` references and `overrides` are taken into account (FR-006),
   **When** the module is evaluated, **Then** it fails with an English error naming the package and
   the difference, and telling the consumer to run `bun install` and commit the lockfile.
7. **Given** the same module evaluated on Linux, macOS and Windows, **When** the extension's
   generated repository set (names listed with `bazel mod show_extension`, attributes with
   `bazel mod show_repo`) is compared, **Then** it
   is identical on all three, and `MODULE.bazel.lock` holds no entry for the extension because it
   declares itself reproducible (FR-008).

---

### User Story 3 - Platform-specific optional dependencies follow the Bazel platform (Priority: P2)

Some packages ship their native part as optional dependencies restricted to an operating system
and CPU (`os`/`cpu` in their `package.json`). A target gets the optional packages that match its
Bazel target platform, not the host.

**Why this priority**: Common build tools work this way, and choosing by host would put the wrong
binary into a cross-platform build or a remote execution.

**Independent Test**: A fixture package with optional packages for each supported platform; an
analysis test per supported platform checks which packages the target carries; a real run on each
CI operating system checks that the matching one loads.

**Acceptance Scenarios**:

1. **Given** a target platform P, **When** a target that depends on the fixture package is
   analyzed, **Then** it carries the optional packages whose `os` and `cpu` match P and none other.
2. **Given** a package used as the tool of a build action, **When** the action is built, **Then**
   it carries the optional packages of the execution platform.
3. **Given** a fixture package whose entry point throws a fixed English error when none of its
   optional packages is present, and a CI platform that none of its optional packages matches,
   **When** a target that depends on it runs there, **Then** the target carries none of the
   optional packages and the run fails with exactly that fixture's error message.

---

### User Story 4 - Workspaces declared in the root `package.json` (Priority: P2)

A consumer's repository is a Bun workspace: the root `package.json` lists member directories,
directly or by glob patterns, each with its own `package.json`. Targets in a member get the
packages that member declares, and a member that depends on another member gets the consumer's own
Bazel target for it.

**Why this priority**: Monorepos are where Bazel is used, and the strict layout must hold per
member.

**Independent Test**: A fixture workspace with members named by a glob and excluded by a negative
glob, two members that declare different packages, and one that depends on the other; integration
tests add and remove a member.

**Acceptance Scenarios**:

1. **Given** members A and B where only A declares package X, **When** a target in A imports X,
   **Then** it resolves; **When** a target in B imports X, **Then** it fails as in US1-5.
2. **Given** member A that depends on member B (`workspace:` protocol), **When** a target in A
   imports B by package name, **Then** it gets the sources of the Bazel target the consumer declared
   for B, not a downloaded copy.
3. **Given** a member and the root declaring different versions of the same package, **When**
   targets in each import it, **Then** each gets the version the lockfile resolves for it.
4. **Given** a root `workspaces` field with a glob pattern and a negative glob, **When** the module
   is evaluated, **Then** the members are exactly the directories the pattern matches minus those
   the negative glob excludes, as bun.com documents for workspaces.
5. **Given** a glob pattern in the root `workspaces` field, **When** a member directory is added or
   removed, and the lockfile is updated with `bun install`, without changing the root
   `package.json`, **Then** the next build sees the member's targets added or removed; **and When**
   the lockfile is not updated, **Then** evaluation fails as in US2-6.
6. **Given** a member that declares package D under `dependencies`, V under `devDependencies`, R
   under `peerDependencies` and O, restricted by `os` and `cpu`, under `optionalDependencies`,
   **When** the member's `BUILD` file calls the macro and a member target depends on each, **Then**
   the target imports D, V and R at the versions the lockfile lists for the member, and imports O
   on target platforms that O's `os` and `cpu` match; on other platforms it cannot load O: the
   import fails with Bun's module-not-found error, or with the load guard's error when a copy is
   reachable outside the declared set (FR-012).

---

### User Story 5 - Peer dependencies resolve by npm's semantics (Priority: P2)

A package that declares a peer dependency (for example `react-dom` on `react`) gets the instance of
the peer that its dependent's context provides, as npm v7 and later document for
`peerDependencies`. The ruleset resolves this itself, because the lockfile does not record it.

**Why this priority**: Two copies of a peer break libraries that keep module state; React hooks
fail with two copies of `react`.

**Independent Test**: The hook in US1's proof fails if `react-dom` and the test load different
`react` copies; a fixture checks one module identity across the boundary, and fixtures cover the
cases below on Linux, macOS and Windows.

**Acceptance Scenarios**:

1. **Given** a component using a hook rendered with `react-dom/server`, **When** it runs, **Then**
   rendering succeeds (one `react` instance).
2. **Given** a package whose non-optional peer its dependent's context does not provide, **When**
   the package imports the peer, **Then** it gets the version the lockfile lists for that package
   name in the dependent's workspace; **and given** a peer that `peerDependenciesMeta` marks optional
   and the context does not provide, **When** the package imports it, **Then** it cannot load it:
   the import fails with Bun's module-not-found error, or with the load guard's error when a copy is
   reachable outside the declared set (FR-017).
3. **Given** two dependents in different targets that provide different versions of one package's
   peer, **When** each target runs, **Then** in each the package loads the peer version that
   target's dependent provides.
4. **Given** one target in which a package version would need two different versions of its peer,
   or of one of its dependencies (two lockfile entries of that version that resolve differently),
   **When** the target is analyzed, **Then** it fails with an English error naming the package, the
   peer or dependency and both versions, because a target holds one instance per package version
   (FR-003).

---

### User Story 6 - Package executables as tools (Priority: P2)

A package's `bin` entries whose file is a JavaScript or TypeScript source become executable
targets: they run with `bazel run` and serve as the tool of a build action, with the target or
execution platform's Bun respectively.

**Why this priority**: Compilers, bundlers and generators ship as npm executables, and a build
uses them as tools.

**Independent Test**: A fixture package with a `bin` entry runs under `bazel run` and as the tool
of a build action (for example bazel-lib's `run_binary`) whose output a test checks, on all three
operating systems; a fixture `bin` entry without a source extension checks the analysis error.

**Acceptance Scenarios**:

1. **Given** a package with a `bin` entry whose file has a JavaScript or TypeScript source
   extension, which a workspace declares directly, **When** its executable target runs with
   `bazel run` and arguments, **Then** it runs that file with those arguments.
2. **Given** that target as the tool of a build action, **When** the action runs, **Then** it
   produces its output, with the execution platform's Bun and packages.
3. **Given** a `bin` entry whose name is scoped or contains characters a target name cannot hold,
   **When** the extension generates its target, **Then** the target name follows the documented
   naming rule (FR-012).
4. **Given** a `bin` entry whose file has no JavaScript or TypeScript source extension, **When** its
   target is analyzed, **Then** analysis fails with an English error naming the package, the `bin`
   entry and the reason, as documented.
5. **Given** a package that declares executables only through `directories.bin`, **When** the macro
   creates the workspace package's targets, **Then** no executable target exists for it, because
   rules_js reads only `bin` (see Sources), and the documentation states this (FR-018).

---

### User Story 7 - Private registries, mirrors and credentials through Bazel's downloader (Priority: P3)

Packages the lockfile records from a registry other than the default are fetched from that
registry, or from a mirror the consumer configures for Bazel's downloader. An `.npmrc` the consumer
passes to the extension as a label maps scopes to registries. Credentials come only from
`--credential_helper` and `.netrc`, as bazel.build documents them for its downloader; never from an
`.npmrc` or `bunfig.toml`, and never written into a repository attribute or a file.

**Why this priority**: Companies publish internal packages to private registries and route
downloads through mirrors; credentials in generated files would leak into caches and logs.

**Independent Test**: Bazel-in-Bazel integration tests (FR-025) start a loopback registry that
requires a credential and serves a fixture package: the fetch fails without the credential and
succeeds with each supported mechanism; a downloader configuration redirects to a second loopback
server acting as a mirror.

**Acceptance Scenarios**:

1. **Given** a package recorded with a registry URL other than the default, **When** it is fetched,
   **Then** the download goes to that registry.
2. **Given** a registry that requires credentials and none supplied, **When** the package is
   fetched, **Then** the fetch fails with Bazel's download error naming the URL.
3. **Given** the credentials supplied through `--credential_helper`, **When** the package is
   fetched, **Then** it succeeds, and the credential appears in no generated file.
4. **Given** the credentials supplied through a `.netrc` file as bazel.build documents, **When** the
   package is fetched, **Then** it succeeds, and the credential appears in no generated file.
5. **Given** a `--downloader_config` that rewrites the lockfile's URL to a mirror, **When** the
   package is fetched, **Then** the download goes to the mirror and is verified with the lockfile's
   integrity value.
6. **Given** an `.npmrc` passed to the extension that maps a scope to a registry, **When** a package
   of that scope whose entry records an empty URL is fetched, **Then** the download goes to that
   registry (FR-009).
7. **Given** authentication values in the passed `.npmrc` and in the home directory's `.npmrc`, and
   neither `--credential_helper` nor `.netrc` set up, **When** a package from a registry that
   requires credentials is fetched, **Then** the fetch fails as in US7-2, and no authentication
   value appears in any repository attribute or generated file (FR-020).

---

### User Story 8 - The consumer module uses npm packages (Priority: P3)

`e2e/smoke` gains a `package.json`, a `bun.lock` and the JSX proof of US1, using only the public
API and packages from the public npm registry.

**Why this priority**: It proves the feature from outside the ruleset; it depends on US1–US5.

**Independent Test**: On Linux, macOS and Windows with Bazel's default settings (FR-003),
`bazel test //...` passes in `e2e/smoke` including the JSX test, and `bazel run` on its program
exits zero.

**Acceptance Scenarios**:

1. **Given** the consumer module as checked in, **When** its test set runs, **Then** the JSX test
   passes.
2. **Given** the consumer module, **When** `git grep -n 'bun/private' -- e2e` runs, **Then** it
   prints nothing; the hand-back record keeps the output.

---

### User Story 9 - Several lockfiles and non-root modules (Priority: P3)

A repository may hold several Bun projects, each with its own `bun.lock`, and a module the consumer
depends on may use the extension for its own lockfile. Each lockfile gets its own hub repository,
named by its tag's `name` as rules_js names `npm_translate_lock` hubs.

**Why this priority**: Large repositories hold several projects, and rulesets built on rules_bun
need their own npm packages without the root module's lockfile.

**Independent Test**: Bazel-in-Bazel integration tests with a root module that uses two lockfiles
and depends on a module that uses its own.

**Acceptance Scenarios**:

1. **Given** a root module with two lockfiles under distinct hub names, **When** targets of each
   project import their packages, **Then** each gets the versions its own lockfile records.
2. **Given** a non-root module that uses the extension for its lockfile, **When** the root module
   builds a target of that module, **Then** the target gets the non-root module's packages.
3. **Given** two uses of the extension, in one module or in two, that ask for the same hub name,
   **When** the module is evaluated, **Then** evaluation fails with an English error naming each
   module that asked for it and the name; rules_js v3.5.1 does not deconflict hub names either
   (see Sources; FR-032).

### Edge Cases

- A `node_modules` directory in the consumer's source tree, left by a local `bun install`
  (restated by Revision 6): nothing in it loads. When `ignore_directories` in `REPO.bazel` does
  not cover it, it is reachable from a target's copy tree through the execution root, and a
  target's import of a package that the target does not declare but that sits in that
  `node_modules` is rejected by the load guard (feature 002), naming the file; when
  `ignore_directories` covers it, it is not reachable and the import fails with Bun's
  module-not-found error. A test covers each case. The
  documentation tells consumers to ignore it, and states that Bun's resolver may still read
  `package.json` files there.
- Windows with or without `--windows_enable_symlinks`: every link the layout creates points to a
  directory and is a junction on Windows (FR-003), so the flag changes nothing; Windows CI runs the
  package tests both ways (FR-027).
- A lockfile written for hoisted installs (`configVersion = 0`, or no workspaces): Bazel still lays
  packages out in its strict layout (FR-003), so code relying on a phantom dependency fails
  (US1-7); documented.
- `os`/`cpu` values with no Bazel constraint (for example `sunos`; `aix` maps to
  `@platforms//os:aix`), negated values (`!win32`), and
  `libc` (glibc/musl), which `@platforms` does not model: research records how each is treated;
  `libc` variants for the same OS and CPU are all included; documented.
- A package used by many targets: each target copies it into its own copy tree; research records
  the cost, and the load guard's pattern limit (1,048,576 characters with Bun 1.4.2) applies to the
  total; a target over it fails with the existing English error, and research records the largest
  tested package set.
- A lockfile of at least 2,000 packages: evaluation time, actions per target and launcher start
  time are measured and bounded (SC-010).
- A package version whose peer would resolve to two versions within one target: analysis fails
  (US5-4).
- A non-optional peer that the context does not provide and for which the lockfile lists no version
  in the dependent's workspace: fails with an English error naming the package and the peer
  (FR-017).
- Deep `node_modules` paths on Windows (path length): research records the limit and a test pins
  the longest path the fixtures produce.
- A package archive whose top-level directory is not `package/`: its files are used as if it were
  (FR-034).
- A package archive that contains `BUILD` or `BUILD.bazel` files: all its files stay usable
  (FR-035).
- A package archive with a file name Windows cannot hold (for example `aux.js`, or a name with `:`):
  on Windows, Bazel's extractor decides what happens to that file; the ruleset promises no failure;
  documented (FR-036, restated by Revision 5).
- Two lockfile entries of one package version that record different URLs or integrities:
  evaluation fails with an English error naming both entries and both values (Revision 5).
- A package `name` that differs from its alias in the lockfile (`"alias": "npm:pkg@1"`): imported
  by the alias, as Bun does.
- Integrity algorithms Bazel's downloader does not accept: the fetch fails with an English error
  naming the package and the algorithm.
- A package whose `exports` or `main` points at a file the archive lacks: Bun's own error.
- Packages with native add-ons (`.node`) or WebAssembly: not covered by a test; reported unverified.
- A test written first passes before implementation: the test is wrong and must be changed until it
  fails for the expected reason (FR-030).

## Requirements *(mandatory)*

### Decisions made, and stop conditions

- **FR-001 (lockfile format source)**: bun.com does not define the `bun.lock` schema (see Sources),
  yet the extension must read its fields (package keys, version, registry, integrity, dependencies,
  optional and peer dependencies, `os`, `cpu`, `bin`, workspaces). Decided
  2026-10-18 (constitution v2.1.0, V): the Bun blog post that bun.com's lockfile page links for the
  format (https://bun.com/blog/bun-lock-text-lockfile) counts as Bun's documentation; every field or
  positional slot it does not describe (FR-024) MAY be read only when a test pins it against a
  `bun.lock` that the pinned Bun itself wrote, an FR-024 canary fails when Bun's output changes, and
  `research.md` records the field, the evidence and the user's approval of 2026-10-18. This approval
  covers `bun.lock` fields only (Revision 2).
- **FR-002 (reference design)**: The design MUST follow bazel.build for module extensions and
  repository rules, and rules_js `npm_translate_lock` for the structure: one repository per package,
  lazy fetching by Bazel's downloader, a `node_modules` layout created in the output tree, no
  phantom dependencies. rules_js is at aspect-build, not bazelbuild or bazel-contrib; the user named
  it in this request (2026-10-18), which `research.md` MUST record as the approval constitution V
  requires, with why no bazelbuild or bazel-contrib pattern serves. The approval covers the tarball
  URL pattern of FR-009 as a reference pattern.
- **FR-003 (layout, restated by Revisions 3, 4 and 5)**: The ruleset MUST build, in each target's copy
  tree, the strict symlinked `node_modules` layout rules_js uses, whatever linker the lockfile was
  written for, not Bun's isolated layout: each package instance's real path sits in a store
  directory whose `node_modules` holds symlinks to exactly its declared dependencies and its peers
  as FR-017 resolves them, found through Node's documented lookup through `node_modules` folders. A
  package instance MUST NOT be able to load a module from the workspace root's `node_modules` or
  any other `node_modules` outside the target's declared set: the load guard rejects it (Revision
  5; Bun's resolver may read `package.json` files there, a documented limitation). A target MUST hold exactly one
  instance of each package version it carries. On Linux, macOS and Windows the layout MUST work with
  Bazel's default settings: every link points to a directory, and bazel.build documents that
  `ctx.actions.symlink` with `target_type = "directory"`, which it allows only with `target_path`
  (so each link is a `declare_symlink` output), creates a junction on Windows, without tying it to
  `--windows_enable_symlinks` (research G1), and Windows CI pins this (FR-027). Research MUST settle the layout with sources and confirm that
  bun.com documents Bun resolving packages by that lookup; if either is not possible, FR-004
  applies.
- **FR-004 (everything else)**: If no documented Bazel API or documented Bun feature provides a
  mandatory requirement of this specification, work on it MUST stop and the gap MUST be reported to
  the user; recording it does not satisfy the requirement.

### Functional Requirements

**Extension and lockfile**

- **FR-005**: The ruleset MUST provide a module extension, loadable from `bun/extensions.bzl`, that
  takes a label of a `bun.lock`, and optionally a label of an `.npmrc` in the workspace (FR-020),
  and, from the root module only, replacements of packages by archives in the workspace (FR-026),
  and generates the repositories of this feature, with implementation in `bun/private/`. It MUST NOT
  run Bun, a package manager or any host tool, and MUST NOT access the network itself.
- **FR-006**: The extension MUST read the root `package.json` next to the lockfile, the members its
  `workspaces` field names, including glob patterns and negative globs as bun.com documents for
  workspaces, and the lockfile, and MUST fail with an English error naming the file and the
  difference when a `package.json` declares dependencies the lockfile does not record for it, or
  the reverse (US2-6). The comparison MUST resolve `catalog:` references through the catalogs the
  root `package.json` defines and take `overrides` (and `resolutions`) into account as bun.com
  documents them; tests cover both. Adding or removing a member directory that a pattern matches
  MUST take effect at the next evaluation without a change to the root `package.json` (US4-5).
- **FR-007**: The extension MUST fail with an English error naming the file and the remedy when
  only `bun.lockb` exists, when the lockfile version is not one the ruleset supports, or when the
  lockfile does not parse as JSONC. Because Starlark's `json.decode` rejects trailing commas, the
  extension MUST turn the JSONC text into JSON (removing comments and trailing commas outside
  strings) before decoding it; unit tests cover comments, trailing commas, and both inside strings.
- **FR-008 (restated by Revision 2)**: The extension MUST declare itself reproducible through
  `extension_metadata` as bazel.build documents, so that it creates no `MODULE.bazel.lock` entry,
  and the set of repositories it generates, with their attributes, MUST NOT depend on the host
  operating system or CPU (US2-7); platform choice happens at analysis (FR-016).

**Fetching**

- **FR-009 (restated by Revision 3)**: Each package entry MUST become its own repository that
  downloads the archive the lockfile identifies, through Bazel's downloader, verified with the
  integrity value the registry published as the lockfile records it. When the entry records a full
  URL, that URL MUST be used as recorded; when it records an empty URL (entries from the npm
  registry), the URL MUST be built with the pattern rules_js uses,
  `{registry}/{name}/-/{basename}-{version}.tgz`, where `basename` is the name without its scope,
  recorded in `research.md` as the approved reference pattern (FR-002). `{registry}` is the
  registry the passed `.npmrc` (FR-020) configures for the package's scope, or for an unscoped
  package or an unmapped scope its default registry, else `https://registry.npmjs.org`. Only
  repositories a requested target needs are fetched.
- **FR-010**: An entry without an integrity value, or of a kind the ruleset does not fetch (see
  Proposed boundaries), MUST fail with an English error naming the package and the reason, no later
  than when a target that needs it is analyzed, and MUST NOT affect targets that do not need it.
- **FR-011 (restated by Revision 3)**: The ruleset's rules MUST NOT make a consumer's build or test
  need a package manager or network access: no action they create and nothing they put into a
  program or test runs a package manager or accesses the network. The only exception is the FR-024
  canaries, this repository's own tests, which MAY run the pinned Bun's installer against a loopback
  registry started inside the test, with no network beyond the loopback interface. A Linux CI job
  MUST build and test the root and consumer modules with network access denied to actions and tests
  after fetching.

**Using packages in targets**

- **FR-012 (restated by Revision 3)**: Consumer setup MUST follow rules_js: the extension creates
  the package repositories and one hub repository per lockfile, and the hub repository generates a
  `defs.bzl` with the linking macro. The consumer loads it from `@<hub>//:defs.bzl` and calls it
  once in the `BUILD` file of each workspace package (root and members). The macro creates one
  `:node_modules/<package>` target per package that workspace package declares under
  `dependencies`, `devDependencies`, `optionalDependencies` or `peerDependencies`, as rules_js links
  them: each resolves to the version the lockfile lists for that workspace package, and an optional
  dependency is carried only on target platforms its `os` and `cpu` match (FR-016; US4-6). The
  targets are accepted by `bun_library`, `bun_binary` and `bun_test` in `deps`. Generated targets
  are public API (constitution I): the documentation MUST state their naming rules, including scoped
  packages, `bin` targets and names a target label cannot hold, and tests pin each rule.
- **FR-013**: A target that depends on a package MUST carry that package and its transitive
  dependencies, as the lockfile resolves them, and the peers FR-017 resolves, as declared inputs:
  each file is copied into the target's copy tree in the layout of FR-003 and is in the load guard's
  declared set. A package the target does not reach through its `deps` MUST NOT be in its copy tree
  (US1-5).
- **FR-014**: `BunLibraryInfo` or a provider next to it MUST carry packages transitively through
  `bun_library`, so a program gets the packages its libraries depend on.
- **FR-015**: A member that depends on another member MUST get the Bazel target the consumer
  declares for that member, mapped as research decides; the extension MUST NOT download a workspace
  member.

**Platforms**

- **FR-016**: Optional dependencies restricted by `os` and `cpu` MUST be selected by the target's
  Bazel platform through Bazel's documented configuration mechanism, never by the host, and an
  analysis test MUST cover every platform the ruleset's toolchain supports (`linux-x64`,
  `linux-aarch64`, `darwin-x64`, `darwin-aarch64`, `windows-x64`).

**Peer dependencies**

- **FR-017 (restated by Revision 3)**: Because `bun.lock` does not record how peers resolve, the
  ruleset MUST resolve each package's peer dependencies itself by the semantics npm v7 and later
  document for `peerDependencies` and `peerDependenciesMeta`, not by reproducing Bun's layout or
  store hash. A peer the dependent's context provides resolves to that instance, and the package
  and its dependent MUST load one instance of it (US5-1). A non-optional peer the context does not
  provide MUST resolve to the version the lockfile lists for that package name in the dependent's
  workspace, as npm v7 and Bun install it; a peer that `peerDependenciesMeta` marks optional and the
  context does not provide MUST be absent (US5-2). A non-optional peer that the context does not
  provide and for which the lockfile lists no version in that workspace MUST fail, no later than
  when a target that needs it is analyzed, with an English error naming the package and the peer.
  A target in which one package version would need two versions of its peer, or of one of its
  dependencies, MUST fail at analysis with an English error naming the package, that peer or
  dependency and both versions (US5-4). Two lockfile entries of one package version whose
  dependencies or peers resolve differently are distinct instances (Revision 5).

**Executables**

- **FR-018 (restated by Revision 3)**: For each `bin` entry of a package a workspace declares
  directly whose file has a JavaScript or TypeScript source extension that bun.com documents Bun
  running (research records the list), the extension MUST provide an executable target built on
  `bun_binary`, which `bazel run` runs and a build action can use as its tool, with the Bun and
  optional packages of the platform it is built for. A `bin` entry whose file has no such extension
  MUST get a target whose analysis fails with an English error naming the package, the entry and the
  reason, and the documentation MUST state this. As in rules_js, executables come only from the
  `bin` field: a package that declares them only through `directories.bin` gets no executable
  target, and the documentation MUST state this (US6-5).

**Registries, mirrors and credentials**

- **FR-019 (restated by Revision 2)**: A package MUST be fetched from the URL FR-009 determines.
  That URL is the logical origin: rewriting through Bazel's `--downloader_config`, as bazel.build
  documents it, MAY redirect the download to a mirror, the integrity check is unchanged, and the
  documentation MUST state this (US7-5).
- **FR-020 (restated by Revision 3)**: Credentials MUST come only from Bazel's documented
  downloader mechanisms, `--credential_helper` and `.netrc`, as bazel.build documents them. The
  extension MAY read registry and scope-to-registry mappings only from an `.npmrc` the consumer
  passes as a label in the workspace (FR-005, FR-009); it MUST NOT read authentication values from
  it, MUST NOT read the home directory's `.npmrc`, and MUST NOT read registries or credentials from
  `bunfig.toml` or environment variables. Nothing credential-related MAY enter a repository
  attribute or a generated file or be printed (US7-3, US7-4, US7-7).

**Several lockfiles and modules**

- **FR-032 (restated by Revision 3)**: The extension MUST accept several lockfiles, from the root
  module and from non-root modules, each with its own hub repository named by its tag's `name`, as
  rules_js names `npm_translate_lock` hubs. rules_js v3.5.1 does not deconflict hub names (see
  Sources); two uses of the extension that ask for the same hub name MUST fail at evaluation with an
  English error naming each module that asked for it and the name (US9-3).

**Package contents**

- **FR-033**: The consumer MUST be able to exclude files from packages by pattern, as rules_js's
  `exclude_package_contents` does; excluded files are neither copied nor in the load guard's
  declared set; a test covers it.
- **FR-034**: A package archive whose single top-level directory is not `package/` MUST be used as
  if that directory were `package/`; a test covers such an archive.
- **FR-035**: A package archive that contains `BUILD` or `BUILD.bazel` files MUST stay usable with
  all its files, handled as research records from rules_js; a test covers such an archive.
- **FR-036 (restated by Revision 5)**: A package archive with a file name Windows cannot hold is
  extracted on Windows by Bazel's documented extraction API, which may rename, drop or fail on that
  file; the ruleset promises neither a failure nor a message of its own. The documentation MUST
  state this, and a Windows CI canary pins what Bazel does and fails when it changes.

**Copy tree and load guard**

- **FR-021**: Package files MUST be declared inputs of the target in the sense of feature 002:
  copied, guarded, and nothing outside the declared set loads. The guard's documented limitations
  stay and MUST be restated for packages. The limitation "JSX needs the `react` package" MUST be
  removed from the documentation once US1 passes on all three operating systems.
- **FR-022**: Isolation from feature 002 MUST still hold: a target that imports packages still does
  not auto-install, read an undeclared `bunfig.toml` or load `.env` files.

**Lifecycle scripts**

- **FR-023 (restated by Revisions 2 and 4)**: No lifecycle script of any package runs, whatever
  `trustedDependencies` or Bun's built-in allow list says; an opt-in to run them, as rules_js
  offers, is a later feature (decided 2026-10-18). Nothing is printed at analysis. The
  documentation MUST state that packages with trusted-dependency entries would have run scripts
  under Bun and do not under Bazel, and how a consumer finds them. Bun 1.4.2 writes no
  `trustedDependencies` to `bun.lock` for an explicitly empty list, contrary to bun.com (research
  G4), so the lockfile cannot tell an empty list from an absent one (for which Bun would apply its
  built-in list, whose contents the ruleset does not reproduce). The ruleset treats them alike,
  which changes nothing because no script runs either way; the documentation MUST state the
  difference, and a canary pins Bun's behavior (FR-024).

**Upstream reliances**

- **FR-024 (canaries, restated by Revision 3)**: `research.md` MUST list every access the lockfile
  reader makes to `bun.lock`, by key or by position; positional slots of an entry, such as the
  tarball URL and the integrity, count as accesses. Each access the blog post does not describe
  (FR-001) MUST have a canary test that pins it against a lockfile the pinned Bun wrote and fails,
  with an English message naming the access, what to revisit and the source, when Bun's output
  changes. No other undocumented upstream behavior MAY be relied on: not
  a tarball URL form beyond the rules_js pattern of FR-009, not Bun's resolution internals (FR-003
  uses Node's documented lookup), and not the contents of Bun's built-in trusted list (FR-023).
  Canaries that need a newly written lockfile run the pinned Bun's installer against a loopback
  registry started inside the test (FR-011).

**Process**

- **FR-025 (restated by Revisions 2, 4 and 5)**: Root tests MUST cover the extension and generated
  targets with `analysistest`, unit tests of the lockfile reader on fixture lockfiles, and real
  runs; cases expected to fail at run time are checked by spawning as feature 002 FR-021 does. Cases
  that fail at module evaluation, at fetch or in a build action (US2, US7, US9, FR-006, FR-007,
  FR-026, FR-032) MUST be covered by Bazel-in-Bazel integration tests: the ruleset's own `bun_test`
  targets that spawn a Bazel binary pinned with its integrity (constitution VI forbids the `sh_test`
  targets bazel-contrib/rules_bazel_integration_test generates). They run in `bazel test //...`
  and through an explicit test suite. Credential tests use a loopback HTTP registry that the
  integration test starts; no repository rule starts a server. Each inner build uses its own empty
  repository cache, gets its modules from a local registry and its archives from the loopback
  registry, with no external network: blocked by Bazel's `block-network` on Linux, shown by the
  loopback request log on macOS and Windows.
- **FR-026 (restated by Revision 4)**: Root tests MUST NOT need the public npm registry or any
  network beyond the loopback interface. Root real-run tests replace their fixture packages with
  archives checked into the repository through the extension's root-only `replace_package` tag, as
  rules_js's root-only `npm_replace_package` tag replaces a package (see Sources); before a
  replacement archive is used, a build action MUST verify it against the integrity the lockfile
  records for the package (constitution III), and a mismatch fails the build with an English error
  naming the package, the archive and both values. The fetch path itself (FR-009, FR-019, FR-020,
  SC-005) is covered by the integration tests of FR-025 and by `e2e/smoke`. Integration tests and
  canaries MAY use a loopback registry they start. `e2e/smoke` MAY use the public npm registry
  through Bazel's downloader, like any consumer (the BCR presubmit has network access).
- **FR-027**: CI MUST run the root and consumer test sets and the `bazel run` checks on Linux, macOS
  and Windows, the network-denied job of FR-011 on Linux, and the comparison of US2-7 across the
  three. Windows CI runs the package tests with Bazel's default settings and again with
  `--windows_enable_symlinks`, and both MUST pass (FR-003).
- **FR-028**: A new non-dev `bazel_dep` MUST declare the lowest version that works (constitution
  IV), and `e2e/smoke` MUST pass with exactly the declared versions.
- **FR-029**: `research.md` MUST record the source URL for every API, Bun behavior and lockfile
  field the design relies on, and how rules_js solves the same problem; documentation and reports
  claim only tested behavior and name the platforms each test ran on (constitution II).
- **FR-030**: A task that changes observable behavior MUST first add or change a test, run it and
  record that it fails for the expected reason, then implement until it passes, with the record
  rules of feature 002 FR-020. The records are kept with the feature.
- **FR-031**: All text this feature adds to the repository MUST be English (AGENTS.md).
- **FR-037 (scale)**: A fixture lockfile of at least 2,000 packages MUST exist in the root tests;
  extension evaluation time, the number of actions per target and launcher start time with it MUST
  be measured on Linux CI and recorded in `research.md`, and the plan MUST set a numeric bound for
  each that a test or CI check enforces (SC-010).

### Key Entities

- **Lockfile**: the consumer's `bun.lock` (JSONC); lists workspaces with their declared dependencies
  and packages with version, source, integrity, dependencies and platform fields; it does not record
  peer resolution.
- **Registry configuration**: the `.npmrc` the consumer passes as a label; supplies registry and
  scope-to-registry mappings only, never credentials.
- **Hub repository**: one per lockfile use of the extension, named by the tag's `name`; generates
  `defs.bzl` with the workspace macro.
- **Package repository**: one per package version the lockfile lists; holds one verified archive's
  files.
- **Package instance**: one per package version per target, in the strict symlinked layout, seeing
  only its declared dependencies and resolved peers.
- **Workspace macro**: loaded from `@<hub>//:defs.bzl` and called in each workspace package's
  `BUILD` file; creates that package's package targets.
- **Package target**: `:node_modules/<package>`, what a Bun target names in `deps` to use a package;
  public API under documented naming rules.
- **Executable target**: one per `bin` entry of a directly declared package.
- **Workspace mapping**: which Bazel target stands for each workspace member.
- **Canary**: a test pinning one `bun.lock` access, by key or by position, that the blog post does
  not describe.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A consumer imports an npm package with exactly this setup and no rule of their own,
  without running `bun install` for Bazel: in `MODULE.bazel`, one `use_extension` of the ruleset's
  extension, one tag naming the `bun.lock` (and an `.npmrc` label only when registries other than
  the default are used), and one `use_repo` of the hub repository; in the `BUILD` file of each
  workspace package, one `load` of the macro from `@<hub>//:defs.bzl` and one call of it; the
  package target in a target's `deps`; no Bazel flag on any OS (FR-003). `e2e/smoke` uses
  exactly this setup.
- **SC-002**: The JSX proof passes on 3 of 3 CI operating systems, as a test and as a `bazel run`
  program, in the root module (with the replacements of FR-026) and in the consumer module, with
  Bazel's default settings on every OS (FR-003).
- **SC-003**: After fetching, the root and consumer test sets pass on Linux with network access
  denied to every action and test.
- **SC-004**: For 5 of 5 supported platforms, an analysis test shows a target carries exactly the
  optional packages matching that platform.
- **SC-005**: Measured by the archive requests a loopback registry receives in a Bazel-in-Bazel
  test with a fresh output base and an empty repository cache: a build of a target that needs none
  of a lockfile's packages causes no request, and one that needs one package causes requests only
  for it, its dependencies and its resolved peers.
- **SC-006**: Every acceptance scenario is covered by at least one test target (Bazel-in-Bazel
  integration tests for failures at evaluation or fetch, FR-025), except the `bazel run` part of
  US1-2 and US8-2, which CI or a recorded command checks and the hand-back lists.
- **SC-007**: `research.md` lists every lockfile access the reader makes, by key or by position,
  positional slots such as the tarball URL and the integrity included; at the analyze gate the list
  matches the reader's code, and every access the blog post does not describe has a canary; each
  canary, run once with its pinned access altered in its fixture, fails with its English message,
  recorded with the feature.
- **SC-008**: 100% of behavior-changing tasks have the record FR-030 requires.
- **SC-009**: Every gap is listed in `research.md` and shown to the user at the plan gate before any
  task for that requirement exists in `tasks.md`.
- **SC-010**: With the fixture of at least 2,000 packages (FR-037), extension evaluation time,
  actions per target and launcher start time are recorded in `research.md`, and each stays within
  the numeric bound the plan sets, enforced on Linux CI.

## Assumptions

### Proposed boundaries (approved or changed together with this specification)

These are scope choices the request leaves open. Approving the specification approves them.

- **Package sources fetched**: packages from npm registries (the default and others the lockfile
  records) and workspace members. Git and GitHub dependencies (the lockfile records no integrity
  for them, so constitution III cannot be met), tarball URL dependencies, `file:` and `link:`
  dependencies fail as FR-010 says; later work.
- **Patched packages** (`bun patch`, `patchedDependencies`): a package the lockfile marks as patched
  fails as FR-010 says rather than running unpatched; later work. Catalogs and `overrides` are in
  scope for the comparison of FR-006 (Revision 2).
- **The lockfile is maintained outside Bazel** with the consumer's Bun, as rules_js expects pnpm.
  No Bazel target updates it.
- **Only `bun.lock`**: `bun.lockb`, `package-lock.json`, `yarn.lock` and `pnpm-lock.yaml` are not
  read; Bun can migrate them (https://bun.com/docs/pm/lockfile).
- **No bundling**: `bun build` is a later feature.
- **Type-only packages** (`@types/*`) are fetched and copied like any package; type checking is not
  part of this feature.

### Other assumptions

- Local verification runs on Linux only (WSL); macOS and Windows results come from CI and are
  reported unverified until CI succeeds there.
- Windows consumers need no Bazel flag for the layout (FR-003, research G1).
  Bun resolving packages through directory junctions is unverified until Windows CI passes; if it
  does not, FR-004 applies.
- The Bun version tests pin stays the one `MODULE.bazel` requests (1.4.2), and the supported Bazel
  range stays `>=9.2.0`.
- Fixture lockfiles are written by the pinned Bun against a loopback registry; the lockfile reader
  is verified against those, not against lockfiles of other Bun versions, which are reported
  unverified unless a test covers them.
- The integration harness adds no `bazel_dep`: its Bazel binaries and inner-build archives are
  dev-only downloads pinned with their integrity (Revision 5).
- The registry presubmit runs only after a release tag, so it is not a criterion of this feature.
