"""Repository rules that fetch Bun releases and declare their toolchains.

Most users should use the `bun` module extension from `//bun:extensions.bzl`
instead of calling these directly.
"""

load("//bun/private:platforms.bzl", "PLATFORMS")
load("//bun/private:toolchains_repo.bzl", "toolchains_repo")
load("//bun/private:versions.bzl", "TOOL_VERSIONS")

_ATTRS = {
    "bun_version": attr.string(
        doc = "Bun version to download.",
        mandatory = True,
    ),
    "integrity": attr.string(
        doc = "Subresource Integrity of the release archive. Defaults to the value rules_bun knows for `bun_version`.",
    ),
    "platform": attr.string(
        doc = "Platform of the release archive, such as `linux-x64`.",
        mandatory = True,
        values = PLATFORMS.keys(),
    ),
}

def _bun_repo_impl(repository_ctx):
    platform = repository_ctx.attr.platform
    version = repository_ctx.attr.bun_version

    url = "https://github.com/oven-sh/bun/releases/download/bun-v{version}/bun-{platform}.zip".format(
        version = version,
        platform = platform,
    )

    integrity = repository_ctx.attr.integrity
    if not integrity:
        if version not in TOOL_VERSIONS:
            fail((
                "rules_bun 이 Bun {version} 의 integrity 를 모른다. " +
                "MODULE.bazel 에서 직접 넘겨라:\n\n" +
                "    bun.toolchain(\n" +
                "        bun_version = \"{version}\",\n" +
                "        integrity = {{\n" +
                "            \"{platform}\": \"sha256-...\",\n" +
                "            # ... 사용할 플랫폼 전부\n" +
                "        }},\n" +
                "    )\n\n" +
                "값은 릴리스의 공식 SHASUMS256.txt 에서 얻는다:\n" +
                "    curl -sL https://github.com/oven-sh/bun/releases/download/" +
                "bun-v{version}/SHASUMS256.txt \\\n" +
                "      | grep '  bun-{platform}.zip$' | awk '{{print $1}}' \\\n" +
                "      | xxd -r -p | base64 -w0 | sed 's/^/sha256-/'"
            ).format(version = version, platform = platform))
        integrity = TOOL_VERSIONS[version][platform]

    repository_ctx.download_and_extract(
        url = url,
        integrity = integrity,
        stripPrefix = "bun-" + platform,
    )

    exe = ".exe" if platform.startswith("windows") else ""

    repository_ctx.file("BUILD.bazel", """load("@parkrevil_rules_bun//bun:toolchain.bzl", "bun_toolchain")

package(default_visibility = ["//visibility:public"])

exports_files(["bun{exe}"])

bun_toolchain(
    name = "bun_toolchain",
    bun = "bun{exe}",
    version = "{version}",
)
""".format(exe = exe, version = version))

    if not hasattr(repository_ctx, "repo_metadata"):
        return None
    return repository_ctx.repo_metadata(reproducible = True)

bun_repositories = repository_rule(
    _bun_repo_impl,
    doc = "Downloads a Bun release for one platform and defines a `bun_toolchain` target for it.",
    attrs = _ATTRS,
)

def bun_register_toolchains(name, integrity = {}, **kwargs):
    """Creates Bun repositories for every supported platform and a repository of toolchains.

    Creates `<name>_<platform>` for each platform and `<name>_toolchains`,
    whose `:all` target can be passed to `register_toolchains`.

    Args:
        name: Base name of the generated repositories.
        integrity: Subresource Integrity of each release archive, keyed by platform.
            Missing platforms use the values rules_bun knows for the version.
        **kwargs: Passed to `bun_repositories`, such as `bun_version`.
    """
    for platform in PLATFORMS.keys():
        bun_repositories(
            name = name + "_" + platform,
            platform = platform,
            integrity = integrity.get(platform, ""),
            **kwargs
        )

    toolchains_repo(
        name = name + "_toolchains",
        user_repository_name = name,
    )
