load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//bun/private:action.bzl", "bun_action")

def _fixture_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    bun_action(
        ctx,
        arguments = ["-e", "await Bun.write(Bun.argv[Bun.argv.length - 1], \"ok\\n\")", out],
        outputs = [out],
        mnemonic = "BunFixture",
    )
    return [DefaultInfo(files = depset([out]))]

action_fixture = rule(
    implementation = _fixture_impl,
    toolchains = ["//bun/toolchain:execution_type"],
)

_REQUIRED = [
    "--no-install",
    "--no-env-file",
]

def _hardening_emitted_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "BunFixture"]
    asserts.equals(env, 1, len(actions), "BunFixture 액션이 정확히 하나여야 한다")

    argv = actions[0].argv
    for flag in _REQUIRED:
        asserts.true(
            env,
            flag in argv,
            "bun_action 이 {} 를 방출하지 않았다. argv={}".format(flag, argv),
        )

    asserts.true(
        env,
        [a for a in argv if a.startswith("--config=")],
        "bun_action 이 --config=<빈 bunfig> 를 방출하지 않았다. argv={}".format(argv),
    )
    return analysistest.end(env)

hardening_emitted_test = analysistest.make(_hardening_emitted_test_impl)
