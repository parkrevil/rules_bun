# Research: The Ruleset's Design Principles, Held Everywhere

**Feature**: `005-review-defect-fixes` | **Date**: 2026-10-28 | **Spec**: [spec.md](spec.md)

Part 1 lists the sources. Part 2 records one decision per principle (R1–R9). Part 3 holds the
audit tables SC-009 asks for. Part 4 is the register of Bun behaviors FR-009 asks for. Part 5
lists the decisions the user must confirm. Part 6 is the evidence log. Every command in Part 6
ran on Linux x64 (WSL) on 2026-10-28.

## Part 1: Sources

| ID | Source | Used for |
|---|---|---|
| BZ-toolchains | https://bazel.build/extending/toolchains | "Mandatory and Optional Toolchains": "When an optional toolchain type cannot be resolved, analysis continues"; registration order: "Within a package, toolchains are registered in the lexicographical order of their names"; toolchain transition: "Bazel keeps the overall configuration identical, but forces the toolchain to use the same execution platform as the parent" (R6) |
| BZ-modctx | https://bazel.build/rules/lib/builtins/module_ctx | `modules`: "The iteration order of this dictionary is guaranteed to be the same as breadth-first search starting from the root module" (R8) |
| BZ-platforms | https://bazel.build/extending/platforms | `target_compatible_with`, `@platforms//:incompatible`, `constraint_setting.default_constraint_value` (R5, R6) |
| BZ-labels | https://bazel.build/concepts/labels | target-name and repository-name characters (A5) |
| BZ-visibility | https://bazel.build/concepts/visibility | a source file of another package is visible only when exported (R9, FR-020) |
| BUN-run | https://bun.com/docs/cli/run | "`--bun` ... Force a script or package to use Bun's runtime instead of Node.js"; "absolute paths and paths starting with `./` are always run as source files" (R4) |
| BUN-sums | `https://github.com/oven-sh/bun/releases/download/bun-v{1.4.2,1.4.4}/SHASUMS256.txt` | musl archive digests (R5, E1) |
| NPM-pkg | https://docs.npmjs.com/cli/v11/configuring-npm/package-json | `bin`: "make sure that your file(s) referenced in `bin` starts with `#!/usr/bin/env node`"; `libc`: "This field only applies if `os` is `linux`" (R4, R5) |
| NPM-checks | https://github.com/npm/npm-install-checks `lib/index.js` at `fcba600c2e4d` (v9.0.0) | `checkList`, `checkPlatform` (R5, E3) |
| HL-readme | https://github.com/hermeticbuild/hermetic-launcher README | `finalize-stub --template <PATH> [OPTIONS] -- <arg0> ...`, `-o`, `--transform <N>`; `launcher.args_from_entrypoint`, `append_runfile`, `append_embedded_arg`; auto-registered toolchains for Linux, macOS and Windows x86_64 (R6) |
| HL-src | hermetic_launcher 0.0.16, `launcher/private/toolchains.bzl`, `launcher/private/rules/lib.bzl` | template toolchains are `target_compatible_with` the OS and CPU, finalizers `exec_compatible_with`; `_get_finalizer` reads only `ctx.toolchains` (R6) |
| RJS-pnpm | https://github.com/aspect-build/rules_js/blob/main/docs/pnpm.md | "`node_modules` from the current directory BUILD and above can be depended on for resolution at runtime" (R9) |
| RT | bazel-contrib/rules-template `mylang/extensions.bzl` | exports only the extension, not its tag classes (R9) |
| RPY | bazel-contrib/rules_python `python/private/python.bzl` | root module's toolchain settings take precedence over dependencies' (R8) |

## Part 2: Decisions

### R1. P1: content identity of a package instance (FR-001, US2)

- **Decision**: The extension writes, for each instance of a hub, its content identity next to its
  edges: `integrity` (padded, as the download verifies it), `source` (the download URL, or the
  `replace_package` label text when replaced) and `exclude` (the sorted, de-duplicated exclusion
  patterns that apply to the package), plus the hub's `lockfile` label text. `npm_instance` takes
  them as attributes and puts them in `NpmInstanceInfo` (private provider). `_equivalent` in
  `run.bzl` first compares the identities; `_check_unique` fails, before it reports dependency
  differences, naming the package version, both lockfiles and the first differing property in the
  order integrity, source, exclusion policy, with both values. Two instances are carried once only
  when identity and every edge's package version are equal (the existing edge check, which already
  holds the reached instances to the same rule).
- **Integrity checks**: an instance that is carried once has one identity, so the one download
  (`download_and_extract(integrity = ...)`) or the one replacement check verifies every lockfile's
  value; no carried instance loses its check (FR-001).
- **Edge case** (spec): one hub records integrity and the other none: the second is
  `npm_unsupported` (resolve.bzl: "bun.lock records no integrity"), so the target fails analysis
  through that instance already; R1's comparison covers only `ok` instances, and a test pins the
  failure.
- **Rationale**: constitution III; rules_js keys a package store entry by name, version and lockfile
  integrity.
- **Alternatives**: compare only integrity: a different exclusion policy would still drop files
  silently in one hub. Compare package repository labels: every hub has its own repository, so
  nothing would ever be merged, changing behavior US9 of feature 003 requires.

### R2. P1: no URL user information from any input (FR-002, US3)

- **Decision**: Move `_has_userinfo` from `npmrc.bzl` to a public function `has_userinfo(url)` of
  the same file, used by both readers. In `npm_extension.bzl` `_translate`, before any other
  diagnostic that may print a URL (the duplicate-entry check), every entry is checked: slot 1 (URL)
  of an npm entry, and the resolution of slot 0 of every entry kind whose resolution is a URL
  (`tarball`, and `unsupported` resolutions such as `git+https://user:token@host/...`), and every
  dependency spec of workspace `package.json` files and of `bun.lock` `workspaces` before
  `compare_manifests` can print it. A match
  fails evaluation with `rules_bun: <lockfile>: the packages entry "<key>" records a URL that holds
  user information (credentials before an @); give credentials through Bazel's downloader
  (--credential_helper or .netrc) instead`. The key never holds the URL (lockfile keys are package
  paths), and neither the URL nor slot 0 is printed.
- **Audit result that widens the fix**: `resolve.bzl` `unsupported_reason` prints the tarball
  resolution (the URL) into the reason, which the hub writes into `npm_unsupported(reason = ...)`,
  and the hub writes `name@<resolution>` into `npm_unsupported(package = ...)` and a sanitized form
  into the instance ID. R2's evaluation-time rejection removes every such path for URLs with user
  information; URLs without it stay as today.
- **Tag attributes**: no tag attribute of `bun` or `npm` holds a URL (A1).
- **Alternatives**: redact the user information and continue: the lockfile would then name a
  download that cannot succeed without credentials the ruleset never passes, and the `.npmrc` path
  rejects; one rule for both inputs (P1).

### R3. P3: Bun behavior pinned by canaries that assert (FR-009, FR-010, FR-013, US7)

- **C17** (`bun/tests/canary/c17_leading_dashdash.test.ts`, every platform): runs the toolchain's
  Bun (`process.execPath`) as the launcher runs it (`--no-env-file`, an absolute entry point) with
  `-- x` and asserts `process.argv.slice(2)` is `["x"]` and exit 0. When Bun keeps the `--`, it fails
  naming "the launcher's refusal of a leading `--` (bun/private/launcher.js, bun_binary doc)". E2
  shows Bun 1.4.4 drops it and keeps a `--` that is not first.
- **C18** (`bun/tests/canary/c18_extensionless_bin.test.ts`, every platform): writes two files
  without an extension under `TEST_TMPDIR`, each starting with `#!/usr/bin/env node`, one CommonJS
  (`require` of a sibling `.js`, as typescript's `bin/tsc`), one ES module (`import` of a sibling
  `.mjs`); runs each with the absolute path; asserts the output, empty stderr and exit 0. On a
  change it fails naming "rules_bun runs an npm bin file without a source extension with Bun
  (FR-012, bun/private/npm_repositories.bzl)". BUN-run documents that an absolute path runs as a
  source file; which loader an extensionless file gets is not documented, hence the canary (E2).
- **C1**: when `symlinkSync` throws, the test fails (`throw new Error("C1 cannot assert: this
  runner cannot create a symbolic link: ...")`), and it asserts `result.exitCode === 0` with stdout
  and stderr in the message before comparing the output. GitHub's hosted Windows runners run
  elevated, so symbolic links can be created there; if the PR's Windows jobs show otherwise, C1
  gets `target_compatible_with = select({"@platforms//os:windows": ["@platforms//:incompatible"],
  "//conditions:default": []})` and research Part 4 records C1 as unasserted on Windows (Part 5,
  D3).
- **Audit**: every canary was read for a path that returns without asserting (A3).

### R4. P4: a bin is runnable when it is a JavaScript program for Node or Bun (FR-012, US1)

- **Rule**: a bin file is runnable when its archive path ends in one of `SOURCE_EXTENSIONS`, or
  its first line starts with `#!` and names `node` or `bun`: the first word's basename is `node`
  or `bun`, or it is `env` and the first following word that starts with neither `-` nor contains
  `=` has basename `node` or `bun` (covers `#!/usr/bin/env node`, `#!/usr/bin/env -S node --flag`,
  `#!/usr/local/bin/node`, `#!/usr/bin/env bun`). Options on the `#!` line are not applied, as when
  Bun runs the file itself (BUN-run). Anything else is not runnable: a missing file (absent or
  excluded by `exclude_package_contents`), a directory, a file whose first line is another `#!`
  line, or a file with neither (E2: Bun 1.4.4 parses a `#!/bin/sh` file as JavaScript and fails).
- **Where it is decided** (FR-012): the package repository, after extraction and renaming. The
  extension passes the entry's `bin` paths (`bins = attr.string_list`); the repository reads each
  file (through its safe name when R7 renamed it) and writes `bins = {<path>: <reason or "">}` on
  its `:tree` target. `npm_package_tree` returns a new private `NpmPackageTreeInfo(bins)`;
  `npm_instance` copies it into `NpmInstanceInfo.bins`; `npm_bin`'s `_check_bin` looks up its path
  and fails analysis: `<label>: the bin entry "<entry>" of the npm package <name>@<version> is the
  file <path>, which is not a JavaScript program for Node or Bun: <reason>`, reason one of "the
  package holds no such file", "it is a directory", "it has none of the extensions <list> and its
  first line is no #! line naming node or bun". No package is fetched earlier than today: the
  bin's analysis already needs the tree.
- **Removed**: `npm_extension.bzl` `_runnable` and the `runnable` field of the hub's link data.
- **Tags**: the hub can no longer tell at loading time which bins fail, so it cannot tag only those
  `manual`. Decision: every generated bin target is `manual` (D1). `bazel build //...` then builds
  no bin; a bin that a target uses, or that is named on the command line, is analyzed and built.
  This keeps the root suite and every consumer's `bazel build //...` free of failures caused by a
  third-party package's shell or native bin; rules_js creates bin targets only when the consumer
  instantiates a bin macro, so no rules_js bin is built by `//...` unasked either.
- **Rationale**: NPM-pkg names the node shebang as the bin convention; BUN-run runs a package CLI
  with Bun under `--bun`; constitution III forbids running it with anything but the toolchain's
  Bun.
- **Alternatives**: decide in the extension by extension or name: rejected by FR-012, and it is the
  defect. Make a non-runnable bin incompatible through a generated constraint: misuses platform
  constraints for a property of a file and loses the true message. Keep non-runnable bins
  non-`manual`: `bazel test //...` of this repository fails on the `nonjs-bin` fixture, and so would
  a consumer's.

### R5. P2: one platform table (FR-004, FR-005, FR-006, US4, US6)

- **Table**: new `bun/private/platforms.bzl` holds
  - `NPM_OS` (npm `os` → `@platforms//os:*`) and `NPM_CPU` (npm `cpu` → `@platforms//cpu:*`), moved
    from `npm_repositories.bzl`, and `NPM_LIBC` (`glibc`, `musl` → `//bun/platforms/libc:*`);
  - `BUN_ARCHIVES`: each Bun release archive in npm vocabulary: `linux-x64` (linux, x64, glibc),
    `linux-aarch64` (linux, arm64, glibc), `linux-x64-musl` (linux, x64, musl),
    `linux-aarch64-musl` (linux, arm64, musl), `darwin-x64`, `darwin-aarch64`, `windows-x64`;
  - `archive_constraint_sets(archive)`: the constraint lists a toolchain of the archive is
    registered with, mapped through the same three maps. A glibc archive serves `:glibc` and
    `:unconstrained` (two lists), a musl archive `:musl`, a non-Linux archive its OS and CPU only.
  `toolchains_repo.bzl`, `repositories.bzl` (the `platform` values) and `npm_repositories.bzl`
  (`_settings`) derive from it.
- **Toolchains**: `@<name>_toolchains` declares one execution and one target `toolchain()` per
  constraint list, named `<archive>_toolchain` / `<archive>_target_toolchain` for a non-Linux
  archive and a musl archive, and `<archive>_<libc>_toolchain` / `<archive>_<libc>_target_toolchain`
  (`libc` `glibc` or `unconstrained`) for a glibc archive. Constraints are explicit, so resolution
  does not depend on BZ-toolchains' lexicographic order. A Linux platform without the libc
  constraint has `:unconstrained` (BZ-platforms default value) and gets the glibc Bun, as today.
- **Integrity**: `versions.bzl` gains `linux-x64-musl` and `linux-aarch64-musl` for 1.4.2 and
  1.4.4, converted from BUN-sums (E1; the converted `linux-x64` values equal the existing ones,
  which checks the conversion). The archive's top directory is `bun-linux-x64-musl/` (E1), so the
  existing `strip_prefix = "bun-" + platform` holds. Baseline variants stay out of scope.
- **npm `os`/`cpu`**: `_matches` becomes `check_list(value, values)`, a transcription of
  NPM-checks `checkList`: a sole `any` matches; otherwise no `!` value may equal the value, and at
  least one positive value must equal it, unless every value is negated. `value` may be `None`
  (a platform without a mapped OS or CPU); `None` equals no entry. `libc_matches` keeps
  `checkPlatform`'s rule (`libc` only on Linux; `target.libc && !libc` fails) and the documented
  rules_bun reading of `:unconstrained` (feature 004 R11). E3 compares `checkList` and the old rule
  on every case of US6-2; they differ only for the sole `any`, and `["any", "!linux"]` matches
  nothing in both.
- **No musl runner**: musl is verified by toolchain resolution (analysis tests on both CPUs, both
  toolchain types) and by `bazel fetch` of the two musl repositories, not by running Bun on musl
  (spec Assumptions); the documentation says so.
- **Vendored archives**: `restricted_test` analyzes an inner build for a Linux platform with
  `:musl` (`--nobuild --platforms=//:linux_x64_musl`), which now resolves and fetches the musl Bun,
  so the loopback registry vendors `bun-linux-x64-musl.zip` and `bun-linux-aarch64-musl.zip` of
  1.4.4 (`registry/update.ts` `BUN_PLATFORMS`, `archives.bzl`, the generated `MODULE.bazel` block;
  integrity from `versions.bzl`). Found during implementation (T033); the plan said none was needed.

### R6. P2: the Windows launcher's toolchains only for Windows targets (FR-007, US8)

- **Defect, precisely**: `bun_binary`, `bun_test` and `npm_bin` request hermetic-launcher's
  template and finalizer types as optional toolchains. Optional only means "may be unresolved";
  both resolve for Linux and macOS too (HL-src registers templates for those OSes and finalizers
  for every execution platform), so a Linux build analyzes and fetches `runfiles_stub_<cpu>_linux`
  and `finalize_stub_<cpu>_<exec os>` (E4). These are hermetic-launcher stub repositories, not
  Windows stub archives as the spec words it; rules_bun uses them only as the Windows launcher,
  so FR-007 and SC-007 are read as "no hermetic-launcher stub repository" (D2).
- **Decision**: a private toolchain type `//bun/private/windows_launcher:toolchain_type`, with
  one `toolchain(target_compatible_with = ["@platforms//os:windows"])` whose implementation
  `windows_launcher_toolchain` (new `bun/private/windows_launcher.bzl`) requests hermetic-launcher's
  template and finalizer types (optional) and returns
  `platform_common.ToolchainInfo(template = File or None, finalizer = File or None)`. By the
  toolchain transition (BZ-toolchains) it resolves the finalizer for the parent's execution
  platform, and the template for the parent's target platform. rules_bun's `MODULE.bazel`
  registers it (`register_toolchains("//bun/private/windows_launcher:all")`, not dev-only), as
  hermetic_launcher registers its own; consumers need nothing. The rules request only this type
  (optional) instead of hermetic-launcher's two, so on Linux and macOS no toolchain of it matches
  and nothing of hermetic-launcher is analyzed or fetched.
- **Stub compilation**: the embedded arguments are built with hermetic-launcher's public helpers
  (`launcher.args_from_entrypoint`, `append_embedded_arg`, `append_runfile`, HL-readme) and the
  finalizer is run with `ctx.actions.run(executable = finalizer, inputs = [template], arguments =
  ["--template", template, "-o", stub, "--transform", <indices>, "--", <args>], toolchain =
  <windows launcher type>)`, the command line HL-readme documents. `launcher.compile` cannot be
  used: it reads the finalizer from `ctx.toolchains` only (HL-src).
- **Failures kept**: a Windows target without the rules_bun launcher toolchain, or with one whose
  template or finalizer is `None` (Windows on aarch64 has no auto-registered template, HL-readme),
  fails analysis naming the hermetic-launcher toolchain type that did not resolve and the target
  platform, as `no_stub_*` tests expect today.
- **Alternatives**: `alias` + `select()` on `@platforms//os:windows` to a forwarding target: the
  forwarding target picks its own execution platform, so the finalizer could be built for another
  one than the parent's actions run on. Calling the finalizer's CLI without a toolchain: the
  binary must match the execution platform, which only toolchain resolution chooses. Asking
  hermetic-launcher to constrain its templates: they are a cross-platform launcher by design.

### R7. P6: archive names safe on case-insensitive file systems (FR-017, US6-3)

- **Decision**: `_make_addressable` renames a file whose `name.lower()` is `build` or `build.bazel`
  (US6-3: `build`, `Build`, `build.bazel`, `Build.bazel`), as `BUILD` is renamed today. A directory
  named `build` is not renamed: Bazel marks a package only by a `BUILD` or `BUILD.bazel` file.
- **Consequence**: a bin or main file named `build` is renamed in the repository and mapped back by
  `replace_prefixes`; R4 reads it through its safe name.
- **Fixture**: the existing `build-files@1.0.0` archive gains `build`, `Build`, `build.bazel` and
  `Build.bazel` in two directories; `pack.ts` re-packs it with Bun 1.4.4, and its lockfile entries
  are rewritten by `write_lockfiles.ts` (feature 004 R8 procedure).

### R8. P5: module extensions follow Bazel's module semantics (FR-015, FR-016, US5)

- **`bun.toolchain`**: for each tag, in `module_ctx.modules` order (BZ-modctx: root first):
  validate `bun_version` (`version_key`, with the module and tag named in the error), each
  integrity key (`BUN_ARCHIVES`, error naming module, key and the known keys) and each value
  (`sha256-`, `sha384-` or `sha512-` followed by base64, error naming module and key). Collect, per
  name, version and platform, every value with its module. The root's value wins; two different
  root values for one platform fail naming the root module; with no root value, two different
  non-root values fail naming both modules (`name@version`), the Bun version and the platform. The
  highest version per name is selected as today; precedence applies to the integrity of one
  version only (spec Edge Cases). Values from several tags for one version are merged per platform,
  where today the last tag's whole dict replaced the others.
- **`npm`**: `translate_lock.name` must be a valid apparent repository name and
  `workspace_target_name` a valid target name (BZ-labels); each fails naming the module, the tag
  and the value (A5). Everything else is already validated or intentionally lenient (A5).
- **Rationale**: RPY gives the root module's toolchain settings precedence; P5.

### R9. P7: public API and documentation (FR-019–FR-022, US9)

- **`bun_toolchain`**: removed from `bun/extensions.bzl` (RT exports only extensions). Constitution
  VII: no version is published (`.bcr/metadata.template.json` lists none; `v0.0.0-test` is no
  `vMAJOR.MINOR.PATCH` release tag), so no consumer can depend on it and no migration message is
  owed (FR-019). The tag class stays defined in `bun/private/extensions.bzl`.
- **JSX**: the `_FILES_DOC` sentence becomes "JSX needs the `react` package; a consumer gets it from
  its `bun.lock` through the `npm` extension (`:node_modules/react` in `deps`)", covered by
  `//bun/tests/npm/fixtures/jsx:render` and `e2e/smoke` `//jsx:render`.
- **Resolution scope** (FR-020): `:node_modules/<package>` is placed at
  `<package of npm_link_all_packages>/node_modules/<package>` in the copy tree, and Bun's
  `node_modules` lookup walks up from the importing file, so the package resolves for files in and
  below that package and not for files elsewhere, as RJS-pnpm states for rules_js. A new layout
  case covers a source in a subpackage (resolves) and one in a sibling package (Bun's
  module-not-found error).
- **`replace_package` visibility** (FR-020): the generated check target names the archive's label,
  so the archive must be visible to the generated repository (`exports_files([...],
  visibility = ["//visibility:public"])`, BZ-visibility). The `replace` integration workspace gains
  a case without the export that fails with Bazel's visibility error.
- **Platforms** (FR-021): every platform statement names the runner labels of
  `.github/workflows/ci.yaml` (`ubuntu-latest`, `macos-latest`, `windows-latest`) and the jobs:
  root and `e2e/smoke` suites on all three (job `test`); `--noenable_runfiles` without a sandbox
  and coverage on `ubuntu-latest` only (`manifest-only`, `coverage`); Windows without Bash, with
  symbolic links and with an output root holding a space on `windows-latest`. Image names
  (`ubuntu-24.04`, `macos-26-arm64`, `windows-2025-vs2026`) and "Linux (WSL) only" go. The text is
  written once in `run.bzl` and referenced from `defs.bzl` and `npm_extension.bzl`, which then say
  only what differs. Each statement is checked against the PR's CI run before merge (quickstart
  Q12).

## Part 3: Audits (SC-009)

Result: **holds** (no change), **fixed** (decision named), **intended** (a recorded earlier
decision).

### A1. P1 (FR-003): comparing, keying, merging and deduplicating instances; reading and printing URLs

| Place | Result |
|---|---|
| `npm_extension.bzl` `first_entries`: all entries of one `name@version` in one lockfile agree on integrity and URL | holds; its diagnostic prints URLs, safe after R2 because R2 runs first |
| `npm_extension.bzl` `packages.setdefault`: one package repository per `name@version` per hub | holds (guarded by `first_entries`) |
| `npm_extension.bzl` `_package_repo_names`: repository names per hub | holds |
| `npm_extension.bzl` `replacements` keyed by `name@version`, applied to every hub | holds; R1 compares the source, so two hubs with different lockfile integrity for a replaced package fail |
| `resolve.bzl` instance classes (`plain` + `status`): deduplication within one hub | holds (same lockfile, same entry) |
| `run.bzl` `_equivalent` / `_check_unique`: across hubs | fixed (R1). Two instances are from different hubs when their repository or their `hub` differs, so analysis tests can build instances of two hubs in one package. The hub-level uniqueness cases changed pairs: `npm_basic` leaves `test/**` out of every package, so its `a@1.0.0` now differs from `npm_workspace`'s by exclusion policy (new case `hubs_exclude`); `hubs_alike` uses `npm_hoisted`'s and `npm_workspace`'s `b@1.0.0`, `hubs` uses `npm_workspace` and `npm_overrides_top` |
| `run.bzl` `_package_layout` `instances.setdefault(_key(...))` | holds (keys hold the hub) |
| `run.bzl` `_copy_tree`: deduplicates the target's own files by runfiles path | holds (not package instances) |
| `npmrc.bzl` `read_npmrc`: registry URLs | holds (rejects user information); its scheme error prints the URL, after the user-information check |
| `npmrc.bzl` `package_url` | holds after R2 (inputs checked) |
| `lockfile.bzl` slot 1 URL, slot 0 resolution | fixed (R2) |
| `workspaces.bzl` `compare_manifests` / `_difference`: prints dependency specs of workspace `package.json` and `bun.lock` `workspaces` with `json.encode` | fixed (R2 extended: specs checked before comparison; found by the analysis step, G1). The check also walks `overrides`, `resolutions`, `catalog` and `catalogs` of the root `package.json` and of `bun.lock`, which `_difference` prints too (found in implementation) |
| `npm_extension.bzl` `_check_lockfile_urls`, `_check_specs` (new) | fixed (R2). A specifier or resolution counts as a URL only when it holds `://`, so `npm:@scope/x@1` is not mistaken for user information. Consequence: a `git+ssh://git@host/...` resolution holds the user information `git` and now fails evaluation of the whole lockfile, where it was an unsupported entry before (FR-002 applies to every URL with user information) |
| `resolve.bzl` `unsupported_reason`: prints a tarball resolution | fixed (R2 rejects URLs with user information before) |
| `npm_repositories.bzl` `url`, `canonical_id` attributes; `use_netrc` | holds after R2 |
| `repositories.bzl` Bun release URL | holds (built from version and platform) |
| `npm_package.bzl` `npm_unsupported(package = name@resolution)` | fixed (R2) |
| tag attributes of `bun` and `npm` | holds: none holds a URL |

### A2. P2 (FR-008): toolchain types, registrations, platform `select()`s, platform-specific repositories

| Place | Result |
|---|---|
| `//bun/toolchain:execution_type`, `:target_type` | holds |
| `toolchains_repo.bzl` registrations | fixed (R5) |
| `repositories.bzl` `bun_repositories.platform` values, `bun_register_toolchains` | fixed (R5) |
| `versions.bzl` | fixed (R5) |
| `run.bzl` hermetic-launcher toolchain requests | fixed (R6) |
| `run.bzl` `_windows_constraint` (`target_platform_has_constraint`) | holds |
| `run.bzl` `_bash_runfiles` merged on non-Windows only | holds; `@rules_shell//shell/runfiles` is a source file, fetched with `rules_shell`, which every consumer has (Bazel 9.2.0 `MODULE.tools`, feature 002 research) |
| `npm_repositories.bzl` `_settings` / `config_setting`s / `_select` / `_compatible` | fixed (R5: derived from the table, `checkList`) |
| `npm_repositories.bzl` `libc_matches` | holds (R5) |
| `npm_package.bzl` `npm_replacement_check` (`execution_type`) | holds |
| `MODULE.bazel` `register_toolchains` (dev Bun), new launcher registration | holds / added (R6) |
| `bun/platforms/libc` | holds |

### A3. P3 (FR-011): Bun invocations, flags, environment variables, workarounds; canaries

| Place | Behavior relied on | Source or canary | Result |
|---|---|---|---|
| `launcher.sh.tpl` `exec "$bun" --config=... --no-env-file launcher.js` | `--config`, `--no-env-file` | bun.com `runtime/bunfig`, `cli/run` (feature 002 research) | holds |
| `launcher.sh.tpl`, `launcher.js` refuse a set `BUN_OPTIONS` | Bun prepends `BUN_OPTIONS` | C16 (Windows), feature 002 research | holds |
| `BUN_RUNTIME_TRANSPILER_CACHE_PATH=0` | documented variable | bun.com `runtime/env` (feature 002) | holds |
| `launcher.js` binary: `--config`, `--no-env-file`, `--no-install`, `--preload` | documented | feature 002 research | holds |
| `launcher.js` refuses a leading `--` | Bun drops `--` after the entry point | none | fixed: C17 (R3) |
| `launcher.js` test: `test`, `--preload`, `--coverage*`, `--shard`, `--test-name-pattern`, `--reporter=junit` | documented `bun test` flags | feature 002 research | holds |
| `launcher.js` guard (`Bun.plugin` `onLoad`), pattern limit | C13 regexp limit | C13 | holds |
| copy tree instead of links | C1 | C1 | fixed (R3: C1 asserts) |
| `bun test` takes no `--config` | C4 | C4 | holds |
| snapshots unsupported | C2 | C2 | holds |
| Windows argument splitting | C7 | C7 | holds |
| npm bin run by Bun without a source extension | none | fixed: C18 (R3, R4) |
| `check_integrity.js` (`Bun.CryptoHasher`, `Bun.file`, `Bun.write`) | documented APIs | bun.com `api/hashing`, `api/file-io` | holds |
| `bun.lock` reading canaries (`canary/npm/c_*.test.ts`) | each asserts and has a red mode | feature 003, 004 | holds (read: none returns before asserting) |

### A4. P4 (FR-014): places that read package.json fields

| Place | Field | Result |
|---|---|---|
| `lockfile.bzl` `_entry` | `os`, `cpu`, `libc` (string or list) | holds |
| `lockfile.bzl` `_bin` | `bin` (string or object; a string is named after the package without its scope, NPM-pkg) | holds |
| `npm_extension.bzl` `_runnable` | bin runnability by extension | fixed (R4, removed) |
| `npm_repositories.bzl` `_matches` | `os`, `cpu` | fixed (R5: `platforms.bzl` `check_list`). Bun 1.4.4 writes no `os`/`cpu` for a sole `"any"` (E5), so the fixture `any_platform` characterizes and `check_list`'s unit cases carry the red |
| `npm_repositories.bzl` `libc_matches` | `libc` | holds |
| `workspaces.bzl` | `workspaces`, dependency fields, `catalog(s)`, `overrides`, `resolutions` of manifests | holds (compared with the lockfile only, features 003, 004) |
| `main`, `exports`, `type`, `engines`, `directories.bin` | not read; Bun resolves `main`/`exports`/`type` at run time; `directories.bin` ignored as rules_js does (feature 003 R10) | intended |

### A5. P5 (FR-016): tag classes and attributes

| Tag / attribute | Precedence and conflicts | Validation | Result |
|---|---|---|---|
| `bun.toolchain.name` | non-root may not change it | Bazel validates repository names | holds |
| `bun.toolchain.bun_version` | highest per name | `version_key` fails without naming module | fixed (R8: module named, through `semver.bzl` `version_error`) |
| `bun.toolchain.integrity` | last tag replaced the others | keys and values unchecked | fixed (R8) |
| `npm.translate_lock.name` | duplicates across modules fail | not checked as a repository name | fixed (R8) |
| `npm.translate_lock.bun_lock` | — | `.lockb`, missing file, version, JSONC | holds |
| `npm.translate_lock.npmrc` | — | keys, user information, scheme | holds |
| `npm.translate_lock.workspace_target_name` | — | not checked as a target name | fixed (R8) |
| `npm.translate_lock.exclude_package_contents` | per hub | patterns validated by `glob` at loading; keys naming no package are ignored, as rules_js | intended |
| `npm.replace_package` | root only; one per package | an unlisted package is ignored (feature 003 plan fix I) | intended |

### A6. P6 (FR-018): names from an archive or lockfile turned into Bazel names

| Place | Name | Result |
|---|---|---|
| `npm_repositories.bzl` `_make_addressable` | archive file names: `BUILD`, `BUILD.bazel` | fixed (R7: any case). No test of the rename-collision diagnostic exists; it is unchanged (unverified) |
| `npm_repositories.bzl` `_bin_reasons` (new) | `bin` paths read through their safe names | holds (R4). A renamed bin file is read through its safe name; no fixture holds a renamed bin (unverified) |
| same | names outside the target-name set | holds |
| same | Windows-reserved names (`aux.js`, `a:b.js`) | intended (documented as Bazel's extractor's behavior) |
| `npm_extension.bzl` `_sanitize`, `_package_repo_names` | repository names, clash suffix | holds |
| `npm_names.bzl` `target_name`, `bin_targets` | target names, clash error | holds |
| `resolve.bzl` `_target_safe`, store names | instance IDs, store directories (`/` as `+`) | holds |
| `run.bzl` `_npm_bin` copy-tree root | `_npm_bin/<package>/<bin>.bun` | holds |

### A7. P7 (FR-022): `doc =` strings, docstrings and diagnostics of the public API

| Place | Result |
|---|---|
| `bun/extensions.bzl` module docstring and exports | fixed (R9: `bun_toolchain` removed) |
| `bun/defs.bzl` docstring: platform statement | fixed (R9) |
| `run.bzl` `_FILES_DOC`: JSX, Platforms, npm packages platforms, bin wording | fixed (R4, R9) |
| `npm_extension.bzl` `_NPM_DOC` Platforms: "Evaluation of a 2,000-package lockfile took under 1 s" | fixed: `scale_test` asserts at most 10 s on Linux (`MAX_EVALUATION_MS`), and printed 1351 ms on Linux x64 (WSL) in this feature's run, so the doc states the asserted bound |
| `run.bzl` `bun_binary` doc: leading `--` | holds; now pinned by C17 |
| `npm_extension.bzl` `_NPM_DOC`: bins ("a file whose extension Bun does not run"), `BUILD` files kept, platforms, resolution scope, several lockfiles, `replace_package` visibility | fixed (R1, R4, R7, R9) |
| `npm_extension.bzl` `translate_lock` doc: credential sentence covers `bun.lock` too | fixed (R2) |
| `bun/private/extensions.bzl` `integrity` doc: platform keys, precedence | fixed (R5, R8) |
| `repositories.bzl` `_ATTRS.platform` doc | fixed (R5) |
| `bun/toolchain.bzl`, `toolchain.bzl` docs | holds |
| `bun/platforms/libc/BUILD.bazel` comment: now also selects the Bun | fixed (R5) |

## Part 4: Bun behaviors the ruleset relies on (FR-009)

| Behavior (Bun 1.4.4) | Source or canary |
|---|---|
| `--config`, `--no-env-file`, `--no-install`, `--preload`, `BUN_RUNTIME_TRANSPILER_CACHE_PATH` | bun.com (feature 002 research) |
| `BUN_OPTIONS` prepended to every Bun process | feature 002 research; C16 on Windows |
| relative import resolves from the real path under `--preserve-symlinks` | C1 |
| `bun test` has no `--config` | C4 |
| snapshot files written next to the test | C2 |
| guard pattern limit | C13 |
| Windows argument splitting by the stub | C7 |
| a `--` directly after the entry point is dropped | C17 (new, `bun/tests/canary/c17_leading_dashdash.test.ts`) |
| an absolute path runs as a source file | BUN-run |
| an extensionless file after a `#!/usr/bin/env node` line runs as JavaScript (CommonJS and ES module) | C18 (new, `bun/tests/canary/c18_extensionless_bin.test.ts`) |
| `--no-install` in `launcher.js` binary mode | bun.com `cli/run` (feature 002 research) |
| `bun test` flags the launcher passes: `--preload`, `--coverage`, `--coverage-reporter`, `--coverage-dir`, `--shard`, `--test-name-pattern`, `--reporter=junit`, `--reporter-outfile` | bun.com `cli/test` (feature 002 research) |
| `bun test` flags a user passes through `args` unchanged (`--timeout`, `--rerun-each`, `--retry`, `--concurrent`, `--randomize`, `--seed`, `--bail`, `--max-concurrency`, `--todo`, `--isolate`, `--smol`, `--conditions`, `--prefer-offline`, `--frozen-lockfile`) | bun.com `cli/test`; their effect is Bun's, only `--timeout` and `--isolate` are covered by a test (`bun_test` doc) |
| `bun.lock` fields read by `lockfile.bzl` | `canary/npm/c_*` (features 003, 004) |

## Part 5: Decisions for the user

- **D1** (R4): every generated `:node_modules/<package>/bin/<bin>` target becomes `manual`, so
  `bazel build //...` no longer builds bins it builds today; a used or requested bin is unchanged.
  Without it, a package whose bin is a shell script or native binary fails every `bazel build //...`
  of the consumer (FR-012 forbids deciding at loading time). Alternative for the user to choose:
  keep runnable bins non-`manual` by deciding in the extension, which FR-012 rules out.
  **Approved by the user (2026-10-28)**, with D2 and D3, at the plan gate.
- **D2** (R6): the stub repositories fetched for Linux and macOS are hermetic-launcher's Linux and
  macOS template and finalizer, not Windows archives; FR-007 and SC-007 are implemented and tested
  as "no hermetic-launcher stub repository is fetched".
- **D3** (R3): C1 stays compatible with Windows unless the PR's Windows jobs cannot create a
  symbolic link; then it is declared incompatible there and reported unasserted on Windows.

## Part 6: Evidence log

- **E1** (BUN-sums, 2026-10-28): `SHASUMS256.txt` of `bun-v1.4.2` and `bun-v1.4.4` list
  `bun-linux-x64-musl.zip` and `bun-linux-aarch64-musl.zip`. Converted (`xxd -r -p | base64`):
  1.4.2 `linux-x64-musl` `sha256-SDXspZ1tpw9GdPVkL25Fncrat3NpWy7Zki0TEFeYl0I=`,
  `linux-aarch64-musl` `sha256-cXYLbI6jBiO4GkkHy4FdSOLqJm8uc+dRU0pEoGB5UN8=`; 1.4.4
  `linux-x64-musl` `sha256-pajMxedNy4g/6XTxJae9s7QeUZXtG4cOc/F+/9PrKy0=`, `linux-aarch64-musl`
  `sha256-V/AbAqxxE8Yck18o84wuq4SePJcNqyH4tkCoex72UAk=`. The same conversion of `linux-x64` gives
  the values `versions.bzl` already holds for both versions. `bun-linux-x64-musl.zip` of 1.4.4,
  downloaded, has SHA-256 `a5a8ccc5…2b2d` (equal to the list) and holds `bun-linux-x64-musl/bun`.
- **E2** (pinned Bun 1.4.4, `+bun+bun_linux-x64/bun`): `bun --no-env-file --no-install <abs>/tsc a
  -- b` with `tsc` extensionless, `#!/usr/bin/env node`, `require("./lib.js")` prints
  `["a","--","b"]`, exit 0; an extensionless ES module after the shebang runs; an extensionless
  file with TypeScript syntax runs; one without a shebang runs; a `#!/bin/sh` file fails with
  `error: Expected ";" but found "shell"`. `bun <abs>/tsc -- x y` prints `["x","y"]`; `bun t.js --
  x` prints `["x"]`.
- **E3** (NPM-checks): `checkList` returns true for a sole `any`; for `["any", "!linux"]` it returns
  false for every value (`any` is then an ordinary positive value). The old `_matches` agrees with
  `checkList` on every case except the sole `any`.
- **E5** (pinned Bun 1.4.4, `write_lockfiles.ts any_platform`, 2026-10-28): for a package whose
  `package.json` has `"os": ["any"]` and `"cpu": ["any"]`, Bun writes the entry's metadata as `{}`.
- **E6** (implementation deviations, 2026-10-28): T036's "it is a directory" case uses the bin
  `dir` of the new `node-bin` fixture, since `dirbin` declares its executables only through
  `directories.bin` and gets no bin target; `node-bin` also has the bin `gone`, which the hub
  `npm_bins_node` excludes, for "the package holds no such file". T064 adds no case: the existing
  `no_stub` case is the Windows target whose launcher toolchain has no template.
- **E4** (output base of this repository, Linux x64): `external/` holds
  `hermetic_launcher++non_module_dependencies+runfiles_stub_x86_64_linux` and
  `+finalize_stub_x86_64_linux` among others after `bazel test //...`; hermetic_launcher 0.0.16
  `toolchains.bzl` constrains templates by target OS and CPU and finalizers by execution OS and CPU.
  Implementation measures it exactly with the Bazel-in-Bazel test of quickstart Q8 before the fix.
