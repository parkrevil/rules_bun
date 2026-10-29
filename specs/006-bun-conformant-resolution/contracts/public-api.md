# Contract: rules_bun Public API after feature 006

Constitution I: the public API is `bun/*.bzl`, `//bun/toolchain:execution_type`,
`//bun/toolchain:target_type`, `//bun/platforms/libc:libc` with its values, and the targets and
`defs.bzl` symbols the module extensions generate under their documented naming rules. This feature
adds, removes and renames nothing (FR-014, P4).

## Unchanged symbols

Every rule, macro, provider, module extension, tag class, attribute and generated target name of
features 001–005 stays. `:node_modules/<package>` and `:node_modules/<package>/bin/<bin>` keep their
names. Repositories named `<name>__...` (instance IDs) are not public API (`_NPM_DOC`) and may
change.

## What a consumer can observe

Only where the ruleset linked something other than the pinned Bun (FR-015). Each row is covered by
the conformance test (a difference before, none after) and listed in the PR.

| Surface | Before (`main`) | After | BC |
|---|---|---|---|
| A package's optional dependency listed under `unresolved` while another package of that name is in the tree | linked to that package | not linked | BC-1 |
| A workspace named like a package the root aliases | links the root's or the aliased package's dependencies | links its own (`./<name>/<dep>`) | BC-2 |
| An optional or peer dependency of the root or a workspace without a key | evaluation fails ("declares …, which bun.lock lists no entry for") | not linked; no failure | BC-3 |
| A registry package's dependency on a workspace member | not linked | linked to the member | BC-4 |
| A package's peer nothing provides and the lockfile does not resolve | evaluation fails (`missing_peer`) | not linked; no failure | BC-5 |
| Two keys holding one `name@version` whose walks find different versions | one instance per key, each with its walk's version | one package, bound as Bun's row evidence decides | BC-6 |
| A non-optional dependency whose package's `os`/`cpu` exclude the target platform | carried on every platform | not carried on that platform | BC-7 |
| The dependencies of an unfetched entry (`unsupported_reason`) | not followed | followed: they get instances; the entry still fails analysis, no target name changes | BC-8 |
| `_NPM_DOC` | states the old rules above | states Bun's, the Intentional Differences, and the CI runner labels the tests ran on | — |

Diagnostics added: a lockfile Bun 1.4.4 refuses to load fails evaluation with an English message
naming the `bun.lock` label and the key or field (FR-004); a malformed `unresolved` fails naming the
entry and the field without printing its value. No other diagnostic changes text, except those of
BC-3 and BC-5, which disappear.
