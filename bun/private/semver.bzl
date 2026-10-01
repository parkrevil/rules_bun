"""Version ordering used to pick one Bun version among several requests."""

_MAX_SEGMENTS = 4

def _parse_number(text, version):
    if not text:
        fail("Version \"{}\" has an empty segment.".format(version))
    for ch in text.elems():
        if not ch.isdigit():
            fail(
                "Version \"{}\" has a non-numeric segment \"{}\". ".format(version, text) +
                "The supported format is `<number>(.<number>)*`, optionally followed by `-<prerelease>`.",
            )
    return int(text)

def version_key(version):
    """Returns the sort key of a version string.

    Args:
        version: Version string.

    Returns:
        Sort key.
    """
    if not version:
        fail("The version string is empty.")

    parts = version.split("-", 1)
    core = parts[0]
    prerelease = parts[1] if len(parts) > 1 else ""

    segments = core.split(".")
    if len(segments) > _MAX_SEGMENTS:
        fail(
            "Version \"{}\" has {} segments; at most {} are supported.".format(
                version,
                len(segments),
                _MAX_SEGMENTS,
            ),
        )

    release = [_parse_number(s, version) for s in segments]
    for _ in range(_MAX_SEGMENTS - len(release)):
        release.append(0)

    return (release, 0 if prerelease else 1, prerelease)

def max_version(versions):
    """Returns the highest version in a list.

    Args:
        versions: Version strings.

    Returns:
        Highest version string.
    """
    if not versions:
        fail("The version list is empty.")

    best = versions[0]
    best_key = version_key(best)
    for candidate in versions[1:]:
        key = version_key(candidate)
        if key > best_key:
            best, best_key = candidate, key
    return best
