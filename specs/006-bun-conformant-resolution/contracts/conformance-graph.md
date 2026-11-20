# Contract: Conformance Graph and Test

Internal to the repository's tests (not public API). Both sides of the comparison produce this form;
the test compares them as research R8 states.

## Graph JSON

```json
{
  "project": "bun/tests/npm/fixtures/dependency_conflict",
  "holders": {
    "": { "a": "e:1", "b": "e:0", "x": "e:3", "y": "e:4", "z": "e:5" },
    "packages/w1": { "lib": "w:packages/lib" }
  },
  "entries": [
    { "name": "b", "version": "1.0.0", "links": {} },
    { "name": "b", "version": "2.0.0", "links": {} }
  ]
}
```

- `holders`: workspace path (`""` for the root) → dependency name → target. A target is
  `e:<index>` (an entry of `entries`) or `w:<path>` (a workspace).
- `entries`: one per Bun store directory (oracle) or per ruleset instance reached in the host's
  platform class (ruleset). `links` as for holders; a package's own folder is not a link. A ruleset
  entry whose instance `status` is not `ok` carries it as `status` (the hub fails analysis of it),
  and `"unfetched": true` when that is because rules_bun does not fetch the entry (ID-4).
- Indices are local to one graph; nothing is compared by index or directory name.

## Ruleset side

The dev-only extension of `bun/tests/npm/fixture_results.bzl` writes, per project,
`"classes": [{"platforms": [[os, cpu, libc], …], "graph": <Graph JSON>}]` into
`@npm_fixture_results`, from `resolve.bzl`'s output (the function the hub uses). `os`, `cpu`, `libc`
are npm values (`linux`, `x64`, `glibc`); `libc` is `null` off Linux.

## Oracle side

`bun install --frozen-lockfile --ignore-scripts --linker isolated --registry=<loopback>` in a copy of
the project, empty cache, then the graph is read from the file system (research R7):
`node_modules/<name>` of the root and of each workspace, and
`node_modules/.bun/<dir>/node_modules/<name>` of each store directory except
`node_modules/.bun/node_modules`; `name`/`version` from the linked package's `package.json`.

## Test interface

| Item | Value |
|---|---|
| Targets | `//bun/tests/npm/conformance:conformance_test` (Bun 1.4.4, in `bazel test //...`); `//bun/tests/npm/conformance:conformance_1_4_2_test` (`target_compatible_with` the `bun_1_4_2` value, run with `--platforms=//bun/tests/npm/conformance:host_bun_1_4_2`) |
| Projects | every `bun.lock` under `bun/tests/npm/fixtures/`, `bun/tests/npm/scale/`, `bun/tests/integration/workspaces/`, `bun/tests/npm/conformance/bun_1_4_2/`; a fixed, asserted list of not-applicable projects with reasons |
| Exclusions | `ID-1` (`--ignore-scripts`), `ID-2` (host class only), `ID-3` (`node_modules/.bun/node_modules` and root fallbacks not read), `ID-4` (the `status` of an entry marked `unfetched` is not a difference; its links are compared). Named in the test; nothing else excluded. |
| Red mode | `RULES_BUN_CONFORMANCE_RED=1`: one ruleset edge is redirected; the test must fail naming it |
| Failure text | `<project>: <holder or name@version (its other bindings)> links "<dep>" to <ruleset target>, Bun links it to <oracle target>` (a target: `name@version (its bindings)`, `workspace "<path>"`, or "no link"), for the first link, walking down from the holders, whose targets differ in `name@version`; when every holder agrees all the way down, `<project>: <name@version (bindings)> is <n> entries in the ruleset, Bun installs it as <m>` (entry counts, research R8); `<project>: the ruleset fails (<error>), Bun installs the lockfile`; when every link and count agrees, `<project>: <name@version (bindings)> fails analysis in the ruleset (<status>), Bun installs it`, for a `status` not marked `unfetched` |
| Identity | an entry is its `name@version`; a package the ruleset holds at no registry version (`file:`, a URL: bun.lock records no version for it) is identified by its name on both sides |
| Oracle files | a project's own `archives/`; tarballs a lockfile names at another URL are served as the integration test owning the project serves them (`EXTRA_FILES`) |
| 1.4.2 lockfiles | compared by both targets, each with its own toolchain's Bun |
| 1.4.2 extra failure | `<project>: Bun 1.4.2 links this lockfile differently from Bun 1.4.4, which the ruleset follows (<first difference>); the ruleset cannot follow both (constitution V)` |
