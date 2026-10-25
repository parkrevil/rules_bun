"""Normalization of `package.json` overrides to the form `bun.lock` records (FR-006, research R9).

bun.com (`pm/overrides`): "When a `package.json` has both fields, Bun uses only `"overrides"` and
does not read `"resolutions"`"; `overrides` accepts the npm object form, the pnpm `>` form and a
parent with a version range, `resolutions` Yarn's path form (with `**`); "Bun supports only one
parent level. It ignores `a>b>c`, `a/b/c`, and deeper object nesting with a warning." Each form
maps to the nested object form the lockfile records, as the fixtures the pinned Bun wrote show; a
form no fixture pins is an error rather than a guess. Errors are returned as values.
"""

load(":lockfile.bzl", "split_key")

_FORMS = ('use a form bun.com documents in pm/overrides that rules_bun reads: "b", "a>b", ' +
          '"a@<range>>b" or {"a": {".": ..., "b": ...}} in "overrides", "b", "a/b" or "**/a/**/b" in "resolutions"')

def _error(message):
    return struct(value = None, error = message)

def _unread(file, field, key):
    return _error('{}: the {} entry "{}" has a form rules_bun cannot compare with bun.lock; {}'.format(file, field, key, _FORMS))

def _path(field, key):
    """The package names of a rule key, or `None` for a form rules_bun does not read."""
    if field == "overrides":
        return key.split(">")
    segments = split_key(key)
    if "**" not in segments:
        return segments
    if len(segments) == 4 and segments[0] == "**" and segments[2] == "**" and "**" not in [segments[1], segments[3]]:
        return [segments[1], segments[3]]
    return None

def normalize_overrides(manifest, file):
    """The overrides of a root `package.json`, in the nested form `bun.lock` records.

    Args:
        manifest: The decoded `package.json`.
        file: The file's name, for errors.

    Returns:
        `struct(value, error)`; `value` maps a package (or `<parent>`, `<parent>@<range>`) to a
        version or to a map of the overridden dependencies under that parent.
    """
    if "overrides" in manifest:
        field = "overrides"
    elif "resolutions" in manifest:
        field = "resolutions"
    else:
        return struct(value = {}, error = None)
    rules = manifest[field]
    if type(rules) != "dict":
        return _error('{}: "{}" is not an object; {}'.format(file, field, _FORMS))

    result = {}
    for key, value in rules.items():
        if field == "overrides" and type(value) == "dict":
            for child_value in value.values():
                if type(child_value) != "string":
                    return _unread(file, field, key)
            if type(result.get(key, {})) != "dict":
                return _unread(file, field, key)
            result[key] = dict(result.get(key, {}), **value)
            continue
        if type(value) != "string":
            return _unread(file, field, key)
        path = _path(field, key)
        if path == None:
            return _unread(file, field, key)
        if len(path) == 1:
            if path[0] in result:
                return _unread(file, field, key)
            result[path[0]] = value
        elif len(path) == 2:
            parent = result.setdefault(path[0], {})
            if type(parent) != "dict":
                return _unread(file, field, key)
            parent[path[1]] = value

        # Deeper chains: ignored, as Bun ignores them.
    return struct(value = result, error = None)
