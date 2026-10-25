"""Dev-only module extension: the pure npm modules' results on the fixture projects.

Starlark unit tests cannot read files, so this extension reads `bun.lock` and `package.json` of
every project under `bun/tests/npm/fixtures/` (as the pinned Bun wrote them) with `module_ctx.read`,
runs the readers on them, and writes the results into `@npm_fixture_results//:results.bzl`, which
the unit tests load. The readers are thus tested on real lockfiles through the real read path.
"""

load("//bun/private:lockfile.bzl", "read_lockfile")
load("//bun/private:resolve.bzl", "resolve")

def _results_repo_impl(repository_ctx):
    repository_ctx.file("BUILD.bazel", "")
    repository_ctx.file("results.bzl", repository_ctx.attr.content)

_results_repo = repository_rule(
    implementation = _results_repo_impl,
    attrs = {"content": attr.string()},
)

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
    _results_repo(
        name = "npm_fixture_results",
        content = "RESULTS = json.decode({})\n".format(repr(json.encode(results))),
    )
    return module_ctx.extension_metadata(reproducible = True)

fixture_results = module_extension(
    implementation = _fixture_results_impl,
    doc = "Writes `@npm_fixture_results//:results.bzl` for the npm unit tests.",
)
