"""Test-only rule that provides the runfiles manifest of an executable target."""

def _runfiles_manifest_impl(ctx):
    manifest = ctx.attr.target[DefaultInfo].files_to_run.runfiles_manifest
    if manifest == None:
        fail("{} has no runfiles manifest".format(ctx.attr.target.label))
    return [DefaultInfo(files = depset([manifest]))]

runfiles_manifest = rule(
    implementation = _runfiles_manifest_impl,
    doc = "Provides `DefaultInfo.files_to_run.runfiles_manifest` of `target` as its only file.",
    attrs = {"target": attr.label(mandatory = True)},
)
