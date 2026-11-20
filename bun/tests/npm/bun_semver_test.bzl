"""Unit tests for `//bun/private:bun_semver.bzl` (research R5).

Every case is taken from Bun's own semver tests at the pinned tag,
`test/cli/install/semver.test.ts` @ bun-v1.4.4, and cites its line there. Only versions written in
full (`<major>.<minor>.<patch>`) are tested against ranges, because a resolution in `bun.lock`
always is one (`Resolution::from_text_lockfile` refuses a partial version).
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//bun/private:bun_semver.bzl",
    "parse_query",
    "parse_version",
    "query_intersects",
    "query_is_star",
    "query_satisfies",
    "version_eql",
    "version_order",
    "version_order_without_build",
)

def _version(text):
    return parse_version(text).version_min

# semver.test.ts L155-L197 ("comparisons"): `left` orders above `right`.
_GREATER = [
    ("0.0.0", "0.0.0-foo"),  # L157
    ("0.0.1", "0.0.0"),  # L158
    ("1.0.0", "0.9.9"),  # L159
    ("0.10.0", "0.9.0"),  # L160
    ("0.99.0", "0.10.0"),  # L161
    ("2.0.0", "1.2.3"),  # L162
    ("v0.0.0", "0.0.0-foo"),  # L163
    ("v2.0.0", "1.2.3"),  # L168
    ("0.0.0", "v0.0.0-foo"),  # L169
    ("1.2.3", "1.2.3-asdf"),  # L175
    ("1.2.3", "1.2.3-4"),  # L176
    ("1.2.3", "1.2.3-4-foo"),  # L177
    ("1.2.3-5-foo", "1.2.3-5"),  # L178
    ("1.2.3-5", "1.2.3-4"),  # L179
    ("1.2.3-5-foo", "1.2.3-5-Foo"),  # L180
    ("3.0.0", "2.7.2+asdf"),  # L181
    ("1.2.3-a.10", "1.2.3-a.5"),  # L182
    ("1.2.3-a.b", "1.2.3-a.5"),  # L183
    ("1.2.3-a.b", "1.2.3-a"),  # L184
    ("1.2.3-a.b.c.10.d.5", "1.2.3-a.b.c.5.d.100"),  # L185
    ("1.2.3-r2", "1.2.3-r100"),  # L186
    ("1.2.3-r100", "1.2.3-R2"),  # L187
    ("1.0.0-pre.a.b", "1.0.0-pre.a"),  # L188
    ("1.0.0-alpha.22-alpha.jkwejf334jkj43", "1.0.0-alpha.3"),  # L189
    ("1.0.0-alpha.1beta", "1.0.0-alpha.2"),  # L190
]

# semver.test.ts L221-L270 ("equality"): equal versions.
_EQUAL = [
    ("1.2.3", "v1.2.3"),  # L224
    ("1.2.3", "=1.2.3"),  # L225
    ("1.2.3", "v 1.2.3"),  # L226
    ("1.2.3", " = 1.2.3"),  # L231
    ("1.2.3-0", "v1.2.3-0"),  # L232
    ("1.2.3-1", " v 1.2.3-1"),  # L246
    ("1.2.3-beta", "=1.2.3-beta"),  # L249
    ("1.2.3-beta", " = 1.2.3-beta"),  # L255
    ("1.1.1-next.0 ", "1.1.1-next.0    "),  # L262
    ("1.1.1-next.0.a ", "1.1.1-next.0.a    "),  # L263
]

# semver.test.ts L256-L264: equal when build metadata is left out of the order.
_EQUAL_WITHOUT_BUILD = [
    ("1.2.3-beta+build", " = 1.2.3-beta+otherbuild"),  # L256
    ("1.2.3+build", " = 1.2.3+otherbuild"),  # L257
    ("1.2.3-beta+build", "1.2.3-beta+otherbuild"),  # L258
    ("1.2.3+build", "1.2.3+otherbuild"),  # L259
    ("  v1.2.3+build", "1.2.3+otherbuild"),  # L260
    ("1.1.1-next.0.a+abc ", "1.1.1-next.0.a+jkejf    "),  # L264
]

# `(range, version, satisfies)`, each from `testSatisfies(range, version, expected)` or a table row.
_SATISFIES = [
    # L363-L373 ("exact versions")
    ("1.2.3", "1.2.3", True),  # L364
    ("4.0.0", "4.0.0", True),  # L366
    ("5.0.0-beta.1", "5.0.0-beta.1", True),  # L368
    ("5.0.0-beta.1", "5.0.0-beta.2", False),  # L369
    ("5.0.0-beta.1", "5.0.0-beta.0", False),  # L370
    ("5.0.0-beta.1", "5.0.0", False),  # L372
    # L723- ("ranges")
    ("~1.2.3", "1.2.3", True),  # L724
    ("~1.2", "1.2.0", True),  # L725
    ("~1", "1.0.0", True),  # L726
    ("~1", "1.2.999", True),  # L728
    ("~0.2", "0.2.1", True),  # L731
    ("~0 ", "0.0.0", True),  # L732
    ("~1.2.3", "1.3.0", False),  # L734
    ("~1", "2.0.0", False),  # L736
    ("~0.2.3", "0.3.0", False),  # L737
    ("~0.2", "0.1.0", False),  # L740
    ("~3.0.5", "3.3.0", False),  # L743
    ("^1.1.4", "1.1.4", True),  # L745
    (">=3", "3.5.0", True),  # L747
    (">=3", "2.999.999", False),  # L748
    ("<6 >= 5", "5.0.0", True),  # L752
    ("<6 >= 5", "4.0.0", False),  # L753
    ("<6 >= 5", "6.0.0", False),  # L754
    (">1.3", "1.3.1", False),  # L761
    (">1.3", "2.0.0", True),  # L762
    (">2.1.0", "2.2.0", True),  # L763
    ("<=2.2.99999", "2.2.0", True),  # L764
    ("<2.2.99999", "2.2.0", True),  # L766
    ("1.0.0", "2.0.0", False),  # L770
    ("1.0.0 || 2.0.0", "1.0.0", True),  # L772
    ("2.0.0 || 1.0.0", "2.0.0", True),  # L775
    ("2.0.0 || >1.0.0", "2.0.0", True),  # L776
    (">1.0.0 <2.0.0 <2.0.1 >1.0.1", "1.0.2", True),  # L778
    ("2.x", "2.3.3", True),  # L786
    ("<2.0.1 >1.0.0", "2.0.0", True),  # L788
    ("^2", "2.9.9", True),  # L792
    ("~2.2", "2.2.1", True),  # L795
    ("2.1.0 || > 2.2 || >3", "2.1.0", True),  # L797
    ("> 2.2 || 2.1.0 || >3", "2.2.1", False),  # L801
    ("> 2.2 || 2.1.0 || >3", "3.0.1", True),  # L804
    ("1.2.0 - 1.3.0", "1.2.2", True),  # L808
    ("1.2 - 1.3", "1.2.2", True),  # L809
    ("1 - 1.3", "1.3.0", True),  # L811
    ("1.2 - 1.3", "1.3.1", True),  # L812
    ("1.2 - 1.3", "1.4.0", False),  # L813
    ("1.2 - 1.3 || 5.0", "6.4.0", False),  # L816
    ("5.0 || 1.2 - 1.3", "1.2.1", True),  # L818
    ("5.0 || 1.2 - 1.3 || >8", "9.0.2", True),  # L825
    (">=0.34.0-next.3 <1.0.0", "0.34.0-next.8", True),  # L827
    ("<1.0.0", "0.34.0-next.8", False),  # L828
    ("<=7.0.0", "7.0.0-rc2", False),  # L830
    (">=7.0.0", "7.0.0-rc2", False),  # L831
    ("<=7.0.0-rc2", "7.0.0-rc2", True),  # L832
    (">=7.0.0-rc2", "7.0.0-rc2", True),  # L833
    ("^1.2.3-pr.1 || >=1.2.4-alpha", "1.2.4-alpha.notready", True),  # L835
    ("^3.0.0-next.0||^3.0.0", "3.0.0-next.2", True),  # L837
    ("^2 <2.2 || > 2.3", "2.2.0", False),  # L882 (`notPassing`, L839-L879)
    ("> 2.3 || ^2 <2.2", "1.0.0-rc.1", False),  # L883
    ("^2 <2.2 || > 2.3", "2.4.0", True),  # L955 (`passing`, L886-L952)
    ("> 2.3 || ^2 <2.2", "2.1.0", True),  # L956
    # L394- ("> with a partial version starts at the next major or minor")
    (">1 >=2.0.0-rc.0", "2.0.0-rc.1", False),  # L399
    (">1.2 <=1.3.0-rc.5", "1.3.0-rc.1", False),  # L418
    # L536- ("a derived upper bound excludes the prereleases of its own version")
    (">=2.0.0-rc.0 ^1.2.3", "2.0.0-rc.1", False),  # L541
    (">=0.0.2-rc.0 ^0.0.1", "0.0.2-rc.1", False),  # L546
    ("~1.5.0 >=1.6.0-beta", "1.6.0-beta.2", False),  # L547
    ("1.0.0 - 1.5 >=1.6.0-beta", "1.6.0-beta.2", False),  # L565
    ("^1.2.3", "1.9.0", True),  # L570
    ("^1.2.3-alpha", "1.2.3-pre", True),  # L572
    ("1.0.0 - 1.5", "1.5.9", True),  # L574
    ("<2 >=1.5.0-rc.0", "1.5.0-rc.1", True),  # L576
    (">=2.0.0-rc.0 <2.0.0", "2.0.0-rc.1", True),  # L579
    ("^1.2.3", "2.0.0-0", False),  # L583
    ("^1.2.3", "1.5.0-beta", False),  # L586
    ("^1.2.3-alpha", "2.0.0-alpha", False),  # L587
    (">=1.6.0-beta <1.6.0-0", "1.6.0-beta.2", False),  # L590
]

# semver.test.ts L1915- ("range intersection"): `(left, right, intersects)`, checked both ways.
_INTERSECTS = [
    ("1.0.0", "1.0.0", True),  # L1918
    ("1.0.0", "1.0.1", False),  # L1919
    ("1.0.0", "^1.0.0", True),  # L1920
    ("2.0.0", "^1.0.0", False),  # L1922
    ("1.0.0", ">1.0.0", False),  # L1924
    ("3.0.0", "1.0.0 || 2.0.0", False),  # L1928
    ("1.2.3", "1.3", False),  # L1931
    ("1.2.3", "*", True),  # L1935
    ("2.0.1", "1.0.0 - 2.0.0", False),  # L1938
    ("^1.0.0", "^1.2.0", True),  # L1942
    ("^1.0.0", "^2.0.0", False),  # L1943
    ("^0.1.0", "^0.2.0", False),  # L1945
    ("^0.1.0", "^0.1.5", True),  # L1946
    ("^0.0.1", "^0.0.2", False),  # L1947
    ("^1.2.3", "1.2.2", False),  # L1950
    ("~1.2.0", "~1.3.0", False),  # L1955
    ("~1.2.0", "^1.0.0", True),  # L1957
    ("~1.2", "~1.3", False),  # L1960
]

def _order_test_impl(ctx):
    env = unittest.begin(ctx)
    for left, right in _GREATER:
        lhs, rhs = _version(left), _version(right)
        asserts.equals(env, 1, version_order(lhs, rhs), "{} > {}".format(left, right))
        asserts.equals(env, -1, version_order(rhs, lhs), "{} < {}".format(right, left))
        asserts.equals(env, 0, version_order(lhs, lhs), "{} = {}".format(left, left))
    return unittest.end(env)

def _equality_test_impl(ctx):
    env = unittest.begin(ctx)
    for left, right in _EQUAL:
        lhs, rhs = _version(left), _version(right)
        asserts.equals(env, 0, version_order(lhs, rhs), "{} = {}".format(left, right))
        asserts.true(env, version_eql(lhs, rhs), "{} eql {}".format(left, right))
    for left, right in _EQUAL_WITHOUT_BUILD:
        lhs, rhs = _version(left), _version(right)
        asserts.equals(env, 0, version_order_without_build(lhs, rhs), "{} = {}".format(left, right))

        # `Version::eql` compares the prerelease only (Version.rs L275-L280, L1136-L1138).
        asserts.true(env, version_eql(lhs, rhs), "{} eql {}".format(left, right))
    return unittest.end(env)

def _parse_test_impl(ctx):
    env = unittest.begin(ctx)

    # Version.rs L520-L719: a resolution needs all three numbers (resolution.rs L213-L218).
    full = parse_version("1.2.3-beta.1+build.5")
    asserts.true(env, full.valid)
    asserts.equals(env, [1, 2, 3], [full.major, full.minor, full.patch])
    asserts.equals(env, ["beta.1", "build.5"], [full.version_min.pre, full.version_min.build])
    partial = parse_version("1.2")
    asserts.true(env, partial.valid)
    asserts.equals(env, None, partial.patch)
    asserts.equals(env, "patch", partial.wildcard)

    # semver.test.ts L273-L301: a number above u64::MAX is not a version.
    asserts.false(env, parse_version("18446744073709551616.0.0").valid)
    asserts.true(env, parse_version("18446744073709551615.0.0").valid)

    # semver.test.ts L303-L312: a `-` in build metadata belongs to the build metadata.
    build = parse_version("1.2.3+build-1").version_min
    asserts.equals(env, ["", "build-1"], [build.pre, build.build])
    return unittest.end(env)

def _satisfies_test_impl(ctx):
    env = unittest.begin(ctx)
    for text, version, expected in _SATISFIES:
        query = parse_query(text)
        parsed = parse_version(version)
        asserts.true(env, parsed.valid and parsed.patch != None, "{} is a full version".format(version))
        asserts.equals(env, expected, query_satisfies(query, parsed.version_min), "{} satisfies {}".format(version, text))
    return unittest.end(env)

def _star_test_impl(ctx):
    env = unittest.begin(ctx)

    # SemverQuery.rs L495-L503: `*`, `x` and `>=0.0.0` are any version; a build tag is not.
    for text in ["*", "x", "X", ">=0.0.0"]:
        asserts.true(env, query_is_star(parse_query(text)), text)
    for text in ["^1.0.0", "1.x", ">=0.0.0+build", "1.0.0 || *"]:
        asserts.false(env, query_is_star(parse_query(text)), text)

    # semver.test.ts L612-L620: a range with a number above u64::MAX is satisfied by nothing.
    asserts.false(env, query_satisfies(parse_query("^18446744073709551616"), _version("1.0.0")))
    return unittest.end(env)

def _intersects_test_impl(ctx):
    env = unittest.begin(ctx)
    for left, right, expected in _INTERSECTS:
        asserts.equals(env, expected, query_intersects(parse_query(left), parse_query(right)), "{} and {}".format(left, right))
        asserts.equals(env, expected, query_intersects(parse_query(right), parse_query(left)), "{} and {}".format(right, left))
    return unittest.end(env)

order_test = unittest.make(_order_test_impl)
equality_test = unittest.make(_equality_test_impl)
parse_test = unittest.make(_parse_test_impl)
satisfies_test = unittest.make(_satisfies_test_impl)
star_test = unittest.make(_star_test_impl)
intersects_test = unittest.make(_intersects_test_impl)

def bun_semver_test_suite(name):
    unittest.suite(
        name,
        order_test,
        equality_test,
        parse_test,
        satisfies_test,
        star_test,
        intersects_test,
    )
