const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // generate the magics at build time
    const movegen = b.addExecutable(.{
        .name = "movegen",
        .root_source_file = b.path("src/build_movegen.zig"),
        .target = b.graph.host,
    });

    const movegen_step = b.addRunArtifact(movegen);
    const movegen_out = movegen_step.addOutputFileArg("built_movegen.zig");

    const exe = b.addExecutable(.{
        .name = "crig_n_croll",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addAnonymousImport("built_movegen", .{
        .root_source_file = movegen_out,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    // perftree executable
    const pt_exe = b.addExecutable(.{
        .name = "perftree",
        .root_source_file = b.path("src/perftree.zig"),
        .target = target,
        .optimize = optimize,
    });

    pt_exe.root_module.addAnonymousImport("built_movegen", .{
        .root_source_file = movegen_out,
    });

    b.installArtifact(pt_exe);
    const pt_cmd = b.addRunArtifact(pt_exe);
    pt_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        pt_cmd.addArgs(args);
    }

    const pt_step = b.step("perftree", "Run Perftree");
    pt_step.dependOn(&pt_cmd.step);
}
