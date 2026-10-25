"""Test-only rule collecting what the Bazel-in-Bazel tests give their inner builds (G5, G10)."""

def _rlocation_path(ctx, f):
    if f.short_path.startswith("../"):
        return f.short_path[3:]
    return ctx.workspace_name + "/" + f.short_path

def _inner_inputs_impl(ctx):
    files = [ctx.executable.bazel]
    archives = {}
    for target, path in ctx.attr.archives.items():
        archive = target[DefaultInfo].files.to_list()
        if len(archive) != 1:
            fail("{}: {} must provide exactly one file".format(ctx.label, target.label))
        archives[path] = _rlocation_path(ctx, archive[0])
        files.append(archive[0])
    groups = {}
    for name in ["registry", "rules_bun", "workspaces"]:
        group = getattr(ctx.files, name)
        groups[name] = [_rlocation_path(ctx, f) for f in group]
        files.extend(group)
    out = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(out, json.encode({
        "archives": archives,
        "bazel": _rlocation_path(ctx, ctx.executable.bazel),
        "registry": groups["registry"],
        "rules_bun": groups["rules_bun"],
        "workspaces": groups["workspaces"],
    }))
    return [DefaultInfo(
        files = depset([out]),
        runfiles = ctx.runfiles(files = files + [out]),
    )]

inner_inputs = rule(
    implementation = _inner_inputs_impl,
    doc = """Writes `<name>.json` naming, by rlocation path, the pinned Bazel binary, each download
the loopback server serves (keyed by its loopback path), the local registry files, the files of
rules_bun the inner builds override the module with, and the inner workspaces; all of them are its
runfiles.""",
    attrs = {
        "archives": attr.label_keyed_string_dict(
            doc = "Each download, mapped to the loopback path it is served at.",
            allow_files = True,
        ),
        "bazel": attr.label(
            doc = "The Bazel binary of the platform the test runs on.",
            executable = True,
            cfg = "target",
            allow_single_file = True,
        ),
        "registry": attr.label(
            doc = "The local registry files.",
            allow_files = True,
        ),
        "rules_bun": attr.label(
            doc = "The files of rules_bun.",
            allow_files = True,
        ),
        "workspaces": attr.label(
            doc = "The inner workspaces.",
            allow_files = True,
        ),
    },
)
