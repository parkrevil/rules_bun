"""Version ordering used to pick one Bun version among several requests."""

_MAX_SEGMENTS = 4

def version_error(version):
    """Why a version string cannot be ordered, or `None`.

    Args:
        version: Version string.

    Returns:
        An English error naming the version, or `None` when `version_key` accepts it.
    """
    if not version:
        return "The version string is empty."
    segments = version.split("-", 1)[0].split(".")
    if len(segments) > _MAX_SEGMENTS:
        return "Version \"{}\" has {} segments; at most {} are supported.".format(version, len(segments), _MAX_SEGMENTS)
    for text in segments:
        if not text:
            return "Version \"{}\" has an empty segment.".format(version)
        if not text.isdigit():
            return ("Version \"{}\" has a non-numeric segment \"{}\". ".format(version, text) +
                    "The supported format is `<number>(.<number>)*`, optionally followed by `-<prerelease>`.")
    return None

def version_key(version):
    """Returns the sort key of a version string.

    Args:
        version: Version string.

    Returns:
        Sort key.
    """
    error = version_error(version)
    if error:
        fail(error)

    parts = version.split("-", 1)
    core = parts[0]
    prerelease = parts[1] if len(parts) > 1 else ""

    release = [int(s) for s in core.split(".")]
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
