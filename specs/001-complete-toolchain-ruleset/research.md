# Research: Complete the Bun Toolchain Ruleset

**Baseline**: `bazel-contrib/rules-template@cb8787e74153b061b473a7bac92ac11aa2cca346` (2026-07-01),
46 tracked paths. In the tables, **B** means the baseline file at the same path:
`https://github.com/bazel-contrib/rules-template/blob/cb8787e74153b061b473a7bac92ac11aa2cca346/<path>`.

**Bazel**: 9.2.0 (`.bazelversion`, lower bound of `bazel_compatibility`).

**Documentation**:
[toolchains](https://bazel.build/extending/toolchains),
[module extensions](https://bazel.build/external/extension),
[repository rules](https://bazel.build/external/repo),
[testing](https://bazel.build/rules/testing),
[make variables](https://bazel.build/reference/be/make-variables#custom_variables),
[genrule](https://bazel.build/reference/be/general#genrule),
[`ctx.actions.run`](https://bazel.build/rules/lib/builtins/actions#run),
[`Action`](https://bazel.build/rules/lib/builtins/Action),
[`repository_ctx.repo_metadata`](https://bazel.build/rules/lib/builtins/repository_ctx#repo_metadata),
[automatic execution groups](https://bazel.build/extending/auto-exec-groups),
[`repo()` / `ignore_directories`](https://bazel.build/rules/lib/globals/repo).

"Verified" below means run in a scratch module on Bazel 9.2.0, Linux (WSL), 2026-09-29, by the
planner or the adversarial reviewers.

## Part 1 — Decisions

### R0. Test messages

Every assertion added by this feature passes an English `msg` (skylib `asserts.*`) or
`failure_message` (`diff_test`), like every other diagnostic in the repository (FR-012).
Messages were first written in Korean under an earlier AGENTS.md rule and translated on
2026-10-01; tdd-log.md quotes them in English.

### R1. Consumer test in `e2e/smoke` (FR-001, FR-002)

- **Decision**: Keep `verify_toolchain` (runs Bun with `ctx.actions.run`, writes `Bun.version`)
  and compare its output with `write_file(newline = "unix", content = ["1.4.2", ""])` using
  bazel-skylib `diff_test` with an English `failure_message`. Add `bazel_skylib` 1.9.2 as a
  `dev_dependency` and refresh `e2e/smoke/MODULE.bazel.lock`. bazel_skylib 1.9.2 needs only
  `platforms` 0.0.10 and `rules_license` 1.0.0, so no non-dev version rises (FR-013, verified).
- **Rationale**: The baseline's smoke module uses bazel-skylib (`build_test`). `diff_test` writes a
  `.bat` launcher on Windows (`fc.exe /B`) and a shell launcher elsewhere; both are skylib-generated,
  which constitution VI allows. The expected version is a literal, independent of the toolchain.
- **Test-first**: The behavior checked here (Bun reports the requested version) already exists, so
  the new `diff_test` passes once written. Per the spec edge case it must be shown able to fail:
  a mutation run with the literal `0.0.0` is recorded as its red. The run before the task
  (exit 4, "No test targets were found") is recorded as the module's starting state, not as the
  test's red. The genuine red of this story is R2.
- **Windows constraints**: skylib's `.bat` echoes `failure_message` inside a parenthesized `if`
  with delayed expansion, so the message MUST NOT contain `( ) ! % ^ & | < >`; the message is ASCII,
  so the console codepage does not matter. The `.bat` reads manifest entries with
  `tokens=2*` and keeps only the second token, so a runfiles path with a space would break it;
  none of this module's paths contain spaces.
- **Alternatives**: `build_test` (baseline) proves only that the action ran; a Bun-run test
  launcher would be a generated script (VI).

### R2. `toolchain =` on `ctx.actions.run` (FR-008)

- **Decision**: Add `toolchain = BUN_TOOLCHAIN_TYPE` to every `ctx.actions.run` that runs Bun
  (only `e2e/smoke/verify.bzl` after the deletions) and show it in the `BUN_TOOLCHAIN_TYPE`
  docstring. Test: an `analysistest` in `e2e/smoke` on the `verify_toolchain` target with
  `config_settings = {"//command_line_option:incompatible_auto_exec_groups": True}`.
- **Rationale**: `ctx.actions.run` documents that when the executable comes from a toolchain the
  toolchain type must be set so the action runs on the right execution platform. With automatic
  execution groups on, omitting it is an analysis error.
- **Red state (verified)**: With `--incompatible_auto_exec_groups`, a rule that runs a
  toolchain-provided executable without `toolchain =` fails analysis ("Couldn't identify if tools
  are from implicit dependencies or a toolchain. Please set the toolchain parameter"), even with a
  single toolchain type; with the argument it analyzes. The flag defaults to `false` in 9.2.0,
  which is why a first probe without it showed no difference. The analysistest `Action` object has
  no `toolchain` field, so the flag is the observable effect.
- **Coverage limit (verified by review)**: the test also passes with `toolchain = None`, so it
  proves the argument is present, not that its value is `BUN_TOOLCHAIN_TYPE`. No documented API
  exposes an action's toolchain or execution platform to an analysistest. US1 acceptance 3 is
  therefore covered for presence only; the value is checked by
  `git grep -n 'toolchain = BUN_TOOLCHAIN_TYPE'` (quickstart step 3) and reported as not covered
  by a test (constitution II).

### R3. Deleting the hardening helper (FR-003, FR-004)

- **Decision**: Delete `bun/private/{action,hardening,paths}.bzl`,
  `bun/tests/{action_test,hardening_test,platform_transition}.bzl`, their `bzl_library` targets,
  `with_platform`, `action_fixture`, `hardening_*_test` and `cross_*_test`, after R5 lands.
- **Rationale**: User decision in the spec revision; no public API reaches them.
- **Record** (deletion): root `bazel test //...` passes; `git grep -n run_shell -- bun e2e` and
  `git grep -n 'is_executable = True' -- bun e2e` are empty.

### R4. `hasattr(repository_ctx, "repo_metadata")` (FR-005)

- **Decision**: Remove both guards; return `repository_ctx.repo_metadata(reproducible = True)`.
- **Rationale**: Added in Bazel 8.3.0; `bazel_compatibility = [">=9.2.0"]`; constitution V
  forbids feature detection for an API every supported version has. The baseline keeps the guard
  for Bazel <8.3.0, so the divergence is **intentional** (FR-005).
- **Record** (refactor): root and `e2e/smoke` tests pass; `git grep -n hasattr -- bun` is empty.

### R5. Toolchain selection per execution platform (FR-010)

- **Decision**: Replace `cross_*_test` with one `analysistest` per Bun platform. A test-only
  fixture rule declares `BUN_TOOLCHAIN_TYPE` and returns the resolved `BunInfo` in a test-local
  provider (`analysistest.make` takes no `toolchains`). Each test sets
  `config_settings = {"//command_line_option:extra_execution_platforms": ["//bun/tests/platforms:<p>"]}`
  and asserts `buninfo.bun.owner == Label("@bun_<p>//:bun<exe>")`; the root `MODULE.bazel` adds the
  five platform repositories to its dev `use_repo`.
- **Test platforms MUST be hand-written literals** in `bun/tests/platforms/BUILD.bazel` (the three
  existing ones plus `linux_x64`, `darwin_x64`), not generated from `PLATFORMS`. Generated platforms
  would change together with the hub, and a reviewer verified that swapping two entries'
  `compatible_with` then leaves every test green.
- **Rationale**: The hub uses `exec_compatible_with`, so only the execution platform selects Bun;
  flag-given execution platforms are considered before registered ones
  ([`--extra_execution_platforms`](https://bazel.build/reference/command-line-reference#flag--extra_execution_platforms):
  "considered before those declared in MODULE.bazel").
  Comparing `Label`s resolved through the root's repo mapping avoids depending on canonical
  repository names. Prior art: bazel-contrib/rules_python
  `tests/base_rules/py_executable_base_tests.bzl`, bazelbuild/rules_rust
  `test/unit/lint_tests/lint_tests.bzl`.
- **Verified**: all five tests pass with the correct hub.
- **Test-first**: behavior exists; red by mutation (swap two entries' `compatible_with` in
  `PLATFORMS`, record the failures of those two tests, revert).
- **Scope note**: all five platforms, host included — a superset of FR-010's non-host set, and the
  same `//...` on every OS. Cost: analysis fetches all five Bun archives on every CI job.

- **Rejection (added after review)**: the five supported test platforms cannot catch a hub entry
  that is missing one constraint, because such an entry still matches only supported platforms.
  Five `rejection_*_test` targets give a fixture an optional Bun toolchain
  ([`config_common.toolchain_type`](https://bazel.build/rules/lib/toplevel/config_common#toolchain_type),
  `mandatory = False`) and `exec_compatible_with` of an unsupported platform (riscv64 on each OS,
  FreeBSD on each CPU), which keeps the host out of the candidates, and assert that no Bun is
  resolved. Red by mutation: dropping the CPU of `darwin-x64` or the OS of `linux-x64` fails them.

### R6. `cfg = "exec"` on `bun_toolchain.bun` (FR-008a)

- **Decision**: Add `cfg = "exec"`. Test: a test-only rule declares its output as
  `<os>/bun`, where `<os>` comes from `select()` on `@platforms//os` (`linux` / `windows` / …); a
  test-local `bun_toolchain` uses it as `bun`; an `analysistest` on that `bun_toolchain` sets
  `//command_line_option:platforms` to `//bun/tests/platforms:windows_x64` and
  `extra_execution_platforms` to `linux_aarch64`, and asserts that `buninfo.bun.short_path` ends
  with `linux/bun`. The name, not the content, varies, because an analysistest cannot read file
  content ([`File`](https://bazel.build/rules/lib/builtins/File)); `short_path` is documented.
- **Rationale**: [Toolchains and configurations](https://bazel.build/extending/toolchains#toolchains-and-configurations).
  `select()` on constraints is documented; output-directory names such as `-exec-` are not.
  Diverges from the baseline's `target_tool` (no `cfg`), which relies on a source file.
- **Red state (verified by review)**: without `cfg = "exec"` the path ends with `windows/bun`.
- **Constitution VII**: not breaking. A source file (the downloaded Bun every generated repository
  passes) has no configuration, so it is unchanged. A generated `bun` was built for the target
  platform before, which is wrong for a tool that runs in build actions unless target and
  execution platforms coincide, and in that case the result is the same binary.

### R7. `TemplateVariableInfo` with `BUN_BIN` (FR-007)

- **Decision**: `bun_toolchain` returns `platform_common.TemplateVariableInfo({"BUN_BIN": bun.path})`.
  Two tests:
  1. **Value**: an `analysistest` on a test-local `bun_toolchain` (source-file `bun`) asserts
     `TemplateVariableInfo.variables["BUN_BIN"] == ToolchainInfo.buninfo.bun.path`, both read from
     the target under test ([`TemplateVariableInfo`](https://bazel.build/rules/lib/providers/TemplateVariableInfo)).
  2. **Genrule use**: a `manual` genrule with `toolchains = ["//bun/toolchain:execution_type"]` and
     `$(BUN_BIN)` in `cmd` and `cmd_bat`; an `analysistest` with no configuration change asserts
     that the genrule argv, with `\` replaced by `/`, contains the `File.path` of the Bun resolved
     by the R5 fixture (the [genrule `cmd_bat`](https://bazel.build/reference/be/general#genrule.cmd_bat)
     page says paths are expanded "to Windows style paths (with backslash)" there), passed
     as an extra test attribute (both are in the default configuration, so both resolve the host
     execution platform). It runs on each CI OS, which is how Windows (`cmd_bat`) is covered; no
     Windows variant runs on a Linux host, because the genrule page does not say that the
     execution platform selects `cmd_bat`.
  No assertion is made on the action's inputs; see **Gap** below.
- **Rationale (verified)**: A genrule that lists a toolchain type in `toolchains` expands the
  toolchain's `TemplateVariableInfo` ([genrule `toolchains`](https://bazel.build/reference/be/general#genrule.toolchains);
  PR #188: "Genrules now accept the toolchain type directly"). `File.path` is right because genrule commands run from the execution root; the
  baseline's runfiles-style path is not (intentional divergence). Neither command is executed.
- **Red state (verified by review on Bazel 9.2.0)**: analysis error
  `in cmd attribute of genrule rule …: $(BUN_BIN) not defined` (allowed by FR-009). The value
  test's red is its presence assertion; it returns right after that assertion fails.
- **Gap**: Bazel 9.2.0 adds the toolchain's files to the genrule's inputs (verified in analysis),
  but no bazel.build page states it. Constitution V forbids relying on it, so the analysistest
  asserts only the expansion, and the contract promises only the expansion. The genrule page says a tool run by
  `cmd` "must appear in `tools`", and after PR #188 there is no public target to list there, so
  whether a genrule can run `$(BUN_BIN)` is reported as a gap and unverified; the contract says so.

### R8. Other baseline alignments

Taken from Part 2: move `PLATFORMS` into `toolchains_repo.bzl`; `e2e/smoke/MODULE.bazel` without
`module()` and with `dev_dependency = True` on its `bazel_dep`s only, as the baseline does; add
`versions_test`. `.bazelignore` is **not** adopted, `doc_link_template` is not copied, and gazelle's
`-exclude` is left as is (see Part 2).

### R9. `stripPrefix` (constitution V)

- **Decision**: `download_and_extract(strip_prefix = ...)` instead of `stripPrefix`.
- **Rationale**: [`repository_ctx.download_and_extract`](https://bazel.build/rules/lib/builtins/repository_ctx#download_and_extract):
  "this parameter may also be used under the deprecated name `stripPrefix`". Constitution V
  forbids deprecated APIs.
- **Record** (refactor): root and `e2e/smoke` tests pass; `git grep -n stripPrefix -- bun` is empty.

### R10. Implementation moves to `bun/private/` (constitution I)

- **Decision**: Move the implementation of `bun_toolchain` (`bun/toolchain.bzl`), of
  `bun_repositories` / `bun_register_toolchains` (`bun/repositories.bzl`) and of the `bun`
  extension and its tag class (`bun/extensions.bzl`) into `bun/private/`; the public files keep
  their module docstrings and re-export the same names (`bun_toolchain = _bun_toolchain`, …).
- **Rationale**: Constitution I: "Implementation MUST live in `bun/private/`". The baseline keeps
  implementation in public files; the divergence is **intentional**. Re-exporting from a public
  `.bzl` is the pattern of bazel-contrib/rules_python (`python/extensions.bzl` re-exports
  `python/private/python.bzl`'s extension). `use_extension` names the public file, so consumers
  are unaffected.
  The public `extensions.bzl` also re-exports the tag class `bun_toolchain`, a public global today,
  so nothing is removed (constitution VII).
- **Record** (refactor): root and `e2e/smoke` tests pass (the e2e module loads only public files);
  `starlark_doc_extract` targets still build (verified by review: 4 targets, all public symbols
  documented). The extracted docs' `origin_key` names `//bun/private` files; `release_prep.sh`
  does not render it, so consumers are not pointed at private files.

## Part 2 — Divergence register (FR-006, SC-005)

Statuses: **closed** (with its test), **intentional** (with the principle or rule),
**out of scope** (with the excluded scope), **equivalent** (form differs, behavior identical,
with a source), **gap**, **equal** (no divergence) — spec FR-006.
Spec Kit and agent tooling (`.agents/`, `.claude/`, `.specify/`, `specs/`, `AGENTS.md`,
`CLAUDE.md`) is out of scope: Spec Kit workflow files, not part of the ruleset.

### The 46 baseline paths

| # | Baseline path | Divergence in rules_bun | Status | Source |
|---|---|---|---|---|
| 1 | `.bazelignore` (`e2e/`) | `REPO.bazel` `ignore_directories(["e2e"])` instead | equivalent: `ignore_directories` and `.bazelignore` both make Bazel ignore `e2e/` | B; https://bazel.build/rules/lib/globals/repo#ignore_directories |
| 2 | `.bazelrc` | comments removed; the flags are identical | equivalent: comments are not read by Bazel | B; https://bazel.build/run/bazelrc |
| 3 | `.bazelversion` (9.1.1) | 9.2.0 | intentional: constitution V, lower bound of `bazel_compatibility` | B; `MODULE.bazel` |
| 4 | `.bcr/README.md` | missing | out of scope: documentation | B |
| 5 | `.bcr/metadata.template.json` | maintainer and repository values | equivalent: the template's placeholders are filled as the publish-to-bcr templates README instructs | B; https://github.com/bazel-contrib/publish-to-bcr/blob/main/templates/README.md |
| 6 | `.bcr/presubmit.yml` | `bazel: ["9.x"]` vs `["9.*", "8.*"]` | intentional: constitution V (Bazel 8 below `bazel_compatibility`); notation `9.x` vs `9.*` and `.bazelversion` pin recorded, not changed (spec Assumptions) | B; https://github.com/bazelbuild/bazel-central-registry/blob/main/docs/README.md |
| 7 | `.bcr/source.template.json` | — | equal | B |
| 8 | `.devcontainer/Dockerfile` | missing | out of scope: developer environment | B |
| 9 | `.devcontainer/devcontainer.json` | missing | out of scope: developer environment | B |
| 10 | `.gitattributes` | export-ignores agent tooling and lockfiles | out of scope: release packaging (spec Assumptions, release automation) | B |
| 11 | `.github/workflows/ci.yaml` | OS matrix, no Bazel 8, `prek`, SHA pins | intentional: constitution II (tests name the platforms they ran on; SC-001/002 need Linux, macOS, Windows) and V (Bazel 8 unsupported) | B |
| 12 | `.github/workflows/conventional-commits.yaml` | name, SHA-pinned action | out of scope: release automation | B |
| 13 | `.github/workflows/publish.yaml` | `BCR_PUBLISH_TOKEN` secret, publish-to-bcr v1.5.0 SHA-pinned, `actions: read`, own fork | out of scope: release automation | B |
| 14 | `.github/workflows/release.yaml` | no `workflow_call` (no `tag.yaml`), SHA pins, `actions: read` | out of scope: release automation (release-tooling decision) | B |
| 15 | `.github/workflows/release_prep.sh` | quoting, no unused `SHA` line, module name | out of scope: release automation | B |
| 16 | `.github/workflows/tag.yaml` | missing | out of scope: release automation (release-tooling decision) | B |
| 17 | `.gitignore` | — | equal | B |
| 18 | `.pre-commit-config.yaml` | prek, yamlfmt, own hooks | out of scope: lint tooling | B |
| 19 | `.prettierignore` | missing (no prettier) | out of scope: lint tooling | B |
| 20 | `.typos.toml` | missing | out of scope: lint tooling | B |
| 21 | `BUILD.bazel` | holds `# gazelle:map_kind` | intentional: AGENTS.md hand-back runs `bazel run //:gazelle`, and a directive applies only to its directory and below, so the baseline's copy in `tools/` would not reach `bun/` | B; https://github.com/bazel-contrib/bazel-gazelle#directives |
| 22 | `CONTRIBUTING.md` | missing | out of scope: documentation | B |
| 23 | `LICENSE` | — | equal | B |
| 24 | `MODULE.bazel` | toolchain registered dev-only | intentional: AGENTS.md "registering a toolchain is the consuming module's job" | B |
| 24a | `MODULE.bazel` | `bazel_skylib`, `bazelrc-preset.bzl` dev-only; newer dev versions | intentional: constitution IV | B |
| 25 | `MODULE.bazel.lock` | generated | equal | B |
| 26 | `README.md` | missing | out of scope: documentation | B |
| 27 | `REPO.bazel` | `ignore_directories` | intentional (row 1) | B |
| 28 | `e2e/smoke/.bazelrc` (empty) | missing | equivalent: an empty file sets nothing | B; https://bazel.build/run/bazelrc |
| 29 | `e2e/smoke/BUILD` (`build_test`) | `BUILD.bazel`, no test target | **closed**: R1 `//:version_test` (`diff_test`), R2 `//:toolchain_param_test` (tdd-log T006–T008). File name: equal (https://bazel.build/concepts/build-files) | B |
| 30 | `e2e/smoke/MODULE.bazel` | `module(name = …)`; non-dev `bazel_dep`s | **closed** (refactor record, tdd-log T020): remove `module()`, `dev_dependency = True` on `bazel_dep`s only; the extension and registration stay as a consumer writes them; `e2e/smoke` `bazel test //...` passes | B |
| 31 | `e2e/smoke/MODULE.bazel.lock` | generated | equal | B |
| 32 | `e2e/smoke/README.md` | missing | out of scope: documentation | B |
| 33 | `mylang/BUILD.bazel` | gazelle-generated deps | equal | B |
| 34 | `mylang/defs.bzl` | `BUN_TOOLCHAIN_TYPE`, `BunInfo` | intentional: constitution I; docstring gains `toolchain =` (R2) | B |
| 34a | `mylang/{toolchain,repositories,extensions}.bzl` | implementation moves to `bun/private/`, public files re-export | intentional: constitution I (R10) | B |
| 35 | `mylang/extensions.bzl` | `max_version` semver selection, no `print`, `integrity` tag | intentional: constitution VII — both are published behavior; the baseline's lexicographic pick is its own `# TODO: should be semver-aware` | B |
| 36 | `mylang/private/BUILD.bazel` | `package(default_visibility)` instead of per-target `visibility` | equivalent: both give each target the same visibility | B; https://bazel.build/concepts/visibility |
| 37 | `mylang/private/toolchains_repo.bzl` | `PLATFORMS` in separate `platforms.bzl` | **closed** (refactor record, tdd-log T019): move into `toolchains_repo.bzl`; R5 `selection_*_test` still pass and the swap mutation still fails exactly two of them | B |
| 37a | same | no `target_type` toolchains | intentional: constitution I | B |
| 37b | same | no `doc` on rule and attribute | out of scope: documentation | B |
| 37c | same | returns `repo_metadata` (baseline does not) | intentional: constitution V — the page says to declare reproducibility | B; https://bazel.build/rules/lib/builtins/repository_ctx#repo_metadata |
| 38 | `mylang/private/versions.bzl` | — | equal | B |
| 39 | `mylang/repositories.bzl` | `hasattr` guard removed | intentional: constitution V, FR-005 (R4) | B |
| 39b | same | `stripPrefix` | **closed** (refactor record, tdd-log T017): `strip_prefix` (R9) | https://bazel.build/rules/lib/builtins/repository_ctx#download_and_extract |
| 39a | same | versions not limited by `values`; `integrity` override | intentional: constitution III (verified pins for any version) and VII (published attribute) | B |
| 40 | `mylang/tests/BUILD.bazel` | contents | **closed** via R3, R5–R7 and row 41: `selection_*_test`, `exec_cfg_test`, `bun_bin_value_test`, `bun_bin_genrule_test`, `versions` suite, deletions (tdd-log T011–T015, T021–T024) | B |
| 41 | `mylang/tests/versions_test.bzl` | missing | **closed**: `//bun/tests:versions` (`versions_test.bzl`) — every `TOOL_VERSIONS` entry covers exactly `PLATFORMS` with `sha256-` values; red by mutation (drop a key) (tdd-log T024) | B |
| 42 | `mylang/toolchain.bzl` | no `TemplateVariableInfo` | **closed**: R7 `bun_bin_value_test`, `bun_bin_genrule_test` (expansion; tdd-log T021–T023); action inputs are a **gap** (R7) | B; make-variables doc |
| 42a | same | `BUN_BIN` = `File.path` | intentional: constitution V, make-variables doc (genrule runs in the execution root) | make-variables doc |
| 42b | same | no `target_tool_path` | intentional: constitution III | B |
| 42c | same | baseline tool attribute has no `cfg = "exec"` | **closed** in rules_bun: R6 `exec_cfg_test` (tdd-log T012–T013) | toolchains doc |
| 43 | `mylang/toolchain/BUILD.bazel` | no `target_type` | intentional: constitution I | B |
| 44 | `renovate.json` | `matchFileNames: ["**/MODULE.bazel"]` vs `matchFiles: ["MODULE.bazel"]` | intentional: constitution V (`matchFiles` was renamed) and IV (the glob also freezes `e2e/smoke`'s declared versions) | B; https://docs.renovatebot.com/configuration-options/#matchfilenames |
| 45 | `tools/BUILD.bazel` | no `doc_link_template`; gazelle `-exclude=bun/tests` | intentional (AGENTS.md: use the way the official tool defines): the baseline sets the unversioned `https://registry.build/flag/bazel?filter={flag}` by hand on bazelrc-preset 1.6.0, while 1.9.2's documented default is the versioned `https://registry.build/flag/bazel@{version}?filter={flag}`, so rules_bun keeps the default; the `-exclude` has no effect because the skylib gazelle plugin skips `*_test.bzl`, the only `.bzl` files left in `bun/tests` | B; bazelrc-preset.bzl 1.9.2 `bazelrc-preset.bzl:111-118`; bazel_skylib_gazelle_plugin `bzl/gazelle.go:49-50` |
| 46 | `tools/preset.bazelrc` | generated | equal | B |

### Paths without a baseline counterpart

| Path | Status | Source |
|---|---|---|
| `bun/private/providers.bzl` | intentional: constitution I (`BunInfo` is public through `defs.bzl`) | B `mylang/toolchain.bzl` (provider defined there) |
| `bun/private/semver.bzl`, `bun/tests/semver_test.bzl` | intentional (row 35) | B `mylang/extensions.bzl` TODO |
| `bun/private/platforms.bzl` | removed (row 37) | B `mylang/private/toolchains_repo.bzl` |
| `bun/private/{action,hardening,paths}.bzl`, `bun/tests/{action_test,hardening_test,platform_transition}.bzl` | removed (R3) | spec FR-003 |
| `bun/tests/platforms/BUILD.bazel` | test fixture: five literal platforms (R5) | https://bazel.build/rules/testing |
| `bun/tests/toolchain_test.bzl` (new) | test code for R5–R7 | https://bazel.build/rules/testing |
| `e2e/smoke/verify.bzl` | test fixture for R1, R2 | https://bazel.build/extending/toolchains |
| `e2e/smoke/verify_test.bzl` (new) | test code for R2 | https://bazel.build/rules/testing |
| `bun/private/{toolchain,repositories,extensions}.bzl` (new) | implementation moved by R10 | constitution I |
| `e2e/smoke/.bazelversion` | out of scope: presubmit/Bazel pin alignment (spec Assumptions) | https://github.com/bazelbuild/bazelisk#how-does-bazelisk-know-which-bazel-version-to-run |

### Documentation checks with no file counterpart

| Topic | Result | Source |
|---|---|---|
| Execution toolchain with `exec_compatible_with` in a hub repository | equal | toolchains doc; B `mylang/private/toolchains_repo.bzl` docstring |
| `extension_metadata(reproducible = True)`, `os_dependent`/`arch_dependent = False` | equal | module extensions doc |
| Only the root module may rename (`is_root`) | equal | module extensions doc |
| `download_and_extract` with `integrity` | equal | repository rules doc |
| `download_and_extract` `stripPrefix` | closed by R9 (deprecated name) | `repository_ctx` doc |
| Genrule accepting a toolchain type in `toolchains` | used by R7 | genrule doc; rules-template PR #188 |
| `toolchain =` on actions under automatic exec groups | used by R2 | auto-exec-groups doc |

**Gaps**: (1) a genrule's inputs from a toolchain type are undocumented (R7); (2) no documented
API lets an analysistest see an action's `toolchain` value (R2). Both are reported, not worked
around.
