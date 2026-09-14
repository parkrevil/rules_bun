"""Rule that builds targets for another platform, used to test toolchain resolution."""

def _transition_impl(_settings, attr):
    return {"//command_line_option:platforms": str(attr.platform)}

_platform_transition = transition(
    implementation = _transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _impl(ctx):
    return [DefaultInfo(
        files = depset(transitive = [t[DefaultInfo].files for t in ctx.attr.target]),
    )]

with_platform = rule(
    implementation = _impl,
    attrs = {
        "platform": attr.label(mandatory = True),
        "target": attr.label_list(
            mandatory = True,
            cfg = _platform_transition,
        ),
    },
)
