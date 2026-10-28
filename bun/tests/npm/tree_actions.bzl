"""An aspect collecting the copy actions of the instance trees a link target reaches."""

TreeActionsInfo = provider(
    doc = "The copy actions of the instance trees a link reaches.",
    fields = {
        "actions": "list of (outputs, inputs) of each `CopyToDirectory` action",
        "replace_prefixes": "list of the `replace_prefixes` (safe path -> archive path) of each instance tree",
    },
)

def _tree_actions_aspect_impl(target, ctx):
    actions = []
    replace_prefixes = []
    if ctx.rule.kind == "npm_package_tree":
        actions = [(a.outputs.to_list(), a.inputs.to_list()) for a in target.actions if a.mnemonic == "CopyToDirectory"]
        replace_prefixes = [dict(ctx.rule.attr.replace_prefixes)]
    for attr in ["instances", "tree"]:
        deps = getattr(ctx.rule.attr, attr, None)
        if deps == None:
            continue
        for dep in deps if type(deps) == "list" else [deps]:
            if TreeActionsInfo in dep:
                actions = actions + dep[TreeActionsInfo].actions
                replace_prefixes = replace_prefixes + dep[TreeActionsInfo].replace_prefixes
    return [TreeActionsInfo(actions = actions, replace_prefixes = replace_prefixes)]

tree_actions_aspect = aspect(
    implementation = _tree_actions_aspect_impl,
    attr_aspects = ["instances", "tree"],
)
