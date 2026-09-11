_MAX_SEGMENTS = 4

def _parse_number(text, version):
    if not text:
        fail("버전 \"{}\" 의 세그먼트가 비어 있다.".format(version))
    for ch in text.elems():
        if not ch.isdigit():
            fail(
                "버전 \"{}\" 에 숫자가 아닌 세그먼트 \"{}\" 가 있다. ".format(version, text) +
                "지원 형식은 `<숫자>(.<숫자>)*` 이며 뒤에 `-<prerelease>` 를 붙일 수 있다.",
            )
    return int(text)

def version_key(version):
    if not version:
        fail("버전 문자열이 비어 있다.")

    parts = version.split("-", 1)
    core = parts[0]
    prerelease = parts[1] if len(parts) > 1 else ""

    segments = core.split(".")
    if len(segments) > _MAX_SEGMENTS:
        fail(
            "버전 \"{}\" 의 세그먼트가 {} 개다. 최대 {} 개까지 지원한다.".format(
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
    if not versions:
        fail("버전 목록이 비어 있다.")

    best = versions[0]
    best_key = version_key(best)
    for candidate in versions[1:]:
        key = version_key(candidate)
        if key > best_key:
            best, best_key = candidate, key
    return best
