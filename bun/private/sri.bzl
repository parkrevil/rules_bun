"""Subresource Integrity values as Bazel's `integrity` attributes take them (feature 005, P5)."""

_BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

# Digest length in bytes of each algorithm Bazel's downloader verifies.
_DIGEST_BYTES = {"sha256": 32, "sha384": 48, "sha512": 64}

def is_sri(value):
    """Whether `value` is `<algorithm>-<digest>` with the canonical standard base64 of a digest.

    The algorithm is `sha256`, `sha384` or `sha512`; the digest has exactly that algorithm's length,
    with the `=` padding standard base64 (RFC 4648 section 4) requires and zero bits after the last
    byte, so every accepted value is the one encoding of one digest.

    Args:
        value: The text to check.

    Returns:
        Whether it is such a value.
    """
    algorithm, separator, digest = value.partition("-")
    if not separator or algorithm not in _DIGEST_BYTES:
        return False
    size = _DIGEST_BYTES[algorithm]
    padding = (3 - size % 3) % 3
    data = (size * 8 + 5) // 6
    if len(digest) != data + padding or digest[data:] != "=" * padding:
        return False
    if [c for c in digest[:data].elems() if c not in _BASE64]:
        return False

    # The bits of the last character beyond the digest's last byte must be zero.
    unused = data * 6 - size * 8
    return _BASE64.index(digest[data - 1]) % (1 << unused) == 0
