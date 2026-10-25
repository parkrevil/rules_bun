"""Analysis tests of the targets the `npm` extension generates (FR-005, FR-012, research R7)."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//bun/private:providers.bzl", "BunLibraryInfo", "NpmInstanceInfo")
load(":tree_actions.bzl", "TreeActionsInfo", "tree_actions_aspect")

def _record(env, target):
    info = target[BunLibraryInfo]
    asserts.equals(env, [], info.srcs.to_list())
    asserts.equals(env, [], info.data.to_list())
    records = info.packages.to_list()
    asserts.equals(env, 1, len(records))
    return records[0]

def _ids(record):
    return sorted([i.id for i in record.instances.to_list()])

def _link_a_test_impl(ctx):
    env = analysistest.begin(ctx)
    record = _record(env, analysistest.target_under_test(env))
    asserts.equals(env, "a", record.alias)
    asserts.true(env, record.root.startswith("a@1.0.0__"), record.root)
    names = sorted([i.id.split("__")[0] for i in record.instances.to_list()])
    asserts.equals(env, ["a@1.0.0", "b@1.0.0"], names)
    asserts.true(env, record.root in _ids(record), record.root)
    asserts.equals(env, "_main/bun/tests/npm/fixtures/basic", record.link_dir)
    return analysistest.end(env)

def _link_scoped_test_impl(ctx):
    env = analysistest.begin(ctx)
    record = _record(env, analysistest.target_under_test(env))
    asserts.equals(env, "@scope/s", record.alias)
    root = [i for i in record.instances.to_list() if i.id == record.root]
    asserts.equals(env, 1, len(root))
    asserts.equals(env, "@scope+s@1.0.0", root[0].store_name)
    asserts.true(env, root[0].tree.is_directory, "the instance tree is a tree artifact")
    asserts.true(env, NpmInstanceInfo != None)
    return analysistest.end(env)

def _replacement_gate_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    record = _record(env, target)
    actions = target[TreeActionsInfo].actions
    for instance in record.instances.to_list():
        asserts.true(env, instance.check != None, "{} is replaced".format(instance.id))
        copies = [inputs for outputs, inputs in actions if instance.tree in outputs]
        asserts.equals(env, 1, len(copies), "one copy action writes the tree of " + instance.id)
        if copies:
            asserts.true(
                env,
                instance.check in copies[0],
                "the tree of {} is copied after its replacement check".format(instance.id),
            )
    return analysistest.end(env)

link_a_test = analysistest.make(_link_a_test_impl)
link_scoped_test = analysistest.make(_link_scoped_test_impl)
replacement_gate_test = analysistest.make(
    _replacement_gate_test_impl,
    extra_target_under_test_aspects = [tree_actions_aspect],
)

def generated_test_suite(name):
    link_a_test(
        name = name + "_link_a_test",
        target_under_test = "//bun/tests/npm/fixtures/basic:node_modules/a",
    )
    link_scoped_test(
        name = name + "_link_scoped_test",
        target_under_test = "//bun/tests/npm/fixtures/basic:node_modules/@scope/s",
    )
    replacement_gate_test(
        name = name + "_replacement_gate_test",
        target_under_test = "//bun/tests/npm/fixtures/basic:node_modules/a",
    )
    native.test_suite(
        name = name,
        tests = [name + "_link_a_test", name + "_link_scoped_test", name + "_replacement_gate_test"],
    )
