# Contract: rules_bun Public API after feature 007

Constitution I: the public API is `bun/*.bzl`, `//bun/toolchain:execution_type`,
`//bun/toolchain:target_type`, `//bun/platforms/libc:libc` with its values, and the targets and
`defs.bzl` symbols the module extensions generate under their documented naming rules. This feature
adds, removes and renames none of them (FR-017, P4).

## Unchanged

Every rule, macro, provider, module extension, tag class, attribute and generated target name of
`main`. The `npm` extension's `translate_lock` tag keeps its attributes; the hub and package
repositories keep their names.

## What a consumer can observe: evaluation of `npm.translate_lock`

| Root `package.json` holds, with a `bun.lock` the pinned Bun wrote for it | `main` | after |
|---|---|---|
| an `overrides`/`resolutions` rule Bun skips with a warning: a non-string, `""` or `"-"` value, an empty key, a `patch:` value, a key Bun's selector parser rejects (BC-1) | fails | passes; the rule is not applied, as in Bun |
| `{"q": {".": "1.2.3"}}` (BC-2) | fails | passes |
| `"q@^1.0.0": "1.2.3"` (BC-3) | fails | passes |
| `"//"`-prefixed keys (BC-4) | fails | passes |
| `resolutions` `"**/q"`, `"a/**/q"` (BC-5) | fails | passes |
| a top-level `catalog`/`catalogs` next to `workspaces.catalog`, or without `workspaces` (BC-6) | fails | passes; only the catalogs Bun reads are compared and resolved through |
| a catalog entry that is not a string (BC-6) | fails | passes |
| `overrides` keys in Yarn path form, `resolutions` keys in pnpm form, whitespace around `>`, a `>` inside a range, an `npm:` range in a key (BC-7) | fails | passes |
| a flat rule next to rules scoped under its name (BC-8) | fails | passes |
| any of the above with a rule changed after `bun install` | fails | fails (FR-006) |
| `overrides` or `resolutions` that is not an object | fails | fails (Bun refuses it) |

"Passes" means evaluation succeeds and the build links what the pinned Bun links; each row is
covered by a corpus project of research R7 in the conformance test, before (red) and after (0
differences), on the CI runners `ubuntu-latest`, `macos-latest` and `windows-latest`.

## Error messages

- Removed: `"<file>: the <field> entry "<key>" has a form rules_bun cannot compare with bun.lock;
  use a form bun.com documents …"`. No form the pinned Bun parses reaches an error any more.
- A stale rule: `rules_bun: <file>: <field> "<rule>" is <value>, but bun.lock records <value>; run
  `bun install` and commit bun.lock`, or the forms naming a rule only one side holds, as for the
  dependency maps today. `<rule>` is `[<parent>[@<range>]>]<target>[@<range>]`.
- A non-object field: `rules_bun: <file>: "<field>" expects a map of package names to versions,
  which Bun requires; make it an object`. The first part is Bun's own refusal (`not_an_object`,
  OverrideMap.rs L1140–L1150); the remedy does not say to run `bun install`, which Bun refuses for
  such a project (research R6).

## Documentation

`translate_lock`'s `doc` and `_NPM_DOC` (`bun/private/npm_extension.bzl`) state the forms compared
and skipped and the catalogs read, naming the tests and CI runners that cover them (FR-018,
research R11). They are documentation of existing behavior, not new API.

## Not consumer-visible

`overrides.bzl` is removed and `bun_override_map.bzl` added under `bun/private/` (not public API).
The integration tests' inner Bazel version (dev-only, research R10) does not reach consumers.
