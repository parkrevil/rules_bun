"""The Windows launcher toolchain of rules_bun (feature 005 research R6).

`bun_binary`, `bun_test` and `npm_bin` compile a hermetic-launcher stub only for a Windows target.
They request this private toolchain type, whose one toolchain is compatible with Windows only, so
on Linux and macOS no hermetic-launcher toolchain is resolved and none of its repositories is
fetched. Through the toolchain transition (bazel.build extending/toolchains) the toolchain target
resolves hermetic-launcher's template for the parent's target platform and its finalizer for the
parent's execution platform.
"""

load("@hermetic_launcher//launcher:lib.bzl", "launcher")

def _windows_launcher_toolchain_impl(ctx):
    template = ctx.toolchains[launcher.template_toolchain_type]
    finalizer = ctx.toolchains[launcher.finalizer_toolchain_type]
    return [platform_common.ToolchainInfo(
        template = template.templatetoolchaininfo.template_exe if template else None,
        finalizer = finalizer.finalizer_info.finalizer if finalizer else None,
    )]

windows_launcher_toolchain = rule(
    implementation = _windows_launcher_toolchain_impl,
    doc = """Private: hermetic-launcher's stub template and finalizer, each `None` when no toolchain
of its type matches.

Provides `ToolchainInfo(template = File or None, finalizer = File or None)`.""",
    toolchains = [
        config_common.toolchain_type(launcher.template_toolchain_type, mandatory = False),
        config_common.toolchain_type(launcher.finalizer_toolchain_type, mandatory = False),
    ],
)
