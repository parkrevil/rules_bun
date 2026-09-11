load("//bun:defs.bzl", "BUN_TOOLCHAIN_TYPE")
load("//bun/private:hardening.bzl", "empty_bunfig", "hardening_args")
load("//bun/private:paths.bzl", "runfiles_path")

_PROBE = """
const out = Bun.argv[Bun.argv.length - 1];
await Bun.write(out, JSON.stringify({
  poisoned: globalThis.__POISONED__ === true,
  port: process.env.PORT ?? null,
}) + "\\n");
"""

_ATTACK_PRELOAD = "globalThis.__POISONED__ = true;\n"
_ATTACK_BUNFIG = 'preload = ["./attack_preload.ts"]\n'
_ATTACK_ENV = "PORT=9999\n"

def _impl(ctx):
    preload = ctx.actions.declare_file("attack_preload.ts")
    bunfig = ctx.actions.declare_file("bunfig.toml")
    dotenv = ctx.actions.declare_file(".env")
    ctx.actions.write(preload, _ATTACK_PRELOAD)
    ctx.actions.write(bunfig, _ATTACK_BUNFIG)
    ctx.actions.write(dotenv, _ATTACK_ENV)

    out = ctx.actions.declare_file(ctx.label.name + ".json")

    toolchain = ctx.toolchains[BUN_TOOLCHAIN_TYPE]
    bun = toolchain.buninfo.bun
    empty = empty_bunfig(ctx)

    hardening = " ".join([
        "'" + a + "'"
        for a in hardening_args(empty, relative_to = bunfig.dirname)
    ])

    ctx.actions.run_shell(
        inputs = [preload, bunfig, dotenv, empty],
        outputs = [out],
        tools = [bun],
        command = (
            'BUN="$(pwd)/{bun}"; OUT="$(pwd)/{out}"; ' +
            'cd "{dir}" && exec "$BUN" {hard} -e "$1" "$OUT"'
        ).format(
            bun = bun.path,
            out = out.path,
            dir = bunfig.dirname,
            hard = hardening,
        ),
        arguments = [_PROBE],
        mnemonic = "BunHardeningProbe",
    )

    checker = ctx.actions.declare_file(ctx.label.name + ".check.js")
    ctx.actions.write(checker, """
const r = JSON.parse(require("fs").readFileSync(process.argv[2], "utf8"));
const fail = [];
if (r.poisoned) fail.push("bunfig.toml 의 preload 가 실행됐다");
if (r.port !== null) fail.push(".env 가 읽혔다 (PORT=" + r.port + ")");
if (fail.length) { console.error("하드닝 실패:\\n  " + fail.join("\\n  ")); process.exit(1); }
console.log("하드닝 정상: preload 차단, .env 차단");
""")

    bun = ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo.bun
    launcher = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        launcher,
        '#!/bin/sh\nR="${{RUNFILES_DIR:-$TEST_SRCDIR}}"\nexec "$R/{bun}" "$R/{chk}" "$R/{out}"\n'.format(
            bun = runfiles_path(ctx, bun),
            chk = runfiles_path(ctx, checker),
            out = runfiles_path(ctx, out),
        ),
        is_executable = True,
    )
    return [DefaultInfo(
        executable = launcher,
        runfiles = ctx.runfiles(files = [
            out,
            checker,
            bun,
        ]),
    )]

hardening_test = rule(
    implementation = _impl,
    test = True,
    toolchains = [BUN_TOOLCHAIN_TYPE],
)
