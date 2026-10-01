# Contract: rules_bun Public API

Constitution I: the public API is `bun/*.bzl` and `//bun/toolchain:execution_type`. Everything
else may change in any release. This contract lists the API after this feature; **changed** marks
additions. Nothing is removed or renamed.

## `//bun/toolchain:execution_type`

`toolchain_type`, public. Resolved against the **execution** platform.

## `@rules_bun//bun:defs.bzl`

| Symbol | Kind | Contract |
|---|---|---|
| `BUN_TOOLCHAIN_TYPE` | `Label` | Equals `//bun/toolchain:execution_type`. **Changed (docstring)**: shows a consumer rule declaring it and calling `ctx.actions.run(executable = buninfo.bun, tools = buninfo.tool_files, toolchain = BUN_TOOLCHAIN_TYPE, ...)`. |
| `BunInfo` | provider | Fields `bun`, `version`, `tool_files` (data-model.md). |

Consumer usage, as the e2e test does it:

```starlark
load("@rules_bun//bun:defs.bzl", "BUN_TOOLCHAIN_TYPE")

def _impl(ctx):
    buninfo = ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo
    ctx.actions.run(
        executable = buninfo.bun,
        toolchain = BUN_TOOLCHAIN_TYPE,
        ...
    )

my_rule = rule(implementation = _impl, toolchains = [BUN_TOOLCHAIN_TYPE])
```

## `@rules_bun//bun:toolchain.bzl`

`bun_toolchain(name, bun, version)`.

- `bun`: **changed** — built in the exec configuration.
- **Changed**: provides `TemplateVariableInfo` with `BUN_BIN`, the execution-root-relative path of
  Bun. A genrule uses it with `toolchains = ["@rules_bun//bun/toolchain:execution_type"]` and
  `$(BUN_BIN)` in `cmd`. Only the expansion is promised. Running Bun from a genrule this way is
  **unverified**: Bazel does not document that the toolchain's files become action inputs, and the
  genrule page requires a tool to appear in `tools` (research R7, gap).

## `@rules_bun//bun:extensions.bzl`

`bun` module extension, tag `toolchain(name = "bun", bun_version, integrity = {})`, and the tag
class global `bun_toolchain` (re-exported after R10). Creates
`<name>_<platform>` and `<name>_toolchains`; the consumer registers `@<name>_toolchains//:all`.
Unchanged.

## `@rules_bun//bun:repositories.bzl`

`bun_repositories(name, bun_version, platform, integrity = "")` and
`bun_register_toolchains(name, integrity = {}, **kwargs)`. Unchanged interface; the return value
of the repository rule is always `repo_metadata(reproducible = True)`.

## Non-contract

`bun/private/*` (which now holds the implementation re-exported by the public files, R10),
`bun/tests/*`, generated repository layouts beyond the targets named above, and
the `bun_toolchain` target name inside a platform repository.
