# Data Model: Close Feature 006's Follow-ups

Starlark values as the carry-over holds them; names stand in for Bun's name hashes, as in
feature 006 (`bun_lockfile.bzl`). Line numbers are of Bun's source at `bun-v1.4.4` (research
Part 1).

## PackageSelector (override_selector.rs L5–L10)

`struct(name, range)`: a package name and the text of its range, `""` when the rule applies to
every version. Produced by `parse_package_segment` (L29–L52) from `name` or `name@range`; an
`npm:` prefix of a range that is itself an npm range, or empty, is dropped (L41–L47).

## Selector (L12–L15)

`struct(parent, target)`: `parent` a `PackageSelector` or `None`, `target` a `PackageSelector`.
Produced by `parse_selector(key)` (L54–L68), which picks the pnpm parser when `pnpm_delimiter`
finds a `>` not after ` `, `|`, `@` or `:` (L72–L82), else the Yarn path parser (L108–L165).

**Errors** (`SelectorError`, L17–L23): `EmptyName`, `InvalidName` (a bare scope), `TooDeep` (more
than one parent), `EmptyRange` (`name@`). Each makes the rule skipped (`warn_selector_error`,
OverrideMap.rs L1152–L1190).

## Dependency (as feature 006 carries it)

`struct(name, version, behavior)`; `version` is `dependency_parse`'s value, with `tag` and
`literal`. A rule's parent, target range and value are each one.

## OverrideMap (OverrideMap.rs; the struct `bun_lockfile.bzl` already builds)

| Field | Value |
|---|---|
| `map` | target name → `Dependency` of the value: the flat rules (no parent, no target range) |
| `scoped` | list of `struct(parent, target_range, dep)`: `parent` a `Dependency` or `None`, `target_range` a version (`UNINITIALIZED` when empty), `dep` the value |
| `scoped_names` | target name → `True` for each name in `scoped` |

Two maps are built per comparison: one from `package.json` (NEW, `parse_append`) and one from
`bun.lock` (feature 006, `_parse_overrides`). Both insert through the same two steps: a flat rule
replaces the map's entry of its name; a scoped rule replaces the entry with the same parent name,
parent range literal, target name and target range literal, else is appended (`push_scoped`
L644–L668).

### How one `package.json` entry becomes rules (`Field::of` L166–L170)

```text
field = "overrides" if present, else "resolutions", else none (no rules)
field value not an object                    -> refusal (not_an_object L1140-L1150)
for each (key, value):
  key == ""                                  -> skip (L853-L860 / L969-L976)
  key starts with "//"                       -> skip (L862 / L977)
  value is a string                          -> string rule (parse_string_rule L997-L1020)
  overrides only: value is an object         -> object rule (below)
  otherwise                                  -> skip (L870-L880 / L982-L992)

string rule:  parse_selector(key) error      -> skip
              parent with a range that is no selector range (parse_parent, parse_range) -> skip
              put_rule(parent, target, value)

object rule:  parse_package_segment(key) error -> skip; parse_parent fails -> skip
              for each (child_key, child_value):
                child_key starts with "//"   -> skip (L894)
                child_value is an object     -> skip, TooDeep (L902-L905)
                child_value not a string     -> skip (L906-L916)
                child_key == "."             -> put_rule(None, key's selector, child_value) (L918-L927)
                parse_selector(child_key) has a parent or fails -> skip
                else                          -> put_rule(parent, target, child_value)

put_rule:     value starts with "patch:"     -> skip (L1031-L1042)
              value "" or "-"                -> skip (L1257-L1275)
              value "$<name>"                -> the declared specifier, or skip (L1278-L1335)
              value Dependency::parse fails  -> skip (L1345-L1363)
              target range no selector range -> skip
              is_flat (no parent, no range)  -> map[target.name] = dep
              else                           -> push_scoped(parent, target_range, dep)
```

### Comparison (`OverrideMap::changed` L503–L551, `sort` L553–L579)

Different `len(map)` or `len(scoped)` → changed. Else both sorted (map by name; scoped by
parent-less first, parent name, parent range literal, target name, target range literal) and
compared pairwise by names and literals (research R3). The first unequal pair, or the first rule
only one side holds, is the error's subject (research R6).

## CatalogMap (CatalogMap.rs, carried over in `bun_catalog_map.bzl`; the struct `bun_lockfile.bzl` already builds)

`struct(default, groups)`: `default` name → `Dependency` (the singular `catalog`); `groups`
group name → (name → `Dependency`), `catalogs.default` included as the group `"default"`.

### Which catalogs the root has (Package.rs L3418–L3440)

```text
has_workspaces = "workspaces" in manifest
found_any = False
if has_workspaces: found_any = parse_append(manifest["workspaces"])   # True if it holds catalog or catalogs
if has_workspaces and not found_any: parse_append(manifest)           # the top level
parse_append(obj): obj["catalog"] -> default; obj["catalogs"][g] -> groups[g];
                   entries whose value is not a string are skipped (L356-L358)
```

A non-object `workspaces` holds neither key, so the top level is read (US2 scenario 3).

## Corpus project (feature 006 R11)

`bun/tests/npm/fixtures/conformance_<name>/`: `package.json`, the `bun.lock` the pinned Bun wrote,
and the files `write_lockfiles.ts` declares; its `check` asserts what Bun wrote for the form. Its
Bun 1.4.2 lockfile is under `bun/tests/npm/conformance/bun_1_4_2/<name>/`, or the project is in
`NOT_APPLICABLE_1_4_2` with a reason. Lifecycle: added and run red on `main`'s comparison →
`tdd-log.md` row → change → green → 1.4.2 run.

## Reproduction test (US3)

`//bun/tests/integration:test_output_test` and its inner workspace
`bun/tests/integration/workspaces/test_output/`: N `bun_test` targets, each writing S bytes then a
unique marker line, then failing. Pass condition: every marker appears in the inner
`bazel test //:all --test_output=errors` output. N and S are chosen so that the Windows job with
inner Bazel 9.2.0 fails in 30 of 30 runs (research R10).
