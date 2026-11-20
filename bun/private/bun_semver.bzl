"""Bun's semver, carried over from `src/semver` at bun-v1.4.4 (research R5, Part 2 S3, S5).

Versions, their order, npm ranges and `satisfies`: only the parts the loader's version-based peers
(S3), the shared peer versions (S5) and the hoister call. A version is
`struct(major, minor, patch, pre, build)`; Bun's `ExternalString` tags are plain strings here. A
range group (`Query::Group`) is `struct(lists, flags)`: `lists` is the OR of `Query::List`s, each
the AND of `Range`s (`struct(left, right)`, each a `Comparator` `struct(op, version)`).

Starlark has no `while` and no recursion: each Bun loop is a bounded `for`.
"""

U64_MAX = 18446744073709551615

_DIGITS = "0123456789"
_ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
_WHITESPACE = [" ", "\t", "\n", "\r", "\013", "\014"]

def _version(major = 0, minor = 0, patch = 0, pre = "", build = ""):
    """`Version`: three numbers and the prerelease and build tags.

    Bun: src/semver/Version.rs L56–L65 @ bun-v1.4.4
    """
    return struct(major = major, minor = minor, patch = patch, pre = pre, build = build)

_ZERO_PRE = "0"
_EMPTY_FLOOR = struct(pre = "", build = "")

def _parse_ascii(text):
    """`u64::parse_ascii`: `None` for empty text, a non-digit or a number above `u64::MAX`.

    Bun: src/semver/Version.rs L27–L38 @ bun-v1.4.4
    """
    if not text:
        return None
    for c in text.elems():
        if c not in _DIGITS:
            return None
    number = int(text)
    return number if number <= U64_MAX else None

def _length_of_leading_whitespace_ascii(text, start):
    """`strings::length_of_leading_whitespace_ascii` of `text[start:]`, as the range parser uses it.

    Bun: src/semver/SemverQuery.rs L912–L942 @ bun-v1.4.4
    Bun: src/bun_core/string/immutable.rs L1956–L1971 @ bun-v1.4.4
    """
    count = 0
    for i in range(start, len(text)):
        if text[i] not in _WHITESPACE:
            break
        count += 1
    return count

def parse_tag(text, initial_pre_count = 0):
    """`Tag::parse_with_pre_count`: the prerelease and build tag at the start of `text`.

    Bun: src/semver/Version.rs L1140–L1252 @ bun-v1.4.4

    Args:
        text: The text from the `-` or `+` (or, with `initial_pre_count`, the first letter) on.
        initial_pre_count: 1 when the text is a prerelease without `-` (`1.0.0rc.1`).

    Returns:
        `struct(pre, build, len)`.
    """
    build_count = 0
    pre_count = initial_pre_count
    for c in text.elems():
        if c == " ":
            break
        if c == "+":
            build_count += 1
        elif c == "-":
            pre_count += 1
    if build_count == 0 and pre_count == 0:
        return struct(pre = "", build = "", len = 0)

    pre = ""
    build = ""
    state = "none"
    start = 0
    i = 0
    for _ in range(len(text)):
        if i >= len(text):
            break
        c = text[i]
        if c == "+":
            if state == "pre" or (state == "none" and initial_pre_count > 0):
                pre = text[start:i]
            if state != "build":
                state = "build"
                start = i + 1
        elif c == "-":
            if state == "none":
                state = "pre"
                start = i + 1
        elif c in _ALPHA or c in _DIGITS or c == ".":
            pass
        else:
            if state == "pre":
                pre = text[start:i]
                state = "none"
            elif state == "build":
                build = text[start:i]
                state = "none"
            break
        i += 1

    if state == "none" and initial_pre_count > 0:
        state = "pre"
        start = 0
    if state == "pre":
        pre = text[start:i]
    elif state == "build":
        build = text[start:i]
    return struct(pre = pre, build = build, len = i)

def parse_version(text):
    """`Version::parse`: a version, possibly partial or with a wildcard, at the start of `text`.

    Bun: src/semver/Version.rs L520–L728 @ bun-v1.4.4
    Bun: src/semver/Version.rs L963–L972 @ bun-v1.4.4

    Args:
        text: The text.

    Returns:
        `struct(wildcard, valid, overflow, major, minor, patch, pre, build, len, version_min)`:
        `wildcard` is `none`, `major`, `minor` or `patch`; a missing number is `None`;
        `version_min` is `Partial::min`, missing numbers read as 0.
    """
    n = len(text)
    valid = True
    overflow = False
    wildcard = "none"
    parts = [None, None, None]
    pre = ""
    build = ""
    part_i = 0

    i = n
    for c in range(n):
        if text[c] not in _WHITESPACE and text[c] not in ["v", "="]:
            i = c
            break
    if n == 0 or i == n:
        return _parse_result(
            wildcard = "major" if n > 0 else "none",
            valid = False,
            overflow = False,
            parts = parts,
            pre = pre,
            build = build,
            length = i if n > 0 else 0,
        )

    is_done = False
    for _ in range(n + 1):
        if i >= n or is_done:
            break
        c = text[i]
        if c == " ":
            is_done = True
            break
        elif c in ["|", "^", "#", "&", "%", "!"]:
            is_done = True
            i = i - 1 if i > 0 else 0
            break
        elif c in _DIGITS:
            part_start = i
            i += 1
            for _ in range(n):
                if i < n and text[i] in _DIGITS:
                    i += 1
                else:
                    break
            if part_i < 3:
                number = _parse_ascii(text[part_start:i])
                if number == None:
                    valid = False

                    # A range ignores a number after a wildcard, so keep reading the token.
                    if wildcard == "none":
                        overflow = True
                        is_done = True
                        break
                parts[part_i] = number
                part_i += 1
            if i < n and text[i] == "." and part_i != 3:
                i += 1
        elif c == ".":
            valid = False
            is_done = True
            break
        elif c in ["-", "+"]:
            fewest_parts = 1 if c == "+" else 2
            if part_i < fewest_parts and wildcard == "none":
                valid = False
                is_done = True
                break
            tag = parse_tag(text[i:])
            pre, build = tag.pre, tag.build
            i += tag.len
            break
        elif c in ["x", "*", "X"]:
            if i > 0 and text[i - 1] in _DIGITS:
                valid = False
            i += 1
            for _ in range(n):
                if i < n and text[i] in ["x", "*", "X"]:
                    i += 1
                else:
                    break
            if i < n and text[i] == ".":
                i += 1
            if wildcard == "none":
                if part_i == 0:
                    wildcard = "major"
                    part_i = 1
                elif part_i == 1:
                    wildcard = "minor"
                    part_i = 2
                elif part_i == 2:
                    wildcard = "patch"
                    part_i = 3
        else:
            if wildcard == "none" and part_i >= 2 and c in _ALPHA:
                tag = parse_tag(text[i:], 1)
                pre, build = tag.pre, tag.build
                i += tag.len
                is_done = True
                break
            valid = False
            is_done = True
            break

    if wildcard == "none":
        if part_i == 0:
            valid = False
            wildcard = "major"
        elif part_i == 1:
            wildcard = "minor"
        elif part_i == 2:
            wildcard = "patch"

    return _parse_result(wildcard, valid, overflow, parts, pre, build, i)

def _parse_result(wildcard, valid, overflow, parts, pre, build, length):
    """`ParseResult` with `Partial::min` as `version_min`.

    Bun: src/semver/Version.rs L1264–L1286 @ bun-v1.4.4
    Bun: src/semver/Version.rs L963–L972 @ bun-v1.4.4
    """
    return struct(
        wildcard = wildcard,
        valid = valid,
        overflow = overflow,
        major = parts[0],
        minor = parts[1],
        patch = parts[2],
        pre = pre,
        build = build,
        len = length,
        version_min = _version(
            major = parts[0] if parts[0] != None else 0,
            minor = parts[1] if parts[1] != None else 0,
            patch = parts[2] if parts[2] != None else 0,
            pre = pre,
            build = build,
        ),
    )

def _cmp(lhs, rhs):
    """`Ord::cmp` of two numbers or strings, as the version order compares them.

    Bun: src/semver/Version.rs L469–L500 @ bun-v1.4.4
    Bun: src/semver/lib.rs L169–L176 @ bun-v1.4.4
    Bun: src/semver/lib.rs L299–L301 @ bun-v1.4.4

    Strings compare by `strings::order`, byte by byte, as Starlark compares ASCII strings.
    """
    if lhs < rhs:
        return -1
    if lhs > rhs:
        return 1
    return 0

def _order_pre(lhs, rhs):
    """`Tag::order_pre`: dot-separated parts, numbers below words.

    Bun: src/semver/Version.rs L1014–L1075 @ bun-v1.4.4
    """
    lhs_parts = lhs.split(".")
    rhs_parts = rhs.split(".")
    for i in range(max(len(lhs_parts), len(rhs_parts)) + 1):
        lhs_part = lhs_parts[i] if i < len(lhs_parts) else None
        rhs_part = rhs_parts[i] if i < len(rhs_parts) else None
        if lhs_part == None and rhs_part == None:
            return 0
        if rhs_part == None:
            return 1
        if lhs_part == None:
            return -1
        lhs_uint = _parse_ascii(lhs_part)
        rhs_uint = _parse_ascii(rhs_part)
        if lhs_uint != None and rhs_uint == None:
            return -1
        if lhs_uint == None and rhs_uint != None:
            return 1
        if lhs_uint == None and rhs_uint == None:
            order = _cmp(lhs_part, rhs_part)
            if order != 0:
                return order
            continue
        order = _cmp(lhs_uint, rhs_uint)
        if order != 0:
            return order
    return 0

def _tag_order(lhs, rhs):
    """`Tag::order`.

    Bun: src/semver/Version.rs L1077–L1088 @ bun-v1.4.4
    """
    if lhs.pre and rhs.pre:
        return _order_pre(lhs.pre, rhs.pre)
    pre_order = _cmp(lhs.pre, rhs.pre)
    if pre_order != 0:
        return pre_order
    return _cmp(lhs.build, rhs.build)

def _tag_order_without_build(lhs, rhs):
    """`Tag::order_without_build`.

    Bun: src/semver/Version.rs L1090–L1096 @ bun-v1.4.4
    """
    if lhs.pre and rhs.pre:
        return _order_pre(lhs.pre, rhs.pre)
    return _cmp(lhs.pre, rhs.pre)

def _order_without_tag(lhs, rhs):
    """`Version::order_without_tag`: the numbers, then a prerelease below none.

    Bun: src/semver/Version.rs L469–L500 @ bun-v1.4.4
    """
    order = _cmp(lhs.major, rhs.major) or _cmp(lhs.minor, rhs.minor) or _cmp(lhs.patch, rhs.patch)
    if order != 0:
        return order
    if lhs.pre:
        if not rhs.pre:
            return -1
    elif rhs.pre:
        return 1
    return 0

def version_order(lhs, rhs):
    """`Version::order`, the build tag included.

    Bun: src/semver/Version.rs L502–L509 @ bun-v1.4.4

    Args:
        lhs: A version.
        rhs: A version.

    Returns:
        -1, 0 or 1.
    """
    order = _order_without_tag(lhs, rhs)
    if order != 0:
        return order
    return _tag_order(lhs, rhs)

def version_order_without_build(lhs, rhs):
    """`Version::order_without_build`.

    Bun: src/semver/Version.rs L511–L518 @ bun-v1.4.4

    Args:
        lhs: A version.
        rhs: A version.

    Returns:
        -1, 0 or 1.
    """
    order = _order_without_tag(lhs, rhs)
    if order != 0:
        return order
    return _tag_order_without_build(lhs, rhs)

def version_eql(lhs, rhs):
    """`Version::eql`: the numbers and the prerelease; the build is not compared.

    Bun: src/semver/Version.rs L275–L280 @ bun-v1.4.4
    Bun: src/semver/Version.rs L1136–L1138 @ bun-v1.4.4

    Args:
        lhs: A version.
        rhs: A version.

    Returns:
        Whether they are equal.
    """
    return lhs.major == rhs.major and lhs.minor == rhs.minor and lhs.patch == rhs.patch and lhs.pre == rhs.pre

def _is_zero(version):
    """`Version::is_zero`.

    Bun: src/semver/Version.rs L158–L160 @ bun-v1.4.4
    """
    return version.major == 0 and version.minor == 0 and version.patch == 0

def _comparator(op = "unset", version = None):
    """`Comparator`: an operator and a version.

    Bun: src/semver/SemverRange.rs L184–L188 @ bun-v1.4.4
    """
    return struct(op = op, version = version if version != None else _version())

_UNSET = _comparator()

def _range(left = _UNSET, right = _UNSET):
    """`Range`: a left and a right comparator.

    Bun: src/semver/SemverRange.rs L20–L24 @ bun-v1.4.4
    """
    return struct(left = left, right = right)

def _null_set():
    """`Comparator::null_set`: `<0.0.0-0`.

    Bun: src/semver/SemverRange.rs L191–L200 @ bun-v1.4.4
    """
    return _comparator("lt", _version(pre = _ZERO_PRE))

def _lt_next_major(major):
    """`Comparator::lt_next_major`.

    Bun: src/semver/SemverRange.rs L202–L224 @ bun-v1.4.4
    """
    if major + 1 <= U64_MAX:
        return _comparator("lt", _version(major = major + 1, pre = _ZERO_PRE))
    return _comparator("lte", _version(major = U64_MAX, minor = U64_MAX, patch = U64_MAX))

def _lt_next_minor(major, minor):
    """`Comparator::lt_next_minor`.

    Bun: src/semver/SemverRange.rs L226–L248 @ bun-v1.4.4
    """
    if minor + 1 <= U64_MAX:
        return _comparator("lt", _version(major = major, minor = minor + 1, pre = _ZERO_PRE))
    return _comparator("lte", _version(major = major, minor = U64_MAX, patch = U64_MAX))

def _lt_next_patch(major, minor, patch):
    """`Comparator::lt_next_patch`.

    Bun: src/semver/SemverRange.rs L250–L273 @ bun-v1.4.4
    """
    if patch + 1 <= U64_MAX:
        return _comparator("lt", _version(major = major, minor = minor, patch = patch + 1, pre = _ZERO_PRE))
    return _comparator("lte", _version(major = major, minor = minor, patch = U64_MAX))

def _gte_next_major(major, tag):
    """`Comparator::gte_next_major`.

    Bun: src/semver/SemverRange.rs L275–L289 @ bun-v1.4.4
    """
    if major + 1 <= U64_MAX:
        return _comparator("gte", _version(major = major + 1, pre = tag.pre, build = tag.build))
    return _null_set()

def _gte_next_minor(major, minor, tag):
    """`Comparator::gte_next_minor`.

    Bun: src/semver/SemverRange.rs L291–L306 @ bun-v1.4.4
    """
    if minor + 1 <= U64_MAX:
        return _comparator("gte", _version(major = major, minor = minor + 1, pre = tag.pre, build = tag.build))
    return _gte_next_major(major, tag)

def _comparator_satisfies(comparator, version):
    """`Comparator::satisfies`.

    Bun: src/semver/SemverRange.rs L320–L337 @ bun-v1.4.4
    """
    order = version_order_without_build(version, comparator.version)
    op = comparator.op
    if order == 0:
        return op in ["lte", "gte", "eql"]
    if order > 0:
        return op in ["gt", "gte"]
    if op == "gte":
        return _is_zero(comparator.version) and not comparator.version.pre
    return op in ["lt", "lte"]

def _init_wildcard(version, wildcard, floor):
    """`Range::init_wildcard`.

    Bun: src/semver/SemverRange.rs L26–L75 @ bun-v1.4.4
    """
    if wildcard == "none":
        return _range(left = _comparator("eql", version))
    if wildcard == "major":
        return _range(left = _comparator("gte", _version(pre = floor.pre, build = floor.build)))
    if wildcard == "minor":
        return _range(
            left = _lt_next_major(version.major),
            right = _comparator("gte", _version(major = version.major, pre = floor.pre, build = floor.build)),
        )
    return _range(
        left = _lt_next_minor(version.major, version.minor),
        right = _comparator("gte", _version(major = version.major, minor = version.minor, pre = floor.pre, build = floor.build)),
    )

def _range_satisfies(r, version):
    """`Range::satisfies`.

    Bun: src/semver/SemverRange.rs L101–L118 @ bun-v1.4.4
    """
    if r.left.op == "unset":
        return True
    if not _comparator_satisfies(r.left, version):
        return False
    if r.right.op != "unset" and not _comparator_satisfies(r.right, version):
        return False
    return True

def _range_satisfies_pre(r, version, pre_matched):
    """`Range::satisfies_pre`: `(satisfies, pre_matched)`.

    Bun: src/semver/SemverRange.rs L120–L157 @ bun-v1.4.4
    """
    has_right = r.right.op != "unset"
    if r.left.op == "unset":
        return True, pre_matched
    left, right = r.left.version, r.right.version
    pre_matched = (
        pre_matched or
        (left.pre != "" and version.patch == left.patch and version.minor == left.minor and version.major == left.major) or
        (has_right and right.pre != "" and version.patch == right.patch and version.minor == right.minor and version.major == right.major)
    )
    if not _comparator_satisfies(r.left, version):
        return False, pre_matched
    if has_right and not _comparator_satisfies(r.right, version):
        return False, pre_matched
    return True, pre_matched

def _to_range(tag, wildcard, parsed, floor):
    """`Token::to_range`.

    Bun: src/semver/SemverQuery.rs L602–L743 @ bun-v1.4.4
    """
    major, minor, patch = parsed.major, parsed.minor, parsed.patch
    version_min = parsed.version_min
    wildcard_is_written = parsed.valid
    if tag == "caret":
        if major == None:
            if wildcard_is_written:
                return _init_wildcard(version_min, "major", floor)
            return _range()
        left_version = _version(major = major, pre = floor.pre, build = floor.build)
        right = None
        if minor != None:
            if patch != None:
                left_version = _version(major = major, minor = minor, patch = patch, pre = parsed.pre, build = parsed.build)
                if major == 0:
                    if not parsed.pre:
                        left_version = _version(major = major, minor = minor, patch = patch, pre = floor.pre, build = parsed.build)
                    right = _lt_next_patch(0, 0, patch) if minor == 0 else _lt_next_minor(0, minor)
                    return _range(left = _comparator("gte", left_version), right = right)
            else:
                left_version = _version(major = major, minor = minor, pre = floor.pre, build = floor.build)
                if major == 0:
                    return _range(left = _comparator("gte", left_version), right = _lt_next_minor(0, minor))
        return _range(left = _comparator("gte", left_version), right = _lt_next_major(major))
    if tag == "tilde":
        if major == None:
            if wildcard_is_written:
                return _init_wildcard(version_min, "major", floor)
            return _range()
        left_version = _version(major = major)
        if minor != None:
            left_version = _version(major = major, minor = minor)
            if patch != None:
                left_version = _version(major = major, minor = minor, patch = patch, pre = parsed.pre, build = parsed.build)
            return _range(left = _comparator("gte", left_version), right = _lt_next_minor(major, minor))
        return _range(left = _comparator("gte", left_version), right = _lt_next_major(major))
    if tag == "version":
        if wildcard != "none":
            return _init_wildcard(version_min, wildcard, floor)
        return _range(left = _comparator("eql", version_min))

    # node-semver's `replaceXRange`
    op = {"gt": "gt", "gte": "gte", "lt": "lt", "lte": "lte"}[tag]
    first_major = major if major != None else 0
    first_minor = minor if minor != None else 0

    def first_of_partial(pre):
        return _comparator(op, _version(major = first_major, minor = first_minor, pre = pre))

    if wildcard == "none":
        left = _comparator(op, version_min)
    elif op in ["gt", "lt"] and wildcard == "major" and wildcard_is_written:
        left = _null_set()
    elif wildcard == "major":
        return _init_wildcard(version_min, "major", floor)
    elif op == "gte":
        left = _comparator(op, _version(major = first_major, minor = first_minor, pre = floor.pre, build = floor.build))
    elif op == "lt":
        left = first_of_partial(_ZERO_PRE)
    elif op == "gt" and wildcard == "minor":
        left = _gte_next_major(first_major, floor)
    elif op == "gt" and wildcard == "patch":
        left = _gte_next_minor(first_major, first_minor, floor)
    elif wildcard == "minor":
        left = _lt_next_major(first_major)
    else:
        left = _lt_next_minor(first_major, first_minor)
    return _range(left = left)

def _or_range(lists, r):
    """`Group::or_range`.

    Bun: src/semver/SemverQuery.rs L519–L538 @ bun-v1.4.4
    """
    if len(lists) == 1 and len(lists[0]) == 1 and lists[0][0].left.op == "unset":
        lists[0][0] = r
        return
    lists.append([r])

def _and_range(lists, r):
    """`Group::and_range` and `List::and_range`.

    Bun: src/semver/SemverQuery.rs L510–L517 @ bun-v1.4.4
    Bun: src/semver/SemverQuery.rs L324–L345 @ bun-v1.4.4
    """
    tail = lists[-1]
    if tail[0].left.op == "unset" and tail[0].right.op == "unset":
        tail[0] = r
        return
    tail.append(r)

def _null_set_group():
    """`Group::null_set`.

    Bun: src/semver/SemverQuery.rs L480–L486 @ bun-v1.4.4
    """
    return struct(lists = [[_range(left = _null_set())]], flags = struct(pre = False, build = False, skipped = False))

def parse_query(text, floor = _EMPTY_FLOOR):
    """`Query::parse`: an npm range (`||`, hyphen, x-ranges, `~`, `^`, comparators).

    Bun: src/semver/SemverQuery.rs L767–L769 @ bun-v1.4.4
    Bun: src/semver/SemverQuery.rs L777–L1030 @ bun-v1.4.4

    Args:
        text: The range.
        floor: The tag of a derived lower bound; empty except with `includePrerelease`.

    Returns:
        `struct(lists, flags)`; `flags` is `struct(pre, build, skipped)`.
    """
    n = len(text)
    lists = [[_range()]]
    flags = {"pre": False, "build": False, "skipped": False}
    token = "none"
    token_wildcard = "none"
    is_or = False
    after_comparator = False
    i = 0

    def skip_spaces(i):
        for _ in range(n):
            if i < n and text[i] == " ":
                i += 1
            else:
                break
        return i

    for _ in range(n + 1):
        if i >= n:
            break
        skip_round = False
        no_operator = False
        c = text[i]
        if c in [">", "<"]:
            i = skip_spaces(i + 1)
            or_equal = i < n and text[i] == "="
            if or_equal:
                i += 1
            if c == ">":
                token = "gte" if or_equal else "gt"
            else:
                token = "lte" if or_equal else "lt"
            i = skip_spaces(i)
        elif c in ["=", "v"]:
            token = "version"
            no_operator = True
            i = skip_spaces(i + 1)
        elif c == "~":
            token = "tilde"
            i += 1
            if i < n and text[i] == ">":
                i += 1
            i = skip_spaces(i)
        elif c == "^":
            token = "caret"
            i = skip_spaces(i + 1)
        elif c in _DIGITS or c in ["X", "x", "*"]:
            token = "version"
            no_operator = True
        elif c == "|":
            i += 1
            for _ in range(n):
                if i < n and text[i] == "|":
                    i += 1
                else:
                    break
            i = skip_spaces(i)
            is_or = True
            token = "none"
            skip_round = True
        elif c == "-":
            i = skip_spaces(i + 1)
        elif c == " ":
            i = skip_spaces(i + 1)
            skip_round = True
        else:
            i += 1
            token = "none"
            after_comparator = False

            # skip tagged versions
            for _ in range(n):
                if i < n and text[i] != " " and text[i] != "|":
                    i += 1
                else:
                    break
            skip_round = True
            flags["skipped"] = True

        if skip_round:
            continue

        parsed = parse_version(text[i:])

        # node-semver rejects the whole range for a number it cannot hold.
        if parsed.overflow:
            return _null_set_group()
        if not parsed.valid:
            flags["skipped"] = True
        if parsed.build:
            flags["build"] = True
        if parsed.pre:
            flags["pre"] = True
        token_wildcard = parsed.wildcard
        i += parsed.len
        rollback = i

        hyphenate = False
        if i < n and (text[i] == " " or text[i] == "-"):
            i += _length_of_leading_whitespace_ascii(text, i)
            if i < n and text[i] == "-":
                i += 1
                i += _length_of_leading_whitespace_ascii(text, i)
                if i != n:
                    if text[i] == "v" or text[i] == "=":
                        i += 1
                    if i != n:
                        i += _length_of_leading_whitespace_ascii(text, i)
                        if i != n and (text[i] in _DIGITS or text[i] in ["X", "x", "*"]):
                            hyphenate = True

        if not hyphenate:
            i = rollback + 1

        valid = parsed.valid and not hyphenate

        # Malformed text ("=>16.0.0", "1.2.3.4") starts an alternative so that it cannot narrow the
        # range.
        if no_operator and not (after_comparator and valid):
            is_or = True

        if hyphenate:
            second = parse_version(text[i:])
            if second.overflow:
                return _null_set_group()
            if not second.valid:
                flags["skipped"] = True
            if second.build:
                flags["build"] = True
            if second.pre:
                flags["pre"] = True
            i += second.len + 1
            first_version = parsed.version_min
            if not first_version.pre:
                first_version = _version(first_version.major, first_version.minor, first_version.patch, floor.pre, first_version.build)
            second_version = second.version_min
            if second.wildcard == "major":
                right = _UNSET
            elif second.wildcard == "minor":
                right = _lt_next_major(second_version.major)
            elif second.wildcard == "patch":
                right = _lt_next_minor(second_version.major, second_version.minor)
            elif floor.pre and not second_version.pre:
                right = _lt_next_patch(second_version.major, second_version.minor, second_version.patch)
            else:
                right = _comparator("lte", second_version)
            r = _range(left = _comparator("gte", first_version), right = right)
        elif token == "none":
            # No pending comparator token for this chunk, so skip it instead of emitting a
            # comparator.
            token_wildcard = "none"
            flags["skipped"] = True
            continue
        else:
            r = _to_range(token, token_wildcard, parsed, floor)

        if is_or:
            _or_range(lists, r)
        else:
            _and_range(lists, r)
        is_or = False
        token_wildcard = "none"
        after_comparator = valid and rollback < n and text[rollback] == " "

    return struct(lists = lists, flags = struct(**flags))

def query_satisfies(group, version):
    """`Group::satisfies`: with a prerelease, `List::satisfies_pre`, else `List::satisfies`.

    Bun: src/semver/SemverQuery.rs L540–L547 @ bun-v1.4.4
    Bun: src/semver/SemverQuery.rs L259–L300 @ bun-v1.4.4
    Bun: src/semver/SemverQuery.rs L122–L156 @ bun-v1.4.4

    Args:
        group: A `parse_query` result.
        version: A version.

    Returns:
        Whether the version satisfies the range.
    """
    if version.pre:
        for ranges in group.lists:
            pre_matched = False
            satisfied = True
            for r in ranges:
                satisfied, pre_matched = _range_satisfies_pre(r, version, pre_matched)
                if not satisfied:
                    break
            if satisfied and pre_matched:
                return True
        return False
    for ranges in group.lists:
        if all([_range_satisfies(r, version) for r in ranges]):
            return True
    return False

def query_is_star(group):
    """`Group::is_star`: one `>=0.0.0` comparator, without a build tag.

    Bun: src/semver/SemverQuery.rs L495–L503 @ bun-v1.4.4

    Args:
        group: A `parse_query` result.

    Returns:
        Whether every version satisfies it.
    """
    if len(group.lists) != 1 or len(group.lists[0]) != 1:
        return False
    r = group.lists[0][0]
    return r.right.op == "unset" and r.left.op == "gte" and _is_zero(r.left.version) and not group.flags.build

def _raise(interval, version, inclusive):
    """`Interval::raise`: the higher lower bound wins; an exclusive one wins a tie.

    Bun: src/semver/intersects.rs L22–L34 @ bun-v1.4.4
    """
    current = interval.get("lower")
    if current == None:
        replace = True
    else:
        order = version_order_without_build(version, current[0])
        replace = order > 0 or (order == 0 and not inclusive)
    if replace:
        interval["lower"] = (version, inclusive)

def _cap(interval, version, inclusive):
    """`Interval::cap`: the lower upper bound wins; an exclusive one wins a tie.

    Bun: src/semver/intersects.rs L36–L48 @ bun-v1.4.4
    """
    current = interval.get("upper")
    if current == None:
        replace = True
    else:
        order = version_order_without_build(version, current[0])
        replace = order < 0 or (order == 0 and not inclusive)
    if replace:
        interval["upper"] = (version, inclusive)

def _narrow(interval, comparator):
    """`Interval::narrow`.

    Bun: src/semver/intersects.rs L50–L67 @ bun-v1.4.4
    """
    op, version = comparator.op, comparator.version
    if op == "eql":
        _raise(interval, version, True)
        _cap(interval, version, True)
    elif op == "gt":
        _raise(interval, version, False)
    elif op == "gte":
        _raise(interval, version, True)
    elif op == "lt":
        _cap(interval, version, False)
    elif op == "lte":
        _cap(interval, version, True)

def _and_query(interval, ranges):
    """`Interval::and_query`: every comparator of an AND chain.

    Bun: src/semver/intersects.rs L69–L76 @ bun-v1.4.4
    """
    for r in ranges:
        _narrow(interval, r.left)
        _narrow(interval, r.right)

def _is_non_empty(interval):
    """`Interval::is_non_empty`.

    Bun: src/semver/intersects.rs L78–L93 @ bun-v1.4.4
    """
    upper = interval.get("upper")
    if upper == None:
        return True
    lower = interval.get("lower") or (_null_set().version, True)
    order = version_order_without_build(lower[0], upper[0])
    if order < 0:
        return True
    if order == 0:
        return lower[1] and upper[1]
    return False

def _exact_version(ranges):
    """`Query::exact_version`: the version of a chain that is one `=version` comparator.

    Bun: src/semver/SemverQuery.rs L93–L98 @ bun-v1.4.4
    """
    if len(ranges) == 1 and ranges[0].left.op == "eql" and ranges[0].right.op == "unset":
        return ranges[0].left.version
    return None

def _query_is_star(ranges):
    """`Query::is_star` of intersects.rs.

    Bun: src/semver/intersects.rs L213–L220 @ bun-v1.4.4
    """
    r = ranges[0]
    return len(ranges) == 1 and r.left.op == "gte" and _is_zero(r.left.version) and not r.left.version.pre and r.right.op == "unset"

def _admits(group, version):
    """`Group::admits`: `satisfies`, or a prerelease against a `*` alternative.

    Bun: src/semver/intersects.rs L230–L233 @ bun-v1.4.4
    """
    return query_satisfies(group, version) or (version.pre != "" and any([_query_is_star(ranges) for ranges in group.lists]))

def _admits_an_exact_version_of(group, other):
    """`Group::admits_an_exact_version_of`.

    Bun: src/semver/intersects.rs L235–L240 @ bun-v1.4.4
    """
    for ranges in other.lists:
        version = _exact_version(ranges)
        if version != None and _admits(group, version):
            return True
    return False

def query_intersects(group, other):
    """`Group::intersects`: whether some version could satisfy both ranges.

    Bun: src/semver/intersects.rs L244–L266 @ bun-v1.4.4

    Args:
        group: A `parse_query` result.
        other: A `parse_query` result.

    Returns:
        Whether the two ranges overlap.
    """
    if _admits_an_exact_version_of(group, other) or _admits_an_exact_version_of(other, group):
        return True
    for a in group.lists:
        if _exact_version(a) != None:
            continue
        base = {}
        _and_query(base, a)
        if not _is_non_empty(base):
            continue
        for b in other.lists:
            if _exact_version(b) != None:
                continue
            interval = dict(base)
            _and_query(interval, b)
            if _is_non_empty(interval):
                return True
    return False
