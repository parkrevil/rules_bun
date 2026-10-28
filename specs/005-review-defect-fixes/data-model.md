# Data Model: The Ruleset's Design Principles, Held Everywhere

All entities are private (`bun/private/`) unless marked public. Decisions are in
[research.md](research.md).

## Content identity of a package instance (R1)

Written by the `npm` extension per hub instance into the hub's `npm_instance` attributes, carried
in `NpmInstanceInfo`.

| Field | Value | Source |
|---|---|---|
| `integrity` | the padded integrity the download is verified against | `padded_integrity(entry.integrity)` |
| `source` | the download URL, or the `replace_package` label text when replaced | `package_url(...)` / `_label_text(...)` |
| `exclude` | sorted, de-duplicated exclusion patterns of the package | `exclude_package_contents["*"] + [name]` |
| `lockfile` | the hub's `bun.lock` label text, for diagnostics | `str(tag.bun_lock)` |

Rules: two instances of one store name from different hubs are carried once only when
`integrity`, `source` and `exclude` are equal and every edge reaches the same package version;
otherwise analysis fails naming the package version, both lockfiles and the first differing
property (order: integrity, source, exclusion policy, then dependencies) with both values. Only
`ok` instances have an identity; an instance without integrity is `npm_unsupported`.

## URL check (R2)

`has_userinfo(url)` (`npmrc.bzl`): the authority (after `://`, before `/`, `?`, `#`) holds `@`.
Applied during evaluation to: `.npmrc` `registry` and `@<scope>:registry`; `bun.lock` slot 1 of an
npm entry; slot 0's resolution of a `tarball` or `unsupported` entry. A match fails naming the
file and the key (lockfile key or `.npmrc` key), never the URL. It runs before every other check
that prints a URL.

## Bin decision (R4)

| Element | Where | Content |
|---|---|---|
| `bins` attribute | `npm_package_repository` | the entry's `bin` paths (normalized as `npm_bin.path`) |
| decision | computed in the package repository after extraction and renaming | path → `""` (runnable) or a reason |
| `bins` attribute | `npm_package_tree` (`:tree`) | the decision dict |
| `NpmPackageTreeInfo(bins)` | returned by `npm_package_tree` | same dict |
| `NpmInstanceInfo.bins` | copied by `npm_instance` from its `tree` | same dict |

Runnable: path ends in one of `SOURCE_EXTENSIONS`; or the file's first line starts with `#!` and
its command (after `env` and its options and assignments) has basename `node` or `bun`. Reasons:
no such file in the package (absent or excluded), a directory, neither extension nor such a line.
A renamed file (R7) is read through its safe name. `npm_bin` fails analysis on a non-empty
reason. Every generated bin target is tagged `manual` (D1).

## Platform table (R5)

`bun/private/platforms.bzl`:

| Name | Shape | Content |
|---|---|---|
| `NPM_OS` | npm `os` → `@platforms//os:<v>` | aix, android, darwin→macos, freebsd, linux, netbsd, openbsd, win32→windows |
| `NPM_CPU` | npm `cpu` → `@platforms//cpu:<v>` | arm, arm64→aarch64, ia32→x86_32, riscv64, s390x, x64→x86_64 |
| `NPM_LIBC` | npm `libc` → `//bun/platforms/libc:<v>` | glibc, musl |
| `BUN_ARCHIVES` | archive → `struct(os, cpu, libc)` in npm values | linux-x64, linux-aarch64 (glibc); linux-x64-musl, linux-aarch64-musl (musl); darwin-x64, darwin-aarch64, windows-x64 (no libc) |
| `archive_constraint_sets(archive)` | → list of constraint lists | glibc: `[os, cpu, :glibc]` and `[os, cpu, :unconstrained]`; musl: `[os, cpu, :musl]`; other: `[os, cpu]` |

Derived: `bun_repositories.platform` values (= `BUN_ARCHIVES` keys); `toolchains_repo` toolchains
(one execution and one target toolchain per constraint set); the hub's `config_setting`s.

`check_list(value, values)` (npm-install-checks `checkList`): a sole `any` → true; a `!v` equal to
`value` → false; else true when a positive equals `value` or every entry is negated. `value` may
be `None`.

## Known version (R5)

`TOOL_VERSIONS[version]` gains `linux-x64-musl` and `linux-aarch64-musl` for `1.4.2` and `1.4.4`
(values in research E1). Invariant (`versions_test`): every known version has every
`BUN_ARCHIVES` key.

## Toolchain request (R8)

One `bun.toolchain` tag: module (`name@version`, root or not), `name`, `bun_version`,
`integrity` (platform → SRI).

Validation per tag: `bun_version` parses (`version_key`); each key in `BUN_ARCHIVES`; each value
`sha256-`/`sha384-`/`sha512-` followed by base64; a non-root module keeps the default `name`. Each
failure names the module and the tag.

Resolution per `name`: version = highest requested. Per platform of that version: the root's
value if it gave one (two different root values fail); else the one value all non-root modules
agree on (two different values fail naming both modules, the version and the platform); else
none (the `TOOL_VERSIONS` value or the existing "pass the integrity" failure at fetch).

## Windows launcher toolchain (R6)

| Element | Value |
|---|---|
| type | `//bun/private/windows_launcher:toolchain_type` |
| registration | `toolchain(target_compatible_with = ["@platforms//os:windows"])` in the same package; `register_toolchains` in rules_bun's `MODULE.bazel` |
| implementation | `windows_launcher_toolchain` (`bun/private/windows_launcher.bzl`), requesting hermetic-launcher's template and finalizer types as optional |
| provides | `ToolchainInfo(template = File or None, finalizer = File or None)` |
| used by | `bun_binary`, `bun_test`, `npm_bin` (optional type), only when the target platform is Windows |

The stub is compiled by running `finalizer` with `--template`, `-o`, `--transform` and the
embedded arguments built by hermetic-launcher's helpers, `toolchain =` the type. A missing
toolchain, template or finalizer fails analysis naming the hermetic-launcher type and the target
platform.

## Canaries (R3)

| ID | File | Pins | Fails naming |
|---|---|---|---|
| C1 | `canary/c1_preserve_symlinks.test.ts` | relative import resolves from the real path | copy tree and load guard; also fails when no link can be made or the child exits non-zero |
| C17 | `canary/c17_leading_dashdash.test.ts` | `--` directly after the entry point is dropped | the launcher's refusal of a leading `--` |
| C18 | `canary/c18_extensionless_bin.test.ts` | an extensionless CommonJS and ES module file after `#!/usr/bin/env node` runs | FR-012's bin rule |
