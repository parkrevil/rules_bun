"""Test-only rule that writes files no target declares where the load guard must reject them."""

def _undeclared_files_impl(ctx):
    outputs = []

    def write(path, content):
        f = ctx.actions.declare_file(path)
        ctx.actions.write(f, content)
        outputs.append(f)

    package = "_main/" + ctx.label.package

    # A stale copy inside each tree (G10).
    for tree in ctx.attr.trees:
        write("{}.bun/{}/stale.ts".format(tree, package), 'export const stale = "stale";\n')

    guarded = ctx.attr.guarded + ".bun/"

    # A file reached by a "../" climb out of the tree: the package's own output directory.
    write("climb.ts", 'export const climb = "climb";\n')

    # An ancestor package.json whose "imports" maps #undeclared to an undeclared file (G11).
    write(guarded + "package.json", json.encode({"imports": {"#undeclared": "./imports_target.ts"}}) + "\n")
    write(guarded + "imports_target.ts", 'export const target = "imports";\n')

    # An ancestor node_modules package (G11).
    write(guarded + "node_modules/undeclared-pkg/package.json", json.encode({"main": "index.js", "name": "undeclared-pkg"}) + "\n")
    write(guarded + "node_modules/undeclared-pkg/index.js", 'module.exports = "undeclared-pkg";\n')

    # Undeclared CommonJS and JSON files beside the entry point's copy.
    write("{}{}/undeclared.cjs".format(guarded, package), 'module.exports = "cjs";\n')
    write("{}{}/undeclared.json".format(guarded, package), '{"json": true}\n')

    return [DefaultInfo(files = depset(outputs))]

undeclared_files = rule(
    implementation = _undeclared_files_impl,
    doc = "Writes undeclared files into and around the copy trees of targets in this package.",
    attrs = {
        "guarded": attr.string(
            doc = "Name of the target whose tree gets the package.json, node_modules, CommonJS and JSON files.",
            mandatory = True,
        ),
        "trees": attr.string_list(
            doc = "Names of the targets whose tree gets a stale copy `stale.ts` beside their sources.",
            mandatory = True,
        ),
    },
)
