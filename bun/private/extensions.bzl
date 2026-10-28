"""Implementation of the `bun` module extension."""

load(":platforms.bzl", "BUN_ARCHIVES")
load(":repositories.bzl", "bun_register_toolchains")
load(":semver.bzl", "max_version", "version_error")

_DEFAULT_NAME = "bun"

_ALGORITHMS = ["sha256", "sha384", "sha512"]

_BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="

bun_toolchain = tag_class(
    doc = "Requests a Bun toolchain.",
    attrs = {
        "name": attr.string(
            doc = "Base name of the generated repositories. Only the root module may change it.",
            default = _DEFAULT_NAME,
        ),
        "bun_version": attr.string(
            doc = "Bun version to download, such as `1.4.4`.",
            mandatory = True,
        ),
        "integrity": attr.string_dict(
            doc = """\
Subresource Integrity (`sha256-`, `sha384-` or `sha512-` followed by base64) of each release
archive, keyed by platform: `linux-x64`, `linux-aarch64`, `linux-x64-musl`, `linux-aarch64-musl`,
`darwin-x64`, `darwin-aarch64`, `windows-x64`. Required for every platform a build uses when
rules_bun does not know `bun_version`. Another key or a value of another form fails evaluation
naming the module and the key. Several tags for one version are merged per platform. The root
module's value for a platform wins over those of the modules it depends on; two different values
of the root module, or, without one, of two other modules, for one version and platform fail
evaluation naming the modules, the version and the platform.
""",
        ),
    },
)

def _who(mod):
    return "the root module" if mod.is_root else "the module {}@{}".format(mod.name, mod.version)

def _is_sri(value):
    algorithm, separator, digest = value.partition("-")
    return bool(separator) and algorithm in _ALGORITHMS and bool(digest) and all([c in _BASE64 for c in digest.elems()])

def _validate(mod, toolchain):
    """Fails naming the module and the tag when a `bun.toolchain` tag is invalid (FR-016)."""
    tag = 'bun.toolchain(bun_version = "{}")'.format(toolchain.bun_version)
    error = version_error(toolchain.bun_version)
    if error:
        fail("rules_bun: {}: {}: {}".format(_who(mod), tag, error))
    for platform in sorted(toolchain.integrity.keys()):
        if platform not in BUN_ARCHIVES:
            fail('rules_bun: {}: {}: the integrity key "{}" is no Bun platform; the platforms are {}'.format(
                _who(mod),
                tag,
                platform,
                ", ".join(sorted(BUN_ARCHIVES)),
            ))
        if not _is_sri(toolchain.integrity[platform]):
            fail('rules_bun: {}: {}: the integrity of "{}" is no Subresource Integrity value; write sha256-, sha384- or sha512- followed by the base64 digest'.format(
                _who(mod),
                tag,
                platform,
            ))

def _toolchain_extension(module_ctx):
    # name -> version -> platform -> [(module, value)], in module_ctx.modules order, which starts
    # at the root module (bazel.build module_ctx.modules, research R8).
    requests = {}
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            if toolchain.name != _DEFAULT_NAME and not mod.is_root:
                fail(
                    "Only the root module may change the name of a Bun toolchain, " +
                    "because the generated repositories share one global namespace.",
                )
            _validate(mod, toolchain)
            platforms = requests.setdefault(toolchain.name, {}).setdefault(toolchain.bun_version, {})
            for platform, value in toolchain.integrity.items():
                platforms.setdefault(platform, []).append((mod, value))

    for name, declared in requests.items():
        selected = max_version(declared.keys())
        integrity = {}
        for platform, values in sorted(declared[selected].items()):
            root = [v for v in values if v[0].is_root]
            candidates = root or values
            for mod, value in candidates[1:]:
                if value == candidates[0][1]:
                    continue
                if root:
                    fail("rules_bun: the root module gives Bun {} two different integrity values for {} in its bun.toolchain tags; keep one".format(selected, platform))
                fail("rules_bun: {} and {} give Bun {} different integrity values for {}; the root module decides by giving its own value".format(
                    _who(candidates[0][0]),
                    _who(mod),
                    selected,
                    platform,
                ))
            integrity[platform] = candidates[0][1]

        bun_register_toolchains(
            name = name,
            bun_version = selected,
            integrity = integrity,
        )

    return module_ctx.extension_metadata(reproducible = True)

bun = module_extension(
    implementation = _toolchain_extension,
    doc = "Registers the Bun toolchains requested with `bun.toolchain`.",
    tag_classes = {"toolchain": bun_toolchain},
    os_dependent = False,
    arch_dependent = False,
)
