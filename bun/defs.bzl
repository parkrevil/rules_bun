"""Public API for rules_bun.

`bun_library`, `bun_binary` and `bun_test` build, run and test a Bun project:

    load("@rules_bun//bun:defs.bzl", "bun_binary", "bun_library", "bun_test")

    bun_library(
        name = "greet",
        srcs = ["greet.ts"],
    )

    # main.ts reads join(import.meta.dir, "message.txt").
    bun_binary(
        name = "app",
        entry_point = "main.ts",
        data = ["message.txt"],
        deps = [":greet"],
        args = ["--name=world"],
        env = {"GREETING": "hello"},
    )

    bun_test(
        name = "greet_test",
        srcs = ["greet.test.ts"],
        deps = [":greet"],
    )

npm packages come from the `npm` extension (`@rules_bun//bun:extensions.bzl`): its
`:node_modules/<package>` targets go in `deps` of all three rules, and `bun_library` passes them on
to the targets that depend on it. The documentation of `bun_binary` and `bun_test` describes the
package layout, peers, the load guard with packages and the platforms tested.

`bun_binary` and `bun_test` run the Bun of the `BUN_TARGET_TOOLCHAIN_TYPE` toolchain resolved for
the target platform. On Linux and macOS their executable is a shell launcher that finds its files
with the Bash runfiles library (`@rules_shell//shell/runfiles`), and running it needs
`/usr/bin/env`, `bash` and the utilities that library calls (`grep`, `sed`, `cut`, `tr`, `wc`,
`awk`, `tail`, `uname`, `dirname`, `basename`); for a Windows target platform it is
`<name>.exe`, a hermetic-launcher stub, which runs without Bash. The shell launcher works from a
runfiles manifest without a runfiles tree, under `bazel run` and `bazel test`. Where these
targets are tested is the Platforms paragraph of the `bun_binary` documentation.

Rules that run Bun declare `BUN_TOOLCHAIN_TYPE` in `toolchains` and read the
executable from `ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo`, a `BunInfo`.
Every action that runs Bun passes `toolchain = BUN_TOOLCHAIN_TYPE`, so it runs on
the execution platform the toolchain was resolved for:

    load("@rules_bun//bun:defs.bzl", "BUN_TOOLCHAIN_TYPE")

    def _impl(ctx):
        buninfo = ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo
        ctx.actions.run(
            executable = buninfo.bun,
            tools = buninfo.tool_files,
            toolchain = BUN_TOOLCHAIN_TYPE,
            ...
        )

    my_rule = rule(implementation = _impl, toolchains = [BUN_TOOLCHAIN_TYPE])
"""

load("//bun/private:library.bzl", _bun_library = "bun_library")
load("//bun/private:providers.bzl", _BunInfo = "BunInfo", _BunLibraryInfo = "BunLibraryInfo")
load("//bun/private:run.bzl", _bun_binary = "bun_binary", _bun_test = "bun_test")

BUN_TOOLCHAIN_TYPE = Label("//bun/toolchain:execution_type")

BUN_TARGET_TOOLCHAIN_TYPE = Label("//bun/toolchain:target_type")

BunInfo = _BunInfo
BunLibraryInfo = _BunLibraryInfo

bun_binary = _bun_binary
bun_library = _bun_library
bun_test = _bun_test
