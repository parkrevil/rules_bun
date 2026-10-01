# Data Model: Complete the Bun Toolchain Ruleset

The "data" of a Bazel ruleset is its providers, rule attributes, generated repositories and
test records. Names in `code` are the ones in the repository after this feature.

## BunInfo (provider, public via `//bun:defs.bzl`)

| Field | Type | Rule |
|---|---|---|
| `bun` | `File` | The Bun executable for the **execution** platform (`bun` or `bun.exe`). Built in the exec configuration (`cfg = "exec"`, FR-008a). |
| `version` | `string` | The version the repository was created for, such as `1.4.2`. |
| `tool_files` | `list[File]` | Files needed to run `bun`; today `[bun]`. |

Unchanged by this feature.

## bun_toolchain (rule, public via `//bun:toolchain.bzl`)

| Attribute | Type | Change |
|---|---|---|
| `bun` | `label`, `allow_single_file`, mandatory | **adds `cfg = "exec"`** (R6) |
| `version` | `string`, mandatory | none |

Returns:

| Provider | Content | Change |
|---|---|---|
| `DefaultInfo` | `files` and `runfiles` = `tool_files` | none |
| `platform_common.ToolchainInfo` | `buninfo = BunInfo(...)` | none |
| `platform_common.TemplateVariableInfo` | `{"BUN_BIN": bun.path}` | **new** (R7) |

## Generated repositories (created by the `bun` extension)

| Repository | Content | Validation |
|---|---|---|
| `<name>_<platform>` for each key of `PLATFORMS` | Extracted release, `BUILD.bazel` with `exports_files(["bun<exe>"])` and `bun_toolchain(name = "bun_toolchain")` | `integrity` from the tag or `TOOL_VERSIONS`; missing value fails with an English message. Returns `repo_metadata(reproducible = True)` **without a `hasattr` guard** (R4). |
| `<name>_toolchains` (hub) | One `toolchain()` per platform, `exec_compatible_with = PLATFORMS[p].compatible_with`, type `//bun/toolchain:execution_type` | Same return change (R4). |

`PLATFORMS` moves from `bun/private/platforms.bzl` to `bun/private/toolchains_repo.bzl` (research
Part 2, row 37). Keys: `linux-x64`, `linux-aarch64`, `darwin-x64`, `darwin-aarch64`, `windows-x64`.

## `bun.toolchain` tag (module extension, public via `//bun:extensions.bzl`)

Unchanged: `name` (default `bun`, only root may change), `bun_version` (mandatory),
`integrity` (`string_dict` keyed by platform). Several versions under one name resolve to
`max_version`.

## Test fixtures (private, `bun/tests/` and `e2e/smoke/`)

| Fixture | Purpose | Requirement |
|---|---|---|
| `verify_toolchain` (e2e) | Runs Bun, writes `Bun.version` + LF | FR-001, FR-002 |
| analysistest on `verify_toolchain` with `incompatible_auto_exec_groups = True` (e2e) | Analysis fails without a `toolchain` argument; its value (`BUN_TOOLCHAIN_TYPE` vs `None`) is not observable (research R2) | FR-008 |
| `write_file` + `diff_test` (e2e) | Compares with literal `1.4.2` + LF | FR-002, FR-012 |
| resolved-Bun fixture rule + per-platform `analysistest` | Resolved `BunInfo.bun.owner` equals `@bun_<platform>//:bun<exe>` under `extra_execution_platforms` | FR-010 |
| file named `<os>/bun` by `select()` + test-local `bun_toolchain` + `analysistest` | `bun.short_path` ends with the exec OS | FR-008a |
| test-local `bun_toolchain` + `analysistest` | `BUN_BIN` equals `buninfo.bun.path` | FR-007 |
| `manual` genrule using `$(BUN_BIN)` + `analysistest` (default configuration, every CI OS) | argv, with `\` replaced by `/`, contains the resolved Bun's `File.path` | FR-007 |
| `versions_test` | Every `TOOL_VERSIONS` entry covers exactly `PLATFORMS` with `sha256-` values | research Part 2 |
| test platforms | Five hand-written `platform()`s with literal constraints; never derived from `PLATFORMS`, so a wrong hub makes tests fail | FR-010 |

## Divergence record (`research.md` Part 2)

Fields: baseline path, rules_bun path, divergence, status ∈ {closed, intentional, out of scope, equivalent,
gap, equal}, source. **closed** requires a named test (SC-005).

## Test-first record (`tdd-log.md`, written during implementation)

One entry per task:

| Field | Content |
|---|---|
| Task ID | From `tasks.md` |
| Kind | behavior · deletion/refactor · documentation |
| Red | Command, exit code, and the failure line proving the expected reason (behavior tasks; mutation runs are marked as such) |
| Green | Command and result after implementation |
| Platforms | Where it ran (Linux locally; macOS/Windows only from a named CI run) |

State per behavior task: `test written → red recorded → implemented → green recorded`. A test that
is green before implementation goes back to `test written` (spec edge case), unless the task
guards existing behavior, where a reverted mutation provides the red (FR-009).
