"""Unit tests for `//bun/private:bun_install_types.bzl` (research R1, Part 2 S7)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//bun/private:bun_install_types.bzl",
    "BEHAVIOR",
    "LIBC_ALL",
    "RESOLUTION_TAG",
    "VERSION_TAG",
    "behavior_cmp",
    "behavior_is_optional",
    "behavior_is_optional_peer",
    "behavior_is_placed",
    "dependency_features",
    "dependency_parse",
    "dependency_sort_key",
    "libc_for_dependency",
    "meta_is_disabled",
    "negatable_from_json_value",
    "platform_value",
    "resolution_eql",
    "resolution_from_text_lockfile",
    "resolution_order",
    "resolution_satisfies_dependency_version",
    "split_name_and_version",
    "version_tag_infer",
)

def _meta(os = None, cpu = None, libc = None):
    return struct(
        os = negatable_from_json_value("os", os),
        arch = negatable_from_json_value("cpu", cpu),
        libc = negatable_from_json_value("libc", libc),
    )

def _disabled(meta, os, cpu, libc):
    return meta_is_disabled(meta, platform_value("cpu", cpu), platform_value("os", os), platform_value("libc", libc))

def _behavior_test_impl(ctx):
    env = unittest.begin(ctx)
    remote = dependency_features(RESOLUTION_TAG.NPM)
    local = dependency_features(RESOLUTION_TAG.WORKSPACE)
    root = dependency_features(RESOLUTION_TAG.ROOT)
    folder = dependency_features(RESOLUTION_TAG.FOLDER)
    asserts.equals(env, local, root)
    asserts.equals(env, local, folder)

    # resolver_hooks.rs L261-L273: a registry package's dev dependency is not placed, a bundled one
    # never is; the root's and a workspace's dev and workspace dependencies are.
    for behavior, at_remote, at_local in [
        (BEHAVIOR.PROD, True, True),
        (BEHAVIOR.OPTIONAL, True, True),
        (BEHAVIOR.PEER, True, True),
        (BEHAVIOR.PEER | BEHAVIOR.OPTIONAL, True, True),
        (BEHAVIOR.DEV, False, True),
        (BEHAVIOR.WORKSPACE, False, True),
        (BEHAVIOR.PROD | BEHAVIOR.BUNDLED, False, False),
    ]:
        asserts.equals(env, at_remote, behavior_is_placed(behavior, remote), "remote {}".format(behavior))
        asserts.equals(env, at_local, behavior_is_placed(behavior, local), "local {}".format(behavior))

    # An optional peer is not optional (resolver_hooks.rs L208-L216).
    asserts.false(env, behavior_is_optional(BEHAVIOR.PEER | BEHAVIOR.OPTIONAL))
    asserts.true(env, behavior_is_optional_peer(BEHAVIOR.PEER | BEHAVIOR.OPTIONAL))
    asserts.true(env, behavior_is_optional(BEHAVIOR.OPTIONAL))

    # Libc::for_dependency (resolver_hooks.rs L882-L890): the target libc filters optional ones.
    musl = platform_value("libc", "musl")
    asserts.equals(env, musl, libc_for_dependency(musl, BEHAVIOR.OPTIONAL))
    asserts.equals(env, LIBC_ALL, libc_for_dependency(musl, BEHAVIOR.PROD))
    asserts.equals(env, LIBC_ALL, libc_for_dependency(musl, BEHAVIOR.PEER | BEHAVIOR.OPTIONAL))
    return unittest.end(env)

def _disabled_test_impl(ctx):
    env = unittest.begin(ctx)

    # Meta::is_disabled (Meta.rs L72-L74) with the npm.rs/resolver_hooks.rs matching.
    asserts.false(env, _disabled(_meta(), "linux", "x64", "glibc"))
    asserts.false(env, _disabled(_meta(os = ["linux"]), "linux", "arm64", "musl"))
    asserts.true(env, _disabled(_meta(os = ["linux"]), "darwin", "arm64", None))
    asserts.true(env, _disabled(_meta(os = "win32"), "linux", "x64", "glibc"))
    asserts.false(env, _disabled(_meta(os = ["!win32"]), "linux", "x64", "glibc"))
    asserts.true(env, _disabled(_meta(os = ["!win32"]), "win32", "x64", None))
    asserts.true(env, _disabled(_meta(os = ["linux", "!linux"]), "linux", "x64", "glibc"))
    asserts.true(env, _disabled(_meta(cpu = ["x64"]), "linux", "arm64", "glibc"))
    asserts.true(env, _disabled(_meta(libc = ["musl"]), "linux", "x64", "glibc"))
    asserts.false(env, _disabled(_meta(libc = ["musl"]), "linux", "x64", "musl"))

    # Negatable::apply/combine (resolver_hooks.rs L613-L687): `any` is every value until a known
    # value follows; `none` and an unknown value alone are no value; an unknown negation is ignored.
    asserts.false(env, _disabled(_meta(os = ["any"]), "aix", "ppc64", None))
    asserts.true(env, _disabled(_meta(os = ["any", "linux"]), "darwin", "x64", None))
    asserts.true(env, _disabled(_meta(os = ["none"]), "linux", "x64", "glibc"))
    asserts.true(env, _disabled(_meta(os = ["plan9"]), "linux", "x64", "glibc"))
    asserts.false(env, _disabled(_meta(os = ["!plan9"]), "linux", "x64", "glibc"))
    asserts.false(env, _disabled(_meta(os = []), "linux", "x64", "glibc"))

    # A package without `libc` installs on every libc (resolver_hooks.rs L876-L880).
    asserts.false(env, meta_is_disabled(_meta(), platform_value("cpu", "x64"), platform_value("os", "linux"), 0))
    asserts.false(env, meta_is_disabled(_meta(libc = ["glibc"]), platform_value("cpu", "x64"), platform_value("os", "linux"), LIBC_ALL))
    return unittest.end(env)

def _sorter_test_impl(ctx):
    env = unittest.begin(ctx)

    # Behavior::cmp (resolver_hooks.rs L275-L297) and DepSorter (lockfile.rs L320-L341): workspace,
    # dev, optional, prod, peer, then the name.
    deps = [
        struct(name = "p", behavior = BEHAVIOR.PEER),
        struct(name = "a", behavior = BEHAVIOR.PROD),
        struct(name = "o", behavior = BEHAVIOR.OPTIONAL),
        struct(name = "z", behavior = BEHAVIOR.DEV),
        struct(name = "y", behavior = BEHAVIOR.WORKSPACE),
        struct(name = "b", behavior = BEHAVIOR.PROD),
        struct(name = "q", behavior = BEHAVIOR.PEER | BEHAVIOR.OPTIONAL),
    ]
    asserts.equals(env, ["y", "z", "o", "a", "b", "p", "q"], [d.name for d in sorted(deps, key = dependency_sort_key)])
    asserts.equals(env, -1, behavior_cmp(BEHAVIOR.WORKSPACE, BEHAVIOR.PROD))
    asserts.equals(env, 1, behavior_cmp(BEHAVIOR.PEER, BEHAVIOR.PROD))
    asserts.equals(env, 0, behavior_cmp(BEHAVIOR.PEER, BEHAVIOR.PEER | BEHAVIOR.OPTIONAL))
    return unittest.end(env)

def _resolution_test_impl(ctx):
    env = unittest.begin(ctx)

    # Resolution::from_text_lockfile (resolution.rs L161-L252).
    for text, tag in [
        ("1.0.0", RESOLUTION_TAG.NPM),
        ("1.0.0-beta.1+b", RESOLUTION_TAG.NPM),
        ("root:", RESOLUTION_TAG.ROOT),
        ("workspace:packages/a", RESOLUTION_TAG.WORKSPACE),
        ("file:../x", RESOLUTION_TAG.FOLDER),
        ("link:../x", RESOLUTION_TAG.SYMLINK),
        ("http://127.0.0.1/b/-/b-1.0.0.tgz", RESOLUTION_TAG.REMOTE_TARBALL),
        ("./vendor/b.tgz", RESOLUTION_TAG.LOCAL_TARBALL),
        ("github:user/repo#abc", RESOLUTION_TAG.GITHUB),
        ("git+ssh://git@host/repo.git#abc", RESOLUTION_TAG.GIT),
    ]:
        result = resolution_from_text_lockfile(text)
        asserts.equals(env, None, result.error, text)
        asserts.equals(env, tag, result.value.tag, text)
    for text in ["1.0", "latest", "catalog:", "^1.0.0"]:
        asserts.true(env, resolution_from_text_lockfile(text).error != None, text)

    one = resolution_from_text_lockfile("1.0.0").value
    two = resolution_from_text_lockfile("2.0.0").value
    folder = resolution_from_text_lockfile("file:../x").value

    # Resolution::order / eql (resolution.rs L358-L383, L497-L534): by tag, then by value.
    asserts.equals(env, -1, resolution_order(one, two))
    asserts.equals(env, -1, resolution_order(one, folder))
    asserts.true(env, resolution_eql(one, resolution_from_text_lockfile("1.0.0").value))
    asserts.true(env, resolution_eql(one, resolution_from_text_lockfile("1.0.0+build").value))
    asserts.false(env, resolution_eql(one, two))

    # satisfies_dependency_version (resolution.rs L25-L52): npm ranges only, by semver.
    asserts.true(env, resolution_satisfies_dependency_version(one, dependency_parse("a", "^1.0.0")))
    asserts.false(env, resolution_satisfies_dependency_version(two, dependency_parse("a", "^1.0.0")))
    asserts.false(env, resolution_satisfies_dependency_version(folder, dependency_parse("a", "file:../x")))
    asserts.false(env, resolution_satisfies_dependency_version(one, dependency_parse("a", "latest")))
    return unittest.end(env)

def _dependency_test_impl(ctx):
    env = unittest.begin(ctx)

    # Tag::infer (dependency.rs L794-L1113).
    for text, tag in [
        ("^1.0.0", VERSION_TAG.NPM),
        ("1.0.0", VERSION_TAG.NPM),
        ("1.x", VERSION_TAG.NPM),
        ("x", VERSION_TAG.NPM),
        ("*", VERSION_TAG.NPM),
        ("", VERSION_TAG.DIST_TAG),
        ("latest", VERSION_TAG.DIST_TAG),
        ("2x", VERSION_TAG.DIST_TAG),
        ("v1.0.0", VERSION_TAG.NPM),
        ("npm:a@1.0.0", VERSION_TAG.NPM),
        ("npm:a@latest", VERSION_TAG.DIST_TAG),
        ("workspace:*", VERSION_TAG.WORKSPACE),
        ("catalog:", VERSION_TAG.CATALOG),
        ("file:../x", VERSION_TAG.FOLDER),
        ("../x", VERSION_TAG.FOLDER),
        ("./x.tgz", VERSION_TAG.TARBALL),
        ("https://host/x.tgz", VERSION_TAG.TARBALL),
        ("link:../x", VERSION_TAG.SYMLINK),
        ("user/repo", VERSION_TAG.GITHUB),
        ("github:user/repo", VERSION_TAG.GITHUB),
        ("git+ssh://git@host/repo.git", VERSION_TAG.GIT),
        # A drive letter and `/` is a path on every OS (L800-L814).
        ("C:/x", VERSION_TAG.FOLDER),
        ("v:/x.tgz", VERSION_TAG.TARBALL),
        # One arm of `match url[0]` per literal (L894-L972): `+http` with nothing after it falls
        # to the tail, and `hub:` is tested on the text after `git` only.
        ("git+http", VERSION_TAG.DIST_TAG),
        ("git+httphub:a/b", VERSION_TAG.GIT),
    ]:
        asserts.equals(env, tag, version_tag_infer(text), text)

    # parse_with_tag (dependency.rs L1229-L1625).
    alias = dependency_parse("lib", "npm:a@^1.0.0")
    asserts.equals(env, VERSION_TAG.NPM, alias.tag)
    asserts.equals(env, ["a", True], [alias.npm.name, alias.npm.is_alias])
    plain = dependency_parse("a", "^1.0.0")
    asserts.equals(env, ["a", False], [plain.npm.name, plain.npm.is_alias])
    asserts.equals(env, "", dependency_parse("a", "catalog:").catalog)
    asserts.equals(env, "tools", dependency_parse("a", "catalog: tools ").catalog)
    asserts.equals(env, "*", dependency_parse("w", "workspace:*").workspace)
    asserts.equals(env, "../x", dependency_parse("x", "file:../x").folder)

    # A drive-letter path is no folder Bun parses off Windows ("Unsupported protocol", L1531-L1564).
    asserts.equals(env, None, dependency_parse("x", "C:/x"))

    # The committish is the fragment after the first `#` (L1361-L1378).
    github = dependency_parse("r", "user/repo#a#b").github
    asserts.equals(env, ["user", "repo", "a#b"], [github.owner, github.repo, github.committish])

    # `strip_prefix(b"catalog:")?` (L1612): a literal without the prefix is no catalog version.
    asserts.equals(env, None, dependency_parse("a", "tools", VERSION_TAG.CATALOG))
    asserts.equals(env, ["a", "latest"], [dependency_parse("a", "").dist_tag.name, dependency_parse("a", "").dist_tag.tag])

    # split_name_and_version (dependency.rs L486-L532).
    asserts.equals(env, ("a", "1.0.0"), split_name_and_version("a@1.0.0"))
    asserts.equals(env, ("@s/a", "npm:b@1"), split_name_and_version("@s/a@npm:b@1"))
    asserts.equals(env, None, split_name_and_version("a"))
    asserts.equals(env, None, split_name_and_version("a@"))
    return unittest.end(env)

behavior_test = unittest.make(_behavior_test_impl)
disabled_test = unittest.make(_disabled_test_impl)
sorter_test = unittest.make(_sorter_test_impl)
resolution_test = unittest.make(_resolution_test_impl)
dependency_test = unittest.make(_dependency_test_impl)

def bun_install_types_test_suite(name):
    unittest.suite(
        name,
        behavior_test,
        disabled_test,
        sorter_test,
        resolution_test,
        dependency_test,
    )
