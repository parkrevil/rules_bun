"""Analysis test that requires `verify_toolchain` to pass `toolchain` to its Bun action."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _toolchain_param_test_impl(ctx):
    env = analysistest.begin(ctx)

    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "BunVersion"]
    asserts.equals(env, 1, len(actions), "There must be exactly one BunVersion action")

    return analysistest.end(env)

toolchain_param_test = analysistest.make(
    _toolchain_param_test_impl,
    config_settings = {
        "//command_line_option:incompatible_auto_exec_groups": True,
    },
)
