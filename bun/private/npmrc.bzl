"""The registry keys of an `.npmrc` file and the tarball URL of a package (research R11).

Only `registry` and `@<scope>:registry` are read. A key that starts with `//` (a value scoped to
one registry, such as `//host/:_authToken`) and the keys `_auth`, `_authToken`, `_password`,
`username`, `certfile` and `keyfile` are skipped without being kept. A registry value must be an
`http` or `https` URL without user information, and a key of the form `@<scope>:registry` must name
an npm scope (lower-case URL-safe characters); an error prints neither a value nor such a key
(FR-020), since credentials come only from Bazel's downloader (`--credential_helper`, `.netrc`).
Errors are returned as values.
"""

load(":urls.bzl", "has_credentials", "is_download_url")

DEFAULT_REGISTRY = "https://registry.npmjs.org"

_CREDENTIAL_KEYS = ["_auth", "_authToken", "_password", "username", "certfile", "keyfile"]

# The characters of an npm scope name (validate-npm-package-name: lower case and URL-safe).
_SCOPE_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789-._~"

def _scope_key(key):
    """The scope an `@<scope>:registry` key names.

    Returns `@<scope>`, `""` for a key of that shape whose scope is no npm scope name, and `None` for
    any other key.
    """
    if not (key.startswith("@") and key.endswith(":registry")):
        return None
    scope = key[1:-len(":registry")]
    if not scope or scope[0] in "._" or [c for c in scope.elems() if c not in _SCOPE_CHARS]:
        return ""
    return "@" + scope

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
        scope = _scope_key(key)
        if scope == "":
            # The key is not printed: it is not a scope key, and it may hold anything.
            return struct(value = None, error = "{}: a key of the form @<scope>:registry names no npm scope (lower-case URL-safe characters); the key is not printed, and credentials in it belong in Bazel's downloader (--credential_helper or .netrc)".format(file))
        if key != "registry" and scope == None:
            continue

        # From here the key is `registry` or a valid scope key; the value is never printed.
        if has_credentials(value):
            return struct(value = None, error = "{}: the {} URL holds user information (credentials before an @); give credentials through Bazel's downloader (--credential_helper or .netrc) instead".format(file, key))
        if not is_download_url(value):
            return struct(value = None, error = "{}: the {} value is no http or https URL".format(file, key))
        if key == "registry":
            registry = value
        else:
            scopes[scope] = value
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
