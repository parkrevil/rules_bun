"""Test-only rule that writes many `.json` data files."""

_ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"

def _many_files_impl(ctx):
    files = []

    # A linear congruential generator with a fixed seed, so the names are the
    # same in every build.
    state = ctx.attr.seed
    for i in range(ctx.attr.count):
        if ctx.attr.name_length:
            chars = []
            for _ in range(ctx.attr.name_length):
                state = (state * 1103515245 + 12345) % 2147483648
                chars.append(_ALPHABET[(state // 65536) % len(_ALPHABET)])
            name = "".join(chars)
        else:
            name = "f" + str(i + 100000)[1:]
        f = ctx.actions.declare_file("{}/{}.json".format(ctx.label.name, name))
        ctx.actions.write(f, "{}\n".format(i))
        files.append(f)
    return [DefaultInfo(files = depset(files))]

many_files = rule(
    implementation = _many_files_impl,
    doc = "Writes `count` `.json` files, each holding its index.",
    attrs = {
        "count": attr.int(
            doc = "Number of files.",
            mandatory = True,
        ),
        "name_length": attr.int(
            doc = "Length of pseudo-random base names; 0 names the files `f00000` upward.",
        ),
        "seed": attr.int(
            doc = "Seed of the pseudo-random names.",
            default = 1,
        ),
    },
)
