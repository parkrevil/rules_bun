"""Implementation of the `bun_binary` and `bun_test` rules."""

load("@bazel_lib//lib:copy_directory.bzl", "copy_directory_bin_action")
load("@bazel_lib//lib:copy_file.bzl", "COPY_FILE_TOOLCHAINS", "copy_file_action")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@hermetic_launcher//launcher:lib.bzl", "launcher")
load(":library.bzl", "SOURCE_EXTENSIONS", "check_no_directory", "library_info", "library_runfiles", "packages_of")
load(":providers.bzl", "BunLibraryInfo")

_TARGET_TYPE = Label("//bun/toolchain:target_type")

_COPY_DIRECTORY_TOOLCHAIN = "@bazel_lib//lib:copy_directory_toolchain_type"

_FILES_DOC = """
Files: the target copies its {main}, sources, {preload}and data files, including those of its
`deps`, into its own directory `<name>.bun/` next to its outputs, and Bun runs those copies. A file
the target does not declare, even one next to a declared file in the source tree, is not there, so
importing it fails with Bun's module-not-found error. A `bun_library` or a target whose `data`
holds a directory fails analysis.

Load guard: if Bun is about to load a module file outside the declared copies (a copy left from an
earlier build, a file reached by a `../` import, `package.json` `"imports"` or `node_modules`, or
the original of a declared data file), the run fails with an English error naming the file. If the
guard cannot read its configuration, it rejects every module load. The guard is a check, not
complete isolation: it does not cover modules loaded before it, code the program starts itself
(Workers, child processes, `Bun.build`) or plain file reads (`Bun.file`, `fs`), and `tsconfig.json`
and `package.json` in ancestor directories of `<name>.bun/` can still change how a declared import
resolves. A guard error that the code catches itself (for example `try`/`catch` around a dynamic
`import()`) does not fail the run. JSX needs the `react` package, which rules_bun does not provide
yet; TSX without JSX, `.node` and `.wasm` files are not covered by a test.

Launching: on Linux and macOS the executable `<name>` is a shell launcher that finds Bun and the
rule's files with the Bash runfiles library (`@rules_shell//shell/runfiles`), so running it needs
`/usr/bin/env`, `bash` and the utilities that library calls (`grep`, `sed`, `cut`, `tr`, `wc`,
`awk`, `tail`, `uname`, `dirname`, `basename`). For a Windows target platform the executable is
`<name>.exe`, a hermetic-launcher stub, which runs without Bash (see Platforms). The shell launcher
finds its files through a runfiles manifest when no runfiles tree is staged, so `bazel run
--noenable_runfiles` and `bazel test --noenable_runfiles` without a sandbox work.

Platforms: the tests that run these rules' targets pass on Linux (WSL) and, in CI, on the GitHub
Actions images `ubuntu-24.04`, `macos-26-arm64` and `windows-2025-vs2026`. On Windows they also pass
with Bazel's shell set to a path that does not exist and no Bash directory on the `PATH` of
actions, tests and `bazel run`. `bazel run` and `bazel test` with `--noenable_runfiles` and no
sandbox, and `bazel coverage`, ran on Linux only.

Limits: the guard's pattern may be at most 1,048,576 characters with Bun 1.4.4, and its length
grows with the unique part of the declared files' real paths; beyond that the run fails naming
the declared-file count. When the command line of the Bun process that runs the {code}, as the
running operating system builds it, would exceed 32,767 characters (the Windows limit), the run
fails naming the length and the limit, on every operating system. On Linux and macOS the Bun
process that runs only the rule's launcher writes no transpiler-cache entry, and a set
`BUN_OPTIONS` fails the run before Bun starts. Each of these is tested on the platforms named in
Platforms, the Linux and macOS ones on Linux and macOS.

Windows only, each tested on `windows-2025-vs2026` unless marked unverified: an argument containing
`"` does not arrive unchanged, and of 130 runtime arguments fewer arrive
(https://github.com/hermeticbuild/hermetic-launcher/issues/80 reports the first split and arguments
past 128 dropped); the Bun process that runs only the rule's launcher may read a `bunfig.toml` of
the working directory (https://github.com/hermeticbuild/hermetic-launcher/issues/81; unverified);
an inherited `BUN_OPTIONS` reaches that process, because the stub cannot change the environment
(https://github.com/hermeticbuild/hermetic-launcher/issues/78), so code it names runs there; and a
target whose runfiles path of `<name>.launch.json` is longer than 256 bytes fails analysis naming
the path.

A target platform without a `//bun/toolchain:target_type` toolchain, or a Windows target platform
without a hermetic-launcher stub, fails analysis naming the missing toolchain type.

npm packages (the `:node_modules/<package>` targets of the `npm` extension in `deps`): each package
version the target reaches is copied once into `<name>.bun/.store/<name>@<version>/node_modules/<name>/`
(a scope's `/` written `+`), with hardlinks where the file system allows them; an empty directory
of the package's archive is not carried. Each package can
load, by Node's `node_modules` lookup, exactly its own dependencies and resolved peers, and the
workspace package's `node_modules` holds only that package's direct links; importing anything else
fails with Bun's module-not-found error, or with the load guard's error when a copy is reachable.
rules_bun does not read the lockfile's `configVersion`, so a lockfile written for Bun's hoisted
installs gets this layout too, and code that relies on a hoisted, undeclared package fails. Peers
resolve as npm 7 and later resolve them: to the version the dependent package provides, else
to the version the lockfile lists in the dependent's workspace; an optional peer that is not
provided is absent, and a missing non-optional peer makes the package fail analysis of a target
that needs it. A target in which one package version would need two versions of one dependency or
peer fails analysis naming the package, that dependency or peer and both versions.

The load guard admits every file under the target's store entries and nothing else; its limits
above apply unchanged, and Bun's resolver may still read a `package.json` outside the declared set
without loading it. Nothing in a `node_modules` directory that a local `bun install` left in the
source tree loads: when `REPO.bazel` does not ignore it, it is reachable through the execution
root and an undeclared import from it fails with the guard's error naming the file; with
`ignore_directories(["**/node_modules"])` it is not reachable and the import fails with Bun's
module-not-found error. No lifecycle
script (`preinstall`, `postinstall`, ...) runs, whatever `trustedDependencies` says: Bun runs
scripts for the packages named there or, when the field is absent, for those on the list
`bun pm default-trusted` prints (`bun pm untrusted` lists only the packages it blocked).
Packages with native add-ons or WebAssembly are not covered by a test.

Links in the copy tree are symbolic links of type `directory`, which Bazel creates as directory
junctions on Windows, so no Bazel flag is needed there. Store paths are deep: the longest tested
one is 398 characters on Linux and 369 on Windows, over Windows' 260-character `MAX_PATH`, so
Windows needs long-path support enabled (`LongPathsEnabled`, Microsoft's "Maximum Path Length
Limitation"); without it, packages are untested there. A file name Windows cannot hold, such as
`aux.js` or `a:b.js`, is handled as Bazel's extractor handles it; rules_bun promises neither a
failure nor a message. On Windows (one local run), Bazel 9.2.0's extraction of `a:b.js` fails with
an internal error, so such a package cannot be fetched there. Packages ran on Linux (WSL) and, in
one local run with `LongPathsEnabled` set and without `--windows_enable_symlinks`, on Windows;
macOS is unverified.
"""

# hermetic-launcher limits each embedded stub argument to 256 bytes.
_MAX_EMBEDDED_ARGUMENT = 256

def _rlocation_path(f):
    return launcher.to_rlocation_path(f)

def _check_entry_point(ctx):
    files = ctx.files.entry_point
    if len(files) != 1 or ("." + files[0].extension) not in SOURCE_EXTENSIONS:
        fail("{}: entry_point must be exactly one file with one of the extensions {}; got {}".format(
            ctx.label,
            " ".join(SOURCE_EXTENSIONS),
            [f.short_path for f in files],
        ))

def _check_embedded_arguments(ctx, files):
    for f in files:
        path = _rlocation_path(f)
        if len(path) > _MAX_EMBEDDED_ARGUMENT:
            fail("{}: the runfiles path {} is longer than {} bytes, the limit of an embedded launcher argument".format(
                ctx.label,
                path,
                _MAX_EMBEDDED_ARGUMENT,
            ))

def _copy_tree(ctx, root, files):
    """Copies each file once to `<root>/<rlocation path>`.

    Args:
        ctx: The rule context.
        root: The copy tree's directory, relative to the target's package (`<name>.bun`).
        files: List of `File`s, possibly with duplicates.

    Returns:
        A dict from the rlocation path of each original to its copy.
    """
    copies = {}
    for f in files:
        path = _rlocation_path(f)
        if path in copies:
            continue
        copy = ctx.actions.declare_file("{}/{}".format(root, path))
        copy_file_action(ctx, f, copy)
        copies[path] = copy
    return copies

def _relative(from_dir, to):
    """The relative path from the directory `from_dir` to `to`, both relative to one root."""
    a = from_dir.split("/")
    b = to.split("/")
    common = 0
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            break
        common = i + 1
    return "/".join([".."] * (len(a) - common) + b[common:])

def _directory_link(ctx, root, path, target):
    """Declares `<root>/<path>`, a link to the directory `<root>/<target>` (research R5)."""
    link = ctx.actions.declare_symlink("{}/{}".format(root, path))
    ctx.actions.symlink(
        output = link,
        target_path = _relative(path.rpartition("/")[0], target),
        target_type = "directory",
    )
    return link

def _name_version(instance):
    return "{}@{}".format(instance.package, instance.store_name[len(instance.package.replace("/", "+")) + 1:])

def _key(instance, instance_id = None):
    """The identity of `instance`, or of the instance its edge names, across hubs (US9)."""
    return str(instance.label.same_package_label(instance_id or instance.id))

def _resolved(instances, instance, alias):
    """What `alias` of `instance` resolves to: package version and, if ordinary, `bun.lock` key."""
    target = instance.edges.get(alias)
    key = _key(instance, target) if target != None else None
    text = _name_version(instances[key]) if key in instances else (target or "nothing")
    dependency_key = instance.dependency_keys.get(alias)
    return text if dependency_key == None else '{} (bun.lock key "{}")'.format(text, dependency_key)

# The content identity of an instance (feature 005 research R1), in the order differences are
# reported: field, name in the error.
_IDENTITY = [("integrity", "integrity"), ("source", "source"), ("exclude", "exclusion policy")]

def _identity_value(instance, field):
    value = getattr(instance, field)
    return json.encode(value) if type(value) == "list" else value

def _identity_difference(first, second):
    """The first content-identity property two instances differ in, or `None`."""
    for field, what in _IDENTITY:
        if _identity_value(first, field) != _identity_value(second, field):
            return struct(field = field, what = what)
    return None

def _equivalent(instances, first, second):
    """Whether two instances of one package version come from different hubs and lay out alike.

    They lay out alike when their content identity (integrity, source, exclusion policy) is equal
    and every edge reaches the same package version; the uniqueness check holds the instances
    those edges reach to the same rule.
    """
    if first.label.repo_name == second.label.repo_name and first.hub == second.hub:
        return False
    if _identity_difference(first, second):
        return False
    if sorted(first.edges.keys()) != sorted(second.edges.keys()) or sorted(first.peers) != sorted(second.peers):
        return False
    for alias in first.edges.keys():
        a = instances.get(_key(first, first.edges[alias]))
        b = instances.get(_key(second, second.edges[alias]))
        if (a == None) != (b == None) or (a != None and a.store_name != b.store_name):
            return False
    return True

def _check_unique(ctx, instances):
    """Picks one instance per package version and fails when two differ (FR-003, FR-017, US5-4).

    Instance IDs are unique within one hub only, so `instances` is keyed by `_key`. Instances of
    different hubs (several lockfiles) with one content identity whose edges reach the same
    package versions lay out alike and are carried once; any other two instances of one package
    version fail. The error names the first content-identity property that differs, else the
    first dependency whose resolutions differ in version or `bun.lock` key; when two instances
    differ only through instances of one version below them, those are reported instead.

    Returns:
        Key -> the key of the instance carried in its place.
    """
    groups = {}
    for key in sorted(instances.keys()):
        groups.setdefault(instances[key].store_name, []).append(key)
    carried = {}
    conflicts = []
    for store_name in sorted(groups.keys()):
        classes = []
        for key in groups[store_name]:
            match = [c for c in classes if _equivalent(instances, instances[c], instances[key])]
            if not match:
                classes.append(key)
            carried[key] = match[0] if match else key
        if len(classes) > 1:
            conflicts.append((instances[classes[0]], instances[classes[1]]))
    for first, second in conflicts:
        difference = _identity_difference(first, second)
        if difference:
            fail("{}: the npm package {} comes from the hubs {} ({}) and {} ({}) with different {}: {} and {}; one instance per package version is carried only when both hubs describe the same content".format(
                ctx.label,
                _name_version(first),
                first.hub,
                first.lockfile,
                second.hub,
                second.lockfile,
                difference.what,
                _identity_value(first, difference.field),
                _identity_value(second, difference.field),
            ))
    for first, second in conflicts:
        for alias in sorted({a: True for a in first.edges.keys() + second.edges.keys()}.keys()):
            if _resolved(instances, first, alias) == _resolved(instances, second, alias):
                continue
            fail('{}: the npm package {} would be carried twice, because its {} "{}" resolves to {} and to {}; a target holds one instance of each package version, so its dependencies must agree on it'.format(
                ctx.label,
                _name_version(first),
                "peer" if alias in first.peers or alias in second.peers else "dependency",
                alias,
                _resolved(instances, first, alias),
                _resolved(instances, second, alias),
            ))
    if conflicts:
        first, second = conflicts[0]
        fail("{}: the npm package {} would be carried as the two instances {} and {}; a target holds one instance of each package version".format(
            ctx.label,
            _name_version(first),
            _key(first),
            _key(second),
        ))
    return carried

def _package_layout(ctx, root, deps):
    """Lays out the packages of `deps` in the copy tree as a strict store (research R5).

    Each instance tree is copied once to `.store/<store name>/node_modules/<package>`; each
    dependency edge is a directory link next to it, and each link record a direct link in its
    workspace package's `node_modules`, to a store entry or, for a workspace member, to the
    member's package, where the member target's files are copied.

    Args:
        ctx: The rule context.
        root: The copy tree's directory, relative to the target's package.
        deps: The target's `deps`.

    Returns:
        `struct(outputs, checks, directories, links, stores)`: the copies and links, the
        replacement stamps of the carried instances, the store-entry and link paths relative to
        the copy-tree root, and instance key (`_key`) -> its store entry's tree artifact.
    """
    records = depset(transitive = [packages_of(d[BunLibraryInfo]) for d in deps]).to_list()
    instances = {}
    record_roots = []
    for record in records:
        root_key = None
        for instance in record.instances.to_list():
            instances.setdefault(_key(instance), instance)
            if instance.id == record.root:
                root_key = _key(instance)
        record_roots.append(root_key)
    if not records:
        return struct(outputs = [], checks = [], directories = [], links = [], stores = {})
    carried = _check_unique(ctx, instances)

    copy_directory_bin = ctx.toolchains[_COPY_DIRECTORY_TOOLCHAIN].copy_directory_info.bin
    entries = {}
    stores = {}
    outputs = []
    link_paths = []
    kept = sorted([k for k in instances.keys() if carried[k] == k])
    for key in kept:
        instance = instances[key]
        path = ".store/{}/node_modules/{}".format(instance.store_name, instance.package)
        copy = ctx.actions.declare_directory("{}/{}".format(root, path))
        copy_directory_bin_action(ctx, src = instance.tree, dst = copy, copy_directory_bin = copy_directory_bin, hardlink = "auto")
        entries[key] = path
        stores[key] = copy
        outputs.append(copy)
    for key in instances.keys():
        entries[key] = entries[carried[key]]
        stores[key] = stores[carried[key]]
    for key in kept:
        instance = instances[key]
        for alias, target in sorted(instance.edges.items()):
            target = _key(instance, target)
            if alias == instance.package or target not in entries:
                continue
            path = ".store/{}/node_modules/{}".format(instance.store_name, alias)
            outputs.append(_directory_link(ctx, root, path, entries[target]))
            link_paths.append(path)
    links = {}
    for record, root_key in zip(records, record_roots):
        path = "{}/node_modules/{}".format(record.link_dir, record.alias)
        if record.workspace_target != None:
            # A workspace member: the member target's files are copied to its package (R5).
            links.setdefault(path, record.workspace_target)

        # A platform-restricted optional root is absent on other platforms (research R8).
        if root_key in entries:
            links.setdefault(path, entries[root_key])
    for path in sorted(links.keys()):
        outputs.append(_directory_link(ctx, root, path, links[path]))
        link_paths.append(path)
    return struct(
        outputs = outputs,
        checks = [instances[k].check for k in kept if instances[k].check],
        directories = [entries[k] for k in kept],
        links = link_paths,
        stores = stores,
    )

def _required_toolchain(ctx, toolchain_type):
    """Returns the resolved toolchain of an optional type, or fails naming the type and the target platform."""
    toolchain = ctx.toolchains[toolchain_type]
    if toolchain == None:
        fail("{}: no toolchain of type {} matches the target platform {}".format(
            ctx.label,
            toolchain_type,
            ctx.fragments.platform.platform,
        ))
    return toolchain

def _windows_stub(ctx, buninfo, launch_config):
    """Compiles the hermetic-launcher stub `<name>.exe`, the Windows launcher (FR-001)."""
    _required_toolchain(ctx, launcher.template_toolchain_type)
    _required_toolchain(ctx, launcher.finalizer_toolchain_type)
    _check_embedded_arguments(ctx, [buninfo.bun, ctx.file._launcher, launch_config])
    stub = ctx.actions.declare_file(ctx.label.name + ".exe")
    launcher.entrypoint(buninfo.bun).embedded_args("--no-env-file").runfiles(ctx.file._launcher, launch_config).compile(
        ctx,
        output_file = stub,
        cfg = "target",
    )
    return stub

def _shell_launcher(ctx, buninfo, launch_config):
    """Writes the shell launcher `<name>`, the Linux and macOS launcher (FR-001)."""
    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.expand_template(
        template = ctx.file._launcher_template,
        output = executable,
        substitutions = {
            "%bun%": shell.quote(_rlocation_path(buninfo.bun)),
            "%bunfig%": shell.quote(_rlocation_path(ctx.file._bunfig)),
            "%launch_config%": shell.quote(_rlocation_path(launch_config)),
            "%launcher%": shell.quote(_rlocation_path(ctx.file._launcher)),
        },
        is_executable = True,
    )
    return executable

def _bin_record(ctx):
    """The link record and root instance of an `npm_bin` target's package."""
    records = packages_of(ctx.attr.package[BunLibraryInfo]).to_list()
    record = [r for r in records if r.root != None][0]
    root = [i for i in record.instances.to_list() if i.id == record.root][0]
    return record, root

def _check_bin(ctx):
    _, root = _bin_record(ctx)
    if not [e for e in SOURCE_EXTENSIONS if ctx.attr.path.endswith(e)]:
        fail('{}: the bin entry "{}" of the npm package {} is the file {}, which has none of the extensions {}; Bun runs only JavaScript and TypeScript files'.format(
            ctx.label,
            ctx.attr.entry,
            _name_version(root),
            ctx.attr.path,
            " ".join(SOURCE_EXTENSIONS),
        ))

def _bun_run_impl(ctx, mode):
    buninfo = _required_toolchain(ctx, _TARGET_TYPE).buninfo

    if mode == "bin":
        # A package executable: its copy tree lies outside `node_modules` (research R10).
        _check_bin(ctx)
        root = "_npm_bin/{}/{}.bun".format(ctx.attr.package.label.name.removeprefix("node_modules/"), ctx.attr.bin)
        deps = [ctx.attr.package]
        data = []
        main_files = []
        sources = []
    elif mode == "binary":
        _check_entry_point(ctx)
        root = ctx.label.name + ".bun"
        deps = ctx.attr.deps
        data = ctx.attr.data
        main_files = ctx.files.entry_point
        sources = ctx.files.entry_point + ctx.files.srcs
    else:
        if not ctx.files.srcs:
            fail("{}: srcs must name at least one test file".format(ctx.label))
        root = ctx.label.name + ".bun"
        deps = ctx.attr.deps
        data = ctx.attr.data
        main_files = ctx.files.srcs
        sources = ctx.files.srcs

    info = library_info(sources, data, deps)
    preloads = ctx.files.preload if mode == "test" else []
    to_copy = info.srcs.to_list() + preloads + info.data.to_list()
    check_no_directory(ctx.label, to_copy)
    originals = {_rlocation_path(f): f for f in to_copy}
    copies = _copy_tree(ctx, root, to_copy)
    packages = _package_layout(ctx, root, deps)

    config = {
        "copies": [[_rlocation_path(copy), originals[path].path] for path, copy in copies.items()],
        "label": str(ctx.label),
        "mode": "binary" if mode == "bin" else mode,
    }
    if packages.links:
        config["directories"] = packages.directories
        config["links"] = packages.links
    main_copies = [_rlocation_path(copies[_rlocation_path(f)]) for f in main_files]
    if mode == "bin":
        # The entry point is a file of the package's store entry.
        _, instance = _bin_record(ctx)
        config["bunfig"] = _rlocation_path(ctx.file._bunfig)
        config["entry_point"] = _rlocation_path(packages.stores[_key(instance)]) + "/" + ctx.attr.path
        config["entry_point_tree"] = ".store/{}/node_modules/{}/{}".format(instance.store_name, instance.package, ctx.attr.path)
    elif mode == "binary":
        config["bunfig"] = _rlocation_path(ctx.file._bunfig)
        config["entry_point"] = main_copies[0]
        config["entry_point_tree"] = _rlocation_path(main_files[0])
    else:
        config["tests"] = [[copy, _rlocation_path(f)] for copy, f in zip(main_copies, main_files)]
        config["preload"] = [_rlocation_path(copies[_rlocation_path(f)]) for f in preloads]
    launch_config = ctx.actions.declare_file(ctx.label.name + ".launch.json")
    ctx.actions.write(launch_config, json.encode(config))

    windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo])
    rule_files = [ctx.file._launcher, launch_config]
    if windows:
        executable = _windows_stub(ctx, buninfo, launch_config)
        if mode != "test":
            rule_files.append(ctx.file._bunfig)
    else:
        executable = _shell_launcher(ctx, buninfo, launch_config)
        rule_files.append(ctx.file._bunfig)

    runfiles = library_runfiles(
        ctx,
        buninfo.tool_files + rule_files + copies.values() + packages.outputs + packages.checks,
        data,
        deps,
    )
    runfiles = runfiles.merge(ctx.runfiles(transitive_files = info.data))
    if not windows:
        runfiles = runfiles.merge(ctx.attr._bash_runfiles[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(executable = executable, runfiles = runfiles),
        info,
        coverage_common.instrumented_files_info(
            ctx,
            source_attributes = {"bin": [], "binary": ["entry_point", "srcs"], "test": ["srcs"]}[mode],
            dependency_attributes = ["package"] if mode == "bin" else ["deps", "data"],
        ),
        RunEnvironmentInfo(
            environment = getattr(ctx.attr, "env", {}),
            inherited_environment = getattr(ctx.attr, "env_inherit", []),
        ),
    ]

_COMMON_ATTRS = {
    "data": attr.label_list(
        doc = """Files needed at run time. Each file is copied into `<name>.bun/` and is read
relative to `import.meta.dir` of the file that reads it, with the same relative path as in the
source tree. A directory fails analysis.""",
        allow_files = True,
    ),
    "deps": attr.label_list(
        doc = "`bun_library` targets and npm package targets (`:node_modules/<package>`) the sources import; their sources, data files and packages are copied too.",
        providers = [BunLibraryInfo],
    ),
    "env": attr.string_dict(
        doc = """Environment variables of the program or tests. Values are taken literally: `$(location)`
and other substitutions are not expanded. Locate data files through `import.meta.dir`.""",
    ),
    "_bash_runfiles": attr.label(
        default = Label("@rules_shell//shell/runfiles"),
    ),
    "_bunfig": attr.label(
        default = Label("//bun/private:isolated_bunfig.toml"),
        allow_single_file = True,
    ),
    "_launcher": attr.label(
        default = Label("//bun/private:launcher.js"),
        allow_single_file = True,
    ),
    "_launcher_template": attr.label(
        default = Label("//bun/private:launcher.sh.tpl"),
        allow_single_file = True,
    ),
    "_windows_constraint": attr.label(
        default = Label("@platforms//os:windows"),
    ),
}

# A target platform without a Bun, or a Windows platform without a launcher stub,
# fails analysis in English (_required_toolchain) instead of aborting toolchain
# resolution. Linux and macOS targets need no hermetic-launcher toolchain.
_TOOLCHAINS = [
    config_common.toolchain_type(_TARGET_TYPE, mandatory = False),
    config_common.toolchain_type(launcher.template_toolchain_type, mandatory = False),
    config_common.toolchain_type(launcher.finalizer_toolchain_type, mandatory = False),
] + COPY_FILE_TOOLCHAINS + [_COPY_DIRECTORY_TOOLCHAIN]

bun_binary = rule(
    implementation = lambda ctx: _bun_run_impl(ctx, "binary"),
    doc = """Runs a TypeScript or JavaScript entry point with Bun.

`bazel run` runs `entry_point` as Bun's main module with the target's `args` and `env`;
`process.argv.slice(2)` is exactly the program's arguments, and the exit code, standard input,
standard output and standard error are Bun's. An argument list whose first argument is `--` fails
with an English error, because Bun 1.4.4 drops a `--` directly after the entry point. A
`$(rlocationpath …)` in `args` names the original data file, which may be read through
`RUNFILES_DIR` or `RUNFILES_MANIFEST_FILE`, but importing it fails the load guard. A data file of
another repository has no stable path relative to `import.meta.dir`, because the path contains
that repository's canonical name; pass `$(rlocationpath …)` instead.

Isolation: Bun reads only the configuration file the rule supplies (`--config=`, with
`env = false` and `install.auto = "disable"`) and gets `--no-env-file` and `--no-install`, so a
`bunfig.toml` or `.env` in the working directory takes no effect and a missing package is not
installed. The working directory is the one `bazel run` gives. The program runs with
`BUN_RUNTIME_TRANSPILER_CACHE_PATH=0`, so Bun writes no transpiler-cache entry for it.
""" + _FILES_DOC.format(main = "entry point", preload = "", code = "program"),
    executable = True,
    fragments = ["platform"],
    attrs = _COMMON_ATTRS | {
        "entry_point": attr.label(
            doc = "The file Bun runs as its main module: exactly one file with one of the extensions of `srcs`.",
            allow_files = True,
        ),
        "srcs": attr.label_list(
            doc = "Source files the entry point imports (`.ts .tsx .mts .cts .js .jsx .mjs .cjs`).",
            allow_files = SOURCE_EXTENSIONS,
        ),
    },
    toolchains = _TOOLCHAINS,
)

bun_test = rule(
    implementation = lambda ctx: _bun_run_impl(ctx, "test"),
    doc = """Runs test files with `bun test`.

Runs exactly the files in `srcs`, with the root of `<name>.bun/` as the working directory
(`process.cwd()`), not `$TEST_SRCDIR/$TEST_WORKSPACE`; that root holds no file. Each value of
`args` and `--test_arg` must be one of `--timeout=<n>`, `--rerun-each=<n>`, `--retry=<n>`,
`--concurrent`, `--randomize`, `--seed=<n>`, `--bail`, `--bail=<n>`, `--max-concurrency=<n>`,
`--todo`, `--isolate`, `--smol`, `--conditions=<value>`, `--prefer-offline` or
`--frozen-lockfile`; anything else, including short options, positional arguments and a bare
`--`, fails with an English error naming it. An accepted form is passed to `bun test` unchanged;
what it does is Bun's, and only `--timeout` and `--isolate` are covered by a test of their effect.
Under `--isolate` every file stays under the load guard.

Bazel's test protocol: `--test_filter` becomes `--test-name-pattern` (a test name may be prefixed
with its `describe` labels), and a filter that matches no test fails; `--test_filter` on a target
with `shard_count` greater than 1 fails with an English error; a shard that gets no file passes;
`XML_OUTPUT_FILE` receives Bun's JUnit report. Under `bazel coverage` the report is written to
`COVERAGE_DIR` as `bunlcov_<uuid>.dat`, each record naming the source file of a declared file.
Every file Bun reports must match exactly one declared file (its path read relative to the
working directory or as an absolute path); otherwise, for example after the test calls
`process.chdir`, the test fails with an English error naming the reported path and no coverage
file is written. Snapshot tests (`toMatchSnapshot`) are not supported.

Isolation: bun.com documents no `--config` and no `bunfig.toml` lookup for `bun test`
(https://github.com/oven-sh/bun/issues/45331), so the rule passes no configuration option to
`bun test` and offers no `bunfig.toml`; use `preload`. Whether Bun reads a `bunfig.toml` or `.env` from a parent
directory of `<name>.bun/` is not verified. Those parent directories include Bazel's
`execroot/_main`, which links every top-level entry of the main repository, so a `bunfig.toml`
or `.env` at the root of the workspace is within reach if Bun searches upward; the rules_bun
consumer test module has both, declared by no target, and checks that neither takes effect. Bun
1.4.4 does not install a missing package under `bun test`.
""" + _FILES_DOC.format(main = "test files", preload = "preloads ", code = "tests"),
    test = True,
    fragments = ["platform"],
    attrs = _COMMON_ATTRS | {
        "preload": attr.label_list(
            doc = "Files `bun test` imports before the test files, in order (`--preload`).",
            allow_files = SOURCE_EXTENSIONS,
        ),
        "_lcov_merger": attr.label(
            default = configuration_field(fragment = "coverage", name = "output_generator"),
            executable = True,
            cfg = config.exec(exec_group = "test"),
        ),
        "env_inherit": attr.string_list(
            doc = "Names of environment variables to take from the environment Bazel was invoked in; they take precedence over `env`.",
        ),
        "srcs": attr.label_list(
            doc = "The test files; every one is run and nothing else. Supporting sources come through `deps`.",
            allow_files = SOURCE_EXTENSIONS,
        ),
    },
    toolchains = _TOOLCHAINS,
)

npm_bin = rule(
    implementation = lambda ctx: _bun_run_impl(ctx, "bin"),
    doc = """Private: a `:node_modules/<package>/bin/<bin>` target: runs a `bin` file of a package as
`bun_binary` runs its entry point (research R10). The copy tree is `_npm_bin/<package>/<bin>.bun/`
in the target's package, outside any `node_modules` directory.""",
    executable = True,
    fragments = ["platform"],
    attrs = {k: v for k, v in _COMMON_ATTRS.items() if k.startswith("_")} | {
        "bin": attr.string(doc = "The `bin` entry's target name.", mandatory = True),
        "entry": attr.string(doc = "The `bin` entry's name as the package writes it, for errors.", mandatory = True),
        "package": attr.label(doc = "The package's `:node_modules/<package>` target.", mandatory = True, providers = [BunLibraryInfo]),
        "path": attr.string(doc = "The `bin` file's path in the package.", mandatory = True),
    },
    toolchains = _TOOLCHAINS,
)
