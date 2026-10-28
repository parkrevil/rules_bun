"""URLs in the text rules_bun reads, and the credentials they carry (feature 005 P1).

A URL is recognized by RFC 3986's generic syntax: a scheme (a letter, then letters, digits, `+`,
`-` or `.`) directly before `://`, then an authority up to the first `/`, `?` or `#`. A URL ends at
whitespace or at a character RFC 3986 excludes from URLs (`"`, `<`, `>`, `\\`, `^`, `` ` ``, `{`, `|`,
`}`). Every URL of a text is found, including one after a package name (`a@https://...`) or inside
another URL's query.

A URL carries credentials when its authority holds user information (RFC 3986 section 3.2.1),
except the user name alone of an `ssh://` or `git+ssh://` URL, which names an account and
authenticates with keys. A secret in a path or query (`?token=...`) is not recognized.
"""

_ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
_SCHEME_CHARS = _ALPHA + "0123456789+-."

# Whitespace and the characters RFC 3986 (appendix C) excludes from a URL end it.
_ENDS = " \t\r\n\"<>\\^`{|}"

_SSH_SCHEMES = ["ssh", "git+ssh"]

def _scheme_before(text, end):
    """The scheme ending at `end`: the scheme characters before it, starting at a letter."""
    start = end
    for i in range(end - 1, -1, -1):
        if text[i] not in _SCHEME_CHARS:
            break
        start = i

    # RFC 3986 section 3.1: a scheme starts with a letter.
    for i in range(start, end):
        if text[i] in _ALPHA:
            return text[i:end].lower()
    return ""

def _authority_after(text, start):
    """The authority starting at `start`: up to `/`, `?`, `#` or the end of the URL."""
    end = len(text)
    for i in range(start, len(text)):
        if text[i] in "/?#" or text[i] in _ENDS:
            end = i
            break
    return text[start:end]

def urls_in(text):
    """Every URL of a text.

    Args:
        text: Any text.

    Returns:
        A list of `struct(scheme, authority, userinfo)`, `userinfo` being `None` without an `@` in
        the authority.
    """
    found = []
    start = 0
    for _ in range(len(text)):
        index = text.find("://", start)
        if index < 0:
            break
        start = index + 3
        scheme = _scheme_before(text, index)
        if not scheme:
            continue
        authority = _authority_after(text, index + 3)
        userinfo = authority.rpartition("@")[0] if "@" in authority else None
        found.append(struct(scheme = scheme, authority = authority, userinfo = userinfo))
    return found

def has_credentials(text):
    """Whether any URL of a text carries credentials.

    Args:
        text: Any text.

    Returns:
        Whether a URL holds user information other than an SSH user name.
    """
    for url in urls_in(text):
        if url.userinfo == None:
            continue
        if url.scheme in _SSH_SCHEMES and ":" not in url.userinfo:
            continue
        return True
    return False

_HEX = "0123456789abcdefABCDEF"
_DIGITS = "0123456789"

# RFC 3986 section 2: unreserved and sub-delims characters, and those a path also allows.
_UNRESERVED = _ALPHA + _DIGITS + "-._~"
_SUB_DELIMS = "!$&'()*+,;="
_PATH_CHARS = _UNRESERVED + _SUB_DELIMS + ":@/?#%"

def _percent_escapes_valid(text):
    """Whether every `%` of a text starts a percent escape of two hex digits (RFC 3986 2.1)."""
    for i in range(len(text)):
        if text[i] == "%" and (i + 2 >= len(text) or text[i + 1] not in _HEX or text[i + 2] not in _HEX):
            return False
    return True

def _host_valid(host):
    """Whether a host is an IP literal (`[...]`) or a registered name or IPv4 address (RFC 3986 3.2.2)."""
    if host.startswith("[") and host.endswith("]"):
        return len(host) > 2 and not [c for c in host[1:-1].elems() if c not in _HEX + ":."]
    return host != "" and not [c for c in host.elems() if c not in _UNRESERVED + _SUB_DELIMS + "%"]

def is_download_url(text):
    """Whether a text is an `http` or `https` URL with a host and no user information.

    The scheme is compared without case (RFC 3986 section 3.1); the authority is a host (a
    registered name, an IPv4 address or an IP literal) and an optional port of digits (3.2.2,
    3.2.3); the rest holds only URL characters and valid percent escapes (2.1).

    Args:
        text: Any text.

    Returns:
        Whether Bazel's downloader may be given it as a URL.
    """
    scheme, separator, rest = text.partition("://")
    if not separator or scheme.lower() not in ("http", "https"):
        return False
    authority = _authority_after(rest, 0)
    tail = rest[len(authority):]
    if "@" in authority:
        return False
    host, port = authority, ""
    if authority.startswith("["):
        close = authority.find("]")
        if close < 0:
            return False
        host, port = authority[:close + 1], authority[close + 1:]
        if port and not port.startswith(":"):
            return False
        port = port[1:]
    elif ":" in authority:
        host, _, port = authority.rpartition(":")
    if not _host_valid(host) or [c for c in port.elems() if c not in _DIGITS]:
        return False
    if [c for c in tail.elems() if c not in _PATH_CHARS]:
        return False
    return _percent_escapes_valid(host + tail)
