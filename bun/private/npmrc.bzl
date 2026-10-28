"""The registry keys of an `.npmrc` file and the tarball URL of a package (research R11).

Only `registry` and `@<scope>:registry` are read. A key that starts with `//` (a value scoped to
one registry, such as `//host/:_authToken`) and the keys `_auth`, `_authToken`, `_password`,
`username`, `certfile` and `keyfile` are skipped without being kept, and a registry URL holding
user information (`https://user:token@host/`) is an error that does not echo it (FR-020):
credentials come only from Bazel's downloader (`--credential_helper`, `.netrc`). Errors are returned
as values.
"""

DEFAULT_REGISTRY = "https://registry.npmjs.org"

_CREDENTIAL_KEYS = ["_auth", "_authToken", "_password", "username", "certfile", "keyfile"]

def has_userinfo(url):
    """Whether the authority of a URL (RFC 3986 section 3.2) holds user information.

    The authority is the text after `://` up to the first `/`, `?` or `#`; without `://` it is the
    whole text up to the first of those. An empty user information (`https://@host/`) counts.

    Args:
        url: The URL.

    Returns:
        Whether the authority holds an `@`.
    """
    authority = url.partition("://")[2] or url
    for end in ["/", "?", "#"]:
        authority = authority.partition(end)[0]
    return "@" in authority

def read_npmrc(text, file):
    """Reads the registry keys of an `.npmrc`.

    Args:
        text: The file's text.
        file: The file's name, for errors.

    Returns:
        `struct(value, error)`; `value` is `struct(registry, scopes)`: the default registry or
        `None`, and scope (`@scope`) -> registry.
    """
    registry = None
    scopes = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        key, separator, value = line.partition("=")
        key = key.strip()
        if not separator or key.startswith("//") or key in _CREDENTIAL_KEYS:
            continue
        value = value.strip()
        if (key == "registry" or (key.startswith("@") and key.endswith(":registry"))) and has_userinfo(value):
            return struct(value = None, error = "{}: the {} URL holds user information (credentials before an @); give credentials through Bazel's downloader (--credential_helper or .netrc) instead".format(file, key))
        if key == "registry":
            registry = value
        elif key.startswith("@") and key.endswith(":registry"):
            scopes[key[:-len(":registry")]] = value
    for url in [registry] + scopes.values():
        if url != None and not (url.startswith("https://") or url.startswith("http://")):
            return struct(value = None, error = "{}: the registry {} is no http or https URL".format(file, url))
    return struct(value = struct(registry = registry, scopes = scopes), error = None)

def package_url(npmrc, name, version, url):
    """The URL a package is downloaded from.

    Args:
        npmrc: The `value` of `read_npmrc`, or `None` without an `.npmrc`.
        name: The package name, with its scope if any.
        version: The package version.
        url: The URL the lockfile records; `""` when it is under the default registry.

    Returns:
        `url` when it is not empty; else `{registry}/{name}/-/{basename}-{version}.tgz`, with the
        scope's registry, else the `.npmrc` default registry, else `https://registry.npmjs.org`.
    """
    if url:
        return url
    registry = None
    if npmrc != None:
        if name.startswith("@"):
            registry = npmrc.scopes.get(name.partition("/")[0])
        registry = registry or npmrc.registry
    registry = registry or DEFAULT_REGISTRY
    return "{}/{}/-/{}-{}.tgz".format(registry.rstrip("/"), name, name.split("/")[-1], version)
