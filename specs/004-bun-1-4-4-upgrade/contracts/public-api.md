# Contract: rules_bun Public API after feature 004

Constitution I: the public API is `bun/*.bzl`, `//bun/toolchain:execution_type`,
`//bun/toolchain:target_type`, and the targets and `defs.bzl` symbols the module extensions
generate. This feature adds the libc constraint `//bun/platforms/libc:libc` with its values
`:unconstrained` (default), `:glibc` and `:musl` (FR-011, constitution v2.3.0), and removes or
renames nothing.

## Unchanged symbols

Every rule, macro, provider, module extension, tag class, attribute and generated target of
features 001–003 keeps its name, attributes and behavior.

## What a consumer can observe

| Surface | Before | After | Covered by |
|---|---|---|---|
| `bun.toolchain(bun_version = "1.4.4")` without `integrity` | fails: version unknown, integrity required | fetches and verifies the 1.4.4 archives | `e2e/smoke` `version_test`; nested workspaces |
| `bun.toolchain(bun_version = "1.4.2")` without `integrity` | works | entry kept as feature 001 recorded it (FR-003); not re-verified by a fetch | `//bun/tests:versions` (research G3) |
| FR-007 diagnostic for an unsupported `lockfileVersion` | "… the versions Bun 1.4.2 writes: run `bun install` with Bun 1.4.2 and commit bun.lock" | same text with 1.4.4 | `lockfile_errors.test.ts` |
| `bun_binary` error for a leading `--` | names Bun 1.4.2 | names Bun 1.4.4, if 1.4.4 still drops `--` (research R7) | `args.test.ts` |
| Load-guard limit error | "(Bun 1.4.2)" | "(Bun 1.4.4)" with the limit C13 measures | `c13_regexp_limit_test` |
| `bun_binary` / `bun_test` docs | name 1.4.2 behavior | name 1.4.4 behavior; the `trustedDependencies` sentence loses the 1.4.2 clause (research R6) | the tests research R6, R7 name |
| Docstring examples of a version string | `1.4.2` | `1.4.4` | — (examples) |
| Workspace members of a root `package.json` whose `workspaces` list a negative pattern before a glob it excludes from (found at implementation, research E7) | the negative pattern removes only what earlier globs matched | it removes what any glob matched, as Bun 1.4.4 does | `glob_compare_test`, `workspaces_test` |

Accepted `lockfileVersion` values stay 1, 2 and 3. Lockfiles carrying the 1.4.4 keys
`hasInstallScript` and `unresolved` load as before; `unresolved` and `./<name>/<dep>` keys are not
honored (research G1, G2; a follow-up feature). `libc` is read (FR-012) and selects packages by the
target platform's libc constraint (FR-013, research R11).

| Surface | Before | After | Covered by |
|---|---|---|---|
| `//bun/platforms/libc:{libc,unconstrained,glibc,musl}` | absent | public constraint, default `:unconstrained` | libc analysis tests (SC-006) |
| Package with `libc`, Linux platform with `:glibc` / `:musl` | every libc variant linked | only the variants whose `libc` accepts the platform's | libc analysis tests (SC-006) |
| Package with `libc`, Linux platform without the constraint | every variant linked | unchanged | libc analysis tests (SC-006) |
| Package with `libc`, macOS or Windows platform | linked if `os`/`cpu` matched | not linked (npm defines libc only on Linux) | libc analysis tests (SC-006) |
