# Research: Tests that run on every supported platform

Every source below was read or measured during this feature's research, on 2026-09-20 with
Bazel 9.2.0 and Bun 1.4.2.

## (a) Why the Windows test fails, and what Bazel says to do instead

**Decision**: No rule in this repository may produce a shell script as a test executable or run a
build action through a shell.

**Rationale**: <https://bazel.build/rules/windows> states "Shell scripts (`.sh`) are NOT executable
on Windows; you cannot specify them as `ctx.actions.run`'s `executable`" and "For sake of
portability, avoid running Bash commands directly in actions", and points to purpose-made
bazel-skylib rules (`write_file()`, `copy_file()`, `run_binary()`, `native_binary()`) instead. CI
run 35249847668 shows exactly that failure mode: `CreateProcessW(...hardening_test.sh): %1 is not a
valid Win32 application`.

**Alternatives considered**: A `.bat` launcher beside the `.sh` one — rejected: it doubles the
launcher code and keeps the shell dependency. Marking the test `target_compatible_with` non-Windows
— rejected: it drops the guarantee on a supported platform, which principle II forbids.

## (b) How a test compares an observation without a shell

**Decision**: The probe writes a JSON observation, `write_file` writes the expected JSON with
`newline = "unix"`, and `diff_test` compares the two.

**Rationale**: bazel-skylib's `rules/diff_test.bzl` documents that the rule "uses a Bash command
(diff) on Linux/macOS/non-Windows, and a cmd.exe command (fc.exe) on Windows (no Bash is
required)", so the launcher problem is solved by the ruleset that owns it. `fc.exe /B` compares
bytes, so the expected file must have identical bytes on every platform; `write_file`'s
`newline = "unix"` attribute guarantees that, where a checked-in golden file would be rewritten by
Git's line-ending conversion on Windows.

**Alternatives considered**: Keeping a custom test rule and writing a `.bat` launcher on Windows —
rejected as duplicating `diff_test`. Making the probe fail the build on a leak and wrapping it in
`build_test` — rejected: a broken guarantee would surface as a build error rather than a test
failure, and the observed values would not appear in the test log.

## (c) How an external consumer module runs a smoke test

**Decision**: `e2e/smoke` declares `build_test(name = "smoke_test", targets = [":verify"])` and adds
`bazel_dep(name = "bazel_skylib", version = "1.9.2", dev_dependency = True)`.

**Rationale**: bazel-contrib/rules-template — the reference layout this repository follows — uses
exactly this in `e2e/smoke/BUILD` (`load("@bazel_skylib//rules:build_test.bzl", "build_test")`,
`build_test(name = "smoke_test", targets = [...])`) with `bazel_skylib` declared in
`e2e/smoke/MODULE.bazel` as a `dev_dependency`. Building `:verify` runs Bun from the toolchain the
module registered, so the test fails if resolution, the download, or execution fails.

Principle IV requires that `e2e/smoke` keep validating the minimum versions the ruleset declares.
<https://bcr.bazel.build/modules/bazel_skylib/1.9.2/MODULE.bazel> declares `platforms` 0.0.10 and
`rules_license` 1.0.0; `platforms` is already resolved at 1.0.0 through Bazel 9.2.0's own
requirements, and `rules_license` is not a dependency of rules_bun, so nothing rules_bun declares is
raised.

**Alternatives considered**: Comparing the reported Bun version against a golden file — rejected: it
would restate the pinned version in a second place while adding no coverage, because the `integrity`
check already fixes which archive was downloaded.

## (d) How to run Bun in a hostile working directory

**Decision**: The probe runs Bun once through `ctx.actions.run`, and that Bun process spawns a child
Bun in the directory holding the hostile `bunfig.toml`, `.env`, and preload, using `Bun.spawnSync`
with its `cwd` option. The child prints what leaked as JSON on stdout; the parent writes it to the
output file.

**Rationale**: The guarantee under test is about the Bun process's working directory, and a Bazel
action always starts in the execution root. Bun's CLI help and docs define `--cwd` as "Absolute path
to resolve files & entry points from", and an absolute path is not knowable at analysis time, so
`--cwd` cannot be used as documented (principle V). <https://bun.com/docs/api/spawn> documents
`Bun.spawnSync` with a relative `cwd` option (`cwd: "./path/to/subdir"`) and a result carrying
`stdout`, `stderr`, and `success`, which covers exactly this case.

Measured in this session with Bun 1.4.2, a directory containing a `bunfig.toml` that preloads a
poisoning script and a `.env` setting `PORT=9999`:

| Flags | Result |
|-------|--------|
| none | `{"poisoned":true,"port":"9999"}` |
| `--no-install --no-env-file --config=<empty bunfig>` | `{"poisoned":false,"port":null}` |

The first row is what keeps the test non-vacuous (FR-005): the setup demonstrably loads the attack
when the flags are absent.

**Alternatives considered**: A relative `--cwd`, which works in practice — rejected as undocumented
behavior under principle V. Placing the hostile files in the repository root package so that they
land at the execution root — rejected: it would put a `bunfig.toml` and `.env` in the working
directory of everyone who runs Bun in this repository.

## (e) Whether the `repo_metadata` guard is needed

**Decision**: Delete `if not hasattr(repository_ctx, "repo_metadata"): return None` from
`bun/repositories.bzl` and `bun/private/toolchains_repo.bzl`.

**Rationale**: <https://bazel.build/rules/lib/builtins/repository_ctx> documents
`repository_ctx.repo_metadata(*, reproducible = False, attrs_for_reproducibility = {})` with no
deprecation or experimental marker, and `MODULE.bazel` declares
`bazel_compatibility = [">=9.2.0"]`, so no accepted Bazel version lacks it. Principle V forbids
feature detection for such an API.

**Alternatives considered**: Lowering `bazel_compatibility` so the guard has a purpose — rejected:
it is out of this feature's scope and would require testing older Bazel versions that CI does not
run.
