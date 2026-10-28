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

def is_download_url(text):
    """Whether a text is exactly one `http` or `https` URL with a host and no user information.

    Args:
        text: Any text.

    Returns:
        Whether Bazel's downloader may be given it as a URL.
    """
    for scheme in ["https://", "http://"]:
        if text.startswith(scheme):
            if [c for c in text.elems() if c in _ENDS]:
                return False
            authority = _authority_after(text, len(scheme))
            return authority != "" and "@" not in authority
    return False
