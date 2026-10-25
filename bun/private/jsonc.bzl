"""JSONC, the syntax of `bun.lock` (FR-007, research L1): JSON with comments and trailing commas.

Errors are returned as values, not raised, so that callers and unit tests can read the message.
"""

_INVALID = struct()

def _line(text, index):
    return text.count("\n", 0, index) + 1

def _without_trailing_commas(chunk):
    """Removes each `,` of a text outside strings that only whitespace separates from `}` or `]`."""
    if "," not in chunk:
        return chunk
    out = []
    start = 0
    for _ in range(len(chunk)):
        comma = chunk.find(",", start)
        if comma == -1:
            break
        rest = chunk[comma + 1:].lstrip(" \t\r\n")
        out.append(chunk[start:comma])
        if not (rest.startswith("}") or rest.startswith("]")):
            out.append(",")
        start = comma + 1
    out.append(chunk[start:])
    return "".join(out)

def _string_end(text, quote):
    """Returns the index of the `"` closing the string opened at `quote`, or -1."""
    search = quote + 1
    for _ in range(len(text)):
        end = text.find("\"", search)
        if end == -1:
            return -1
        backslashes = 0
        for i in range(end - 1, quote, -1):
            if text[i] != "\\":
                break
            backslashes += 1
        if backslashes % 2 == 0:
            return end
        search = end + 1
    return -1

def jsonc_to_json(text, file):
    """Removes comments and trailing commas outside strings.

    Args:
        text: JSONC text.
        file: The file's name, for error messages.

    Returns:
        `struct(value, error)`: `value` is the JSON text, or `None` with `error` an English message
        naming the file.
    """
    out = []
    structural = []
    pos = 0
    n = len(text)
    slash = -2
    for _ in range(n + 1):
        if pos >= n:
            break
        quote = text.find("\"", pos)

        # The next "/" is searched again only once it lies behind: in a lockfile
        # most "/" are inside strings, far ahead.
        if slash != -1 and slash < pos:
            slash = text.find("/", pos)
        if slash != -1 and (quote == -1 or slash < quote):
            structural.append(text[pos:slash])
            following = text[slash + 1:slash + 2]
            if following == "/":
                newline = text.find("\n", slash)
                pos = n if newline == -1 else newline
            elif following == "*":
                close = text.find("*/", slash + 2)
                if close == -1:
                    return struct(value = None, error = "{}: the comment starting on line {} is not closed".format(file, _line(text, slash)))
                pos = close + 2
            else:
                structural.append("/")
                pos = slash + 1
            continue
        if quote == -1:
            structural.append(text[pos:])
            break
        structural.append(text[pos:quote])
        out.append(_without_trailing_commas("".join(structural)))
        structural = []
        end = _string_end(text, quote)
        if end == -1:
            return struct(value = None, error = "{}: the string starting on line {} is not closed".format(file, _line(text, quote)))
        out.append(text[quote:end + 1])
        pos = end + 1
    out.append(_without_trailing_commas("".join(structural)))
    return struct(value = "".join(out), error = None)

def jsonc_decode(text, file):
    """Decodes JSONC text.

    Args:
        text: JSONC text.
        file: The file's name, for error messages.

    Returns:
        `struct(value, error)`: `value` is the decoded value, or `None` with `error` an English
        message naming the file.
    """
    result = jsonc_to_json(text, file)
    if result.error:
        return result
    value = json.decode(result.value, default = _INVALID)
    if value == _INVALID:
        return struct(value = None, error = "{}: the file is not valid JSON once comments and trailing commas are removed".format(file))
    return struct(value = value, error = None)
