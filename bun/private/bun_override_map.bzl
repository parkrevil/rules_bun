"""Bun's override rules, carried over from bun-v1.4.4 (feature 007, research R1, R5).

`override_selector.rs` parses the key of an `overrides` or `resolutions` rule into a target
package and an optional parent, each a name with an optional range. `OverrideMap.rs` turns the
root `package.json`'s rules (`parse_append`) and the lockfile's (`put_lockfile_rule`, called by
`bun_lockfile.bzl`'s `_parse_overrides`) into one map of flat rules and a list of scoped rules,
and `changed` compares two such maps, as the pinned Bun's frozen install compares the lockfile's
rules with `package.json`'s (`Package::Diff`, Package.rs L1048–L1059).

The map is `struct(map, scoped, scoped_names)`: `map` maps a target name to the `Dependency` of
its value, `scoped` lists `struct(parent, target_range, dep)`, `scoped_names` holds each target
name of `scoped`. Names stand in for Bun's name hashes. A rule Bun skips with a warning is
skipped silently. Errors are returned as values.

Starlark has no `while`: each Bun loop is a `for` over a bound.
"""

load(
    ":bun_install_types.bzl",
    "VERSION_TAG",
    "dependency_parse",
    "dependency_version",
    "new_dependency",
    "split_name_and_maybe_version",
    "version_tag_infer",
)
load(":bun_package.bzl", "package_dependencies")
load(":lockfile.bzl", "DEPENDENCY_KINDS")

# `SelectorError` (SELECTOR L17-L23): why a key selects nothing.
SELECTOR_ERROR = struct(
    EMPTY_NAME = "EmptyName",
    INVALID_NAME = "InvalidName",
    TOO_DEEP = "TooDeep",
    EMPTY_RANGE = "EmptyRange",
)

# Starlark has no `while`; Bun's open loops are bounded by this.
_LIMIT = 1 << 30

# `u8::is_ascii_whitespace`, which `trim_ascii` trims.
_ASCII_WHITESPACE = " \t\n\f\r"

def _selector_error(error):
    """`Err(SelectorError)`: a key that selects nothing.

    Bun: src/install/lockfile/override_selector.rs L17–L23 @ bun-v1.4.4
    """
    return struct(value = None, error = error)

# --- override_selector.rs ------------------------------------------------------------------------

def parse_package_segment(segment):
    """`parse_package_segment`: `name` or `name@range`, with `is_bare_scope` inlined.

    Bun: src/install/lockfile/override_selector.rs L25–L27 @ bun-v1.4.4
    Bun: src/install/lockfile/override_selector.rs L29–L52 @ bun-v1.4.4

    Args:
        segment: One package of an override key.

    Returns:
        `struct(value, error)`; `value` is `struct(name, range)`, `range` `""` for every version.
    """
    if not segment:
        return _selector_error(SELECTOR_ERROR.EMPTY_NAME)
    name, range = split_name_and_maybe_version(segment)
    if not name:
        return _selector_error(SELECTOR_ERROR.EMPTY_NAME)
    if name.startswith("@") and "/" not in name:
        return _selector_error(SELECTOR_ERROR.INVALID_NAME)
    range = range or ""

    # `npm:^1` is the range `^1`; `npm:other` and `npm:other@^1` are aliases and keep the prefix.
    if range.startswith("npm:"):
        rest = range[len("npm:"):]
        if not rest or version_tag_infer(rest) == VERSION_TAG.NPM:
            range = rest
    if not range and len(segment) > len(name):
        return _selector_error(SELECTOR_ERROR.EMPTY_RANGE)
    return struct(value = struct(name = name, range = range), error = None)

def parse_selector(key):
    """`parse_selector`: the parent and target of an override key.

    Bun: src/install/lockfile/override_selector.rs L54–L68 @ bun-v1.4.4

    Args:
        key: An `overrides` or `resolutions` key.

    Returns:
        `struct(value, error)`; `value` is `struct(parent, target)`, each `struct(name, range)`
        (`parent` may be `None`), `error` a `SELECTOR_ERROR`.
    """
    if key.startswith("//"):
        return struct(value = struct(parent = None, target = struct(name = key, range = "")), error = None)
    delimiter = _pnpm_delimiter(key)
    if delimiter != None:
        return _parse_pnpm(key, delimiter)
    return _parse_yarn_path(key)

def _pnpm_delimiter(key):
    """`pnpm_delimiter`: the first `>` that does not come after a space, `|`, `@` or `:`.

    Bun: src/install/lockfile/override_selector.rs L72–L82 @ bun-v1.4.4
    """
    start = 1
    for _ in range(_LIMIT):
        if start >= len(key):
            break
        i = key.find(">", start)
        if i == -1:
            return None
        if key[i - 1] in [" ", "|", "@", ":"]:
            start = i + 1
        else:
            return i
    return None

def _parse_pnpm(key, delimiter):
    """`parse_pnpm`: `parent>name`, each side trimmed.

    Bun: src/install/lockfile/override_selector.rs L84–L98 @ bun-v1.4.4
    """
    parent = key[:delimiter].strip(_ASCII_WHITESPACE)
    name = key[delimiter + 1:].strip(_ASCII_WHITESPACE)
    if not name:
        return _selector_error(SELECTOR_ERROR.EMPTY_NAME)
    if _pnpm_delimiter(name) != None:
        return _selector_error(SELECTOR_ERROR.TOO_DEEP)
    parent = parse_package_segment(parent)
    if parent.error:
        return parent
    target = parse_package_segment(name)
    if target.error:
        return target
    return struct(value = struct(parent = parent.value, target = target.value), error = None)

def _next_token(key, pos):
    """`next_token`: the `/`-delimited token at `pos` and the position after its delimiter.

    Bun: src/install/lockfile/override_selector.rs L100–L106 @ bun-v1.4.4
    """
    i = key.find("/", pos)
    if i == -1:
        return key[pos:], None
    return key[pos:i], i + 1

def _parse_yarn_path(key):
    """`parse_yarn_path`: `[**/]parent/[**/]name`; `**` segments are dropped.

    Bun: src/install/lockfile/override_selector.rs L108–L165 @ bun-v1.4.4
    """
    segments = []
    cursor = 0
    for _ in range(_LIMIT):
        if cursor == None:
            break
        start = cursor
        token, next = _next_token(key, start)
        cursor = next
        if not token:
            return _selector_error(SELECTOR_ERROR.EMPTY_NAME)
        if token == "**":
            if next == None:
                return _selector_error(SELECTOR_ERROR.EMPTY_NAME)
            continue
        end = start + len(token)
        if token.startswith("@"):
            if next == None:
                return _selector_error(SELECTOR_ERROR.INVALID_NAME)
            name, after = _next_token(key, next)
            cursor = after
            if not name:
                return _selector_error(SELECTOR_ERROR.EMPTY_NAME)
            end = next + len(name)

        # In `name@npm:@scope/other@^1` the `/` is part of the alias target, not a path separator.
        if "@npm:@" in key[start:end] and cursor != None:
            rest_start = cursor
            rest, after = _next_token(key, rest_start)
            cursor = after
            end = rest_start + len(rest)
        if len(segments) == 2:
            return _selector_error(SELECTOR_ERROR.TOO_DEEP)
        segments.append(key[start:end])

    if not segments:
        return _selector_error(SELECTOR_ERROR.EMPTY_NAME)
    if len(segments) == 1:
        target = parse_package_segment(segments[0])
        if target.error:
            return target
        return struct(value = struct(parent = None, target = target.value), error = None)
    parent = parse_package_segment(segments[0])
    if parent.error:
        return parent
    target = parse_package_segment(segments[1])
    if target.error:
        return target
    return struct(value = struct(parent = parent.value, target = target.value), error = None)

# --- OverrideMap.rs ------------------------------------------------------------------------------

def push_scoped(overrides, rule):
    """`OverrideMap::push_scoped`: replaces the rule with the same parent, parent range, target and target range.

    Bun: src/install/lockfile/OverrideMap.rs L644–L668 @ bun-v1.4.4

    Args:
        overrides: The map, changed in place.
        rule: `struct(parent, target_range, dep)`.
    """
    name = rule.dep.name
    if name in overrides.scoped_names:
        for i, existing in enumerate(overrides.scoped):
            same_parent = (existing.parent == None and rule.parent == None) or (
                existing.parent != None and rule.parent != None and
                existing.parent.name == rule.parent.name and existing.parent.version.literal == rule.parent.version.literal
            )
            if existing.dep.name == name and same_parent and existing.target_range.literal == rule.target_range.literal:
                overrides.scoped[i] = rule
                return
    else:
        overrides.scoped_names[name] = True
    overrides.scoped.append(rule)

def put_lockfile_rule(overrides, parent, target, value):
    """`OverrideMap::put_lockfile_rule`: one rule of a lockfile's `overrides`.

    Bun: src/install/lockfile/OverrideMap.rs L671–L737 @ bun-v1.4.4

    Args:
        overrides: The map, changed in place.
        parent: `struct(name, range)` or `None`.
        target: `struct(name, range)`.
        value: The rule's value.

    Returns:
        False when the value, the parent range or the target range does not parse.
    """
    target_range = lockfile_range(target.name, target.range, True)
    if target_range == None:
        return False
    parent_dep = None
    if parent != None:
        parent_version = lockfile_range(parent.name, parent.range, False)
        if parent_version == None:
            return False
        parent_dep = new_dependency(parent.name, parent_version, 0)
    is_flat = parent_dep == None and target_range.tag == VERSION_TAG.UNINITIALIZED
    version = dependency_parse(target.name, value)
    if version == None:
        return False
    dep = new_dependency(target.name, version, 0)
    if is_flat:
        overrides.map[target.name] = dep
    else:
        push_scoped(overrides, struct(parent = parent_dep, target_range = target_range, dep = dep))
    return True

def _is_selector_range(version, is_target):
    """`is_selector_range`: a parent is selected by its installed version, a target by how it is declared.

    Bun: src/install/lockfile/OverrideMap.rs L1081–L1087 @ bun-v1.4.4
    """
    if version.tag == VERSION_TAG.NPM:
        return is_target or not version.npm.is_alias
    if version.tag == VERSION_TAG.CATALOG:
        return is_target
    return False

def lockfile_range(name, range, is_target):
    """`lockfile_range`: the range of a lockfile rule's selector; `None` if it selects nothing.

    Bun: src/install/lockfile/OverrideMap.rs L1089–L1115 @ bun-v1.4.4

    Args:
        name: The selected package's name.
        range: The selector's range, `""` for every version.
        is_target: Whether it is the target's range rather than the parent's.

    Returns:
        The version, `UNINITIALIZED` for `""`, or `None`.
    """
    if not range:
        return dependency_version(VERSION_TAG.UNINITIALIZED, "")
    version = dependency_parse(name, range)
    if version != None and _is_selector_range(version, is_target):
        return version
    return None

def _is_comment_key(key):
    """`is_comment_key`: npm's `"//"` comment keys.

    Bun: src/install/lockfile/OverrideMap.rs L206–L209 @ bun-v1.4.4
    """
    return key.startswith("//")

def override_field(manifest):
    """`Field::of`: the field whose rules Bun reads, `"overrides"` whenever present.

    Bun: src/install/lockfile/OverrideMap.rs L166–L170 @ bun-v1.4.4

    Args:
        manifest: The decoded root `package.json`.

    Returns:
        `"overrides"`, `"resolutions"`, or `None` when it has neither.
    """
    for field in ["overrides", "resolutions"]:
        if field in manifest:
            return field
    return None

def override_map_parse_append(manifest, file, members):
    """`OverrideMap::parse_append`: the rules of a root `package.json`.

    The rules of the field `override_field` picks; a field that is not an object is refused, as
    Bun refuses to install the project (`not_an_object`).

    Bun: src/install/lockfile/OverrideMap.rs L802–L838 @ bun-v1.4.4
    Bun: src/install/lockfile/OverrideMap.rs L1140–L1150 @ bun-v1.4.4

    Args:
        manifest: The decoded root `package.json`.
        file: Its name, for errors.
        members: The decoded `package.json` of each workspace member, for `$<name>` values.

    Returns:
        `struct(value, error)`; `value` is the map.
    """
    overrides = struct(map = {}, scoped = [], scoped_names = {})
    field = override_field(manifest)
    if field == None:
        return struct(value = overrides, error = None)
    rules = manifest[field]
    if type(rules) != "dict":
        return struct(value = None, error = '{}: "{}" expects a map of package names to versions, which Bun requires; make it an object'.format(file, field))
    ctx = struct(manifest = manifest, members = members)
    if field == "overrides":
        _parse_from_overrides(overrides, ctx, rules)
    else:
        _parse_from_resolutions(overrides, ctx, rules)
    return struct(value = overrides, error = None)

def _parse_from_overrides(overrides, ctx, rules):
    """`parse_from_overrides`: a rule's value is a string, or an object of its children.

    Bun: src/install/lockfile/OverrideMap.rs L841–L955 @ bun-v1.4.4
    """
    for key, value in rules.items():
        if not key:
            continue
        if _is_comment_key(key):
            continue
        if type(value) == "string":
            _parse_string_rule(overrides, ctx, key, value)
            continue
        if type(value) != "dict":
            continue
        parent_selector = parse_package_segment(key)
        if parent_selector.error:
            continue
        parent_selector = parent_selector.value
        parent = _parse_parent(parent_selector)
        if parent == None:
            continue
        for child_key, child_value in value.items():
            if _is_comment_key(child_key):
                continue
            if type(child_value) == "dict":
                continue
            if type(child_value) != "string":
                continue
            if child_key == ".":
                _put_rule(overrides, ctx, None, parent_selector, child_value)
                continue
            selector = parse_selector(child_key)
            if selector.error or selector.value.parent != None:
                continue
            _put_rule(overrides, ctx, parent, selector.value.target, child_value)

def _parse_from_resolutions(overrides, ctx, rules):
    """`parse_from_resolutions`: each rule's value is a string.

    Bun: src/install/lockfile/OverrideMap.rs L959–L995 @ bun-v1.4.4
    """
    for key, value in rules.items():
        if not key:
            continue
        if _is_comment_key(key):
            continue
        if type(value) != "string":
            continue
        _parse_string_rule(overrides, ctx, key, value)

def _parse_string_rule(overrides, ctx, key, value):
    """`parse_string_rule`: a key read by `parse_selector`, for either field.

    Bun: src/install/lockfile/OverrideMap.rs L997–L1020 @ bun-v1.4.4
    """
    selector = parse_selector(key)
    if selector.error:
        return
    parent = None
    if selector.value.parent != None:
        parent = _parse_parent(selector.value.parent)
        if parent == None:
            return
    _put_rule(overrides, ctx, parent, selector.value.target, value)

def _put_rule(overrides, ctx, parent, target, value):
    """`put_rule`: a flat rule into `map`, any other into `scoped`.

    Bun: src/install/lockfile/OverrideMap.rs L1022–L1069 @ bun-v1.4.4
    """
    if value.startswith("patch:"):
        return
    is_flat = parent == None and not target.range
    dep = _parse_override_value(ctx, target.name, value)
    if dep == None:
        return
    target_range = _parse_range(dep.name, target.range, True)
    if target_range == None:
        return
    if is_flat:
        overrides.map[dep.name] = dep
    else:
        push_scoped(overrides, struct(parent = parent, target_range = target_range, dep = dep))

def _parse_parent(selector):
    """`parse_parent`: the parent of a rule, selected by a version range.

    Bun: src/install/lockfile/OverrideMap.rs L1192–L1206 @ bun-v1.4.4
    """
    version = _parse_range(selector.name, selector.range, False)
    if version == None:
        return None
    return new_dependency(selector.name, version, 0)

def _parse_range(name, range, is_target):
    """`parse_range`: the range of a `package.json` rule's selector; `None` if it selects nothing.

    Bun: src/install/lockfile/OverrideMap.rs L1208–L1245 @ bun-v1.4.4
    """
    if not range:
        return dependency_version(VERSION_TAG.UNINITIALIZED, "")
    version = dependency_parse(name, range)
    if version != None and _is_selector_range(version, is_target):
        return version
    return None

def _parse_override_value(ctx, key, value):
    """`parse_override_value`: the rule's dependency, stored under `key`; `None` to skip the rule.

    Bun: src/install/lockfile/OverrideMap.rs L1248–L1371 @ bun-v1.4.4
    """
    if not value:
        return None
    if value == "-":
        return None
    literal = value
    if value[0] == "$":
        literal = _reference(value, ctx.manifest, ctx.members)
        if literal == None:
            return None
    version = dependency_parse(key, literal)
    if version == None:
        return None
    return new_dependency(key, version, 0)

def _declared(manifest, name):
    """`declared_dependency`: the first string specifier of `name` in a workspace's four maps.

    Bun: src/install/lockfile/OverrideMap.rs L1373–L1380 @ bun-v1.4.4
    """
    for kind in DEPENDENCY_KINDS:
        dependencies = manifest.get(kind)
        if type(dependencies) == "dict" and type(dependencies.get(name)) == "string":
            return dependencies[name]
    return None

def _root_declared(manifest, name):
    """The specifier of the root package's first dependency named `name`, as Bun lists them.

    The overrides read the first entry of the name in the root package's dependency list, as
    `Package::parse` builds and sorts it (`package_dependencies`: dev, optional, prod, then peer
    entries; feature 006 T179, T182).

    Bun: src/install/lockfile/OverrideMap.rs L1286–L1297 @ bun-v1.4.4
    """
    for dependency in package_dependencies(manifest, is_main = True):
        if dependency.name == name and type(dependency.literal) == "string":
            return dependency.literal
    return None

def _reference(value, manifest, members):
    """The specifier an override value stands for: `value`, or for `$<name>` the declared one.

    A `$<name>` reference is the specifier the root declares for `<name>` (`_root_declared`), else
    the one every workspace that declares `<name>` declares; Bun ignores the rule, with a warning,
    when nothing declares it or the workspaces declare different specifiers (feature 006 T177, T179).

    Bun: src/install/lockfile/OverrideMap.rs L1278–L1335, L1405–L1452 @ bun-v1.4.4

    Returns:
        The specifier, or `None` for a rule Bun ignores.
    """
    if not value.startswith("$"):
        return value
    name = value[1:]
    declared = _root_declared(manifest, name)
    if declared != None:
        return declared
    found = None
    for member in members:
        declared = _declared(member, name)
        if declared == None:
            continue
        if found != None and found != declared:
            return None
        found = declared
    return found

def _selector_key(name, range):
    """`override_selector_key`: `name`, or `name@range`.

    Bun: src/install/lockfile/bun.lock.rs L1274–L1287 @ bun-v1.4.4
    """
    return name + "@" + range if range else name

def _rule_text(rule):
    """A rule as `[<parent>[@<range>]>]<target>[@<range>]`, for errors (research R6).

    Each side is the key `bun.lock` writes for it; the two are joined as the pnpm key
    `parse_pnpm` reads.

    Bun: src/install/lockfile/bun.lock.rs L1274–L1287 @ bun-v1.4.4
    Bun: src/install/lockfile/override_selector.rs L84–L98 @ bun-v1.4.4
    """
    text = _selector_key(rule.dep.name, rule.target_range.literal)
    if rule.parent != None:
        text = _selector_key(rule.parent.name, rule.parent.version.literal) + ">" + text
    return text

def _scoped_key(rule):
    """The order of `sort`: rules without a parent first, then parent name and range, target name and range.

    Bun: src/install/lockfile/OverrideMap.rs L558–L578 @ bun-v1.4.4
    """
    return (
        rule.parent != None,
        rule.parent.name if rule.parent != None else "",
        rule.parent.version.literal if rule.parent != None else "",
        rule.dep.name,
        rule.target_range.literal,
    )

def _sort(overrides):
    """`OverrideMap::sort`: the flat rules by name, the scoped rules by `_scoped_key`.

    Bun: src/install/lockfile/OverrideMap.rs L553–L579 @ bun-v1.4.4

    Returns:
        `(flat, scoped)`, each a list of `(key, rule)`; a flat rule is `struct(parent, target_range,
        dep)` with no parent and no range, so both lists compare alike.
    """
    flat = []
    for name in sorted(overrides.map.keys()):
        dep = overrides.map[name]
        rule = struct(parent = None, target_range = dependency_version(VERSION_TAG.UNINITIALIZED, ""), dep = dep)
        flat.append(((False, "", "", name, ""), rule))
    scoped = [(_scoped_key(rule), rule) for rule in sorted(overrides.scoped, key = _scoped_key)]
    return flat, scoped

def _first_difference(declared, recorded):
    """The first pair of two sorted rule lists that differs, by key, then by the value's literal.

    Both lists are sorted with unique keys, so the smaller of two unequal keys is a rule only its
    side holds.

    Bun: src/install/lockfile/OverrideMap.rs L509–L550 @ bun-v1.4.4
    """
    i, j = 0, 0
    for _ in range(len(declared) + len(recorded)):
        if i == len(declared) and j == len(recorded):
            return None
        if j == len(recorded) or (i < len(declared) and declared[i][0] < recorded[j][0]):
            rule = declared[i][1]
            return struct(rule = _rule_text(rule), declared = rule.dep.version.literal, recorded = None)
        if i == len(declared) or recorded[j][0] < declared[i][0]:
            rule = recorded[j][1]
            return struct(rule = _rule_text(rule), declared = None, recorded = rule.dep.version.literal)
        if declared[i][1].dep.version.literal != recorded[j][1].dep.version.literal:
            return struct(
                rule = _rule_text(declared[i][1]),
                declared = declared[i][1].dep.version.literal,
                recorded = recorded[j][1].dep.version.literal,
            )
        i, j = i + 1, j + 1
    return None

def override_map_changed(declared, recorded):
    """`OverrideMap::changed`: the first rule two maps hold differently.

    Bun returns only whether they differ: a different count of flat or scoped rules, else a pair
    of the lists `sort` orders whose names, parent range, target range or value differ. Each is
    compared by its literal (research R3). The first such pair, or the first rule only one side
    holds, is returned as the subject of the error (research R6).

    Bun: src/install/lockfile/OverrideMap.rs L503–L551 @ bun-v1.4.4

    Args:
        declared: The map of the root `package.json`.
        recorded: The map of `bun.lock`.

    Returns:
        `None` when they hold the same rules, else `struct(rule, declared, recorded)`: the rule as
        `[<parent>[@<range>]>]<target>[@<range>]` and each side's value literal, `None` on the side
        that lacks it.
    """
    declared_flat, declared_scoped = _sort(declared)
    recorded_flat, recorded_scoped = _sort(recorded)
    return _first_difference(declared_flat, recorded_flat) or _first_difference(declared_scoped, recorded_scoped)
