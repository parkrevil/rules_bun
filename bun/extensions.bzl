"""Module extensions that register Bun toolchains and fetch npm packages.

`bun` registers Bun toolchains. Every module may request a Bun version under the default name,
`bun`. When several versions are requested under the same name, the highest one is used. Only the
root module may request toolchains under another name.

    bun = use_extension("@rules_bun//bun:extensions.bzl", "bun")
    bun.toolchain(bun_version = "1.4.4")
    use_repo(bun, "bun_toolchains")

    register_toolchains("@bun_toolchains//:all")

`npm` creates a hub repository with the packages of a `bun.lock`, pinned and verified by the
integrity the lockfile records:

    npm = use_extension("@rules_bun//bun:extensions.bzl", "npm")
    npm.translate_lock(bun_lock = "//:bun.lock")
    use_repo(npm, "npm")

In the `BUILD` file of the lockfile's package (and of each workspace member):

    load("@npm//:defs.bzl", "npm_link_all_packages")
    load("@rules_bun//bun:defs.bzl", "bun_test")

    npm_link_all_packages()

    bun_test(
        name = "render_test",
        srcs = ["render.test.tsx"],
        deps = [":node_modules/react", ":node_modules/react-dom"],
    )

and in `REPO.bazel`, so that Bazel does not read a `node_modules` directory a local `bun install`
left in the source tree:

    ignore_directories(["**/node_modules"])

The documentation of `npm` lists the generated targets, their naming rules and the limits.
"""

load(
    "//bun/private:extensions.bzl",
    _bun = "bun",
    _bun_toolchain = "bun_toolchain",
)
load("//bun/private:npm_extension.bzl", _npm = "npm")

bun = _bun
bun_toolchain = _bun_toolchain
npm = _npm
