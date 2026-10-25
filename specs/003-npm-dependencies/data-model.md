# Data Model: npm Dependencies from `bun.lock`

Sources and rationale for every element are in [research.md](research.md) (R- and G-numbers).
Public names are fixed in [contracts/public-api.md](contracts/public-api.md).

## Extension inputs

### Tag `npm.translate_lock` (one per lockfile)

| Field | Type | Rule |
|---|---|---|
| `name` | string, default `npm` | Hub repository name. Two tags, in any modules, with one name fail evaluation naming each module and the name (FR-032). |
| `bun_lock` | label, mandatory | A file named `bun.lock`. A sibling `bun.lockb` without `bun.lock` cannot be passed; a label to `bun.lockb` fails with the FR-007 error. The root `package.json` is the file `package.json` in the same package. |
| `npmrc` | label, optional | Registry and scope keys only (R11). |
| `workspace_target_name` | string, default `pkg` | Target a workspace member's link points to (R7). |
| `exclude_package_contents` | string-list dict | Package name, or `*`, to Bazel `glob` exclude patterns relative to the package root (FR-033, R4). |

### Tag `npm.replace_package` (root module only; G3)

| Field | Type | Rule |
|---|---|---|
| `package` | string | `name@version` as in slot 0 of an npm entry. Applies to every lockfile that lists it, the root module's and those of the modules it depends on (T129); a package no lockfile lists is ignored, as in rules_js (plan fix I). One replaced twice fails evaluation naming it. |
| `replacement` | label | A `.tgz` package archive, extracted by the package repository instead of a download (R4); its digest must equal the lockfile integrity (checked by a build action, English error naming package, archive and both values). A non-root use fails evaluation naming the module. |

## Lockfile model (reader output; accesses L1–L16, L18–L22 only)

- **Lockfile**: `version` (1–3), `workspaces` (path → Workspace), `entries` (key → Entry),
  `overrides` (normalized nested form, R9), `catalogs`, `patched` (set of `name@version`).
- **Workspace**: `path` (`""` for root), `name`, `deps` per kind (`dependencies`,
  `devDependencies`, `optionalDependencies`, `peerDependencies`) as written.
- **Entry**: `key` (hoisted path), `segments` (the key split into package names, scope-aware:
  `@s/a/@s/b` → `[@s/a, @s/b]`, R2), `alias` (last segment), `kind` (`npm`, `workspace`, `file`,
  `link`, `tarball`, `git`, `github`), `name`, `version`, `url` (may be `""`), `integrity`,
  `dependencies`, `optional_dependencies`, `peers`, `optional_peers`, `os`, `cpu`, `bin` (name →
  path). Only an `npm` entry fills `url`, `integrity` and the info fields; of any other entry only
  slot 0 is read (Part 3 lists no other slot), so they stay empty (T125).

Validation: unknown `lockfileVersion` → FR-007 error; JSONC that does not decode → FR-007 error
naming the file; an npm entry with a non-string slot → error naming the key and slot; two entries
of one `name@version` with different URLs or integrities → error naming both keys and both values
(R3).

Manifest overrides (R9): `overrides` if present, else `resolutions`; chains deeper than one parent
dropped as Bun drops them; every accepted form (top-level, npm object with `"."`, `a>b`,
`a@<range>>b`, `a/b`, `**/a/**/b`) normalized to the nested form before comparison; a form no
fixture pins fails evaluation naming it.

## Resolution model (R2)

- **Instance**: `name`, `version`, `edges` (alias → target: an ordinary dependency by the lockfile
  key it resolves to, a peer by the peer instance's identity, a back-edge by its lockfile key);
  `optional_edges` (alias → (target, os, cpu)); `id` = `name@version__<h>`, `<h>` the Starlark
  `hash()` of the sorted, encoded edge map, with `__<n>` added in sorted order when two edge maps
  of one `name@version` hash alike; `store_name` = `name@version` with `/` → `+`; `status` (`ok`, or
  the FR-010/FR-017 failure reason).
- **Link**: workspace package (repository-relative path), alias, root instance id, `closure` (set of
  instance ids reachable through edges, with optional parts keyed by platform condition).
- State: computed once per evaluation; no transitions.

Rules: a peer the dependent provides resolves to that instance; otherwise an optional peer is
absent; otherwise it resolves by the walk from the starting key of the workspace the instance is
reached from (`N/P`, then `P`), and fails (English, package and peer) when the walk finds nothing. A
peer already being resolved on the current dependent chain is a back-edge and counts as resolved.
Two entries of one `name@version` whose edges differ are distinct instances.

## Generated repositories

| Repository | Name | Contents |
|---|---|---|
| Hub | `<name>` | `BUILD.bazel`: one instance target per instance (referencing its package's replacement check), platform `config_setting`s; `defs.bzl`: `npm_link_all_packages`, per-workspace link tables |
| Package | `<name>__<sanitized name>__<sanitized version>[__n]`, one per `name@version` | `package/` (extracted with `strip_components = 1` from the download, or from the replacement archive; `BUILD` files and label-invalid names renamed), `BUILD.bazel` with the instance-tree target over `glob(["package/**"], exclude = ...)` |

No repository attribute holds a credential; package repository attributes are `url`, `integrity`,
`package`, `version`, `exclude` and, for a replaced package, `replacement` only.

## Build-time targets and providers

| Target | Where | Rule | Provides |
|---|---|---|---|
| Instance tree | package repository | private, `copy_to_directory_bin_action` with `replace_prefixes` restoring renamed paths | tree artifact of the package's files |
| Replacement check | package repository of a replaced package (`:check`), one per `name@version` | private, runs the execution Bun with `Bun.CryptoHasher` | a stamp file; fails with the FR-026 error on a mismatch |
| Instance `<id>` | hub | `npm_instance` (private) | `NpmInstanceInfo`: `id`, `store_name`, `tree`, `edges`, `check` (the replacement stamp, if any) |
| Unsupported instance | hub | `npm_unsupported` (private) | analysis fails with the reason (FR-010) |
| `:node_modules/<package>` | consumer's workspace package | `npm_link` (private), created by the macro; declares no files | `BunLibraryInfo` with empty `srcs`/`data` and `packages` = one `NpmLinkInfo` record |
| `:node_modules/<package>/bin/<bin>` | same | private executable rule sharing `bun_binary`'s implementation; copy tree at `_npm_bin/<package>/<bin>.bun/` | `DefaultInfo` executable, `RunEnvironmentInfo` |

- **`BunLibraryInfo.packages`** (new, public): `depset` of link records; `bun_library` merges its
  deps' records (FR-014).
- **`NpmLinkInfo`** (private): `link_dir` (rlocation path of the workspace package), `alias`,
  `root` (instance id), `instances` (`depset` of `NpmInstanceInfo` in the closure, platform
  `select()` already applied), or `workspace_target` for a member link.
- A target that carries an instance with a `check` puts the stamp in its runfiles, so no program or
  test runs before the check passes (G3).

## Per-target copy tree additions (R5)

```text
<name>.bun/
├── .store/<store name>/node_modules/<package>/...       # copy of the instance tree (one action)
├── .store/<store name>/node_modules/<dep alias>          # directory link to another store entry
└── <repo>/<workspace package>/node_modules/<alias>       # direct link to a store entry or to <repo>/<member>
```

No copy tree sits under a `node_modules` ancestor: link targets declare no files, and `bin` targets
place theirs under `_npm_bin/`.

Validation at analysis: each `name@version` maps to one instance id in the target (else the US5-4
error naming package, the differing peer or dependency and both versions).

## Launch configuration additions (R6, G8)

- `directories`: list of store-entry tree paths relative to the copy-tree root.
- `entry_point` for bins: a tree path inside a store entry.
- The launcher computes the copy-tree root's real path for programs as for tests; the guard adds
  `root/<directory>/` prefix branches.
- `launcher.js` writes `Date.now()` into the file named by the private, test-only environment
  variable `RULES_BUN_LAUNCH_TIMESTAMP` as its first statement, when the variable is set.

## Test map

TDD notes (plan fix K): **mutation** = feature 002's mutation-red procedure; **characterization** =
behavior no rules_bun change can break, recorded with the reason.

| Requirement / scenario | Test kind | Location |
|---|---|---|
| FR-007 JSONC, versions, `bun.lockb` | unit; Bazel-in-Bazel for the evaluation error | `bun/tests/npm/`, `bun/tests/integration/` |
| Scope-aware key split (R2) | unit | `bun/tests/npm/` |
| FR-006, US2-6, US4-4, US4-5 | unit (glob, comparison), Bun-comparison test, Bazel-in-Bazel | same |
| FR-006 overrides precedence and normalization (R9) | unit per accepted form, against fixtures the pinned Bun wrote | `bun/tests/npm/` |
| R2, FR-017, US5-2 | unit (resolver: workspace-context fallback, peer cycles, identity from edges), real runs | `bun/tests/npm/` |
| Same `name@version` with different URL or integrity (R3) | Bazel-in-Bazel evaluation error | `bun/tests/integration/` |
| US1-1–US1-7, US5-1, US5-3, US5-4, FR-013, FR-021 | analysis + real runs | `bun/tests/npm/` |
| US1-7, US5-2 with a source `node_modules` (G9) | real runs: none (module-not-found), ignored and unignored holding the package (guard error) | `bun/tests/npm/` |
| US3, FR-016, SC-004 | analysis on 5 platforms, real run per CI OS | `bun/tests/npm/`, CI |
| US4-1–US4-3, US4-6, FR-015 | analysis + real runs | `bun/tests/npm/workspaces/` |
| US6, FR-018 | analysis (naming, copy tree under `_npm_bin/`) + `bazel run` (CI) + `run_binary` test | `bun/tests/npm/bins/` |
| US2-1 | Bazel-in-Bazel; **mutation** (integrity dropped) | `bun/tests/integration/` |
| US2-2, US2-4, US2-5, US7-1, US7-6, US7-7, US9, FR-008, FR-032 | Bazel-in-Bazel with loopback registry | `bun/tests/integration/` |
| US2-3, SC-005 | Bazel-in-Bazel, request log, empty repository cache, a package with a resolved peer and an unprovided optional peer; **mutation** (hub references every package repository; an optional peer resolves in the workspace context) | `bun/tests/integration/` |
| US7-3, US7-4 | Bazel-in-Bazel; **mutation** (`auth` dropped) | `bun/tests/integration/` |
| US7-2, US7-5 | Bazel-in-Bazel; **characterization** (Bazel's downloader) | `bun/tests/integration/` |
| US2-7 | `bazel mod show_extension` (set) and `bazel mod show_repo` (attributes) compared across CI OSes, for `e2e/smoke` and for `reproducible_test`'s inner workspace, whose lockfile lists `os`/`cpu`-restricted packages | CI |
| FR-011, SC-003 | network-denied job | CI |
| FR-033–FR-035 | analysis + real runs (exclusion, non-`package/` top directory, `BUILD` files, a space in a file name) | `bun/tests/npm/archives/` |
| FR-036, G2 | canary C-WINNAME on Windows CI: pins what Bazel's extractor does | `bun/tests/canary/npm/`, CI |
| FR-026 replacement integrity | Bazel-in-Bazel builds: a matching archive for each of `sha256`, `sha384`, `sha512` passes, a wrong archive fails (red first) | `bun/tests/integration/` |
| FR-026 replacement scope (I) | Bazel-in-Bazel: two lockfiles both replaced, a non-root module's lockfile replaced, an unlisted package ignored, non-root use and double replacement fail | `bun/tests/integration/` |
| FR-022 isolation with packages | real runs (no auto-install, no undeclared `bunfig.toml`, no `.env`); **mutation** of feature 002's isolation | `bun/tests/npm/` |
| FR-023 no lifecycle script | real run: trusted fixture package with a `postinstall` marker; marker absent; **mutation** (instance rule runs `postinstall`) | `bun/tests/npm/` |
| FR-023, G4 | canary C-TD (no empty list in `bun.lock`) | `bun/tests/canary/npm/` |
| FR-003, FR-027, G1 | Windows CI package tests with Bazel's defaults and with `--windows_enable_symlinks`; two output bases with one disk cache, store-link consumers are cache hits | CI |
| Windows path length (G8, G11) | test computing the longest fixture store path and loading the module at its end; that fixture runs on Windows CI | `bun/tests/npm/`, CI |
| FR-024, SC-007 | canaries with recorded reds, C-VER1 included | `bun/tests/canary/npm/` |
| FR-037, SC-010 | generated 2,000-package fixture, CI check (launcher start through `RULES_BUN_LAUNCH_TIMESTAMP`) | `bun/tests/npm/scale/`, CI |
| US8 | `e2e/smoke` JSX test, `bazel run`, `git grep` record | `e2e/smoke/` |
| Edge: source `node_modules` ignored / not ignored | real runs (ignored: Bun's module-not-found error; not ignored: guard error naming the file) | `bun/tests/integration/` |
| Edge: hoisted lockfile (`configVersion = 0`) | reader reads it as with 1; phantom import fails as US1-7; **mutation** (reader honoring `configVersion` 0) | `bun/tests/npm/` |
| Edge: `aix` → `@platforms//os:aix` | analysis on an `aix`/`x86_64` platform; **mutation** (`aix` dropped from `_OS`) | `bun/tests/npm/`, `bun/tests/platforms/` |
