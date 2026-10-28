# Contract: rules_bun Public API after feature 005

Constitution I: the public API is `bun/*.bzl`, `//bun/toolchain:execution_type`,
`//bun/toolchain:target_type`, `//bun/platforms/libc:libc` with `:unconstrained`, `:glibc`,
`:musl`, and the targets and `defs.bzl` symbols the module extensions generate under their
documented naming rules. This feature removes one symbol that was never released and adds two
platform keys (FR-019, FR-024).

## Symbols

| Symbol | Change |
|---|---|
| `@rules_bun//bun:extensions.bzl` `bun_toolchain` | removed; the file exports `bun` and `npm` only. No published version contains it (constitution VII, FR-019), so no migration message ships. |
| `bun.toolchain` `integrity` keys | gain `linux-x64-musl`, `linux-aarch64-musl` |
| `@rules_bun//bun:repositories.bzl` `bun_repositories(platform = ...)` | values gain `linux-x64-musl`, `linux-aarch64-musl` |
| `bun_register_toolchains` | also creates `<name>_linux-x64-musl` and `<name>_linux-aarch64-musl` |
| every other rule, macro, provider, extension, tag class, attribute | unchanged |

## What a consumer can observe

| Surface | Before | After | Covered by |
|---|---|---|---|
| Linux platform with `@rules_bun//bun/platforms/libc:musl` | glibc Bun | musl Bun of its CPU, for the execution and the target toolchain; verified by resolution and integrity, not run on musl | `toolchain_test`, `target_toolchain_test`, `bazel fetch` (Q4) |
| Linux platform with `:glibc` or without the libc constraint | glibc Bun | unchanged | same |
| `@bun_toolchains` target names (undocumented; `:all` is the documented target) | `<platform>_toolchain`, `<platform>_target_toolchain` | same for macOS, Windows and musl; `<platform>_glibc_…` and `<platform>_unconstrained_…` for the glibc archives | `toolchain_test` |
| `bun.toolchain` from the root and a dependency, one version, different integrity | the tag read last wins | the root's value wins per platform | `toolchain_tags.test.ts` |
| two non-root modules, one version and platform, different integrity | the tag read last wins | evaluation fails naming both modules, the version and the platform | same |
| an integrity key such as `linux_x64`, or a value that is no SRI | ignored, or fails at download | evaluation fails naming the module, the key and the known keys / the value's form | same |
| several `bun.toolchain` tags for one version | the last tag's dict replaces the others | merged per platform | same |
| `npm.translate_lock` `name` that is no repository name, `workspace_target_name` that is no target name | Bazel's error later | evaluation fails naming the module, the tag and the value | `lockfile_errors.test.ts` |
| `bun.lock` URL, or tarball/`git+` resolution, holding user information | accepted, written into repository attributes and diagnostics | evaluation fails naming the lockfile and the entry key, without the URL | `credentials.test.ts` |
| two hubs, one package version, different integrity, source or exclusion policy | carried once (one archive and its check dropped) | analysis fails naming the package version, both lockfiles, the property and both values | `uniqueness_test`, `multi.test.ts` |
| npm `os` or `cpu` `["any"]` | excluded everywhere | included everywhere (npm-install-checks `checkList`) | `platforms_test` |
| archive file `build`, `Build`, `build.bazel`, `Build.bazel` | kept (a Bazel package on case-insensitive file systems) | renamed and mapped back, as `BUILD` | layout and `glob_test` cases |
| `bin` file without a source extension whose first line is a `node` or `bun` `#!` line (typescript `bin/tsc`) | analysis fails ("Bun runs only JavaScript and TypeScript files") | runs with the toolchain's Bun | `bins.test.ts`, C18 |
| any other non-source `bin` file | analysis fails with the false reason | analysis fails: "is not a JavaScript program for Node or Bun: <reason>" | `bins_test`, `bins.test.ts` |
| `:node_modules/<package>/bin/<bin>` tags | `manual` only for non-runnable or unsupported | always `manual`: `bazel build //...` builds no bin; a used or requested bin builds as before (research D1) | `bins.test.ts` |
| Linux or macOS `bun_binary`, `bun_test`, bin | hermetic-launcher template and finalizer repositories fetched | none fetched | `launcher_fetch.test.ts` |
| Windows target | hermetic-launcher stub `<name>.exe` | unchanged; missing template or finalizer fails analysis naming the hermetic-launcher type | `run_test` no-stub cases; Windows CI jobs |
| rules_bun `MODULE.bazel` | registers no toolchain for consumers | registers its private Windows-launcher toolchain (`//bun/private/windows_launcher:all`) | Windows CI jobs |

## Documentation statements that change

- `bun_binary`/`bun_test` (`_FILES_DOC`): JSX's `react` comes from the consumer's lockfile through
  the `npm` extension; Platforms name the CI runner labels and jobs; the npm-packages platform
  sentence names the jobs that ran them.
- `npm` (`_NPM_DOC`): bins by FR-012 and always `manual`; `BUILD`/`BUILD.bazel` in any case renamed;
  `:node_modules/<package>` resolves only for files in and below the package that calls
  `npm_link_all_packages`; a `replace_package` archive must be visible to the generated repository
  (`exports_files(..., visibility = ["//visibility:public"])`); several lockfiles: carried once only
  with equal integrity, source and exclusion policy; credentials rejected from `bun.lock` too;
  Platforms as above.
- `bun/defs.bzl`: platform sentence as above.
- `bun.toolchain` `integrity` doc: the seven keys, root precedence, conflict failure.
