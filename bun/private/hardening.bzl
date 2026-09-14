"""Flags that stop Bun from reading local configuration or installing packages."""

_BASE_ARGS = [
    "--no-install",
    "--no-env-file",
]

def empty_bunfig(ctx):
    f = ctx.actions.declare_file(ctx.label.name + ".empty.bunfig.toml")
    ctx.actions.write(f, "")
    return f

def hardening_args(bunfig, relative_to = None):
    """Returns the Bun flags that isolate an action from its working directory.

    Args:
        bunfig: Empty bunfig file.
        relative_to: Directory Bun runs from, relative to the execution root.

    Returns:
        List of flags.
    """
    path = bunfig.path
    if relative_to:
        depth = len(relative_to.split("/"))
        path = "/".join([".."] * depth) + "/" + path
    return _BASE_ARGS + ["--config=" + path]
