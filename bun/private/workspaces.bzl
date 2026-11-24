"""Workspace members and manifests compared with `bun.lock` (FR-006, research R9).

Members are the directories the root `package.json`'s `workspaces` patterns match, by Bun's glob
syntax (bun.com `runtime/glob`), with the semantics the pinned Bun 1.4.4 shows and
`bun/tests/npm/workspaces` pins against it: a negative pattern, wherever it stands in the list,
removes what any glob matched, not a directory listed by its path; wildcards do not
match a leading `.`; `{a,b}` expands within one segment; `**` enters no hidden directory and no
pattern enters `node_modules`; a
matched directory is a member when it holds `package.json`. Each member's four dependency maps,
as Bun reads and writes them (`package_dependencies`, `workspace_groups`), must equal the
lockfile's for it (the lockfile records `catalog:` and `workspace:` specifiers literally); the
root's catalogs and overrides must equal the lockfile's. Errors are returned as values.
"""

load(":bun_lockfile.bzl", "lockfile_overrides")
load(":bun_override_map.bzl", "override_field", "override_map_changed", "override_map_parse_append")
load(":bun_package.bzl", "package_dependencies", "workspace_groups")
load(":lockfile.bzl", "DEPENDENCY_KINDS")

_REMEDY = "run `bun install` and commit bun.lock"

# Starlark has neither `while` nor recursion; work lists are bounded by this.
_LIMIT = 1 << 30

_GLOB_CHARACTERS = "*?[{"

# The dependency kinds whose `catalog:` reference may name no catalog entry: Bun writes no key for
# such an optional or peer dependency and installs, as for any optional or peer dependency without a
# key (`may_stay_unresolved`, src/install/lockfile/bun.lock.rs L3297–L3299 @ bun-v1.4.4; feature 006
# BC-21, T176), while it refuses a `dependencies` or `devDependencies` one, at install ("<name>@catalog:
# not in catalog") and on loading ("Failed to resolve root prod dependency", L3301–L3345).
_MAY_STAY_UNRESOLVED = ["optionalDependencies", "peerDependencies"]

def workspace_patterns(manifest):
    """The `workspaces` patterns of a root `package.json`: an array, or an object's `packages`.

    Args:
        manifest: The decoded root `package.json`.

    Returns:
        The list of patterns; empty when the manifest has no `workspaces`.
    """
    workspaces = manifest.get("workspaces")
    if workspaces == None:
        return []
    if type(workspaces) == "dict":
        return list(workspaces.get("packages", []))
    return list(workspaces)

def _normalize(pattern):
    """Drops `./`, empty segments and a trailing `/`."""
    return "/".join([p for p in pattern.split("/") if p not in ("", ".")])

def _expand_braces(pattern):
    """`{a,b}` alternatives, nested ones included, as separate patterns."""
    result = []
    work = [pattern]
    for _ in range(_LIMIT):
        if not work:
            break
        p = work.pop()
        start = p.find("{")
        if start == -1:
            result.append(p)
            continue
        depth = 0
        end = -1
        commas = []
        for i in range(start, len(p)):
            c = p[i]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
            elif c == "," and depth == 1:
                commas.append(i)
        if end == -1:
            result.append(p)
            continue
        bounds = [start] + commas + [end]
        for j in range(len(bounds) - 1):
            work.append(p[:start] + p[bounds[j] + 1:bounds[j + 1]] + p[end + 1:])
    return sorted(result)

def _tokens(segment):
    """The tokens of one pattern segment, or `None` when a `[` is not closed (matches nothing)."""
    tokens = []
    i = 0
    for _ in range(len(segment) + 1):
        if i >= len(segment):
            break
        c = segment[i]
        if c == "*":
            tokens.append(("*",))
        elif c == "?":
            tokens.append(("?",))
        elif c == "[":
            close = segment.find("]", i + 2)
            if close == -1:
                return None
            body = segment[i + 1:close]
            negate = body[0] in "!^"
            if negate:
                body = body[1:]
            ranges = []
            k = 0
            for _ in range(len(body) + 1):
                if k >= len(body):
                    break
                if k + 2 < len(body) and body[k + 1] == "-":
                    ranges.append((body[k], body[k + 2]))
                    k += 3
                else:
                    ranges.append((body[k], body[k]))
                    k += 1
            tokens.append(("[", negate, ranges))
            i = close
        else:
            tokens.append(("=", c))
        i += 1
    return tokens

def _token_matches(token, c):
    if token[0] == "?":
        return True
    if token[0] == "=":
        return token[1] == c
    inside = [r for r in token[2] if r[0] <= c and c <= r[1]]
    return (not inside) if token[1] else bool(inside)

def _segment_matches(tokens, name):
    """Whether a directory name matches a segment's tokens; wildcards do not match a leading `.`."""
    if tokens == None:
        return False
    if name.startswith(".") and not (tokens and tokens[0] == ("=", ".")):
        return False
    row = [True] + [False] * len(name)
    for token in tokens:
        if token[0] == "*":
            following = [row[0]]
            for j in range(1, len(name) + 1):
                following.append(following[j - 1] or row[j])
        else:
            following = [False]
            for j in range(1, len(name) + 1):
                following.append(row[j - 1] and _token_matches(token, name[j - 1]))
        row = following
    return row[len(name)]

def _path_matches(segments, path):
    """Whether a member path matches a pattern's segments, `**` standing for any segments."""
    parts = path.split("/") if path else []
    row = [True] + [False] * len(parts)
    for segment in segments:
        if segment == "**":
            following = [row[0]]
            for j in range(1, len(parts) + 1):
                following.append(following[j - 1] or row[j])
        else:
            tokens = _tokens(segment)
            following = [False]
            for j in range(1, len(parts) + 1):
                following.append(row[j - 1] and _segment_matches(tokens, parts[j - 1]))
        row = following
    return row[len(parts)]

def _glob(segments, list_dir):
    """The directories a pattern's segments match, walking only what the pattern can reach."""
    found = {}
    seen = {}
    work = [("", 0)]
    compiled = [None if s == "**" else _tokens(s) for s in segments]
    for _ in range(_LIMIT):
        if not work:
            break
        path, i = work.pop()
        key = "{}|{}".format(i, path)
        if key in seen:
            continue
        seen[key] = True
        if i == len(segments):
            found[path] = True
            continue
        for child in list_dir(path):
            if child == "node_modules":
                continue
            child_path = path + "/" + child if path else child
            if segments[i] == "**":
                if not child.startswith("."):
                    work.append((child_path, i))
            elif _segment_matches(compiled[i], child):
                work.append((child_path, i + 1))
        if segments[i] == "**":
            work.append((path, i + 1))
    return found.keys()

def match_members(patterns, list_dir, has_manifest, file):
    """The workspace members a root `package.json`'s `workspaces` patterns select.

    Args:
        patterns: The patterns, in order (`workspace_patterns`).
        list_dir: Directory path relative to the root (`""` for the root) -> its child directory
            names.
        has_manifest: Directory path -> whether it holds `package.json`.
        file: The root `package.json`'s name, for errors.

    Returns:
        `struct(value, error)`; `value` is the sorted member paths.
    """
    members = {}
    negatives = []
    for raw in patterns:
        negative = raw.startswith("!")
        base = _normalize(raw[1:] if negative else raw)

        # Braces expand within one segment: Bun 1.4.4 matches nothing for `{a/b,c}`.
        expansions = [[]]
        for segment in base.split("/") if base else []:
            expansions = [e + [a] for e in expansions for a in _expand_braces(segment)]
        for segments in expansions:
            pattern = "/".join(segments)
            if negative:
                negatives.append(segments)
            elif [c for c in _GLOB_CHARACTERS.elems() if c in pattern]:
                for path in _glob(segments, list_dir):
                    if path and has_manifest(path):
                        members.setdefault(path, "glob")
            else:
                if not pattern or not has_manifest(pattern):
                    return _error('{}: the workspace "{}" holds no package.json; {}'.format(file, raw, _REMEDY))
                members[pattern] = "path"
    for segments in negatives:
        for path, how in members.items():
            if how == "glob" and _path_matches(segments, path):
                members.pop(path)
    return struct(value = sorted(members.keys()), error = None)

def _error(message):
    return struct(value = None, error = message)

def manifest_catalogs(manifest):
    """The catalogs of a root `package.json`: top level and under `workspaces` (bun.com pm/catalogs).

    Args:
        manifest: The decoded root `package.json`.

    Returns:
        `struct(catalog, catalogs)`.
    """
    workspaces = manifest.get("workspaces")
    nested = workspaces if type(workspaces) == "dict" else {}
    catalog = dict(manifest.get("catalog", {}))
    catalog.update(nested.get("catalog", {}))
    catalogs = dict(manifest.get("catalogs", {}))
    catalogs.update(nested.get("catalogs", {}))
    return struct(catalog = catalog, catalogs = catalogs)

def resolve_catalog(name, spec, catalogs):
    """The version range a dependency specifier stands for, through `catalog:` references.

    Args:
        name: The dependency's name.
        spec: Its specifier, such as `1.0.0`, `catalog:` or `catalog:<name>`.
        catalogs: `struct(catalog, catalogs)` of the root `package.json`.

    Returns:
        `struct(value, error)`; `value` is the specifier itself unless it is a `catalog:` reference.
    """
    if not spec.startswith("catalog:"):
        return struct(value = spec, error = None)
    which = spec[len("catalog:"):]

    # `catalog:` and `catalog:default` name one catalog, `catalog` and `catalogs.default`, looked up
    # under the spelling the reference names first (feature 006 T180).
    # Bun: src/install/lockfile/CatalogMap.rs L48–L101 @ bun-v1.4.4
    default = catalogs.catalogs.get("default", {})
    if which == "":
        tables = [catalogs.catalog, default]
    elif which == "default":
        tables = [default, catalogs.catalog]
    else:
        tables = [catalogs.catalogs.get(which, {})]
    for table in tables:
        if type(table) == "dict" and name in table:
            return struct(value = table[name], error = None)
    return _error('"{}": "{}" names no entry of the {} in the root package.json'.format(
        name,
        spec,
        'default catalog ("catalog" or "catalogs.default")' if which in ["", "default"] else 'catalog "{}"'.format(which),
    ))

def _difference(file, what, declared, recorded):
    """The first difference of two maps, as an English error, or `None`."""
    for key in sorted({k: None for k in declared.keys() + recorded.keys()}.keys()):
        if key not in recorded:
            return '{}: {} "{}": {} is not in bun.lock; {}'.format(file, what, key, json.encode(declared[key]), _REMEDY)
        if key not in declared:
            return '{}: bun.lock records {} "{}": {}, which the file does not declare; {}'.format(file, what, key, json.encode(recorded[key]), _REMEDY)
        if json.encode(declared[key]) != json.encode(recorded[key]):
            return '{}: {} "{}" is {}, but bun.lock records {}; {}'.format(
                file,
                what,
                key,
                json.encode(declared[key]),
                json.encode(recorded[key]),
                _REMEDY,
            )
    return None

def _override_difference(file, field, subject):
    """The error naming the first rule `override_map_changed` found (research R6)."""
    if subject.recorded == None:
        return '{}: {} "{}": {} is not in bun.lock; {}'.format(file, field, subject.rule, json.encode(subject.declared), _REMEDY)
    if subject.declared == None:
        return '{}: bun.lock records {} "{}": {}, which the file does not declare; {}'.format(file, field, subject.rule, json.encode(subject.recorded), _REMEDY)
    return '{}: {} "{}" is {}, but bun.lock records {}; {}'.format(
        file,
        field,
        subject.rule,
        json.encode(subject.declared),
        json.encode(subject.recorded),
        _REMEDY,
    )

def compare_manifests(lockfile, manifests, lock_file):
    """Compares the root and member manifests with the lockfile.

    The root's overrides are compared as the pinned Bun's frozen install compares them: both
    sides parsed into rules, then `OverrideMap::changed` (feature 007, research R1).

    Args:
        lockfile: The value `read_lockfile` returns.
        manifests: Member path (`""` for the root) -> `struct(file, value)`, `value` the decoded
            `package.json`.
        lock_file: The lockfile's label, for errors.

    Returns:
        `struct(value = None, error)`; `error` names the file, the package and the difference.
    """
    root = manifests[""]
    catalogs = manifest_catalogs(root.value)
    for path in sorted(manifests.keys()):
        manifest = manifests[path]
        workspace = lockfile.workspaces.get(path)
        if workspace == None:
            return _error("{}: the workspace member {} is not in bun.lock; {}".format(manifest.file, path, _REMEDY))
        groups = workspace_groups(package_dependencies(manifest.value, is_main = path == ""))
        for kind in DEPENDENCY_KINDS:
            declared = groups[kind]
            difference = _difference(manifest.file, kind, declared, getattr(workspace, kind))
            if difference:
                return _error(difference)
            if kind in _MAY_STAY_UNRESOLVED:
                continue
            for name, spec in sorted(declared.items()):
                resolved = resolve_catalog(name, spec, catalogs)
                if resolved.error:
                    return _error("{}: {} {}; {}".format(manifest.file, kind, resolved.error, _REMEDY))

    difference = _difference(root.file, "catalog", catalogs.catalog, lockfile.catalog) or _difference(root.file, "catalogs", catalogs.catalogs, lockfile.catalogs)
    if difference:
        return _error(difference)
    declared = override_map_parse_append(root.value, root.file, [manifests[path].value for path in sorted(manifests.keys()) if path])
    if declared.error:
        return declared
    recorded = lockfile_overrides(lockfile.overrides, lock_file)
    if recorded.error:
        return recorded
    subject = override_map_changed(declared.value, recorded.value)
    if subject:
        return _error(_override_difference(root.file, override_field(root.value) or "overrides", subject))
    return struct(value = None, error = None)
