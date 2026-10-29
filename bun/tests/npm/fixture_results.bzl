"""Dev-only module extension: the pure npm modules' results on the fixture projects.

Starlark unit tests cannot read files, so this extension reads `bun.lock` and `package.json` of
every project under `bun/tests/npm/fixtures/` (as the pinned Bun wrote them) with `module_ctx.read`,
runs the readers on them, and writes the results into `@npm_fixture_results//:results.bzl`, which
the unit tests load. The readers are thus tested on real lockfiles through the real read path.

It also writes `@npm_fixture_results//:graphs.json`, the ruleset's linked graph per platform class
of every project the conformance test compares (feature 006 research R9, contract "Ruleset side"):
every directory under `bun/tests/npm/fixtures/` holding a `bun.lock`, `bun/tests/npm/scale/`, every
`bun.lock` under `bun/tests/integration/workspaces/`, and every directory under
`bun/tests/npm/conformance/bun_1_4_2/`.
"""

load("//bun/private:lockfile.bzl", "read_lockfile")
load("//bun/private:resolve.bzl", "resolve")
load("//bun/tests/npm/conformance:graph.bzl", "conformance_graphs", "platform_tuples")

# Starlark has no `while`; the directory walk is bounded by this.
_LIMIT = 1 << 20

def _results_repo_impl(repository_ctx):
    repository_ctx.file("BUILD.bazel", 'exports_files(["graphs.json"])\n')
    repository_ctx.file("results.bzl", repository_ctx.attr.content)
    repository_ctx.file("graphs.json", repository_ctx.attr.graphs)

_results_repo = repository_rule(
    implementation = _results_repo_impl,
    attrs = {"content": attr.string(), "graphs": attr.string()},
)

def _lockfiles_under(directory):
    """The directories at or below `directory` that hold a `bun.lock`, `node_modules` skipped."""
    found = []
    stack = [directory]
    for _ in range(_LIMIT):
        if not stack:
            break
        current = stack.pop()
        if current.get_child("bun.lock").exists:
            found.append(current)
        for child in current.readdir():
            if child.is_dir and child.basename != "node_modules":
                stack.append(child)
    return found

def _projects(root):
    """Repository-relative directory -> path of every project the conformance test compares."""
    projects = {}
    for base in ["bun/tests/npm/fixtures", "bun/tests/npm/conformance/bun_1_4_2"]:
        directory = root.get_child(base)
        if not directory.exists:
            continue
        for project in directory.readdir():
            if project.get_child("bun.lock").exists:
                projects["{}/{}".format(base, project.basename)] = project
    projects["bun/tests/npm/scale"] = root.get_child("bun/tests/npm/scale")
    integration = root.get_child("bun/tests/integration/workspaces")
    for project in _lockfiles_under(integration):
        projects["bun/tests/integration/workspaces/" + str(project)[len(str(integration)) + 1:]] = project
    return projects

def _graphs(module_ctx, root):
    tuples = platform_tuples()
    graphs = {}
    for name, project in sorted(_projects(root).items()):
        lockfile = read_lockfile(module_ctx.read(project.get_child("bun.lock")), name + "/bun.lock")
        if lockfile.error:
            graphs[name] = {"error": lockfile.error}
            continue
        result = conformance_graphs(resolve(lockfile.value, file = name + "/bun.lock"), tuples)
        graphs[name] = result if type(result) == "dict" else {"classes": result}
    return graphs

def _fixture_results_impl(module_ctx):
    fixtures = module_ctx.path(Label("//bun/tests/npm/fixtures/basic:bun.lock")).dirname.dirname
    results = {}
    for project in fixtures.readdir():
        lock = project.get_child("bun.lock")
        if not lock.exists:
            continue
        file = "bun/tests/npm/fixtures/{}/bun.lock".format(project.basename)
        manifest = project.get_child("package.json")
        text = module_ctx.read(lock)
        lockfile = read_lockfile(text, file)
        members = {}
        for path in (lockfile.value.workspaces.keys() if lockfile.value else []):
            member = project.get_child(path).get_child("package.json") if path else None
            if member and member.exists:
                members[path] = module_ctx.read(member)
        results[project.basename] = {
            "text": text,
            "lockfile": lockfile,
            "resolution": resolve(lockfile.value) if lockfile.value else None,
            "manifest": module_ctx.read(manifest) if manifest.exists else None,
            "members": members,
        }
    root = module_ctx.path(Label("//:MODULE.bazel")).dirname
    _results_repo(
        name = "npm_fixture_results",
        content = "RESULTS = json.decode({})\n".format(repr(json.encode(results))),
        graphs = json.encode_indent(_graphs(module_ctx, root)) + "\n",
    )
    return module_ctx.extension_metadata(reproducible = True)

fixture_results = module_extension(
    implementation = _fixture_results_impl,
    doc = "Writes `@npm_fixture_results//:results.bzl` for the npm unit tests and `:graphs.json` for the conformance test.",
)
