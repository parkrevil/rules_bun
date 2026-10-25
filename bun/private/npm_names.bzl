"""The naming rule of the targets the `npm` extension generates (FR-012, FR-018)."""

# Bazel's target-name characters (concepts/labels, 9.2.0).
_NAME_CHARACTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!%-@^_\"#$&'()*+,;<=>?[]{|}~/."

def target_name(text):
    """A package or `bin` name as a target name: each character outside Bazel's set written `_`.

    Args:
        text: The name.

    Returns:
        The name with every character outside Bazel's target-name set replaced by `_`.
    """
    return "".join([c if c in _NAME_CHARACTERS else "_" for c in text.elems()])

def bin_targets(package, bins):
    """The target names of a package's `bin` entries.

    Args:
        package: `name@version`, for errors.
        bins: `bin` name -> path, as the lockfile reader returns it.

    Returns:
        `struct(value, error)`; `value` maps each target name to the entry's path, `error` names
        two entries whose names become the same target name.
    """
    names = {}
    for name in sorted(bins.keys()):
        target = target_name(name)
        if target in names:
            return struct(value = None, error = 'the npm package {} has the bin entries "{}" and "{}", which both become the target name "{}"'.format(
                package,
                names[target],
                name,
                target,
            ))
        names[target] = name
    return struct(value = {target: bins[name] for target, name in names.items()}, error = None)
