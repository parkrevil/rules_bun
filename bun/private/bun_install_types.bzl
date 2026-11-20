"""Bun's install types, carried over from bun-v1.4.4 (research R1, Part 2 S1, S7).

`Behavior` and the platform sets of `src/install_types/resolver_hooks.rs`, `Meta::is_disabled`,
`DepSorter`, and the two value types every later stage compares: `Resolution`
(`src/install/resolution.rs`) and the parsed dependency version (`src/install/dependency.rs`).
Bun's bit sets stay integers with the same bits; its tagged unions are structs whose unused arms
are `None`. Names that Bun hashes (`name_hash`) are kept as the names themselves.
"""

load(":bun_semver.bzl", "parse_query", "parse_version", "query_satisfies", "version_eql", "version_order")

# Behavior bits (resolver_hooks.rs L171-L188).
BEHAVIOR = struct(PROD = 1 << 1, OPTIONAL = 1 << 2, DEV = 1 << 3, PEER = 1 << 4, WORKSPACE = 1 << 5, BUNDLED = 1 << 6)

# resolution::Tag (resolution.rs L997-L1039).
RESOLUTION_TAG = struct(
    UNINITIALIZED = 0,
    ROOT = 1,
    NPM = 2,
    FOLDER = 4,
    LOCAL_TARBALL = 8,
    GITHUB = 16,
    GIT = 32,
    SYMLINK = 64,
    WORKSPACE = 72,
    REMOTE_TARBALL = 80,
)

# DependencyVersionTag (resolver_hooks.rs L306-L329).
VERSION_TAG = struct(
    UNINITIALIZED = 0,
    NPM = 1,
    DIST_TAG = 2,
    TARBALL = 3,
    FOLDER = 4,
    SYMLINK = 5,
    WORKSPACE = 6,
    GIT = 7,
    GITHUB = 8,
    CATALOG = 9,
)

def _has(bits, flag):
    """`Behavior::contains` of one bit.

    Bun: src/install_types/resolver_hooks.rs L171–L188 @ bun-v1.4.4
    """
    return bits & flag != 0

def behavior_is_prod(behavior):
    """`Behavior::is_prod`.

    Bun: src/install_types/resolver_hooks.rs L204–L207 @ bun-v1.4.4

    Args:
        behavior: A behavior bit set.

    Returns:
        Whether it is a dependency of `dependencies`.
    """
    return _has(behavior, BEHAVIOR.PROD)

def behavior_is_optional(behavior):
    """`Behavior::is_optional`: an optional dependency, not an optional peer.

    Bun: src/install_types/resolver_hooks.rs L208–L212 @ bun-v1.4.4

    Args:
        behavior: A behavior bit set.

    Returns:
        Whether it is optional and not a peer.
    """
    return _has(behavior, BEHAVIOR.OPTIONAL) and not _has(behavior, BEHAVIOR.PEER)

def behavior_is_optional_peer(behavior):
    """`Behavior::is_optional_peer`.

    Bun: src/install_types/resolver_hooks.rs L213–L216 @ bun-v1.4.4

    Args:
        behavior: A behavior bit set.

    Returns:
        Whether it is an optional peer.
    """
    return _has(behavior, BEHAVIOR.OPTIONAL) and _has(behavior, BEHAVIOR.PEER)

def behavior_is_dev(behavior):
    """`Behavior::is_dev`.

    Bun: src/install_types/resolver_hooks.rs L217–L220 @ bun-v1.4.4

    Args:
        behavior: A behavior bit set.

    Returns:
        Whether it is a dev dependency.
    """
    return _has(behavior, BEHAVIOR.DEV)

def behavior_is_peer(behavior):
    """`Behavior::is_peer`.

    Bun: src/install_types/resolver_hooks.rs L221–L224 @ bun-v1.4.4

    Args:
        behavior: A behavior bit set.

    Returns:
        Whether it is a peer, optional or not.
    """
    return _has(behavior, BEHAVIOR.PEER)

def behavior_is_workspace(behavior):
    """`Behavior::is_workspace`.

    Bun: src/install_types/resolver_hooks.rs L225–L228 @ bun-v1.4.4

    Args:
        behavior: A behavior bit set.

    Returns:
        Whether it is the root's dependency on a workspace.
    """
    return _has(behavior, BEHAVIOR.WORKSPACE)

def behavior_is_bundled(behavior):
    """`Behavior::is_bundled`.

    Bun: src/install_types/resolver_hooks.rs L229–L232 @ bun-v1.4.4

    Args:
        behavior: A behavior bit set.

    Returns:
        Whether the package ships it in its tarball.
    """
    return _has(behavior, BEHAVIOR.BUNDLED)

def behavior_is_enabled(behavior, features):
    """`Behavior::is_enabled`.

    Bun: src/install_types/resolver_hooks.rs L261–L267 @ bun-v1.4.4

    Args:
        behavior: A behavior bit set.
        features: A `dependency_features` result.

    Returns:
        Whether the install follows dependencies of this kind.
    """
    return (
        behavior_is_prod(behavior) or
        (features.optional_dependencies and behavior_is_optional(behavior)) or
        (features.dev_dependencies and behavior_is_dev(behavior)) or
        (features.peer_dependencies and behavior_is_peer(behavior)) or
        (features.workspaces and behavior_is_workspace(behavior))
    )

def behavior_is_placed(behavior, features):
    """`Behavior::is_placed`: false when the installers filter the dependency.

    Bun: src/install_types/resolver_hooks.rs L269–L273 @ bun-v1.4.4

    Args:
        behavior: A behavior bit set.
        features: A `dependency_features` result.

    Returns:
        Whether the dependency is placed.
    """
    return not behavior_is_bundled(behavior) and behavior_is_enabled(behavior, features)

def behavior_cmp(lhs, rhs):
    """`Behavior::cmp`: workspace, dev, optional, prod, then peer dependencies first.

    Bun: src/install_types/resolver_hooks.rs L275–L297 @ bun-v1.4.4

    Args:
        lhs: A behavior bit set.
        rhs: A behavior bit set.

    Returns:
        -1, 0 or 1.
    """
    if lhs == rhs:
        return 0
    for check in [behavior_is_workspace, behavior_is_dev, behavior_is_optional, behavior_is_prod, behavior_is_peer]:
        left, right = check(lhs), check(rhs)
        if left != right:
            return -1 if left else 1
    return 0

def dependency_sort_key(dependency):
    """The sort key of `Dependency::cmp` and `DepSorter::is_less_than`: behavior group, then name.

    Bun: src/install_types/resolver_hooks.rs L552–L558 @ bun-v1.4.4
    Bun: src/install/lockfile.rs L320–L341 @ bun-v1.4.4

    Args:
        dependency: A struct with `behavior` and `name`.

    Returns:
        A key that orders as `Behavior::cmp`, then the name's bytes.
    """
    b = dependency.behavior
    return (
        not behavior_is_workspace(b),
        not behavior_is_dev(b),
        not behavior_is_optional(b),
        not behavior_is_prod(b),
        not behavior_is_peer(b),
        dependency.name,
    )

def _features(dependencies = True, dev_dependencies = False, optional_dependencies = False, peer_dependencies = True, workspaces = False):
    """`Features` with its defaults.

    Bun: src/install_types/resolver_hooks.rs L1183–L1215 @ bun-v1.4.4
    """
    return struct(
        dependencies = dependencies,
        dev_dependencies = dev_dependencies,
        optional_dependencies = optional_dependencies,
        peer_dependencies = peer_dependencies,
        workspaces = workspaces,
    )

# The install's features without `--omit` or `--production` (PackageManagerOptions.rs L150-L159).
_REMOTE_PACKAGE_FEATURES = _features(optional_dependencies = True)
_LOCAL_PACKAGE_FEATURES = _features(optional_dependencies = True, dev_dependencies = True, workspaces = True)

def tag_is_local_package(tag):
    """`Tag::is_local_package`: the root, a workspace, or a `file:` folder.

    Bun: src/install/resolution.rs L1047–L1049 @ bun-v1.4.4

    Args:
        tag: A `RESOLUTION_TAG`.

    Returns:
        Whether a package.json on disk rather than fetched content defines it.
    """
    return tag in [RESOLUTION_TAG.ROOT, RESOLUTION_TAG.WORKSPACE, RESOLUTION_TAG.FOLDER]

def tag_can_enqueue_install_task(tag):
    """`Tag::can_enqueue_install_task`.

    Bun: src/install/resolution.rs L1074–L1080 @ bun-v1.4.4

    Args:
        tag: A `RESOLUTION_TAG`.

    Returns:
        Whether the package is fetched.
    """
    return tag in [RESOLUTION_TAG.NPM, RESOLUTION_TAG.LOCAL_TARBALL, RESOLUTION_TAG.REMOTE_TARBALL, RESOLUTION_TAG.GIT, RESOLUTION_TAG.GITHUB]

def dependency_features(parent_tag):
    """`Options::dependency_features` of a default `bun install`.

    Bun: src/install/PackageManager/PackageManagerOptions.rs L276–L282 @ bun-v1.4.4
    Bun: src/install/PackageManager/PackageManagerOptions.rs L150–L159 @ bun-v1.4.4

    Args:
        parent_tag: The `RESOLUTION_TAG` of the package that declares the dependencies.

    Returns:
        The local package features for the root, a workspace or a folder; else the remote ones.
    """
    return _LOCAL_PACKAGE_FEATURES if tag_is_local_package(parent_tag) else _REMOTE_PACKAGE_FEATURES

# The name tables of `negatable_names!` (resolver_hooks.rs L795-L965).
_OS_NAMES = {
    "aix": 1 << 1,
    "darwin": 1 << 2,
    "freebsd": 1 << 3,
    "linux": 1 << 4,
    "openbsd": 1 << 5,
    "sunos": 1 << 6,
    "win32": 1 << 7,
    "android": 1 << 8,
}
_CPU_NAMES = {
    "arm": 1 << 1,
    "arm64": 1 << 2,
    "ia32": 1 << 3,
    "mips": 1 << 4,
    "mipsel": 1 << 5,
    "ppc": 1 << 6,
    "ppc64": 1 << 7,
    "s390": 1 << 8,
    "s390x": 1 << 9,
    "x32": 1 << 10,
    "x64": 1 << 11,
}
_LIBC_NAMES = {
    "glibc": 1 << 1,
    "musl": 1 << 2,
}

def _all(names):
    """`ALL_VALUE`: every named bit of a platform set.

    Bun: src/install_types/resolver_hooks.rs L810–L817 @ bun-v1.4.4
    """
    value = 0
    for bit in names.values():
        value |= bit
    return value

_NAMES = {"cpu": _CPU_NAMES, "libc": _LIBC_NAMES, "os": _OS_NAMES}

# A target `os` or `cpu` that Bun does not name (an unmapped Bazel platform, `netbsd`, `riscv64`):
# Bun refuses such a `--os` or `--cpu`, so no Bun behavior exists for it. It gets a bit that no
# package names and that "every value" includes, which is npm's rule for an unknown value, as on
# `main`: a package without the field, with `any`, or with negations only matches it.
_UNNAMED = 1 << 15
_ALL = {kind: _all(names) | (_UNNAMED if kind != "libc" else 0) for kind, names in _NAMES.items()}

# `Libc::ALL`, the target "every libc" (resolver_hooks.rs L859-L866).
LIBC_ALL = _ALL["libc"]

def platform_names(kind):
    """The npm values Bun's `OperatingSystem`, `Architecture` or `Libc` names.

    Bun: src/install_types/resolver_hooks.rs L847–L850 @ bun-v1.4.4
    Bun: src/install_types/resolver_hooks.rs L904–L904 @ bun-v1.4.4
    Bun: src/install_types/resolver_hooks.rs L961–L965 @ bun-v1.4.4

    Args:
        kind: `os`, `cpu` or `libc`.

    Returns:
        The sorted names.
    """
    return sorted(_NAMES[kind].keys())

def platform_value(kind, name):
    """The bit set of one platform value, as `--os`, `--cpu` and `--libc` set it.

    Bun: src/install/PackageManager/CommandLineArguments.rs L37–L64 @ bun-v1.4.4

    Args:
        kind: `os`, `cpu` or `libc`.
        name: An npm value, or `None` when the target has none.

    Returns:
        The value's bit; `LIBC_ALL` for a `None` libc (`Libc::CURRENT` off Linux, and a Linux
        platform without the libc constraint); for an `os` or `cpu` Bun does not name, the bit no
        package names.
    """
    if kind == "libc":
        return LIBC_ALL if name == None else _NAMES[kind][name]
    return _NAMES[kind].get(name, _UNNAMED) if name != None else _UNNAMED

def negatable_from_json_value(kind, value):
    """`negatable_from_json_value` with `Negatable::apply` and `Negatable::combine`.

    Bun: src/install/npm.rs L850–L865 @ bun-v1.4.4
    Bun: src/install_types/resolver_hooks.rs L610–L687 @ bun-v1.4.4

    Args:
        kind: `os`, `cpu` or `libc`.
        value: The field's JSON value: a string, a list, or `None` when the field is absent.

    Returns:
        The bit set the package allows; every value when the field is absent, except `libc`, whose
        absence is 0 ("not declared").
    """
    names = _NAMES[kind]
    all_value = _ALL[kind]
    if value == None:
        # `Meta::default` (Meta.rs L51-L66): every os and cpu, no declared libc.
        return 0 if kind == "libc" else all_value
    items = [value] if type(value) == "string" else [item for item in value if type(item) == "string"] if type(value) == "list" else []
    added = 0
    removed = 0
    had_wildcard = False
    had_unrecognized_values = False
    for item in items:
        if not item:
            continue
        if item == "any":
            had_wildcard = True
            continue
        if item == "none":
            had_unrecognized_values = True
            continue
        is_not = item[0] == "!"
        field = names.get(item[1:] if is_not else item)
        if field == None:
            if not is_not:
                had_unrecognized_values = True
            continue

        # Applying a recognised token resets `had_wildcard` and `had_unrecognized_values`.
        had_wildcard = False
        had_unrecognized_values = False
        if is_not:
            removed |= field
        else:
            added |= field

    if had_wildcard:
        added = all_value
    if added == 0 and removed == 0:
        return 0 if had_unrecognized_values else all_value
    if added == 0:
        return all_value & ~removed
    if removed == 0:
        return added
    return added & ~removed

def _is_match(kind, declared, target):
    """`OperatingSystem::is_match`, `Architecture::is_match` and `Libc::is_match`.

    Bun: src/install_types/resolver_hooks.rs L833–L836 @ bun-v1.4.4
    Bun: src/install_types/resolver_hooks.rs L876–L880 @ bun-v1.4.4
    Bun: src/install_types/resolver_hooks.rs L947–L950 @ bun-v1.4.4
    """
    if kind == "libc" and declared == 0:
        return True
    return declared & target != 0

def libc_for_dependency(libc, behavior):
    """`Libc::for_dependency`: the target libc filters optional dependencies only.

    Bun: src/install_types/resolver_hooks.rs L882–L890 @ bun-v1.4.4

    Args:
        libc: The target libc bit set.
        behavior: The dependency's behavior.

    Returns:
        `libc` for an optional dependency, else `LIBC_ALL`.
    """
    return libc if behavior_is_optional(behavior) else LIBC_ALL

def meta_is_disabled(meta, cpu, os, libc):
    """`Meta::is_disabled`: the package's `cpu`, `os` or `libc` excludes the target.

    Bun: src/install/lockfile/Package/Meta.rs L70–L74 @ bun-v1.4.4

    Args:
        meta: `struct(os, arch, libc)` bit sets of `negatable_from_json_value`.
        cpu: The target cpu bit set.
        os: The target os bit set.
        libc: The target libc bit set.

    Returns:
        Whether the package is disabled for the target.
    """
    return not _is_match("cpu", meta.arch, cpu) or not _is_match("os", meta.os, os) or not _is_match("libc", meta.libc, libc)

# --- resolution.rs -------------------------------------------------------------------------------

def _resolution(tag, value = None):
    """`Resolution`: a tag and its value.

    Bun: src/install/resolution.rs L66–L72 @ bun-v1.4.4
    """
    return struct(tag = tag, value = value)

def _parse_repository_git(text):
    """`Repository::parse_append_git`.

    Bun: src/install/repository.rs L152–L168 @ bun-v1.4.4
    """
    remain = text[len("git+"):] if text.startswith("git+") else text
    hash = remain.rfind("#")
    if hash != -1:
        return struct(owner = "", repo = remain[:hash], committish = remain[hash + 1:], resolved = "", package_name = "")
    return struct(owner = "", repo = remain, committish = "", resolved = "", package_name = "")

def _parse_repository_github(text):
    """`Repository::parse_append_github`.

    Bun: src/install/repository.rs L170–L198 @ bun-v1.4.4
    """
    remain = text[len("github:"):] if text.startswith("github:") else text
    hash = remain.rfind("#")
    before_hash, committish = (remain[:hash], remain[hash + 1:]) if hash != -1 else (remain, "")
    slash = before_hash.rfind("/")
    owner, repo = (before_hash[:slash], before_hash[slash + 1:]) if slash != -1 else ("", before_hash)
    return struct(owner = owner, repo = repo, committish = committish, resolved = "", package_name = "")

def repository_with_resolved(repository, resolved):
    """The repository with the `.bun-tag` the loader sets as `resolved`.

    Bun: src/install/lockfile/bun.lock.rs L2714–L2719 @ bun-v1.4.4

    Args:
        repository: A repository struct.
        resolved: The resolved tag.

    Returns:
        The repository with `resolved` set.
    """
    return struct(owner = repository.owner, repo = repository.repo, committish = repository.committish, resolved = resolved, package_name = repository.package_name)

def _repository_eql(lhs, rhs):
    """`Repository::eql`.

    Bun: src/install_types/resolver_hooks.rs L1035–L1046 @ bun-v1.4.4
    """
    if lhs.owner != rhs.owner or lhs.repo != rhs.repo:
        return False
    if not lhs.resolved or not rhs.resolved:
        return lhs.committish == rhs.committish
    return lhs.resolved == rhs.resolved

def _repository_order(lhs, rhs):
    """`Repository::order`.

    Bun: src/install_types/resolver_hooks.rs L996–L1012 @ bun-v1.4.4
    """
    for field in ["owner", "repo", "committish", "resolved"]:
        left, right = getattr(lhs, field), getattr(rhs, field)
        if left != right:
            return -1 if left < right else 1
    return 0

def resolution_from_text_lockfile(text):
    """`Resolution::from_text_lockfile`.

    Bun: src/install/resolution.rs L161–L252 @ bun-v1.4.4

    Args:
        text: The resolution after `<name>@` in slot 0 of a `packages` row.

    Returns:
        `struct(value, error)`; `value` is `struct(tag, value)`: a version for npm, a repository
        for git and GitHub, else the text after the protocol; `error` is `UnexpectedResolution`.
    """
    if text.startswith("root:"):
        return struct(value = _resolution(RESOLUTION_TAG.ROOT), error = None)
    for prefix, tag in [("link:", RESOLUTION_TAG.SYMLINK), ("workspace:", RESOLUTION_TAG.WORKSPACE), ("file:", RESOLUTION_TAG.FOLDER)]:
        if text.startswith(prefix):
            return struct(value = _resolution(tag, text[len(prefix):]), error = None)
    tag = version_tag_infer(text)
    if tag == VERSION_TAG.GIT:
        return struct(value = _resolution(RESOLUTION_TAG.GIT, _parse_repository_git(text)), error = None)
    if tag == VERSION_TAG.GITHUB:
        return struct(value = _resolution(RESOLUTION_TAG.GITHUB, _parse_repository_github(text)), error = None)
    if tag == VERSION_TAG.TARBALL:
        if is_remote_tarball(text):
            return struct(value = _resolution(RESOLUTION_TAG.REMOTE_TARBALL, text), error = None)
        return struct(value = _resolution(RESOLUTION_TAG.LOCAL_TARBALL, text), error = None)
    if tag == VERSION_TAG.NPM:
        parsed = parse_version(text)
        if not parsed.valid or parsed.major == None or parsed.minor == None or parsed.patch == None:
            return struct(value = None, error = "UnexpectedResolution")
        return struct(value = _resolution(RESOLUTION_TAG.NPM, parsed.version_min), error = None)
    return struct(value = None, error = "UnexpectedResolution")

def resolution_order(lhs, rhs):
    """`Resolution::order`: by tag, then by value (a version for npm).

    Bun: src/install/resolution.rs L358–L383 @ bun-v1.4.4
    Bun: src/install_types/resolver_hooks.rs L1089–L1092 @ bun-v1.4.4

    Args:
        lhs: A resolution.
        rhs: A resolution.

    Returns:
        -1, 0 or 1.
    """
    if lhs.tag != rhs.tag:
        return -1 if lhs.tag < rhs.tag else 1
    if lhs.tag == RESOLUTION_TAG.NPM:
        return version_order(lhs.value, rhs.value)
    if lhs.tag in [RESOLUTION_TAG.GIT, RESOLUTION_TAG.GITHUB]:
        return _repository_order(lhs.value, rhs.value)
    if lhs.tag in [RESOLUTION_TAG.LOCAL_TARBALL, RESOLUTION_TAG.FOLDER, RESOLUTION_TAG.REMOTE_TARBALL, RESOLUTION_TAG.WORKSPACE, RESOLUTION_TAG.SYMLINK]:
        if lhs.value == rhs.value:
            return 0
        return -1 if lhs.value < rhs.value else 1
    return 0

def resolution_eql(lhs, rhs):
    """`Resolution::eql`: an npm version ignores its build tag.

    Bun: src/install/resolution.rs L497–L534 @ bun-v1.4.4
    Bun: src/install_types/resolver_hooks.rs L1085–L1087 @ bun-v1.4.4

    Args:
        lhs: A resolution.
        rhs: A resolution.

    Returns:
        Whether they are one resolution.
    """
    if lhs.tag != rhs.tag:
        return False
    if lhs.tag == RESOLUTION_TAG.ROOT:
        return True
    if lhs.tag == RESOLUTION_TAG.NPM:
        return version_eql(lhs.value, rhs.value)
    if lhs.tag in [RESOLUTION_TAG.GIT, RESOLUTION_TAG.GITHUB]:
        return _repository_eql(lhs.value, rhs.value)
    return lhs.value == rhs.value

def resolution_satisfies_dependency_version(resolution, version):
    """`Resolution::satisfies_dependency_version`: npm ranges by semver, repositories by equality.

    Bun: src/install/resolution.rs L25–L52 @ bun-v1.4.4

    Args:
        resolution: A resolution.
        version: A `dependency_parse` result.

    Returns:
        Whether the resolution can satisfy the dependency.
    """
    if resolution.tag == RESOLUTION_TAG.NPM and version.tag == VERSION_TAG.NPM:
        return query_satisfies(version.npm.version, resolution.value)
    if resolution.tag == RESOLUTION_TAG.GIT and version.tag == VERSION_TAG.GIT:
        return _repository_eql(resolution.value, version.git)
    if resolution.tag == RESOLUTION_TAG.GITHUB and version.tag == VERSION_TAG.GITHUB:
        return _repository_eql(resolution.value, version.github)
    return False

# --- dependency.rs -------------------------------------------------------------------------------

_DIGITS = "0123456789"
_LITERAL_WHITESPACE = [" ", "\t", "\n", "\r"]
_WHITESPACE = [" ", "\t", "\n", "\r", "\013", "\014"]

def _has_suffix_ignore_ascii_case(text, suffix):
    """`has_suffix_ignore_ascii_case`.

    Bun: src/install/dependency.rs L429–L432 @ bun-v1.4.4
    """
    return len(text) >= len(suffix) and text[len(text) - len(suffix):].lower() == suffix

def is_tarball(dependency):
    """`is_tarball`: a `.tgz`, `.tar.gz` or `.tar` suffix.

    Bun: src/install/dependency.rs L420–L432 @ bun-v1.4.4

    Args:
        dependency: A dependency literal.

    Returns:
        Whether it names a tarball.
    """
    return _has_suffix_ignore_ascii_case(dependency, ".tgz") or _has_suffix_ignore_ascii_case(dependency, ".tar.gz") or _has_suffix_ignore_ascii_case(dependency, ".tar")

def is_remote_tarball(dependency):
    """`is_remote_tarball`.

    Bun: src/install/dependency.rs L434–L438 @ bun-v1.4.4

    Args:
        dependency: A tarball literal.

    Returns:
        Whether it is an `http://` or `https://` URL.
    """
    return dependency.startswith("https://") or dependency.startswith("http://")

def _is_scp_like_path(dependency):
    """`is_scp_like_path`.

    Bun: src/install/dependency.rs L354–L391 @ bun-v1.4.4
    """
    if len(dependency) < 3:
        return False
    at_index = None
    for i in range(len(dependency)):
        c = dependency[i]
        if c == "@":
            if at_index == None:
                at_index = i
        elif c == ":":
            if dependency[i:].startswith("://"):
                return False
            return i > (at_index + 1 if at_index != None else 0)
        elif c == "/":
            return i > at_index + 1 if at_index != None else False
    return False

def _is_github_tarball_path(dependency):
    """`is_github_tarball_path`.

    Bun: src/install/dependency.rs L393–L418 @ bun-v1.4.4
    """
    if is_tarball(dependency):
        return True
    parts = dependency.split("/")
    return len(parts) >= 3 and parts[2] == "tarball"

def _is_github_shorthand(text):
    """`is_github_shorthand`.

    Bun: src/install/hosted_git_info.rs L544–L601 @ bun-v1.4.4
    """
    if not text:
        return False
    if text[0] == "." or text[0] == "/":
        return False
    pound_idx = None
    seen_slash = False
    for i in range(len(text)):
        c = text[i]
        if c == ":" or c == "@":
            if pound_idx == None:
                return False
        elif c == "#":
            pound_idx = i
        elif c == "/":
            if seen_slash and pound_idx == None:
                return False
            seen_slash = True
        elif c in _WHITESPACE and pound_idx == None:
            return False
    if pound_idx != None:
        does_not_end_with_slash = pound_idx == 0 or text[pound_idx - 1] != "/"
    else:
        does_not_end_with_slash = text[-1] != "/"
    return seen_slash and does_not_end_with_slash

# `HostProvider::from_domain` (hosted_git_info.rs L874-L940).
_GIT_HOSTS = ["github.com", "bitbucket.org", "gitlab.com", "gist.github.com", "git.sr.ht"]

def _hosted_git_tag(dependency):
    """The tag `HostedGitInfo::from_url` and `hgi_to_tag` give a URL, or `None` without a host.

    Bun: src/install/hosted_git_info.rs L231–L326 @ bun-v1.4.4
    Bun: src/install/dependency.rs L1635–L1649 @ bun-v1.4.4

    Only the host provider decides the tag: a known host is `git`, except a `github:` shortcut,
    which `is_github_shorthand` and the `github:` checks of `Tag::infer` already return. The URL
    is not parsed further (research Part 2, "Not carried over").
    """
    rest = dependency
    scheme = rest.find("://")
    if scheme != -1:
        rest = rest[scheme + 3:]
    for end in ["/", ":", "#"]:
        at = rest.find(end)
        if at != -1:
            rest = rest[:at]
    host = rest[rest.rfind("@") + 1:]
    if host in _GIT_HOSTS:
        return VERSION_TAG.GIT
    return None

def _is_dist_tag_with_leading_digit(dependency):
    """`is_dist_tag_with_leading_digit`: `2x`, `1beta` and `v2x` are tags.

    Bun: src/install/dependency.rs L440–L469 @ bun-v1.4.4
    """
    if len(dependency) <= 17:
        dots = 0
        after_digit = False
        is_plain = True
        for c in dependency.elems():
            if c in _DIGITS:
                after_digit = True
            elif c == "." and after_digit:
                after_digit = False
                dots += 1
            else:
                is_plain = False
                break
        if is_plain and after_digit and dots == 2:
            return False
    for c in ["|", "+", " ", "\t", "\n", "\r", "\013", "\014"]:
        if c in dependency:
            return False
    parsed = parse_version(dependency)
    return not parsed.valid and parsed.wildcard != "none"

def _split_npm_alias(target):
    """`split_npm_alias`: `@scope/name@version` to the name and the version.

    Bun: src/install/dependency.rs L1191–L1199 @ bun-v1.4.4
    """
    scope = 1 if target.startswith("@") else 0
    at = target.find("@", scope)
    if at == -1:
        return target, None
    return target[:at], target[at + 1:]

def version_tag_infer(dependency):
    """`Tag::infer`: the kind of a dependency literal.

    Bun: src/install/dependency.rs L794–L1113 @ bun-v1.4.4

    Bun calls itself for the version of an `npm:` alias (L1025-L1031); Starlark has no recursion,
    so each alias is unwrapped in a loop.

    Args:
        dependency: A trimmed dependency literal.

    Returns:
        A `VERSION_TAG`.
    """
    for _ in range(len(dependency) + 1):
        if not dependency.startswith("npm:"):
            break
        _, version = _split_npm_alias(dependency[len("npm:"):])
        if version == None:
            return VERSION_TAG.NPM
        dependency = version
    return _infer(dependency)

def _infer(dependency):
    """`Tag::infer` of a literal that is not an `npm:` alias.

    Bun: src/install/dependency.rs L794–L1113 @ bun-v1.4.4
    """
    if not dependency:
        return VERSION_TAG.DIST_TAG

    # A Windows drive letter is a folder only on Windows; keys and literals are not paths here.
    c = dependency[0]
    if c in ["=", ">", "<", "^", "*", "|"]:
        return VERSION_TAG.NPM
    if c == ".":
        return VERSION_TAG.TARBALL if is_tarball(dependency) else VERSION_TAG.FOLDER
    if c == "~":
        if len(dependency) > 1 and dependency[1] == "/":
            return VERSION_TAG.TARBALL if is_tarball(dependency) else VERSION_TAG.FOLDER
        return VERSION_TAG.NPM
    if c == "/":
        return VERSION_TAG.TARBALL if is_tarball(dependency) else VERSION_TAG.FOLDER
    if c in _DIGITS:
        if is_tarball(dependency):
            return VERSION_TAG.TARBALL
        if _is_dist_tag_with_leading_digit(dependency):
            return VERSION_TAG.DIST_TAG
        return VERSION_TAG.NPM
    if c == "f" and dependency.startswith("file:"):
        return VERSION_TAG.TARBALL if is_tarball(dependency) else VERSION_TAG.FOLDER
    if c == "c" and dependency.startswith("catalog:"):
        return VERSION_TAG.CATALOG
    if c == "g" and dependency.startswith("git"):
        url = dependency[len("git"):]
        if len(url) > 2:
            if url[0] == ":" and url.startswith("://"):
                url = url[len("://"):]
                if url.startswith("github.com/") and _is_github_shorthand(url[len("github.com/"):]):
                    return VERSION_TAG.GITHUB
                return _hosted_git_tag(dependency) or VERSION_TAG.GIT
            if url[0] == "+":
                if url.startswith("+ssh:") or url.startswith("+file:") or url.startswith("+git:"):
                    return VERSION_TAG.GIT
                if url.startswith("+http"):
                    url = url[len("+http"):]
                    advanced = False
                    if len(url) > 2:
                        if url.startswith("://"):
                            url = url[len("://"):]
                            advanced = True
                        elif url.startswith("s://"):
                            url = url[len("s://"):]
                            advanced = True
                    if advanced:
                        if url.startswith("github.com/") and _is_github_shorthand(url[len("github.com/"):]):
                            return VERSION_TAG.GITHUB
                        return _hosted_git_tag(dependency) or VERSION_TAG.GIT
            if url[0] == "h" and url.startswith("hub:") and _is_github_shorthand(url[len("hub:"):]):
                return VERSION_TAG.GITHUB
    if c == "h" and (dependency.startswith("http:") or dependency.startswith("https:")):
        url = dependency[len("http"):]
        if url.startswith("://"):
            url = url[len("://"):]
        elif url.startswith("s://"):
            url = url[len("s://"):]
        if url.startswith("github.com/"):
            path = url[len("github.com/"):]
            if _is_github_tarball_path(path):
                return VERSION_TAG.TARBALL
            if _is_github_shorthand(path):
                return VERSION_TAG.GITHUB
        return _hosted_git_tag(dependency) or VERSION_TAG.TARBALL
    if c == "s" and dependency.startswith("ssh:"):
        return VERSION_TAG.GIT
    if c == "l" and dependency.startswith("link:"):
        return VERSION_TAG.SYMLINK
    if c == "v":
        if is_tarball(dependency):
            return VERSION_TAG.TARBALL
        if _is_github_shorthand(dependency):
            return VERSION_TAG.GITHUB
        if _is_scp_like_path(dependency):
            return VERSION_TAG.GIT
        if len(dependency) == 1:
            return VERSION_TAG.DIST_TAG
        if dependency[1] in _DIGITS and not _is_dist_tag_with_leading_digit(dependency):
            return VERSION_TAG.NPM
        return VERSION_TAG.DIST_TAG
    if c == "w" and dependency.startswith("workspace:"):
        return VERSION_TAG.WORKSPACE
    if c in ["x", "X"]:
        if len(dependency) == 1 or dependency[1] == ".":
            return VERSION_TAG.NPM
    if c == "p" and dependency.startswith("patch:"):
        return VERSION_TAG.NPM

    if is_tarball(dependency):
        return VERSION_TAG.TARBALL
    if _is_github_shorthand(dependency):
        return VERSION_TAG.GITHUB
    if _is_scp_like_path(dependency):
        return _hosted_git_tag(dependency) or VERSION_TAG.GIT
    if "|" not in dependency:
        return VERSION_TAG.DIST_TAG
    return VERSION_TAG.NPM

def _is_range_after_npm_protocol(target):
    """`is_range_after_npm_protocol`: `npm:^1.0.0` is a range for the dependency's own name.

    Bun: src/install/dependency.rs L1201–L1208 @ bun-v1.4.4
    """
    has_range_char = False
    for c in ["^", "~", ">", "<", "=", "*", "|", " "]:
        if c in target:
            has_range_char = True
            break
    if not has_range_char:
        # `Version::parse_exact` (Version.rs L166-L174): one complete version, nothing else.
        trimmed = _trim(target, _WHITESPACE)
        parsed = parse_version(trimmed)
        has_range_char = parsed.valid and parsed.wildcard == "none" and parsed.len == len(trimmed)
    return has_range_char and version_tag_infer(target) == VERSION_TAG.NPM

def _trim(text, characters):
    """`strings::trim`: `characters` removed at both ends, as `parse_exact` and a catalog use it.

    Bun: src/semver/Version.rs L166–L174 @ bun-v1.4.4
    Bun: src/install/dependency.rs L1610–L1623 @ bun-v1.4.4
    """
    start, end = 0, len(text)
    for _ in range(len(text)):
        if start < end and text[start] in characters:
            start += 1
        elif start < end and text[end - 1] in characters:
            end -= 1
        else:
            break
    return text[start:end]

def _trim_literal(literal):
    """`trim_literal`: leading spaces, tabs and line breaks.

    Bun: src/install/dependency.rs L1140–L1145 @ bun-v1.4.4
    """
    for i in range(len(literal)):
        if literal[i] not in _LITERAL_WHITESPACE:
            return literal[i:]
    return ""

def _version_value(tag, literal, **fields):
    """`dependency::Version`: a tag, the literal and the arm of the tag.

    Bun: src/install_types/resolver_hooks.rs L439–L444 @ bun-v1.4.4
    """
    value = dict(npm = None, dist_tag = None, tarball = None, folder = None, symlink = None, workspace = None, git = None, github = None, catalog = None)
    value.update(fields)
    return struct(tag = tag, literal = literal, **value)

def dependency_version(tag, literal, **fields):
    """A dependency version: `tag`, `literal` and the arm of `tag`; the other arms are `None`.

    Bun: src/install_types/resolver_hooks.rs L405–L444 @ bun-v1.4.4

    Args:
        tag: A `VERSION_TAG`.
        literal: The literal as written.
        **fields: The arm of `tag`.

    Returns:
        The version.
    """
    return _version_value(tag, literal, **fields)

def dependency_parse(alias, literal, tag = None):
    """`Dependency::parse`: `Tag::infer`, then `parse_with_tag`.

    Bun: src/install/dependency.rs L1147–L1189 @ bun-v1.4.4
    Bun: src/install/dependency.rs L1229–L1625 @ bun-v1.4.4

    Args:
        alias: The dependency's name (its key in package.json).
        literal: The version as written.
        tag: The `VERSION_TAG` to parse it as (`parse_with_optional_tag`); inferred when `None`.

    Returns:
        The version, or `None` where Bun's parse returns none (an unsupported protocol).
    """
    dependency = _trim_literal(literal)
    if tag == None:
        tag = version_tag_infer(dependency)
    if tag == VERSION_TAG.NPM:
        text = dependency
        is_alias = False
        name = alias
        if text.startswith("npm:"):
            target = text[len("npm:"):]
            alias_name, version = _split_npm_alias(target)
            if version == None and _is_range_after_npm_protocol(target):
                text = target
            else:
                is_alias = True
                text = version if version != None else ""
                name = alias_name

        # Strip a single leading `v`.
        if len(text) > 1 and text[0] == "v":
            text = text[1:]
        return _version_value(tag, literal, npm = struct(name = name, version = parse_query(text), is_alias = is_alias))
    if tag == VERSION_TAG.DIST_TAG:
        tag_to_use = dependency
        name = alias
        if dependency.startswith("npm:"):
            name, dist_tag = _split_npm_alias(dependency[len("npm:"):])
            tag_to_use = dist_tag if dist_tag != None else ""
        return _version_value(tag, literal, dist_tag = struct(name = name, tag = tag_to_use or "latest"))
    if tag == VERSION_TAG.GIT:
        repository = _parse_repository_git(dependency)
        return _version_value(tag, literal, git = repository)
    if tag == VERSION_TAG.GITHUB:
        # `HostedGitInfo::from_url` for the GitHub forms `Tag::infer` returns `github` for.
        text = dependency
        for prefix in ["git+https://github.com/", "git+http://github.com/", "git://github.com/", "https://github.com/", "http://github.com/", "github:"]:
            if text.startswith(prefix):
                text = text[len(prefix):]
                break
        repository = _parse_repository_github(text)
        if repository.repo.endswith(".git"):
            repository = struct(owner = repository.owner, repo = repository.repo[:-len(".git")], committish = repository.committish, resolved = "", package_name = "")
        return _version_value(tag, literal, github = repository)
    if tag == VERSION_TAG.TARBALL:
        if is_remote_tarball(dependency):
            return _version_value(tag, literal, tarball = struct(uri_kind = "remote", uri = dependency, package_name = ""))
        if dependency.startswith("file://"):
            return _version_value(tag, literal, tarball = struct(uri_kind = "local", uri = dependency[7:], package_name = ""))
        if dependency.startswith("file:"):
            return _version_value(tag, literal, tarball = struct(uri_kind = "local", uri = dependency[5:], package_name = ""))
        if "://" in dependency:
            return None
        return _version_value(tag, literal, tarball = struct(uri_kind = "local", uri = dependency, package_name = ""))
    if tag == VERSION_TAG.FOLDER:
        protocol = dependency.find(":")
        if protocol != -1:
            if dependency[:protocol] == "file":
                rest = dependency[protocol + 1:]
                maybe_dot_dot = None
                if len(dependency) > protocol + 1 and dependency[protocol + 1] == "/":
                    if len(dependency) > protocol + 2 and dependency[protocol + 2] == "/":
                        if len(dependency) > protocol + 3 and dependency[protocol + 3] == "/":
                            maybe_dot_dot = dependency[protocol + 4:]
                        else:
                            maybe_dot_dot = dependency[protocol + 3:]
                    else:
                        maybe_dot_dot = dependency[protocol + 2:]
                if maybe_dot_dot != None and maybe_dot_dot.startswith(".."):
                    return _version_value(tag, literal, folder = maybe_dot_dot)
                return _version_value(tag, literal, folder = rest)
            return None
        return _version_value(tag, literal, folder = dependency)
    if tag == VERSION_TAG.SYMLINK:
        colon = dependency.find(":")
        return _version_value(tag, literal, symlink = dependency[colon + 1:] if colon != -1 else dependency)
    if tag == VERSION_TAG.WORKSPACE:
        return _version_value(tag, literal, workspace = dependency[len("workspace:"):] if dependency.startswith("workspace:") else dependency)
    if tag == VERSION_TAG.CATALOG:
        return _version_value(tag, literal, catalog = _trim(dependency[len("catalog:"):], _WHITESPACE))
    return _version_value(VERSION_TAG.UNINITIALIZED, literal)

def split_name_and_maybe_version(text):
    """`split_name_and_maybe_version`: `name@version`, the scope's `@` being part of the name.

    Bun: src/install/dependency.rs L485–L516 @ bun-v1.4.4

    Args:
        text: `<name>` or `<name>@<version>`.

    Returns:
        `(name, version)`; `version` is `None` when nothing follows the name.
    """
    at = text.find("@")
    if at == -1:
        return text, None
    if at == 0:
        second = text.find("@", 1)
        if second == -1:
            return text, None
        at = second
    return text[:at], (text[at + 1:] if at + 1 < len(text) else None)

def split_name_and_version(text):
    """`split_name_and_version`.

    Bun: src/install/dependency.rs L529–L532 @ bun-v1.4.4

    Args:
        text: Slot 0 of a `packages` row.

    Returns:
        `(name, version)`, or `None` when no version follows (`MissingVersion`).
    """
    name, version = split_name_and_maybe_version(text)
    if version == None:
        return None
    return name, version

def is_safe_install_folder_name(name):
    """`is_safe_install_folder_name`: a name that can be a folder under `node_modules`.

    Bun: src/install/dependency.rs L570–L596 @ bun-v1.4.4

    Args:
        name: A package name or alias.

    Returns:
        Whether it is safe.
    """
    if not name or len(name) > 255 + 1 + 255:
        return False
    for component in name.split("/"):
        if len(component) > 255 or component in ["", ".", ".."]:
            return False
    for i in range(len(name)):
        c = name[i]
        if c == "\\" or c == ":" or c < " " or c == "\177":
            return False

        # A UTF-8 encoded C1 control (`C2 80`..`C2 9F`); the file's bytes are the string's characters.
        if c == "\302" and i + 1 < len(name) and "\200" <= name[i + 1] and name[i + 1] <= "\237":
            return False
    return True
