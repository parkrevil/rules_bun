# Feature Specification: The Ruleset's Design Principles, Held Everywhere

**Feature Branch**: `005-review-defect-fixes`

**Created**: 2026-10-27

**Status**: Draft

**Input**: User description: "Fix the defects that two adversarial reviews of the whole repository
(main at aca8c13, a Claude subagent and Codex) found and that were each confirmed against the code.
Every fix follows bazel.build, bun.com, npm's documented rules and the reference rulesets
(rules-template, rules_js, rules_python), test-first, with no workaround that lacks a canary.
(1) npm_bin and the npm extension refuse a bin file without a JS/TS extension (bun/private/run.bzl
_check_bin, npm_extension.bzl _runnable) with a false message; Bun 1.4.4 runs an extensionless file
such as typescript's bin/tsc (#!/usr/bin/env node). Run such bins with Bun; keep rejecting only what
Bun cannot load; pin the behavior with a canary. (2) Cross-hub deduplication (run.bzl _equivalent)
merges two instances of one package version from different lockfiles without comparing content
identity (integrity, URL/replacement, exclusion policy), so a different archive and its integrity
check can be dropped silently (constitution III). Compare content identity and fail on a mismatch,
keeping every applicable integrity check; add a test. (3) A bun.lock package URL holding user
information (credentials) is accepted and written into repository attributes, and the
duplicate-entry diagnostic prints it (npm_extension.bzl, npmrc.bzl package_url); reject it as the
.npmrc path does, without echoing the URL; test both paths. (4) A Linux target platform with
//bun/platforms/libc:musl gets the glibc Bun (toolchains_repo.bzl, repositories.bzl): register
Bun's official musl release archives for musl platforms and keep glibc archives for :glibc and
:unconstrained, with integrity from SHASUMS256.txt. (5) The launcher's rejection of a leading `--`
works around Bun dropping it, but no canary pins that Bun behavior (launcher.js, run.bzl doc); add
one. (6) Canary C1 (bun/tests/canary/c1_preserve_symlinks.test.ts) returns successfully when it
cannot create a symbolic link, so it can pass without asserting anything; make it fail or be
explicitly incompatible where it cannot run, and assert the child's exit status. (7)
bun/private/extensions.bzl lets a dependency module's toolchain tag overwrite the root module's
integrity values for the same Bun version, and does not validate integrity keys against the known
platforms; let the root win, fail on conflicts, validate keys. (8) npm os/cpu values [\"any\"]
exclude a package everywhere (npm_repositories.bzl _matches); follow npm-install-checks checkList.
(9) An npm archive file named build or Build.bazel is not renamed (npm_repositories.bzl,
case-sensitive check) although a case-insensitive file system makes it a Bazel package; compare
case-insensitively. (10) The hermetic_launcher Windows stubs are fetched for Linux and macOS targets
that never use them (run.bzl optional toolchains); resolve them only where used, the way Bazel
documents for optional toolchains. (11) Documentation: the claim that rules_bun does not provide
react (run.bzl) is false; the platform statements in run.bzl, defs.bzl and npm_extension.bzl
contradict each other and the CI runner labels; document where :node_modules/<pkg> resolves (only
below the package that calls npm_link_all_packages, as rules_js documents) and that a
replace_package archive must be visible to the generated repository. (12) bun/extensions.bzl
exports the tag class bun_toolchain as public API, which rules-template does not; remove it (a
breaking change under constitution VII only if a consumer could use it; decide per the
constitution). Done when root bazel test //..., the unsandboxed run, e2e/smoke bazel test //...,
prek, and PR CI on Linux, macOS and Windows pass. Work on a branch from main and deliver it as one
PR."

**Direction (user, 2026-10-28)**: not a list of patches. The design is stated first as principles
taken from the official sources, each principle is applied to every place in the ruleset it
governs (an audit, not only the reviewed lines), and each reviewed defect is one acceptance case of
a principle.

## Design Principles

Each principle is a rule the whole ruleset holds. Its source is the authority; the defects the
reviews found are where the ruleset broke it.

### P1. A package instance is its content

An npm package instance is identified by name, version and content: the integrity the lockfile
records (constitution III, rules_js verifies pnpm-lock.yaml entries the same way), its source (the
registry or tarball URL, or a `replace_package` archive) and the file set it keeps (exclusions).
Instances are interchangeable only when all of that and the instances their dependencies resolve
to are equal. A URL is a location, never part of the trust: credentials come only from Bazel's
downloader (bazel.build credential helpers, `.netrc`), never from a lockfile or `.npmrc` URL, and
no attribute or diagnostic carries them.
Defects removed: cross-hub deduplication ignoring content; credentials in `bun.lock` URLs.

### P2. One platform model

A target platform is described only by Bazel constraints: `@platforms//os`, `@platforms//cpu` and
`@rules_bun//bun/platforms/libc`. Every platform-dependent choice is derived from that one model:
the Bun archive a toolchain uses (by Bazel toolchain resolution), the npm optional packages a link
carries (by npm's rule, npm-install-checks `checkPlatform`/`checkList`) and the launcher an
executable gets. Bun's published archives (`SHASUMS256.txt`) and npm's `os`/`cpu`/`libc` values map
to those constraints in one table. A dependency that only one platform uses is reached only on that
platform (Bazel platforms: incompatible targets and platform `select()`).
Defects removed: a musl platform getting the glibc Bun; npm `"any"` excluding a package; Windows
launcher stubs fetched for Linux and macOS.

### P3. Bun's behavior comes from bun.com or a canary that asserts

Every Bun behavior the ruleset relies on is documented on bun.com; a workaround of an upstream
defect, and a documented behavior the ruleset depends on closely, is also pinned by a canary
(constitution V). A canary asserts on every platform it is compatible with and is declared
incompatible (`target_compatible_with`) where it cannot run; it never passes without asserting.
Defects removed: no canary for Bun dropping a leading `--`; canary C1 passing vacuously.

### P4. npm's package.json semantics decide what a package means

What a package's `bin`, `os`, `cpu` and `libc` mean is what docs.npmjs.com (`package-json`) and
npm's own implementation say. A `bin` entry is a file the package runs as a JavaScript program
(npm: it "starts with `#!/usr/bin/env node`"); no file extension is required. The ruleset runs it
with Bun, as Bun runs a package's CLI with `--bun` (bun.com `cli/run`).
Defects removed: extensionless bins refused with a false message.

### P5. Module extensions follow Bazel's module semantics

`module_ctx.modules` is in breadth-first order from the root module (bazel.build `module_ctx`);
the root module's tags take precedence over its dependencies', non-root modules that disagree fail,
and every tag value is validated with an error naming the module and the tag. This holds for every
tag class of every extension the ruleset defines (`bun`, `npm`).
Defects removed: a dependency overwriting the root's integrity; unvalidated integrity keys.

### P6. A file name from an archive is safe on every file system Bazel runs on

Names that come from a package archive are mapped to Bazel-addressable names by one total rule that
holds on case-insensitive file systems (macOS, Windows), where any case of `BUILD` or `BUILD.bazel`
makes a Bazel package.
Defects removed: `build` and `Build.bazel` not renamed.

### P7. The public API is minimal and every statement is tested

The public API is what constitution I lists, exported as rules-template exports its symbols; every
documentation statement is true and covered by a test, naming the platforms (by the CI runner
labels) where it ran (constitution II).
Defects removed: the `bun_toolchain` tag class exported; the false "rules_bun does not provide
react"; contradicting platform statements; undocumented `node_modules` resolution scope and
`replace_package` visibility.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A package executable that Bun can run is runnable (Priority: P1)

A consumer depends on an npm package whose `bin` entry is a file without an extension, such as
typescript's `bin/tsc` (a JavaScript file starting with `#!/usr/bin/env node`). Today the ruleset
refuses it, both in `npm_bin` and in the targets the npm extension generates, claiming that Bun runs
only JavaScript and TypeScript files with a known extension. Bun 1.4.4 runs such a file. After the
fix, the consumer runs `tsc` through the ruleset, with Bun, exactly as the package's author intends;
only a file Bun cannot load is refused, with a message that is true.

**Why this priority**: The refusal blocks common packages (typescript, and every package whose
executables follow the npm convention of extensionless bins) and its message is false.

**Independent Test**: A fixture package with an extensionless `bin` file that starts with a node
shebang is run through `npm_bin` and through the generated bin target; both print the expected
output. A canary pins that the pinned Bun runs an extensionless JavaScript file.

**Acceptance Scenarios**:

1. **Given** a package whose `bin` file has no extension and holds JavaScript with a
   `#!/usr/bin/env node` line, **When** the consumer runs its `npm_bin` target or the generated bin
   target, **Then** Bun runs it and the program's output and exit status are those of the file.
2. **Given** a package whose `bin` file has neither a source extension nor a `#!` line naming
   `node` or `bun` (npm's bin convention), **When** analysis reaches the target, **Then** it fails
   naming the package, the bin entry and the file, with that reason.
3. **Given** the pinned Bun stops running an extensionless JavaScript file, **When** the canary
   runs, **Then** it fails naming the ruleset behavior that relies on it.

---

### User Story 2 - Every package archive stays verified when several lockfiles share it (Priority: P1)

A consumer translates two lockfiles into two hubs. Both list the same package version. Today the
ruleset carries such a package once when its dependency edges match, without comparing what the two
lockfiles say the package is: its integrity, its source URL or replacement archive, and which files
are excluded from it. A different archive, and the integrity check that should reject it, can then be
dropped without a word. After the fix, two instances are carried once only when they are the same
content; any difference fails with a diagnostic naming the package version, both lockfiles and the
property that differs, and every integrity check either lockfile requires still runs.

**Why this priority**: Constitution III: a download that is not verified against the integrity its
lockfile records breaks reproducibility and supply-chain verification.

**Independent Test**: Two lockfile fixtures list one package version with (a) identical content
identity, (b) different integrity, (c) different URL or replacement, (d) different exclusion policy;
(a) builds with one instance, (b)–(d) each fail naming the difference.

**Acceptance Scenarios**:

1. **Given** two hubs whose instances of one package version have equal integrity, source and
   exclusion policy and lay out alike, **When** a target uses both, **Then** the package is carried
   once and its integrity is verified.
2. **Given** two hubs whose instances of one package version differ in integrity, **When** a target
   uses both, **Then** the build fails naming the package version, both hubs and that the integrity
   differs.
3. **Given** two hubs whose instances differ in source URL, replacement archive or exclusion policy,
   **When** a target uses both, **Then** the build fails naming the property that differs.

---

### User Story 3 - Credentials in a lockfile URL are rejected and never printed (Priority: P1)

A `bun.lock` package entry may record a URL that holds user information
(`https://user:token@host/...`). Today the ruleset accepts it, writes it into the attributes of the
generated repository (where it is visible to anyone who can read Bazel's output) and prints it in the
diagnostic for a duplicate entry. The `.npmrc` path already rejects such a URL without echoing it.
After the fix, a lockfile URL with user information is rejected the same way, naming the lockfile and
the package but never the URL or the credentials; credentials come only from Bazel's downloader.

**Why this priority**: Leaking credentials into repository attributes and logs is a security defect.

**Independent Test**: A lockfile fixture whose entry URL holds user information fails evaluation; the
failure text holds neither the user nor the token. The existing `.npmrc` rejection is tested the same
way.

**Acceptance Scenarios**:

1. **Given** a `bun.lock` entry whose URL holds user information, **When** the npm extension
   evaluates, **Then** it fails naming the lockfile and the package, telling the user to give
   credentials through Bazel's downloader (`--credential_helper` or `.netrc`), and the message
   contains neither the user information nor the URL.
2. **Given** an `.npmrc` registry URL holding user information, **When** the npm extension
   evaluates, **Then** it fails the same way (existing behavior, now covered by a test).
3. **Given** a lockfile with a duplicate entry whose URL holds user information, **When** the npm
   extension evaluates, **Then** no diagnostic contains the user information.

---

### User Story 4 - A musl platform gets the musl Bun (Priority: P1)

A consumer builds for a Linux platform with `@rules_bun//bun/platforms/libc:musl` (for example an
Alpine container image). Today the ruleset gives it the glibc build of Bun, which does not run on a
musl system. After the fix, the ruleset knows Bun's official musl release archives for x64 and
aarch64 Linux, with integrity from each release's `SHASUMS256.txt`, and selects them for musl
platforms, both as execution and as target toolchain; `:glibc` and `:unconstrained` platforms keep the
glibc archives.

**Why this priority**: The libc constraint is public API since feature 004; a musl platform getting a
binary that cannot run on it makes that constraint wrong for the toolchain.

**Independent Test**: Toolchain-resolution analysis tests select the musl toolchain for a Linux
platform with `:musl` and the glibc toolchain for `:glibc` and for a platform without the libc
constraint, on both CPUs; `bazel fetch` of the musl repositories verifies their integrity.

**Acceptance Scenarios**:

1. **Given** a Linux target platform with `:musl`, **When** a target needs the Bun target
   toolchain, **Then** the toolchain resolved is the musl archive for that CPU.
2. **Given** a Linux execution platform with `:musl`, **When** an action needs the Bun execution
   toolchain, **Then** the toolchain resolved is the musl archive for that CPU.
3. **Given** a Linux platform with `:glibc` or without the libc constraint, **When** a Bun toolchain
   is resolved, **Then** it is the glibc archive, as before.
4. **Given** a consumer requesting a known Bun version without integrity, **When** the musl archive
   is fetched, **Then** it is verified against the integrity taken from that release's
   `SHASUMS256.txt`.

---

### User Story 5 - Toolchain requests from several modules resolve predictably (Priority: P2)

The root module and a dependency module both request the same Bun version with integrity values.
Today whichever tag the extension reads last overwrites the other, so a dependency can replace the
root's integrity. A key such as `linux_x64` (a typo) is accepted and silently ignored. After the fix,
the root module's value wins for each platform it lists; two non-root modules that give different
values for the same version and platform fail naming both modules and the platform; a key that is not
a known platform fails naming the key and the known platforms.

**Why this priority**: The root module must control what it downloads (rules_python and rules_js give
the root precedence); a silently ignored key defeats the integrity the user meant to pin.

**Independent Test**: Bazel-in-Bazel or extension-level tests with a root and dependency modules
cover root-wins, non-root conflict and unknown key.

**Acceptance Scenarios**:

1. **Given** the root and a dependency request one version with different integrity for one
   platform, **When** the extension evaluates, **Then** the root's value is used.
2. **Given** two non-root modules request one version with different integrity for one platform,
   **When** the extension evaluates, **Then** it fails naming both modules, the version and the
   platform.
3. **Given** an integrity key that is not a known platform, **When** the extension evaluates,
   **Then** it fails naming the key and listing the known platforms.

---

### User Story 6 - npm's platform and file-name rules hold (Priority: P2)

A package whose `os` or `cpu` is `["any"]` is excluded on every platform today, although npm
(`npm-install-checks` `checkList`) treats `any` as matching every value. A file named `build` or
`Build.bazel` inside an npm archive is not renamed today, because the check is case-sensitive, yet on
a case-insensitive file system (macOS, Windows defaults) Bazel treats it as a `BUILD` file and the
directory becomes a package. After the fix, `os`/`cpu` lists follow `checkList` exactly, and every
file whose name equals `BUILD` or `BUILD.bazel` ignoring case is renamed as `BUILD` is today.

**Why this priority**: Both lose package content silently on some platforms.

**Independent Test**: Unit tests of the `os`/`cpu` rule over npm's `checkList` cases including
`any`; a fixture archive with `build` and `Build.bazel` files keeps those files reachable on every CI
platform.

**Acceptance Scenarios**:

1. **Given** an entry with `os: ["any"]` or `cpu: ["any"]`, **When** a target is built for any
   platform, **Then** the entry is linked.
2. **Given** each case of npm's `checkList` (positive list, `!` negation, mixed, empty, `any`),
   **When** the rule is evaluated, **Then** its result equals `checkList`'s.
3. **Given** an archive holding files named `build`, `Build`, `build.bazel` or `Build.bazel`,
   **When** the package repository is created, **Then** each is renamed, the package's files stay in
   one Bazel package, and a program reading the original path still reads the file.

---

### User Story 7 - Every workaround is pinned and every canary asserts (Priority: P2)

The launcher refuses `--` as the first program argument because Bun 1.4.4 drops a `--` right after
the entry point, but no canary pins that Bun behavior, so the refusal would outlive the defect
unnoticed. Canary C1 returns successfully when the runner cannot create a symbolic link, so it can
pass without asserting anything, and it does not check the child's exit status. After the fix, a
canary pins the dropped `--` and fails naming the launcher check when Bun keeps it; C1 fails where it
cannot create a link, or is declared incompatible with the platforms where it cannot run, and asserts
the child's exit status.

**Why this priority**: Constitution V: a workaround of upstream behavior is allowed only while a
canary pins that behavior; a canary that can pass without asserting pins nothing.

**Independent Test**: The new canary passes against Bun 1.4.4; C1 run where symbolic links cannot be
created fails (or is reported incompatible, not passed); C1 with a child that exits non-zero fails.

**Acceptance Scenarios**:

1. **Given** the pinned Bun drops a `--` directly after the entry point, **When** the new canary
   runs, **Then** it passes; **Given** a Bun that keeps it, **Then** it fails naming the launcher's
   refusal of a leading `--`.
2. **Given** a runner that cannot create a symbolic link, **When** C1 runs, **Then** it fails, or the
   target is incompatible with that platform and is reported as skipped by Bazel, never as passed.
3. **Given** the child process exits with a non-zero status, **When** C1 checks it, **Then** C1
   fails reporting the status and the output.

---

### User Story 8 - Linux and macOS builds do not fetch the launcher only Windows uses (Priority: P3)

A consumer builds a `bun_binary` for Linux or macOS. Today the ruleset resolves, and so fetches,
hermetic-launcher's stub template and finalizer toolchains (their Linux and macOS builds, research
R6/D2), although only a Windows target's launcher uses them. After the fix, they are resolved only
for Windows targets, so a Linux or macOS build fetches no hermetic-launcher stub repository.

**Why this priority**: Unneeded downloads slow builds and break offline builds, but nothing is
miscompiled.

**Independent Test**: A Bazel-in-Bazel build of a `bun_binary` for a Linux target, with the
hermetic-launcher stub archives absent from the offline registry and network denied, succeeds; a
Windows target still gets its `.exe` stub.

**Acceptance Scenarios**:

1. **Given** a Linux or macOS target platform, **When** a `bun_binary` or `bun_test` is built,
   **Then** no hermetic-launcher stub repository is fetched.
2. **Given** a Windows target platform, **When** the same target is built, **Then** its launcher is
   the hermetic-launcher stub, as before, and a missing stub toolchain fails analysis naming it.

---

### User Story 9 - Documentation and public API state only what is true (Priority: P3)

The rule documentation says rules_bun does not provide `react`, though a consumer gets `react` from
its lockfile through the npm extension; the platform statements in `run.bzl`, `defs.bzl` and
`npm_extension.bzl` contradict each other and the runner labels CI uses; nothing says where
`:node_modules/<pkg>` resolves or that a `replace_package` archive must be visible to the generated
repository. `bun/extensions.bzl` exports the tag class `bun_toolchain`, which rules-template does not
export. After the fix, every such statement is true and covered by a test that ran on the platforms
it names, the two missing facts are documented, and `bun_toolchain` is no longer exported.

**Why this priority**: Constitution I and II; wrong documentation misleads consumers but breaks no
build.

**Independent Test**: Review of the generated documentation against the tests and CI configuration;
a test that loads `bun_toolchain` from `@rules_bun//bun:extensions.bzl` is impossible (the symbol is
absent) while `bun.toolchain` keeps working in `e2e/smoke`.

**Acceptance Scenarios**:

1. **Given** the documentation of the rules and the npm extension, **When** it names a platform,
   **Then** that platform is one CI runs the covering test on, named consistently in every file and
   with CI's runner labels.
2. **Given** the npm extension documentation, **When** a consumer reads it, **Then** it says that
   `:node_modules/<pkg>` exists only in the package that calls `npm_link_all_packages` (as rules_js
   documents) and that a `replace_package` archive label must be visible to the generated
   repository.
3. **Given** `@rules_bun//bun:extensions.bzl`, **When** its symbols are listed, **Then** they are
   `bun` and `npm` only.

### Edge Cases

- A `bin` file that is not a JavaScript program for Node or Bun (a `#!/bin/sh` script, a native
  executable, no `#!` line and no source extension): its target fails analysis with the FR-012
  reason; the ruleset never runs it with any tool other than Bun (constitution III).
- Two hubs list one package version where one records integrity and the other records none: the
  entry without integrity is unsupported, so a target that uses it fails with the existing
  "bun.lock records no integrity" reason before any deduplication.
- A lockfile URL whose user information is empty (`https://@host/`): it is treated as holding user
  information, as the `.npmrc` check treats it.
- A Bun version that rules_bun does not know, requested with integrity for the glibc platforms only:
  the musl repositories fail only when a musl platform actually resolves them, with the existing
  "pass the integrity" diagnostic naming the musl platform key.
- A release that does not publish a musl archive for a platform, or whose `SHASUMS256.txt` lacks it:
  work stops and the gap is reported; no integrity is computed from a local download.
- `os: ["any", "!linux"]`: the result is whatever `checkList` returns for it.
- An archive holding both `BUILD` and `build`, or a renamed name that collides with an existing file:
  the existing collision diagnostic fires.
- A root module that requests a version under the default name and a dependency that requests a
  higher one: the highest version is selected, as before; root precedence applies to integrity of
  the same version only.

## Requirements *(mandatory)*

### Functional Requirements

Each principle has an audit requirement: the plan enumerates every place in `bun/`, `e2e/` and the
tests that the principle governs, and `research.md` records each place and its result. A defect the
audit finds is fixed under the same principle.

**P1. A package instance is its content**

- **FR-001**: Two instances of one package version from different hubs MUST be carried once only
  when their content identity (integrity, source: registry or tarball URL or `replace_package`
  archive, and exclusion policy) and the identities of the instances their dependencies resolve to
  are equal; otherwise the build MUST fail naming the package version, both hubs (by the name the
  `npm.translate_lock` tag gives) with their `bun.lock` labels, and the first property that differs. Every integrity check of every carried instance MUST run.
- **FR-002**: A URL holding user information MUST NOT be accepted from any input the ruleset reads
  (`bun.lock`, `.npmrc`, tag attributes); it MUST be rejected during evaluation, naming the file and
  the package or key without echoing the URL, and pointing to Bazel's downloader for credentials.
  Repository attributes and diagnostics MUST NOT contain URL user information; this covers URLs and
  dependency specs in `bun.lock` `packages` and `workspaces`, workspace `package.json` files and
  `.npmrc`.
- **FR-003** (audit): every place that compares, keys, merges or deduplicates package instances, and
  every place that reads or prints a URL.

**P2. One platform model**

- **FR-004**: One table MUST map each Bun release archive and each npm `os`/`cpu`/`libc` value to
  Bazel constraints; toolchain registration and npm package selection MUST both derive from it.
- **FR-005**: The ruleset MUST know Bun's official musl archives (linux-x64, linux-aarch64) for
  every Bun version it knows, with integrity from each release's `SHASUMS256.txt`. A Linux platform
  with `@rules_bun//bun/platforms/libc:musl` MUST resolve the musl Bun of its CPU for both the
  execution and the target toolchain; `:glibc` and `:unconstrained` MUST resolve the glibc Bun.
- **FR-006**: npm's `os`, `cpu` and `libc` MUST match exactly as npm-install-checks
  `checkPlatform`/`checkList` do, including `any` and `!` values.
- **FR-007**: A dependency only one platform uses MUST be reached only on that platform: for a
  Linux or macOS target, no hermetic-launcher stub repository is fetched; a Windows target
  keeps the stub launcher and its analysis failure naming a missing stub toolchain.
- **FR-008** (audit): every toolchain type, toolchain registration, platform `select()` and
  platform-specific repository of the ruleset.

**P3. Bun's behavior comes from bun.com or a canary that asserts**

- **FR-009**: Every Bun behavior the ruleset relies on or works around MUST be listed in
  `research.md` with its bun.com source or its canary. The launcher's refusal of a leading `--`
  MUST get a canary that passes while the pinned Bun drops a `--` directly after the entry point
  and fails naming the refusal when Bun keeps it.
- **FR-010**: A canary MUST NOT pass without asserting: where its precondition cannot hold it MUST be
  declared incompatible (`target_compatible_with`) or fail; C1 MUST also assert the child's exit
  status.
- **FR-011** (audit): every Bun invocation, flag, environment variable and workaround in the
  launchers and rules, and every canary.

**P4. npm's package.json semantics decide what a package means**

- **FR-012**: A `bin` file MUST be run with the toolchain's Bun when it has one of Bun's source
  extensions or its first line is a `#!` line naming `node` or `bun` (npm: bins start with
  `#!/usr/bin/env node`), whatever its extension. The repository that holds the package MUST decide
  this from the file. Any other bin file MUST fail analysis of its target naming the package, the
  bin entry, the file and the true reason (it is not a JavaScript program for Node or Bun).
- **FR-013**: A canary MUST pin the documented behavior FR-012 relies on (bun.com `cli/run`: an
  absolute path runs as a source file): the pinned Bun runs an extensionless file holding
  JavaScript after a `#!/usr/bin/env node` line; it fails naming FR-012's behavior when that changes.
- **FR-014** (audit): every place that reads `bin`, `os`, `cpu`, `libc`, `main` or other
  package.json fields.

**P5. Module extensions follow Bazel's module semantics**

- **FR-015**: For one toolchain name and Bun version, the root module's integrity value MUST win
  for every platform it lists; non-root modules that disagree for one platform MUST fail naming both
  modules, the version and the platform. Integrity keys MUST be exactly the platforms the ruleset
  registers; any other key MUST fail naming it and the known keys.
- **FR-016** (audit): every tag class and attribute of the `bun` and `npm` extensions, for
  precedence (root first), conflicts between modules, and validation of every value.

**P6. A file name from an archive is safe on every file system Bazel runs on**

- **FR-017**: Every file of an npm archive whose name equals `BUILD` or `BUILD.bazel` ignoring case
  MUST be renamed and mapped back to its original path, as `BUILD` is today.
- **FR-018** (audit): every rule that turns a name from an archive or a lockfile into a file name,
  a directory name, a target name or a repository name.

**P7. The public API is minimal and every statement is tested**

- **FR-019**: `@rules_bun//bun:extensions.bzl` MUST export only `bun` and `npm`. No rules_bun
  version has been published (`.bcr/metadata.template.json` lists none; the only tag, `v0.0.0-test`,
  is not a release tag under constitution VII), so removing `bun_toolchain` is not a
  release-visible breaking change.
- **FR-020**: The documentation MUST NOT claim that rules_bun does not provide `react`, and MUST say
  how a consumer gets JSX's runtime package; it MUST state that `:node_modules/<pkg>` resolves only
  in and below the package that calls `npm_link_all_packages` (as rules_js documents) and that a
  `replace_package` archive must be visible to the generated repository.
- **FR-021**: Every platform statement MUST agree with the others and name the CI runner labels of
  `.github/workflows/ci.yaml` on which a covering test ran (constitution II).
- **FR-022** (audit): every `doc =` string, docstring and diagnostic of the public API.

**All principles**

- **FR-023**: Every fix MUST be test-first: the test that shows the defect is written and fails
  before the fix and passes after it.
- **FR-024**: The change MUST add no public API other than what `contracts/public-api.md` lists (the
  musl platform keys and `bun_repositories.platform` values, the musl repositories, the
  toolchains registered for them), and MUST NOT change behavior beyond what the principles require
  and that contract lists (including D1: every generated bin target is `manual`).

### Key Entities

- **Content identity of a package instance**: the integrity, source (URL or replacement archive) and
  exclusion policy that decide which bytes a package version consists of.
- **Bun platform**: a release archive Bun publishes, with its Bazel constraints; now including
  linux-x64-musl and linux-aarch64-musl, constrained to `//bun/platforms/libc:musl`.
- **Toolchain request**: a `bun.toolchain` tag with its module, name, version and per-platform
  integrity.
- **Canary**: a test that pins an upstream behavior the ruleset relies on or works around against
  the pinned Bun, and fails naming that reliance when the behavior changes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The root suite (sandboxed and unsandboxed), the `e2e/smoke` suite and `prek run
  --all-files` pass locally, and every job of the PR's CI run passes on Linux, macOS and Windows.
- **SC-002**: Each reviewed defect, and each defect the audits find, has at least one test that
  failed before its fix and passes after it.
- **SC-003**: A consumer can run a bin shaped like typescript's `tsc` (an extensionless file with a
  `#!/usr/bin/env node` line; the `node-bin` fixture) through the ruleset with zero extra
  configuration.
- **SC-004**: Zero diagnostics or repository attributes produced from a lockfile or `.npmrc` with
  credentials in a URL contain those credentials.
- **SC-005**: For two lockfiles sharing a package version, 100% of content-identity differences
  (integrity, source, exclusion policy) fail the build; zero are merged.
- **SC-006**: A Linux musl platform resolves the musl Bun on both CPUs, and glibc and unconstrained
  platforms resolve the glibc Bun, each case covered by a test.
- **SC-007**: A Linux or macOS build fetches zero hermetic-launcher stub repositories.
- **SC-008**: Zero canaries can pass without asserting their pinned behavior.
- **SC-009**: `research.md` holds one audit table per principle (FR-003, FR-008, FR-011, FR-014,
  FR-016, FR-018, FR-022), each listing every governed place and its result.

## Assumptions

- Bun publishes `bun-linux-x64-musl.zip` and `bun-linux-aarch64-musl.zip` for 1.4.2 and 1.4.4, listed
  in each release's `SHASUMS256.txt`; the baseline variants are out of scope, as they are for glibc
  today.
- No CI runner uses musl, so the musl Bun is verified by toolchain resolution and integrity only;
  running it on musl is reported as unverified (constitution II).
- "Root wins" applies per platform key; platforms the root does not list take a non-root value when
  the non-root modules agree on it.
- npm documents that a `bin` file starts with `#!/usr/bin/env node`; bun.com (`cli/run`) documents
  that "Bun always executes absolute paths and paths starting with `./` or `.\\` as source files",
  whatever their extension, and the launcher passes an absolute path. Canary C18 (FR-013) is a
  regression pin of that documented behavior.
- `npm-install-checks` `checkList` (npm's own package) is the authority for `os`/`cpu` matching, as
  feature 004 used its `checkPlatform` for `libc`.
- Platform documentation may be fixed either by naming the runner labels CI uses or by pinning CI to
  the images the documentation names; the plan picks one, and both must agree afterwards.
- The change touches `bun/` and `e2e/`, so it goes through the speckit workflow (AGENTS.md), on
  branch `005-review-defect-fixes` from `main`, delivered as one PR.
