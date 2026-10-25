# Research: npm Dependencies from `bun.lock`

**Feature**: `003-npm-dependencies` | **Date**: 2026-10-19, updated 2026-10-20 | **Spec**: [spec.md](spec.md) (Revision 5)

Every source below was read on 2026-10-19 unless marked otherwise. "Observed" means reproduced on
2026-10-19 on Linux (WSL) with the pinned Bun 1.4.2 (`bun --version` → `1.4.2`, commit `744846f84`)
or Bazel 9.2.0; the commands are in Part 5. Bazel API facts are taken from the 9.2.0 versioned pages
(`https://bazel.build/versions/9.2.0/...`) unless a HEAD page is named.

Part 1 lists the gaps the plan gate must see (SC-009). Part 2 holds the decisions R1–R17. Part 3 is
the lockfile access inventory and its canaries (FR-024, SC-007). Part 4 records approvals
(constitution V). Part 5 is the evidence log. Part 6 lists the sources.

## Part 1: Gaps and decisions for the plan gate

G1–G4 changed what the specification said; spec Revision 4 (2026-10-20) adopted the decision
recorded under each, and the spec text they cite below is the Revision 3 text they replaced. The
others are technical and decided here.

The implementer's plan fixes A–M of 2026-10-20 (after two adversarial reviews and Windows
experiments) are applied below: A in G1, B in R4, C in G9, D in G2, E in G10, F in R2, G in R9, H
in R2, I in G3, J in Part 4, K in the plan's Implementation Order, L in G5, M across G1, G7, G8,
R3, R5, R8 and the test map. Spec Revision 5 restates the requirements they touch. G11 (Windows
path length, 2026-10-25) is decided; every decision uses documented APIs, sourced in Part 6.

### G1 (decided, spec Revision 4): Windows does not need `--windows_enable_symlinks`

Spec FR-003, SC-001, SC-002, US8, FR-027 and an edge case require `--windows_enable_symlinks` on
Windows and an English error naming it when it is missing.

Facts:

- bazel.build documents `ctx.actions.symlink(..., target_type = ...)` (Bazel 9.2.0): "If specified,
  it must be one of 'file' or 'directory' ... On Windows, this determines which kind of filesystem
  object to create (junction for a directory, symlink for a file)." The documentation does not tie
  this to `--windows_enable_symlinks`.
- Bazel 9.2.0 source (`WindowsFileSystem.createSymbolicLink`) creates a junction whenever the target
  is not an existing file and the type is `DIRECTORY`, whatever `--windows_enable_symlinks` says;
  the flag only decides file symlinks versus copies. No source read here states whether creating a
  junction needs developer mode; Windows CI pins that the layout works with Bazel's defaults.
- rules_js v3.5.1 (`npm/private/utils.bzl`) passes `target_type = "directory"` on Bazel 9 for the
  same reason ("creates junctions instead of file symlinks on Windows"), after
  bazelbuild/bazel#26701 (closed 2025-10-17).
- Every link this design creates points to a directory (R5), so every link is a junction on Windows.

So the flag has nothing to do in this design, and there is no documented way to detect it from a
rule (no Starlark API reads startup options), so the "fails naming the flag" requirement could only
be met by an artificial failure.

**Decision**: the Windows flag requirement is dropped from FR-003, FR-027, SC-001, SC-002, US8 and
the edge case. Windows CI runs the npm tests twice, with Bazel's defaults and with
`--windows_enable_symlinks`, and both must pass (Bun resolving through junctions is unverified until
then; if it fails, FR-004 applies and the user is told).

Disk-cache portability (plan fix A, 2026-10-20). Concern: rules_js issue #1069 ("Caching broken on
Windows", open) reports cache misses on Windows when the workspace path differs, and a junction's
target is absolute. Observed (E8, Windows 11, Bazel 9.2.0, driven from WSL through interop): a
`declare_symlink` output made by `ctx.actions.symlink(target_path = <relative>)` becomes a junction
whose target is an absolute path under the output base; the symlink action itself is internal (it is
recreated in each output base and never restored from a cache); and an action that consumes the
junction got a disk cache hit from a build in a different output base and a different workspace
path. So junctions do not break disk-cache portability. The #1069 misses come from other absolute
paths (rules_js's Bash invocation inside its `.bat` launchers), which rules_bun does not have
(feature 002 launches through hermetic-launcher on Windows). The strict layout stays on Windows, with
`target_type = "directory"` and no `--windows_enable_symlinks`. Because E8 ran on one machine, a
Windows CI check pins it: the job builds the npm test targets twice with different
`--output_base` values and one shared `--disk_cache`, and asserts from the second build's execution
log (`--execution_log_json_file`, `spawn.proto`) that every action consuming a store link was a
cache hit; the field name is taken from `spawn.proto` at Bazel 9.2.0 when the check is written.

### G2 (decided, spec Revision 5; replaces the Revision 4 decision): Windows-invalid file names are not promised to fail

Revision 4 made FR-036 a build-time failure of a bsdtar extraction action. Plan fix B moves
extraction into the package repository (`repository_ctx.download_and_extract`, R4), so that action
no longer exists, and plan fix D drops the promise of a failure.

Facts: the extension cannot list an archive's entries before extraction (the lockfile records no
file names, and nothing in `module_ctx` opens an archive). Bazel 9.2.0 extracts tar archives with
Apache Commons Compress (`CompressedTarFunction.java` imports
`org.apache.commons.compress.archivers.tar.TarArchiveInputStream`) and writes entries through its
own file system layer; neither that file nor `StripPrefixedPath.java` handles Windows-invalid names
(`aux.js`, a name with `:`). The plan-fix note that libarchive renames such names to `_` concerns
bsdtar, which this design no longer runs. What Bazel does on Windows with such an entry (stores it
under another name, writes something else, or fails) is unverified.

**Decision**: FR-036 now says such a name may be renamed, dropped or fail on Windows, as Bazel's
extractor handles it, and the ruleset promises neither a failure nor a message. The documentation
states this. A Windows CI canary (C-WINNAME, Part 3) extracts a fixture archive holding `aux.js`
and `a:b.js` and pins what Bazel 9.2.0 does; it fails, naming the behavior to revisit, when that
changes.

### G3 (decided, spec Revision 4): root real-run tests cannot use a `--downloader_config` rewrite to local files

Spec Revision 3 item (5) and FR-026 say root real-run tests fetch fixture archives in the repository
through a `--downloader_config` rewrite.

Facts (command-line reference, `--downloader_config`): the file holds `allow`, `block`, `rewrite`
and `all_blocked_message` directives; for `rewrite`, "Do not include the URL scheme (`http://` or
`https://`) in the patterns." Rewriting to a `file://` URL is therefore not documented, and a file
URL would need an absolute path, which a checked-in `.bazelrc` cannot hold. `--distdir` is marked
"[Deprecated]" on `run/build` (constitution V forbids it). The repository cache is documented to
serve a download only when it "has a SHA256 sum of the file specified", and npm integrity values are
SHA-512.

**Decision**: add rules_js's `npm_replace_package` pattern (rules_js v3.5.1
`npm/extensions.bzl`: root-module-only tag, `package = "name@version"`, `replacement = <label>`) as a
root-only tag `npm.replace_package`. Its replacement is a package archive (`.tgz`) in the workspace,
and the build checks that the archive's digest, computed with the algorithm the lockfile's
integrity names (`sha256`, `sha384` or `sha512`, R13), equals that integrity before using it, so constitution III's verification still holds.
The package repository of a replaced package extracts the replacement with `repository_ctx.extract`
(R4) instead of downloading; the check is a build action whose output joins the runfiles of every
target that carries the package, so no program or test runs before it passes.

Scope (plan fix I, rules_js semantics, part of the rules_js approval of 2026-10-18, Part 4): rules_js
v3.5.1 `npm/extensions.bzl` collects `npm_replace_package` tags from all modules into one
`replace_packages` map, fails for a non-root module and for a package replaced twice, and passes the
map to every `npm_translate_lock`; `npm_translate_lock_helpers.bzl` applies a replacement only where
a package matches and never fails for one that matches nothing. So `npm.replace_package` applies to
every lockfile in the module and never fails for a package no lockfile lists; a non-root use and a
double replacement still fail evaluation. Root tests replace every package of the root fixture
hubs with checked-in archives and need no network: real runs, and analysis tests as well, because
an analysis test that loads an instance target fetches that package's repository, and a fixture
lockfile records full URLs with the loopback port of the run that wrote it, which no root build
can reach; the fetch path itself (URL construction,
integrity, credentials, mirrors, laziness) is covered by the Bazel-in-Bazel tests with a loopback
registry (FR-025) and by `e2e/smoke` against the public registry. `--downloader_config` stays as the
consumer's mirror mechanism (FR-019, US7-5), tested in Bazel-in-Bazel with a rewrite from one
loopback host to another, which the documented syntax covers.

### G4 (decided, spec Revision 4): bun.com and Bun 1.4.2 disagree on an empty `trustedDependencies`

bun.com (`pm/lifecycle`) says: "The lockfile records the list, even if it's empty." Observed: Bun
1.4.2 writes no `trustedDependencies` key for `"trustedDependencies": []` (Part 5, E5), and writes
the list when it is not empty (E6). So the lockfile cannot tell absent from empty with the pinned Bun.

**Decision**: the ruleset treats an absent and an empty list alike and reads neither: no lifecycle
script runs in any mode (FR-023), so telling them apart would change nothing the ruleset does. The
earlier proposal to tell them apart from the root `package.json` and export the result as
`TRUSTED_DEPENDENCIES` from the hub is dropped, because it would add a public name (constitution I,
VII) that no behavior needs. The documentation states the bun.com/Bun 1.4.2 difference and how
consumers find the packages whose scripts do not run (R12). Canary C-TD fails when Bun
starts writing the empty list, so the documentation can be revisited.

### G5 (decided, plan fix L; replaces the prefilled-cache decision): Bazel-in-Bazel inner builds without external network

bazel.build documents: a registry may be "a local directory" used "by `--registry=file://<registry_path>`"
(`external/registry`); `source.json` gives each module's archive URL and integrity;
`--override_module` "Override a module with a local path"; `--downloader_config` lines "rewrite"
with "two patterns, one to match against, and one to use as a substitute URL"; `--repository_cache`;
and the `block-network` tag ("blocks access to the external network from inside the sandbox. In
this case, only communication with localhost is allowed"), which `--modify_execution_info`
("Add or remove keys from an action's execution info based on action mnemonic ... e.g. ...
TestRunner") can add to test actions.

**Decision**: each inner build gets its own empty `--repository_cache` and `--output_user_root`
under `TEST_TMPDIR`, as SC-005 requires, and no prefilled cache:

- Modules: `--registry=file://<dir>`, a local registry the test writes from checked-in fixtures
  under `bun/tests/integration/registry/` (copies of the BCR's `MODULE.bazel`, `metadata.json` and
  `source.json` files for exactly the module versions the inner module graph resolves, Bazel's
  built-in dependencies included, with each `source.json` URL pointing at the loopback server and
  the BCR's integrity kept); rules_bun itself comes from `--override_module=rules_bun=<dir>`, a
  directory the test assembles from a test-only `filegroup` of the ruleset's files.
- Archives: the loopback registry (R15) serves the npm fixture archives, the module source archives
  and the Bun release archive of the host platform. The outer build fetches the module and Bun
  archives as dev-only `http_file` repositories with the BCR's and `versions.bzl`'s integrity
  (`use_repo_rule`, documented; each call `dev_dependency = True`, which per bazel.build denotes "that
  a certain repo is only to be created when the current module is the root module"), declared
  directly in `MODULE.bazel`. Not through `include()`: "Only the root module and modules subject to
  a non-registry override may use `include()`", and consumers get rules_bun from a registry; every other URL the inner build requests (the Bun release URL, any
  module's own downloads) is rewritten to the loopback server by a `--downloader_config` the test
  writes, and the server answers an unknown path with 404 and logs it, so the test fails naming
  the URL.
- Network: on Linux, `.bazelrc` adds `block-network` to every `TestRunner` action
  (`test:linux --modify_execution_info=TestRunner=+block-network`, with
  `--enable_platform_specific_config`), so the linux-sandbox lets the outer test and the inner
  Bazel reach only loopback; root tests need nothing else (FR-026). On macOS and Windows the
  offline proof is the loopback server's request log (every request it saw, and no request that
  bypassed it, because nothing else is configured and the inner repository cache starts empty).

A maintenance script (pinned Bun, network, run by hand) regenerates the registry fixtures and the
`http_file` list from the inner module graph. Step 2 of the plan proves this first; if an inner
build cannot finish without external network, FR-004 applies and the gap goes to the user.

Implementation record (T010–T013, 2026-10-21, Linux WSL2, Bazel 9.2.0):

- Rewrite target: the inner `--downloader_config` holds one line,
  `rewrite ((?!127\.0\.0\.1[:/]).*) http://127.0.0.1:<port>/$1`. The flag's reference text calls
  the second pattern "a substitute URL"; Bazel 9.2.0 keeps a scheme the substitute names
  (`UrlRewriter.prefixWithProtocol`, which adds the original scheme only to a substitute without
  `http://` or `https://`), so an `https` download reaches the plain-HTTP loopback server. Loopback
  URLs (the npm registry of a test) are left alone by the lookahead.
- Inner workspaces are files of `//bun/tests/integration` (`glob(["workspaces/**"])`), not packages
  of the root module: `.bazelrc` lists each inner package in `--deleted_packages`, as
  bazel-contrib/rules_bazel_integration_test arranges child workspaces. Text files of an inner
  workspace get `{REGISTRY}` (the loopback URL) and other `{NAME}` placeholders replaced when the
  harness copies it.
- `bun/tests/integration/registry/update.ts` learns the downloads by running the pinned Bazel on the
  probe workspaces against the BCR with every download rewritten to a logging proxy: `bazel test
  //...` on the host, then, for each of the five platforms, `bazel build --nobuild` of a
  `bun_binary` with that platform as target and execution platform, so each platform's launcher
  stubs, coreutils and Bun archive are fetched (a test rule cannot be analyzed for a foreign
  execution platform: its implicit dependencies need a C++ toolchain there). First run: 164
  `MODULE.bazel`, 30 `metadata.json`, 30 `source.json`, 10 patches; 41 `http_file` repositories
  (5 Bazel binaries, 36 served downloads: 18 module source archives, 5 Bun archives, 10 hermetic-launcher
  stubs, 5 coreutils archives, bats-core).
- Inner flags needed: none beyond the harness's own (`--output_user_root` under `TEST_TMPDIR`,
  `--nosystem_rc`, `--nohome_rc`; `--registry=file://…`, `--override_module=rules_bun=…`,
  `--repository_cache=…`, `--downloader_config=…`). The inner build's own test ran in the
  linux-sandbox nested in the outer test's linux-sandbox with `block-network`; the harness test
  passed with 20 loopback requests and no unknown path.

### G6: `libc` is not in `bun.lock` (decided)

npm documents `libc` (`package.json`, "This field only applies if os is linux"). Observed (E1): a
package with `"libc": ["glibc"]` gets `{ "os": "linux", "cpu": "x64" }` in `bun.lock`, no `libc`.
The spec's edge case already says all `libc` variants for an OS and CPU are included; that is the
only behavior the lockfile allows. Documented.

### G7: supported lockfile versions (decided)

Bun 1.4.2 (`src/install/lockfile/bun.lock.rs` at tag `bun-v1.4.2`) defines `lockfileVersion` 0–3 and
writes 1, 2 or 3: 3 when `overrides` holds scoped rules, 1 when an off-registry npm tarball lacks a
supported integrity, a loaded 1 or 2 is kept, and 0 is never written (it is floored to 1). Observed:
2 for a plain install (E1), 3 with `"overrides": {"a>b": "2.0.0"}` (E6). The reader accepts 1, 2 and
3, each pinned by a fixture the pinned Bun wrote (version 1: a version-2 fixture whose stamp is
edited to 1 and re-saved by Bun 1.4.2, which keeps it), and rejects 0 and anything else with the
FR-007 error. Version 1 gets its own canary (C-VER1, Part 3, plan fix M): Bun 1.4.2 keeps
`lockfileVersion: 1` on a re-save and writes the entry shapes the reader reads (L9–L16).

### G8: SC-010 bounds (decided; measured and re-recorded at implementation)

The plan sets these numeric bounds for the 2,000-package fixture on Linux CI; the measurement task
records the observed values here and a bound is changed only by a plan amendment:

- Extension evaluation (`bazel mod deps` wall time minus the same command with the extension tag
  removed): at most 10 s.
- Actions per target: exactly `P + E + L + A`, where P is the package instances the target
  carries (one copy each), E their dependency edges (one link each), L the target's direct links,
  and A the feature-002 actions of the target with no packages; an analysis test asserts the
  equality on a small fixture and the CI check asserts the 2,000-package count.
- Launcher start (plan fix M): from the first statement of `launcher.js` to the program's first
  line, on one clock, `Date.now()`. When the private environment variable
  `RULES_BUN_LAUNCH_TIMESTAMP` names a file, the launcher's first statement writes `Date.now()`
  into it; the scale test's program reads the file in its first line and reports the difference.
  The variable is test-only and not public API. Bound: at most 2 s more than the same target
  without packages.

Also recorded by the measurement task (plan fix M): the per-target copy cost for the 2,000-package
fixture (wall time and bytes written by the store copies, with `hardlink = "auto"`, R5), and the
largest tested package set under the guard's pattern limit.

Windows path length (plan fix M): Windows limits paths to `MAX_PATH` (260 characters) for programs
that do not opt into long paths (Microsoft, "Maximum Path Length Limitation"), and bazel.build
(`configure/windows`, "Avoid long path issues") recommends a short `--output_user_root`. The
longest store path a target creates is
`<output base>/execroot/_main/bazel-out/<config>/bin/<package>/<name>.bun/.store/<store name>/node_modules/<package>/<deepest file>`;
a test computes the longest such path among the fixtures, records it here, and Windows CI runs the
fixture that produces it. The documentation names the limit and the `--output_user_root` advice.

**Measured (T111, T112; Linux WSL2, Bazel 9.2.0, Bun 1.4.2, local run; Linux CI values come with
POST-1 and are not recorded yet).** The fixture (`bun/tests/npm/scale/`, T110) has P = 2,000
packages, E = 5,662 dependency edges, and a target with L = 100 direct links. Every bound held, so
no plan amendment is needed:

| Quantity | Measured | Bound |
|---|---|---|
| Extension evaluation (`bazel mod deps` on a fresh server, median of 3 with the tag minus median of 3 without) | 888 ms (2,323 − 1,435) | ≤ 10 s |
| Actions of the target | 7,769 = 2,000 + 5,662 + 100 + 7 (A = 7) | exactly `P + E + L + A` |
| Launcher start, median of 5 (target with packages; the same program without) | 84 ms; 7 ms; overhead 77 ms | ≤ 2 s more |
| Per-target copy cost (`bazel build` of the target after analysis; bytes of the store's regular files) | 3,320 ms; 432,086 bytes, of which 0 not hardlinked | recorded only |
| Largest tested package set under the guard's pattern limit | 2,000 packages, pattern 97,606 characters (limit 1,048,576, research R13) | recorded only |
| Longest store path among the fixtures (T060, `path_length_test`) | 398 characters on Linux, the output-base-relative part 336; Windows estimate about 382 under `C:/bazel root` (computed, not run); Windows local run (T141, `C:\Users\revil\rbwin\o5`): 369, loads with `LongPathsEnabled` (G11) | recorded; Windows CI (POST-1) |

### G9 (decided, plan fix C, spec Revision 5): a source-tree `node_modules` stays reachable; the guard decides

A reviewer verified that a consumer's source-tree `node_modules` is reachable from a target's copy
tree through the `execroot/_main` symlinks to the workspace's top-level entries, even when
`ignore_directories` in `REPO.bazel` covers it. Node's lookup walks every parent directory (R5), so
Bun's resolver can find a package there that the target does not declare.

**Decision**: the load guard rejects every module outside the target's declared set (R6), so a
phantom import (US1-7), an absent optional peer (US5-2) or a platform package the target does not
carry (US4-6) cannot load: the import fails with Bun's module-not-found error when no copy of the
package is reachable, and with the guard's English error when one is (a source-tree
`node_modules`, or another ruleset's outputs). Spec Revision 5 restates US1-7, US4-6, US5-2 and
FR-003's "MUST NOT see" as "cannot load". The resolver's reads of `package.json` files outside the
set are not `onLoad` loads, so the guard does not see them (feature 002's documented limit); this is
documented as a limitation. `ignore_directories` stays recommended (it keeps Bazel from reading the
directory as packages). Tests: the phantom and optional-peer cases run once with no source
`node_modules` (module-not-found) and once with an unignored and an ignored one holding the package
(guard error).

### G10 (decided, plan fix E, spec Revision 5): integration tests run on `bun_test`, not rules_bazel_integration_test

rules_bazel_integration_test v0.37.1 generates its tests on `sh_test`, which constitution VI forbids
for this repository's own tests (purpose-made bazel-skylib rules or the ruleset's own rules only).
Its `bazel_binaries` extension is no substitute: its `bazel_binary` repository rule writes an
`sh_binary` wrapper (`bazel.sh`) that runs Bazelisk at test time, and it downloads Bazelisk with
`repository_ctx.download` without a checksum (`bazel_binaries.bzl`, `_download_bazelisk_binary`), so
the Bazel binary arrives over the network at test time, unverified (constitution III).

**Decision**: the integration harness is the ruleset's own `bun_test`. Each integration test is a
`bun_test` whose TypeScript runner spawns the Bazel 9.2.0 binary of the platform it runs on,
fetched by a dev-only `http_file` per platform (`https://github.com/bazelbuild/bazel/releases/download/9.2.0/bazel-9.2.0-<os>-<arch>[.exe]`,
integrity from the release's `.sha256` file) and chosen by `select()` on `@platforms`; G5 gives the
inner builds their modules and archives. The rules_bazel_integration_test dev dependency is
dropped. The tests are not tagged `manual`: `bazel test //...` runs them, and the explicit
`test_suite` `//bun/tests/integration:integration_tests` runs them alone (quickstart, CI).

### G11 (decided 2026-10-25 by the implementer: option (a) plus the guard fix): Windows store paths exceed `MAX_PATH`

**Observed** on Windows (local run through WSL interop: `C:\Users\revil\rbwin\tools\bazelisk.exe`
with `USE_BAZEL_VERSION=9.2.0`, the working tree copied to `C:\Users\revil\rbwin\rb`,
`--output_user_root=C:\Users\revil\rbwin\o5`; `LongPathsEnabled` is 1 on this machine):

1. `bazel test //bun/tests/npm/fixtures/basic:path_length_test` fails: "longest store path (369
   characters): C:\Users\revil\rbwin\o5\oelucidu\execroot\_main\bazel-out\x64_windows-fastbuild\bin\bun\tests\npm\fixtures\basic\path_length_test.bun\.store\deep@1.0.0\node_modules\deep\lib\level0_directory_name\…\leaf_module_file.js",
   "Expected: < 260, Received: 369". Bazel created the tree and Bun listed it. The part after the
   output base is 336 characters (T060's estimate), so no `--output_user_root` brings it below 260:
   CI's `C:/bazel root` gives about 360. T060's assertion cannot hold on Windows CI (POST-1) either.
2. A diagnostic case added to the Windows copy only (`require("deep")`, not committed) failed
   with the load guard's error: "…\path_length_test.bun\.store\deep@1.0.0\node_modules\deep\index.js
   is not declared by this target". Bazel prints this output root as `C:/users/revil/rbwin/o5/…`
   (lower case) while the file system path is `C:\Users\…`; the guard's comparison may be
   case-sensitive on a case-insensitive file system. Not diagnosed further: whether CI's
   all-lower-case `C:/bazel root` avoids it is unknown.

**Decision needed** (no supported way chosen; constitution V): either (a) rely on Windows long-path
support and replace T060's `< 260` assertion with a load of the deepest module, stating the
`LongPathsEnabled` requirement in the documentation; (b) shorten the store layout so the longest
path of the tested fixture stays below 260 characters; or (c) document Windows paths over 260
characters as unsupported and narrow the fixture. Item 2 needs its own task (test first on
Windows) whichever is chosen. T141 stops here; its C-WINNAME part is done (tdd-log T141).

**Decision**: (a). Windows long paths are documented by Microsoft (`LongPathsEnabled`,
https://learn.microsoft.com/windows/win32/fileio/maximum-file-path-limitation) and Bazel and Bun use
long-path APIs; T060's `< 260` assertion is replaced, on Windows, by loading the deepest fixture
module through the target, run on the local Windows Bazel through WSL and on Windows CI. If it fails
without `LongPathsEnabled`, the requirement is documented, not worked around. Item 2 is a defect of
the load guard: on Windows the guard MUST compare paths case-insensitively (Windows file names are
case-insensitive, https://learn.microsoft.com/windows/win32/fileio/naming-a-file), test-first on
Windows with the `require("deep")` case as the red.

**Implemented (T141, T142; Windows, local run through WSL interop, `LongPathsEnabled` = 1, no
`--windows_enable_symlinks`)**: `path_length_test` keeps printing the longest store path and now
loads `deep`, whose `index.js` requires the file at that path; on Windows it failed with the load
guard's error (the test file's copy resolved to `C:\users\…`, the module Bun loaded to
`C:\Users\…`), and passes once the guard's filter is case-insensitive on Windows (`launcher.js`,
regular-expression flag `i`). The same defect rejected declared entry points and test files: with
the fix reverted, 22 of 24 `//bun/tests/npm/fixtures/...` tests failed on Windows with the guard's
error. Without `LongPathsEnabled` nothing was run (changing it needs administrator rights);
`_FILES_DOC` states the requirement.

### Decisions during implementation (2026-10-21, implementer)

- **T055 / G9 corrected**: observed on Linux (WSL2, Bazel 9.2.0, default and local strategy): a
  source-tree `node_modules` covered by `ignore_directories(["**/node_modules"])` is not reachable
  through the execution root, and an import of it fails with Bun's module-not-found error; when it
  is not ignored, the load guard rejects the import. The spec and T055 expect exactly that; either
  way the package cannot be loaded.
- **Stale links (R6)**: Bazel never deletes outputs a newer build no longer declares, so after a
  lockfile or `deps` change an old `node_modules` link can remain and point into a package the
  target still carries. The launcher compares every entry of every `node_modules` directory in the
  target's copy tree with the declared link set before Bun starts, and fails with an English error
  naming the extra entry and telling the user to run `bazel clean` (fail closed). A test reproduces
  the stale link with T051's mutation and expects that error.

## Part 2: Decisions

### R1: Lockfile format and reading

**Decision**: The extension reads `bun.lock` with `module_ctx.read`, strips comments and trailing
commas outside strings (FR-007), and decodes it with `json.decode`. It reads exactly the accesses
listed in Part 3, each pinned by a canary.

**Rationale**: bun.com documents `bun.lock` only as the text lockfile (`pm/lockfile`) and links the
blog post for the format. The blog post says the file is JSONC and shows one example with
`lockfileVersion`, `workspaces` (key `""` with `dependencies`) and `packages` (a map from a name to an
array). It names no other field and defines no entry shape. Every other access is the FR-001 case
the user approved on 2026-10-18 (Part 4).

Observed shapes (E1–E6), Bun 1.4.2:

- Top level: `lockfileVersion`, `configVersion`, `workspaces`, `trustedDependencies` (non-empty
  only), `overrides`, `catalog`/`catalogs`, `patchedDependencies`, `packages`.
- `workspaces`: key `""` for the root, else the member's path relative to the lockfile
  (`"packages/w1"`); value holds `name`, `version`, and `dependencies`, `devDependencies`,
  `optionalDependencies`, `peerDependencies` exactly as the member's `package.json` writes them
  (`"q": "catalog:"`, `"w2": "workspace:*"`, `"aliased": "npm:b@2.0.0"`).
- `packages` keys are paths in Bun's hoisted tree: `"b"` (root), `"c/b"` (b as resolved under c),
  `"w1/q"` (q as resolved in workspace w1, keyed by its package name).
- npm entry: `[ "<name>@<version>", "<url>", { <info> }, "<integrity>" ]`. `<url>` is `""` when the
  tarball URL is under `https://registry.npmjs.org/` (Bun source: "only write the registry if it's
  not the default"), else the full URL.
- Alias: key is the alias (`"aliased"`), first slot names the real package (`"b@2.0.0"`).
- Workspace member entry: `[ "<name>@workspace:<path>" ]`.
- `file:` entry: `[ "<name>@file:<path>", { } ]`; tarball-URL entry:
  `[ "<name>@<url>", { }, "<integrity>" ]`; `git+`/`github:` entries (from Bun source, not
  observed): `[ "<name>@<git+|github:...>", ..., { }, "<tag>" ]`.
- `<info>`: `dependencies`, `optionalDependencies`, `peerDependencies`, `optionalPeers` (array of
  names), `bin` (a string or an object), `binDir` (from `directories.bin`), `os`, `cpu` (a string
  when one value).

**Alternatives**: reading Bun's binary `bun.lockb` (undocumented, binary; rejected by the spec);
running `bun install --lockfile-only` in a repository rule (a host or toolchain tool in a repository
rule; constitution III).

### R2: Dependency and peer resolution

**Decision**: The extension computes package instances statically, as pnpm does in its snapshot keys
and rules_js consumes them:

1. A dependency `D` of the entry at key `K` resolves to the first of `K/D`, `parent(K)/D`, …, `D`
   that exists in `packages` (the hoisted-tree walk the keys encode; observed E1: `c` → `c/b` =
   b@2.0.0, `a` → `b` = b@1.0.0). For workspace `W` named `N`, the walk starts at `N/D`
   (observed: `w1/q` = q@2.0.0). Keys are split into package-name segments, scope-aware (plan fix
   H): a segment starting with `@` takes the next `/`-separated part with it, so
   `@s/a/@s/b` is `[@s/a, @s/b]` and `parent` drops the last segment, never splitting a scoped name.
2. A peer `P` of a package reached from dependent `X` resolves to the instance `X` provides: one of
   `X`'s own dependencies or resolved peers named `P`. If `X` provides none and `P` is in
   `optionalPeers`, it is absent. Otherwise it resolves in the dependent's workspace context (plan
   fix F, FR-017): by the walk of step 1 from the starting key of the workspace whose link the
   instance is reached from (`N/P`, then `P`), not from the package's own key; if the walk finds
   nothing, the instance fails at analysis naming the package and the peer. Peer cycles terminate:
   a peer whose resolution is already in progress on the current dependent chain (a back-edge) is
   treated as resolved to that in-progress instance.
3. Instance identity (plan fix F): `name@version` plus the instance's edge map, its resolved
   ordinary dependencies and peers. An ordinary edge is recorded by the lockfile key it resolves to
   (finite, no recursion), a peer edge by the peer's identity, and a back-edge by its lockfile key.
   Two entries of one `name@version` whose edges resolve differently (for example `x` and `y/x`
   whose dependencies the walk resolves to different keys) are distinct instances. The instance ID
   (a hub target name, not public) is `name@version__<h>`, `<h>` the Starlark `hash()` of the
   sorted, encoded edge map ("computed deterministically using the same algorithm as Java's
   String.hashCode()"); when two different edge maps of one `name@version` hash alike, `__<n>` in
   sorted order of their encodings separates them. One target still holds one instance per
   `name@version` (FR-003): two distinct instances of one `name@version` in a target fail analysis
   naming the package, the differing dependency or peer and both versions (US5-4).

**Rationale**: npm documents that "As of npm v7, peerDependencies are installed by default" and that
`peerDependenciesMeta` marks a peer optional and npm "will not automatically install optional peer
dependencies". bun.com documents the same ("`bun install` installs peer dependencies by default,
unless they are marked optional in `peerDependenciesMeta`"). Observed (E1): Bun installs `p@1.0.0`
twice, once per peer resolution (`p@1.0.0+532dfa3fa31723bc` linking q@2.0.0 in w1,
`p@1.0.0+bd89d05a9c91edde` linking q@1.0.0 at the root), while `bun.lock` holds one `p` entry, so
the lockfile does not record peer resolution and the ruleset must resolve it (spec Revision 2).
bun.com (`pm/isolated-installs`) documents that a store directory name ends in a hash of its peers;
the ruleset does not reproduce the hash (FR-017).

**Alternatives**: one instance per version regardless of peers (breaks US5-3 and React's single
instance across workspaces); reproducing Bun's store hash (undocumented).

### R3: Repositories

**Decision**: One hub repository per `npm.translate_lock` tag, named by `name` (default `npm`), and
one package repository per `name@version`, named `<hub>__<name>__<version>` with every character
outside `[A-Za-z0-9.-]` replaced by `_` and a `__<n>` suffix in sorted order when two packages map to
one name (package repository names are not public API). Two entries of one `name@version` that
record different URLs or integrities fail evaluation with an English error naming both keys and
both values (plan fix M). A package repository fetches and extracts the archive (R4); it reads no
`package.json`: `bin`, `os`, `cpu` and dependencies come from the lockfile.

The extension declares `os_dependent = False`, `arch_dependent = False` and returns
`module_ctx.extension_metadata(reproducible = True)` ("States that this module extension ensures
complete reproducibility, thereby it should not be stored in the lockfile"), so `MODULE.bazel.lock`
holds no entry for it (FR-008). Its inputs are the files it reads, which `module_ctx.read` and
`path.readdir(watch = "auto")` watch.

Credentials: the package repository computes `auth` with `read_user_netrc` and `use_netrc` from
`@bazel_tools//tools/build_defs/repo:utils.bzl` (documented: `read_user_netrc` reads the file named
by `NETRC`, else `.netrc` in `$HOME` or `%USERPROFILE%`; the generated reference page writes the
label as `@bazel//tools/...`, the user-guide pages load the same files as `@bazel_tools//tools/...`,
which is the form rules_bun uses). `--credential_helper` needs nothing from
the rule: it "Configures a credential helper ... to use for retrieving authorization credentials for
repository fetching". Nothing credential-related is an attribute or written to a file (FR-020).

**Rationale**: rules_js v3.5.1 (`npm/private/npm_import.bzl`) creates one `npm_import` per package
and downloads `package.tgz` with the lockfile's integrity and `canonical_id = download_url`. Bazel's
downloader fetches a repository only when a requested target needs it, which gives lazy fetching
(US2-3, SC-005).

**Alternatives**: one repository per lockfile entry, duplicating identical archives (`aliased` and
`c/b` both name b@2.0.0 in E1); a single repository with all packages (not lazy).

### R4: Extraction (plan fix B; replaces the bsdtar build action)

**Decision**: The package repository extracts the archive with Bazel's own documented API, and one
build action per package and configuration turns the extracted files into the instance tree:

1. Fetch and extract: `repository_ctx.download_and_extract(url, output = "package", integrity = ...,
   canonical_id = url, auth = ..., type = "tgz", strip_components = 1)`; a replaced package (G3)
   uses `repository_ctx.extract(<replacement label>, output = "package", type = "tgz",
   strip_components = 1)` instead. `strip_components = 1` drops the single top-level directory
   whatever its name (FR-034).
2. Make every file addressable: the rule walks `package/` with `path.readdir` and renames, with
   `repository_ctx.rename` ("Fails if the destination path already exists"), every file named
   `BUILD` or `BUILD.bazel` and every file or directory whose name holds a character outside
   Bazel's target-name set (`concepts/labels`) to a generated safe name; it records each rename.
   Without this, an archive's `BUILD` file would make its directory a subpackage, and `glob` "matches
   every file in every non-subpackage subdirectory" only (`be/functions#glob`), losing files
   (FR-035).
3. The repository's generated `BUILD.bazel` passes `glob(["package/**"], exclude = <FR-033
   patterns under package/>)` (hidden files included: "A hidden file with filename starting with .
   is completely matched by both the ** and the * wildcards") to a private rule that runs bazel-lib's
   public `copy_to_directory_bin_action` once per configuration into a tree artifact, with
   `replace_prefixes` mapping each recorded safe path back to its original path ("If the output
   directory path for a file starts with or fully matches a key in the dict then the matching
   portion ... is replaced"), so the instance tree holds the archive's files under their own names.
4. Each target copies that tree into its store with `copy_directory_bin_action` (R5).

FR-033's patterns are Bazel `glob` exclude patterns relative to the package root, documented as
such. Empty directories are not carried (glob matches files only, `exclude_directories = 1`);
documented. Symbolic links in an archive: extraction creates them; whether the glob and the copy
keep them is unverified until a fixture covers it; documented as unverified.

**Rationale**: `download_and_extract`, `extract` (`strip_components`, `rename_files`), `rename`,
`delete` and `path.readdir` are documented in `repository_ctx` 9.2.0; `copy_to_directory_bin_action`
and `copy_directory_bin_action` are public in bazel-lib 3.0.0 (`lib/copy_to_directory.bzl`,
`lib/copy_directory.bzl`) and run bazel-lib's registered copy toolchains (constitution III). No tool
runs in a repository rule. bazel-contrib/tar.bzl documents only archive creation, not extraction,
so it is not used. rules_js v3.5.1 also extracts in the repository when it needs the files
(`_download_and_extract_archive`, with `package_src = "package"`), with the comment "npm packages are
always published with one top-level directory inside the tarball, tho the name is not predictable",
but it runs bsdtar from `rctx.execute`, which constitution III forbids here.

**Alternatives**: bsdtar from tar.bzl in a build action (the Revision 4 design; tar.bzl documents no
extraction API, plan fix B). Passing the extracted `package` directory itself as a source directory
(rules_js's `src = ":package"`): bazel.build discourages referencing directories directly ("the
build system does not have full knowledge of all files below the directory"). `rename_files` at
extraction: needs the entry names in advance, which the lockfile does not record. `Bun.Archive`
(bun.com `runtime/archive`): a tool run in a build action, with no documented way to strip the top
directory or keep file modes.

**Dependency**: none new; `tar.bzl` is dropped.

### R5: Layout in the copy tree

**Decision**: In a target's copy tree `<name>.bun/` (feature 002):

- Store: `<name>.bun/.store/<store name>/node_modules/<package>/` is a per-target copy of the
  extracted tree, made with bazel-lib's public `copy_directory_bin_action` (`hardlink = "auto"`,
  which hardlinks generated files). `<store name>` is `<name>@<version>` with `/` written `+`, as
  Bun's store names it (`@scope+s@1.0.0`).
- Edges: for each dependency or resolved peer, a link
  `<name>.bun/.store/<store name>/node_modules/<dep>` made with `ctx.actions.declare_symlink` and
  `ctx.actions.symlink(target_path = "<relative>", target_type = "directory")`.
- Direct links: `<name>.bun/<repo>/<workspace package>/node_modules/<package>` points to the store
  entry, at the rlocation path of the workspace package, so a source copied to
  `<name>.bun/<repo>/<pkg>/x.ts` finds it by walking up.
- Workspace members: `<name>.bun/<repo>/<A>/node_modules/<B>` points to `<name>.bun/<repo>/<B>`,
  where B's target copies its files.

`.store` is not inside any `node_modules`, and no ancestor of `<name>.bun/` that the rule controls
holds one. The `:node_modules/<package>` link targets declare no files, and a `bin` target, whose
label lies under `node_modules/`, declares its copy tree outside it, at
`_npm_bin/<package>/<bin>.bun/` in its package (plan fix M), so no copy tree sits under a
`node_modules` ancestor. A package instance can therefore load only from its own `node_modules`
(FR-003); the walk can still reach directories the rule does not control (a source-tree
`node_modules` through `execroot/_main`, ignored or not, G9, or another ruleset's outputs), and the
load guard rejects every module there.

**Rationale**: Node documents the lookup ("starts at the directory of the current module, and adds
/node_modules ... moves to the parent directory") and the realpath rule ("Because Node.js looks up
the realpath of any modules it loads ... and then looks for their dependencies in node_modules
folders"), with a store-and-symlink layout as its own example. bun.com (`runtime/module-resolution`):
"Bun implements the Node.js module resolution algorithm ... Bun scans up the file system for a
`node_modules` directory containing the package". Canary C1 (feature 002) already pins that Bun
resolves from the real path. bazel.build documents `declare_symlink` ("Bazel will never dereference
this symlink and will transfer it verbatim to sandboxes or remote executors") and
`symlink(target_path = ...)` (a dangling or relative link is allowed). rules_js uses the same
`declare_symlink` + relative `target_path` + `target_type = "directory"` (`npm_package_store.bzl`
line 541–546).

Observed (E7, prototype in Bazel 9.2.0 with Bun 1.4.2): from a file in such a layout, `require("a")`
resolves through the direct link to `.store/a@1/node_modules/a`, `a`'s `require("b")` resolves
through its edge to `.store/b@1/...`, and `a`'s `require("c")`, where `c` sits only in the
workspace's `node_modules`, fails; both from `bazel-bin` and from an `sh_test` in the linux-sandbox
reading the runfiles tree (realpaths land in `bazel-out`).

**Alternatives**: Bun's isolated layout (`node_modules/.bun/`, with hoisted fallback and the root
`node_modules` visible; rejected by spec Revision 2); a store shared by all targets (one instance
per version per target is required, FR-003, and peers differ by target).

### R6: Load guard for package files

**Decision**: The launch configuration gains `directories`: tree paths, relative to the copy-tree
root, of the store entries the target carries. The launcher and the guard compute the copy-tree
root's real path as `copyTreeRoot` already does for tests (now for programs too, from the entry
point) and add each `root + sep + directory + sep` as a prefix branch of the guard's trie (the
branch matches any continuation). Files of the target's own copies keep exact entries. A path under
a store entry is a declared output of that target, because the entry is a tree artifact the target
produced.

**Rationale**: the guard's filter stays a prefix trie (feature 002 R13) and grows with the number of
store entries, not files, keeping 2,000 packages far below the 1,048,576-character limit (canary
C13). Bun loads modules by real path (C1), and package `package.json` reads are resolver reads, not
`onLoad` loads, so they are not guarded (feature 002's documented limit); a `package.json` outside
the declared set (G9) may therefore be read, never loaded as a module, documented.

Stale links (found at T051, 2026-10-21, Linux WSL2, Bazel 9.2.0): Bazel removes no output that a
later build no longer declares. A store-entry edge link or a direct link that an earlier build of
the same target declared therefore stays in `bazel-out` after the lockfile or the target's `deps`
change, and Bun resolves through it from the real path. When it points into a store entry the
target still carries, the guard admits the load (the entry is a declared prefix), so an
incremental build can load what a clean build cannot: T051's mutation (an edge from `phantom-user`
to `b`), once reverted, left `phantom.bun/.store/phantom-user@1.0.0/node_modules/b`, and the
phantom import kept succeeding until the link was removed. A link into an entry the target no
longer carries is rejected by the guard. No documented Bazel mechanism removes orphaned outputs,
and a tree artifact cannot hold the links instead, because they point outside it. Open for a
decision (reported to the user): document it as a limit of the guard, or change the layout or the
launcher (store entries named per instance, which covers edge links only; or a launcher check
that fails a run when a `node_modules` directory of the copy tree holds an undeclared entry).

### R7: Package targets, macro, providers

**Decision**:

- The hub's `defs.bzl` defines `npm_link_all_packages()`. Called in the `BUILD` file of a workspace
  package (the lockfile's directory or a member), it creates `:node_modules/<package>` for each name
  that workspace package declares in `dependencies`, `devDependencies`, `optionalDependencies` or
  `peerDependencies`, and `:node_modules/<package>/bin/<bin>` for each JS/TS `bin` entry of those.
  It fails, in English and listing the valid packages, when called anywhere else.
- A `:node_modules/<package>` target provides `BunLibraryInfo` (empty `srcs` and `data`) whose new
  field `packages` holds one link record, so `deps` of `bun_library`, `bun_binary` and `bun_test`
  accept it unchanged. `bun_library` merges `packages` transitively (FR-014).
- A link record holds the link location (repository and package of the macro call), the link name,
  the root instance, and the instance closure: the instances reachable through dependencies and
  resolved peers, precomputed by the extension, with optional platform-restricted parts behind
  `select()` (R8). Instances live in the hub as leaf targets with no `deps` (each holds its
  extracted tree and its edges as instance IDs), so dependency cycles, which npm allows, never
  become Bazel cycles. rules_js solves cycles the same way (`ref_deps` and a precomputed transitive
  closure, `npm/private/transitive_closure.bzl`).
- `bun_binary` and `bun_test` collect the link records, check that each `name@version` appears as
  exactly one instance (US5-4: English error naming the package, the peer and both versions), and
  create R5's copies and links.
- A workspace member dependency (`workspace:`) links to the consumer's target
  `//<member path>:pkg`; the tag's `workspace_target_name` changes `pkg`, as rules_js's
  `npm_package_target_name` (default `"pkg"`) does. The member target must provide
  `BunLibraryInfo`; its `package.json` belongs in its `data`.

**Rationale**: rules_js documents `npm_link_all_packages()` "in the BUILD file of each package in
the pnpm workspace" and `:node_modules/{package}` targets (`docs/pnpm.md`). bazel.build allows `@`,
`/` and `.` in target names ("a–z, A–Z, 0–9, and the punctuation symbols
!%-@^_"#$&'()*-+,;<=>?[]{|}~/."); a character outside that set in a package or `bin` name is
written `_` in the target name (FR-012 naming rule, tested).

### R8: Platform-specific optional dependencies

**Decision**: An optional dependency edge to a package whose entry has `os` or `cpu` is wrapped in
`select()` over `config_setting`s the hub generates from `@platforms` constraints:

| npm `os` | `@platforms//os:` | npm `cpu` | `@platforms//cpu:` |
|---|---|---|---|
| `linux` | `linux` | `x64` | `x86_64` |
| `darwin` | `macos` | `arm64` | `aarch64` |
| `win32` | `windows` | `ia32` | `x86_32` |
| `freebsd`, `openbsd`, `netbsd`, `android`, `aix` | same name | `arm` | `arm` |
| | | `riscv64`, `s390x` | same name |

A negated value (`!win32`) matches every value except it; a value without a constraint (for example
`sunos`, which `process.platform` can return and `@platforms` 1.1.0 `os/BUILD` does not define)
matches no Bazel platform, so the package is never carried, documented. `aix` has a constraint
(`@platforms//os:aix`, in `os/BUILD`; plan fix M corrects the spec's example). The selection is resolved in the
target's configuration, so a tool built for the execution platform gets that platform's packages
(US3-2). Non-optional dependencies are carried whatever their `os` and `cpu` say, documented.

**Rationale**: npm documents `os` and `cpu` with `!` negation and says the host values are
`process.platform` and `process.arch` (values from Node's `process` documentation). The
`@platforms` 1.1.0 names are the ones in its `os/BUILD` and `cpu/BUILD`; rules_bun's toolchain
already uses `os:linux`, `os:macos`, `os:windows`, `cpu:x86_64`, `cpu:aarch64`. `select()` on
constraint `config_setting`s is the documented configurable-attribute mechanism
(`configure/attributes`).

### R9: Workspaces, globs, catalogs, overrides

**Decision**: The extension reads the root `package.json` next to the lockfile and expands its
`workspaces` (array, or object with `packages`) by Bun's documented glob syntax (`?`, `*`, `**`,
`[...]`, `{a,b}`, `!` negation; bun.com `runtime/glob`), listing directories with
`path.readdir(watch = "auto")` so adding or removing a member re-evaluates the extension (US4-5).
"A negative pattern removes what the globs match, wherever it is in the list ... does not remove a
directory that is listed by its path" (bun.com `pm/workspaces`). A directory is a member when it
holds a `package.json`. The member set must equal the lockfile's `workspaces` keys, and each
member's four dependency maps must equal the lockfile's for it, literally (the lockfile records
`catalog:` and `workspace:` specifiers as written, E1); the root `catalog`/`catalogs` and
`overrides`/`resolutions` must equal the lockfile's `catalog`/`catalogs` and `overrides`. Any
difference fails evaluation in English naming the file, the package and the difference, and telling
the consumer to run `bun install` and commit the lockfile (FR-006).

Overrides before comparing (plan fix G): bun.com (`pm/overrides`) says "When a `package.json` has
both fields, Bun uses only `"overrides"` and does not read `"resolutions"`"; Bun "accepts the npm
object form, the pnpm `>` form, and a parent with a version range", `"resolutions"` "accepts Yarn's
path form" (with `**` "for compatibility"), and "Bun supports only one parent level. It ignores
`a>b>c`, `a/b/c`, and deeper object nesting with a warning." The extension therefore takes
`overrides` when present, else `resolutions`, drops the chains Bun ignores, and normalizes each
rule to the nested object form the lockfile records (observed E6: `"a>b": "2.0.0"` →
`{ "a": { "b": "2.0.0" } }`) before comparing: top-level `"b": v`; npm object form (including the
`"."` key); `a>b`; `a@<range>>b`; `a/b` and `**/a/**/b`. Names in these forms are split
scope-aware (`@s/a>@s/b`, `@s/a/@s/b`), as lockfile keys are (R2). The lockfile shape of each form
is pinned by a fixture the pinned Bun wrote and by C-OVERRIDES; a form no fixture pins fails
evaluation in English naming the form, rather than being compared by guess.

A test runs the pinned Bun against fixture trees (globs, negative globs, `node_modules` directories
with `package.json` inside a matched tree) and checks that the member set the extension computes
equals the `workspaces` keys Bun writes; this pins the glob implementation against Bun's.

### R10: Executables

**Decision**: For a directly declared package, each `bin` entry (a string means one entry named
after the package name without its scope, as npm documents) whose file ends in an extension in
feature 002's `SOURCE_EXTENSIONS` (`.ts .tsx .mts .cts .js .jsx .mjs .cjs`, the ones bun.com
`runtime/module-resolution` lists) becomes `:node_modules/<package>/bin/<bin>`, a target of a
private rule sharing `bun_binary`'s implementation whose entry point is a file inside the package's
store entry; other entries get a target whose analysis fails naming the package, the entry and the
reason. `binDir` (`directories.bin`) is ignored, as rules_js `_get_bin_entries` reads only `bin`
(FR-018, US6-5).

### R11: `.npmrc` and registries

**Decision**: The optional `npmrc` label is read for `registry=` and `@<scope>:registry=` lines only;
lines whose key starts with `//` or names `_auth`, `_authToken`, `_password`, `username`,
`certfile` or `keyfile` are skipped without being stored. An empty URL slot becomes
`{registry}/{name}/-/{basename}-{version}.tgz` (rules_js `_npm_registry_download_url`), with
`{registry}` the scope's registry, else the `.npmrc` default registry, else
`https://registry.npmjs.org`. A full URL is used as recorded.

**Rationale**: npm documents `@myscope:registry` and that credentials "must be scoped to a specific
registry" by a `//host/:` prefix (`configuring-npm/npmrc`); bun.com documents the same keys
(`pm/npmrc`: `registry`, `@<scope>:registry`). Bun's own reader turns `""` into the scope's
registry, else the default, and builds the URL with `ExtractTarball::build_url`
(`bun.lock.rs` at `bun-v1.4.2`); canary C-URL2 pins that Bun 1.4.2 requests
`/{name}/-/{basename}-{version}.tgz` from the configured registry for an empty slot (E4).

### R12: Lifecycle scripts

**Decision**: No script runs, and the ruleset reads no `trustedDependencies` (G4). The documentation
explains that Bun runs scripts for packages named in `trustedDependencies` or, when the field is
absent, on the list `bun pm default-trusted` prints, and that Bazel runs none; that `bun pm
untrusted` lists only the packages with scripts Bun blocked (https://bun.com/docs/pm/cli/pm); and
that Bun 1.4.2 does not record an empty list in `bun.lock`. A real-run test pins that no script
runs: a fixture package whose `postinstall` would write a marker file, named in the root
`package.json`'s `trustedDependencies`, is imported by a `bun_test` that asserts the package loads
and the marker is absent from its store entry.

**Rationale**: bun.com `pm/lifecycle` documents the three modes; rules_js runs lifecycle hooks only
on opt-in. Bun's built-in list is not reproduced (FR-024).

### R13: Unsupported entries

**Decision**: An entry the ruleset does not fetch (`git+`, `github:`, tarball URL, `file:`, `link:`,
a package in `patchedDependencies`, no integrity, or an integrity whose algorithm is not `sha256`,
`sha384` or `sha512`) becomes an instance target whose analysis fails with an English error naming
the package and the reason (FR-010). Targets that do not need it are unaffected.

**Rationale**: `repository_ctx.download` takes "Expected checksum ... in Subresource Integrity
format"; the algorithms Bazel accepts are recorded from its error at implementation (canary-free: an
ordinary unit test of the extension's check against a fixture with `sha1-`).

### R14: Root tests and fixtures

**Decision**: Fixture packages are built from sources in `bun/tests/npm/registry/` by a script that
runs the pinned Bun (`bun pm pack`), and the archives are checked in. Fixture lockfiles are written by
the pinned Bun against a loopback registry serving them (the script in E1), checked in, and
regenerated only by that script. Root tests, real runs and analysis tests alike, consume them
through `npm.replace_package` for every package of the root fixture hubs (G3); Bazel-in-Bazel tests serve them from a loopback registry. React for the root JSX proof comes
from checked-in archives of `react`, `react-dom` and `scheduler` at the versions `e2e/smoke` pins,
verified against the integrity the public npm registry published.

### R15: Bazel-in-Bazel

**Decision**: `bun_test` targets that spawn a pinned Bazel 9.2.0 (G10), with G5's offline setup, in
`bun/tests/integration/`, collected by the `test_suite` `integration_tests`. The loopback registry
for archives, modules, credential, mirror and laziness tests is a Bun module the test runner
starts in-process, never a repository rule; it logs every request, which SC-005 and the macOS and
Windows offline proof read. Credential tests write a `.netrc` into the inner `HOME` and a
credential helper script into the inner workspace, then grep every generated file and
`bazel mod show_repo` output for the secret. US2-7 lists the extension's repositories with
`bazel mod show_extension` and their attributes with `bazel mod show_repo` (plan fix M), and CI
compares the output across the three operating systems.

TDD for behavior Bazel owns (plan fix K): Bazel's downloader verifies integrity (US2-1), fetches
lazily (US2-3), reports download and credential failures (US7-2, US7-3, US7-4, US7-5), and the
rules already isolate a run (FR-022, feature 002); no lifecycle script runs (FR-023) because nothing
runs one. A test of such a behavior cannot be red before implementation for the expected reason, so
it records its red by feature 002's mutation procedure (FR-020 there: a mutation that breaks the
behavior, marked as a mutation and reverted; for example dropping `integrity` from the download,
referencing every package repository from the hub, dropping `auth`, running `postinstall` in the
instance rule), or, where no change of rules_bun can break it (a download error Bazel prints), it is
recorded as a characterization test with the reason. The plan states which per step.

### R16: Network-denied job

**Decision**: A Linux CI job runs `bazel fetch //...`, then `bazel test //... --nosandbox_default_allow_network`
in the root and in `e2e/smoke` (documented: "Allow network access by default for actions; this may
not work with all sandboxing implementations"; it does with linux-sandbox, which CI uses).

### R17: Canaries (FR-024)

**Decision**: One canary per lockfile access in Part 3, under `bun/tests/canary/npm/`. Each canary
starts a loopback registry inside the test, runs the pinned Bun's `bun install` (or
`--lockfile-only`) in a `TEST_TMPDIR` project, and checks the access; on failure it prints
`rules_bun canary <id>: Bun's bun.lock <access> changed: revisit <reader function>; source <URL>`.
Each is run once with its access altered in its fixture to record the red (SC-007).

## Part 3: Lockfile access inventory (FR-024, SC-007)

"Blog" means the blog post describes the access. Every other access has a canary; the inventory is
compared with the reader's code at the analyze gate.

| ID | Access | Described by | Canary |
|---|---|---|---|
| L1 | JSONC syntax (comments, trailing commas) | Blog ("JSONC") | none; unit tests (FR-007) |
| L2 | `lockfileVersion` ∈ {1, 2, 3} | Blog (key only) | C-VER: Bun writes 2 (plain) and 3 (scoped override); C-VER1: Bun keeps 1 on re-save, same entry shapes (G7) |
| L3 | `workspaces[""]` and its `dependencies` | Blog | none |
| L4 | `workspaces[<path>]` keys are member paths relative to the lockfile | — | C-WSKEY |
| L5 | `workspaces[*].name` | — | C-WSNAME |
| L6 | `workspaces[*].devDependencies`, `optionalDependencies`, `peerDependencies` as written | — | C-WSDEPS |
| L7 | `packages` is a map from key to array | Blog | none |
| L8 | key path `parent/child` encodes the hoisted resolution (R2 step 1) | — | C-KEYPATH |
| L9 | slot 0 `<name>@<resolution>` (npm version, `workspace:`, `file:`, `link:`, `git+`, `github:`, URL) | Blog (one `github:` example) | C-SLOT0 |
| L10 | npm entry slot 1: tarball URL, `""` under the default registry | — | C-URL1 (writer: `--lockfile-only`, manifest tarball under `https://registry.npmjs.org/`), C-URL2 (reader: `""` + loopback default registry requests `/{name}/-/{basename}-{version}.tgz`) |
| L11 | npm entry slot 2: info object | — | C-INFO |
| L12 | npm entry slot 3: integrity (SRI) | — | C-INTEGRITY |
| L13 | info `dependencies`, `optionalDependencies` | — | C-INFODEPS |
| L14 | info `peerDependencies`, `optionalPeers` | — | C-PEERS |
| L15 | info `os`, `cpu` (string or array) | — | C-OSCPU |
| L16 | info `bin` (string or object) | — | C-BIN |
| L18 | top-level `overrides` (flat and scoped object form; the form each manifest form is written as, R9) | — | C-OVERRIDES |
| L19 | top-level `catalog`, `catalogs` | — | C-CATALOG |
| L20 | top-level `patchedDependencies` keys | — | C-PATCHED |
| L21 | alias key with a different slot-0 name | — | C-ALIAS |
| L22 | workspace member entry `["<name>@workspace:<path>"]` | — | C-SLOT0 (same canary) |

`configVersion`, `binDir` and `trustedDependencies` are not read; L17 is retired (G4). C-TD is not
an access canary but a behavior canary for FR-023: it pins that Bun 1.4.2 writes no
`trustedDependencies` for an empty list, and its message names the documentation to revisit.
C-WINNAME is a Bazel behavior canary for FR-036 (G2), run on Windows CI: it pins what Bazel 9.2.0's
extractor does with `aux.js` and `a:b.js` and names the documentation to revisit.

## Part 4: Approvals (constitution V)

- **`bun.lock` fields** (FR-001): approved by the user on 2026-10-18 under constitution v2.1.0 V; the
  accesses are L2–L16 and L18–L22, each with the evidence of Part 5 and the canary of Part 3.
- **aspect-build/rules_js** as the reference design (FR-002): named by the user in the feature
  request, recorded as approval on 2026-10-18; it covers the tarball URL pattern (R11), the store
  layout and links (R5), extraction (R4), the linking macro and target names (R7), `bin` handling
  (R10), `exclude_package_contents` (FR-033) and `npm_replace_package` (G3, spec Revision 4; here
  the replacement is an archive checked against the lockfile's integrity, where rules_js takes any
  target in place of the download), including its scope: replacements apply to every lockfile and
  never fail for a package no lockfile lists (plan fix I). Why no bazelbuild or bazel-contrib pattern serves:
  bazel-contrib/rules_nodejs (v6.7.6) says it "provides a Node.js development toolchain and runtime
  ... It does not have any rules for using Node.js ... we recommend rules_js", and no bazelbuild or
  bazel-contrib ruleset reads an npm lockfile.
- **hermeticbuild/hermetic-launcher**: unchanged (2026-10-01; Windows launcher).
- No new dependency: bazel-contrib/tar.bzl (R4) and bazel-contrib/rules_bazel_integration_test
  (G10) are no longer used.
- **Generated hub `defs.bzl`** (plan fix J): constitution v2.2.1 I makes the `.bzl` symbols the
  ruleset's module extensions generate public API, as it does their targets. The macro the hub
  generates, `@<hub>//:defs.bzl` `npm_link_all_packages`, is therefore public under the naming
  rules the extension documents (rules_js documents its generated `npm_link_all_packages` for
  consumers, `docs/pnpm.md`).

## Part 5: Evidence log

Scripts lived in `/tmp/rbexp/scripts`, data in separate directories. `B` is the pinned Bun at
`$(bazel info output_base)/external/+bun+bun_linux-x64/bun`.

- **E1** (workspace install): fixture packages `a`, `b@1`, `b@2`, `c`, `@scope/s` (object `bin`),
  `single-bin` (string `bin`), `dirbin` (`directories.bin`), `p` (peers `q`, optional `r`), `q@1`,
  `q@2`, `r`, `native` with optional `native-{linux-x64,darwin-arm64,win32-x64}` (`os`/`cpu`, one
  with `libc`), `scripted` (`postinstall`); packed with `B pm pack`, served by a loopback registry;
  root `workspaces: {packages: ["packages/*", "!packages/excluded"], catalog: {q: "1.0.0"}}`,
  `overrides: {r: "1.0.0"}`, an `npm:` alias; members `w1` (all four kinds, `workspace:*` on `w2`),
  `w2`, `excluded`. `B install` wrote `lockfileVersion: 2`, `configVersion: 1`; `excluded` absent;
  keys `c/b` and `w1/q`; `p` once with `optionalPeers: ["r"]`; `native-linux-x64` without `libc`;
  `dirbin` with `binDir`; `w1`, `w2` as `["w1@workspace:packages/w1"]`. Store:
  `p@1.0.0+532dfa3fa31723bc` and `p@1.0.0+bd89d05a9c91edde`; `packages/w1/node_modules/p` → the
  first, whose `node_modules/q` → `q@2.0.0`.
- **E2** (URL slot, configured registry): the same install with `BUN_CONFIG_REGISTRY` equal to the
  tarball host still records full URLs.
- **E3** (public registry): `react@19.2.0`, `react-dom@19.2.0`, `@types/react@19.2.2` from
  `registry.npmjs.org` recorded `""` URLs; `react-dom` info
  `{ "dependencies": { "scheduler": "^0.27.0" }, "peerDependencies": { "react": "^19.2.0" } }`.
- **E4** (`""` round trip, loopback only): a manifest naming
  `https://registry.npmjs.org/@scope/s/-/s-1.0.0.tgz`; `B install --lockfile-only` wrote `""` and
  requested only `/@scope/s`; `B install --frozen-lockfile` with the loopback registry as default
  then requested `/@scope/s/-/s-1.0.0.tgz` from it.
- **E5** (`trustedDependencies: []`, `file:` and tarball URL dependencies): no
  `trustedDependencies` key; `"local": ["local@file:local", {}]`;
  `"tb": ["b@http://localhost:48713/b/-/b-1.0.0.tgz", {}, "sha512-..."]`.
- **E6** (`trustedDependencies: ["scripted"]`, `overrides: {"a>b": "2.0.0"}`): `lockfileVersion: 3`,
  `"trustedDependencies": ["scripted"]`, `"overrides": { "a": { "b": "2.0.0" } }`.
- **E7** (layout prototype, Bazel 9.2.0): a rule writing two tree artifacts with the execution Bun,
  a third as a "phantom" in `_main/node_modules/c`, and `declare_symlink` + `symlink(target_path,
  target_type = "directory")` links; `B bazel-bin/L/_main/app/main.js` printed `a+b1+nophantom` with
  real paths under `bazel-out/k8-fastbuild/bin/L/.store/`; the same under `bazel test` in
  linux-sandbox from the runfiles tree.
- **E8** (Windows junctions and the disk cache, 2026-10-20, recorded by the implementer; Windows 11,
  Bazel 9.2.0, driven from WSL through interop): a `declare_symlink` output made by
  `ctx.actions.symlink(target_path = <relative>)` is a junction whose target is absolute under the
  output base; the symlink action is internal, recreated per output base and never restored from a
  cache; a downstream action consuming the junction got a disk cache hit from a build in a
  different output base and a different workspace path (G1). Windows CI repeats the check.

## Part 6: Sources

Bun (bun.com, Bun 1.4.3 docs as served; behavior checked against 1.4.2 where observed):

- https://bun.com/docs/pm/lockfile — text lockfile; links the blog post for the format
- https://bun.com/blog/bun-lock-text-lockfile — JSONC; example with `lockfileVersion`, `workspaces`, `packages`
- https://bun.com/docs/pm/isolated-installs — store layout, peer hash in store names
- https://bun.com/docs/pm/cli/pm — `bun pm untrusted` (blocked packages only), `bun pm default-trusted` (read 2026-10-20)
- https://bun.com/docs/pm/lifecycle — `trustedDependencies` modes; "The lockfile records the list, even if it's empty"
- https://bun.com/docs/pm/workspaces — glob support, negative patterns
- https://bun.com/docs/runtime/glob — supported glob patterns
- https://bun.com/docs/pm/catalogs — catalogs
- https://bun.com/docs/pm/overrides — overrides/resolutions: precedence, accepted forms, one parent level (read 2026-10-20)
- https://bun.com/docs/pm/npmrc — `registry`, `@<scope>:registry`, credential keys
- https://bun.com/docs/pm/cli/install — "Bun installs `peerDependencies` by default"
- https://bun.com/docs/guides/install/add-peer — optional peers not installed
- https://bun.com/docs/runtime/module-resolution — Node.js algorithm; extensions; built-in replacements (`undici`, `ws`, ...)
- https://bun.com/docs/runtime/archive — `Bun.Archive` (alternative rejected in R4)
- https://github.com/oven-sh/bun/blob/bun-v1.4.2/src/install/lockfile/bun.lock.rs — versions 0–3, URL slot writer and reader

npm and Node:

- https://docs.npmjs.com/cli/v11/configuring-npm/package-json — `peerDependencies` (npm v7), `peerDependenciesMeta`, `os`, `cpu`, `libc`, `bin`
- https://docs.npmjs.com/cli/v11/configuring-npm/npmrc — scoped registries, credential scoping
- https://nodejs.org/api/modules.html — loading from `node_modules` folders; realpath and the store example
- https://nodejs.org/api/process.html — `process.platform`, `process.arch` values

Microsoft:

- https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation — `MAX_PATH` "defined as 260 characters" (read 2026-10-20)

Bazel 9.2.0:

- https://bazel.build/versions/9.2.0/rules/lib/builtins/actions — `declare_symlink`, `symlink(target_type)`, `declare_directory`
- https://bazel.build/versions/9.2.0/rules/lib/builtins/repository_ctx — `download(integrity, auth, canonical_id)`, `download_and_extract(strip_components)`, `extract(archive, strip_components, rename_files)`, `rename`, `delete` (read 2026-10-20)
- https://bazel.build/versions/9.2.0/reference/be/functions — `glob`: subpackages, hidden files (read 2026-10-20)
- https://bazel.build/versions/9.2.0/reference/be/general — `filegroup`: "Directly referencing directories is discouraged" (read 2026-10-20)
- https://bazel.build/versions/9.2.0/rules/lib/globals/all — `hash()` (read 2026-10-20)
- https://bazel.build/versions/9.2.0/configure/windows — "Avoid long path issues", `--output_user_root` (read 2026-10-20)
- https://bazel.build/external/registry — local registries through `--registry=file://`, `source.json` (read 2026-10-20)
- https://bazel.build/remote/cache-local — cache hits in the status line and execution logs (read 2026-10-20)
- https://github.com/bazelbuild/bazel/blob/9.2.0/src/main/java/com/google/devtools/build/lib/bazel/repository/decompressor/CompressedTarFunction.java — tar extraction with Apache Commons Compress; no Windows renaming (read 2026-10-20)
- https://bazel.build/versions/9.2.0/rules/lib/builtins/module_ctx — `extension_metadata(reproducible)`, `read`, `watch`
- https://bazel.build/versions/9.2.0/rules/lib/builtins/path — `readdir(watch)`
- https://bazel.build/versions/9.2.0/rules/lib/repo/utils — `read_user_netrc`, `use_netrc`
- https://bazel.build/versions/9.2.0/rules/lib/globals/repo — `ignore_directories`
- https://bazel.build/rules/lib/globals/module — `include()`: "Only the root module and modules subject to a non-registry override may use `include()`"; `use_repo_rule` proxy `dev_dependency`; `use_extension(dev_dependency)` (read 2026-10-21)
- https://bazel.build/versions/9.2.0/concepts/labels — target name characters
- https://bazel.build/versions/9.2.0/configure/attributes — `select()`
- https://bazel.build/versions/9.2.0/reference/be/common-definitions — `block-network`, `requires-network`
- https://bazel.build/versions/9.2.0/reference/test-encyclopedia — test environment
- https://bazel.build/versions/9.2.0/run/build — repository cache; `--distdir` deprecated
- https://bazel.build/external/lockfile — registry file hashes and the repository cache
- https://bazel.build/external/faq — `--downloader_config` for mirrors
- https://bazel.build/reference/command-line-reference — `--windows_enable_symlinks`, `--downloader_config` syntax, `--credential_helper`, `--repository_cache`, `--sandbox_default_allow_network`, `--enable_runfiles`; 9.2.0 page (read 2026-10-20): `--override_module`, `--registry`, `--modify_execution_info` (`TestRunner`), `--execution_log_json_file`
- https://github.com/bazelbuild/bazel/blob/9.2.0/src/main/java/com/google/devtools/build/lib/windows/WindowsFileSystem.java — junctions for directory targets
- https://github.com/bazelbuild/bazel/issues/26701 — Windows directory symlinks; fixed by `target_type`

Reference rulesets:

- https://github.com/aspect-build/rules_js/tree/v3.5.1 — `docs/pnpm.md`, `npm/private/npm_import.bzl` (`_download_and_extract_archive`), `npm_package_store.bzl`, `utils.bzl`, `transitive_closure.bzl`, `npm/extensions.bzl` (`npm_replace_package`), `npm/private/npm_translate_lock_helpers.bzl` (replacements applied by match)
- https://github.com/aspect-build/rules_js/issues/1069 — "Caching broken on Windows" (open; read 2026-10-20)
- https://github.com/bazel-contrib/tar.bzl (BCR 0.10.9) — documents archive creation only; not used (R4)
- https://github.com/bazel-contrib/bazel-lib/tree/v3.0.0 — `copy_directory_bin_action(hardlink)`, `copy_to_directory_bin_action(replace_prefixes)`
- https://github.com/bazel-contrib/rules_bazel_integration_test/tree/v0.37.1 — `sh_test`-based tests, `bazel_binaries` through Bazelisk at test time; not used (G10)
- https://github.com/bazelbuild/bazel/releases/tag/9.2.0 — Bazel binaries and `.sha256` files for the integration harness (G10)
- https://github.com/bazelbuild/platforms/blob/1.1.0/os/BUILD — `os` constraint values, including `aix`; no `sunos` (read 2026-10-20)
- https://github.com/bazel-contrib/rules_nodejs (v6.7.6 README) — no npm rules; recommends rules_js
