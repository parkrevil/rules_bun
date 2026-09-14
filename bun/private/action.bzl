load(":hardening.bzl", "empty_bunfig", "hardening_args")

def bun_action(
        ctx,
        arguments,
        outputs,
        inputs = [],
        mnemonic = "BunAction",
        progress_message = None,
        env = {},
        param_file = False):
    toolchain = ctx.toolchains["//bun/toolchain:execution_type"]
    bun = toolchain.buninfo.bun
    bunfig = empty_bunfig(ctx)

    hardening = ctx.actions.args()
    hardening.add_all(hardening_args(bunfig))

    payload = ctx.actions.args()
    payload.add_all(arguments)
    if param_file:
        payload.use_param_file("@%s", use_always = True)
        payload.set_param_file_format("multiline")

    direct = [bunfig]
    transitive = []
    for i in inputs if type(inputs) == "list" else [inputs]:
        if type(i) == "depset":
            transitive.append(i)
        else:
            direct.append(i)

    ctx.actions.run(
        executable = bun,
        arguments = [hardening, payload],
        inputs = depset(direct, transitive = transitive),
        outputs = outputs,
        tools = [bun],
        env = env,
        mnemonic = mnemonic,
        progress_message = progress_message or (mnemonic + " %{label}"),
    )
