# Contract: rules_bun Public API after feature 003

Constitution I (v2.2.0): the public API is `bun/*.bzl`, the two toolchain types, and the targets the
ruleset's module extensions generate under the naming rules documented here. This contract extends
that wording to the macro the extension generates in the hub's `defs.bzl`
(`npm_link_all_packages`), under the same documented naming rules, as generated API (plan fix J;
research Part 4 says what happens if the analysis reads constitution I otherwise). **New** marks
additions; nothing is removed, renamed or changed in behavior. G1–G10 are settled (research
Part 1; spec Revisions 4 and 5). No claim below is made for a platform until a test ran there
(constitution II).

## `@rules_bun//bun:extensions.bzl`

| Symbol | Kind | Contract |
|---|---|---|
| `bun`, `bun_toolchain` | extension, tag class | unchanged |
| `npm` | module extension | **new**; reproducible (`extension_metadata(reproducible = True)`), not OS- or architecture-dependent; no `MODULE.bazel.lock` entry |

### `npm.translate_lock` (**new**)

```starlark
npm = use_extension("@rules_bun//bun:extensions.bzl", "npm")
npm.translate_lock(
    name = "npm",                    # hub repository name; default "npm"
    bun_lock = "//:bun.lock",        # mandatory
    npmrc = "//:.npmrc",             # optional: registry and scope keys only
    workspace_target_name = "pkg",   # optional
    exclude_package_contents = {},   # optional: {"<package>" | "*": ["<glob>", ...]}, Bazel glob patterns relative to the package root, matched against the archive's file names
)
use_repo(npm, "npm")
```

Evaluation fails with an English error naming the file and the remedy when: the label names
`bun.lockb`; `lockfileVersion` is not 1, 2 or 3; the file is not JSONC; a `package.json` (root or
member) and the lockfile differ in dependencies, members, catalogs or overrides ("run `bun install`
and commit `bun.lock`"); two tags in any modules use one `name` (naming each module and the name);
two lockfile entries of one `name@version` record different URLs or integrities (naming both keys
and both values); the root `package.json` uses an override form no fixture pins (naming the form).

Overrides are compared as Bun reads them (bun.com `pm/overrides`): `overrides` when present, else
`resolutions`; the npm object form, the `>` form, a parent with a version range, and the
`resolutions` path forms; chains deeper than one parent are ignored, as Bun ignores them.

### `npm.replace_package` (**new**)

```starlark
npm.replace_package(package = "react@19.2.0", replacement = "//third_party:react-19.2.0.tgz")
```

Root module only, with rules_js's `npm_replace_package` semantics: a non-root use fails evaluation
naming the module; a package replaced twice fails evaluation naming it; a replacement applies to
every lockfile that lists the package, the root module's and those of the modules it depends on
(as rules_js applies it), and one that no lockfile lists is ignored.
The archive replaces the download; a build that needs it fails when the archive's digest differs
from the integrity the lockfile records, with an English error naming the package, the archive and
both values (FR-026), and no program or test that carries the package runs before that check
passes.

## Hub repository `@<name>`

| Symbol | Kind | Contract |
|---|---|---|
| `@<name>//:defs.bzl` `npm_link_all_packages()` | generated macro | **new**, public as generated API (constitution I as extended above); call once in the `BUILD` file of each workspace package (the lockfile's package and each member). Elsewhere it fails, naming the valid packages. |

### Generated targets and naming rules (public, constitution I)

In each workspace package where `npm_link_all_packages()` is called:

| Target | For |
|---|---|
| `:node_modules/<package>` | each package that workspace package declares in `dependencies`, `devDependencies`, `optionalDependencies` or `peerDependencies`; a scoped package keeps its scope: `:node_modules/@scope/name` |
| `:node_modules/<package>/bin/<bin>` | each `bin` entry of such a package; a string `bin` is named after the package name without its scope; for a declared optional package with `os` or `cpu`, compatible only with the platforms it matches |

Naming rule: every character of `<package>` or `<bin>` outside Bazel's target-name set (`a–z A–Z
0–9` and `!%-@^_"#$&'()*-+,;<=>?[]{|}~/.`) is written `_`. Two names that become equal fail
evaluation naming both.

Behavior:

- `:node_modules/<package>` is accepted in `deps` of `bun_library`, `bun_binary` and `bun_test` and
  resolves to the version the lockfile lists for that workspace package. A workspace member
  dependency (`workspace:`) resolves to the consumer's `//<member>:<workspace_target_name>` target,
  which must provide `BunLibraryInfo` and should carry the member's `package.json` in `data`.
- An optional dependency restricted by `os`/`cpu` is carried only on target platforms that match
  (`select()` on `@platforms`); values with no `@platforms` constraint (for example `sunos`) match
  nothing; `aix` maps to `@platforms//os:aix`; `libc` is not
  in `bun.lock`, so every `libc` variant is carried; non-optional dependencies are carried whatever
  their `os`/`cpu` say.
- A `bin` target runs its file with the Bun of the platform it is built for, under `bazel run` or as
  a build action's tool. Its files live under `_npm_bin/` in the workspace package, not under
  `node_modules/` (that path is not public API). A `bin` file without a `.ts .tsx .mts .cts .js .jsx .mjs .cjs` extension
  gives a target whose analysis fails naming the package, the entry and the reason. Executables
  declared only through `directories.bin` get no target.
- An entry the ruleset does not fetch (`git`, `github:`, tarball URL, `file:`, `link:`, patched, no
  integrity, an integrity algorithm other than `sha256`, `sha384`, `sha512`) fails analysis of a
  target that needs it, naming the package and the reason; other targets are unaffected. A link
  that reaches one on any platform (also only through its platform `select`) is `manual`.
- A target depending on packages of several hubs carries one instance per package version:
  instances from different lockfiles whose dependencies resolve to the same versions are carried
  once; any other two fail analysis naming the dependency whose versions differ (FR-017).

Repositories named `<name>__...` and targets of the hub other than those above are not public API.

## `@rules_bun//bun:defs.bzl`

| Symbol | Kind | Contract |
|---|---|---|
| `BunLibraryInfo` | provider | **new field** `packages: depset` of package link records, merged transitively by `bun_library`; absent on providers created by other rules, which are read as empty |
| `bun_library`, `bun_binary`, `bun_test` | rules | `deps` accept package targets; documentation of the copy tree, the load guard and the limits below |

Behavior of `bun_binary` and `bun_test` with packages:

- Layout: each package version the target reaches through `deps` is copied once into
  `<name>.bun/.store/<name>@<version>/node_modules/<name>/` (scope `/` written `+`); each can load,
  by Node's `node_modules` lookup, exactly its dependencies and resolved peers; the workspace
  package's `node_modules` holds only that package's direct links; a package cannot load anything
  else: the import fails with Bun's module-not-found error, or with the load guard's error when a
  copy is reachable outside the declared set. A target in which one package version would need two
  versions of a peer or of a dependency fails analysis naming the package, that peer or dependency
  and both versions.
- Peers resolve by npm's v7+ semantics: to what the dependent provides, else to the version the
  lockfile lists in the dependent's workspace; an unprovided optional peer is absent. Two lockfile
  entries of one `name@version` whose dependencies or peers resolve differently are distinct
  instances.
- Load guard: package files under the target's store are declared; nothing outside the declared
  set loads. The feature-002 limits apply unchanged; in particular Bun's resolver may read a
  `package.json` outside the declared set (never load it as a module).
- Package contents: an archive's files keep their names, `BUILD` files included; empty directories
  are not carried (tested on Linux); archives with symbolic links are not covered by a test.
- Fetching: only packages a requested target needs are downloaded, by Bazel's downloader, with the
  lockfile's integrity; URLs as recorded, or `{registry}/{name}/-/{basename}-{version}.tgz` for an
  empty slot, `{registry}` from the passed `.npmrc`, else `https://registry.npmjs.org`. A
  `--downloader_config` rewrite may redirect a download; the integrity check is unchanged.
  Credentials come only from `--credential_helper` and `.netrc`; nothing credential-related enters
  a repository attribute or generated file. A `registry` or `@<scope>:registry` URL in the passed
  `.npmrc` that holds user information (`https://user:token@host/`) fails evaluation with an error
  naming the key and the file, without the credential.
- No lifecycle script runs, whatever `trustedDependencies` or Bun's built-in list says; the
  documentation states that Bun 1.4.2 records no empty `trustedDependencies` in `bun.lock`, and
  that Bun runs scripts for packages in `trustedDependencies` or, when it is absent, on the list
  `bun pm default-trusted` prints (`bun pm untrusted` lists only the blocked ones). Packages with native add-ons or WebAssembly
  are not covered by a test.
- Windows: links are directory junctions (`target_type = "directory"`); no Bazel flag and no
  setting is needed, and Windows CI runs with and without `--windows_enable_symlinks` and checks
  that disk-cache hits survive a different output base. A file name Windows cannot hold may be
  renamed, dropped or fail, as Bazel's extractor handles it; the ruleset promises neither a failure
  nor a message. Deep store paths exceed Windows' 260-character `MAX_PATH` (369 characters for
  the tested fixture), so Windows needs long-path support enabled (`LongPathsEnabled`); the
  documentation names the longest tested path and the requirement (research G11).
- A `node_modules` directory in the source tree should be covered by `ignore_directories` in
  `REPO.bazel`; nothing in it loads either way. Not ignored, it is reachable through the execution
  root and an undeclared import from it fails the load guard, naming the file; ignored, it is not
  reachable and the import fails with Bun's module-not-found error (spec Revision 6).
- The documentation of `_FILES_DOC` drops "JSX needs the `react` package" once US1 passes on Linux,
  macOS and Windows.
