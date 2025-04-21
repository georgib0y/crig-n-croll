const std = @import("std");

const ExeConfig = struct {
    name: []const u8,
    root_src: []const u8,
    step: []const u8,
    desc: []const u8,
};

const exes = [_]ExeConfig{
    .{
        .name = "crig_n_croll",
        .root_src = "src/main.zig",
        .step = "run",
        .desc = "Run the app",
    },
    .{
        .name = "perftree",
        .root_src = "src/perftree.zig",
        .step = "perftree",
        .desc = "Run perftree",
    },
    .{
        .name = "perft",
        .root_src = "src/perft.zig",
        .step = "perft",
        .desc = "Run perft",
    },
    .{
        .name = "strength_test",
        .root_src = "src/strength_testing.zig",
        .step = "st",
        .desc = "Run strength testing",
    },
};

fn add_runnable_exe(
    b: *std.Build,
    exe_config: ExeConfig,
    consts_out: std.Build.LazyPath,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
) void {
    const exe = b.addExecutable(.{
        .name = exe_config.name,
        .root_source_file = b.path(exe_config.root_src),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addAnonymousImport("consts", .{
        .root_source_file = consts_out,
    });

    b.installArtifact(exe);

    const cmd = b.addRunArtifact(exe);

    cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        cmd.addArgs(args);
    }

    const step = b.step(exe_config.step, exe_config.desc);
    step.dependOn(&cmd.step);
}

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
    const consts = b.addExecutable(.{
        .name = "buildtime_consts_gen",
        .root_source_file = b.path("src/buildtime_consts.zig"),
        .target = b.graph.host,
    });

    const consts_step = b.addRunArtifact(consts);
    const consts_out = consts_step.addOutputFileArg("buildtime_consts.zig");

    for (exes) |exe_config| {
        add_runnable_exe(b, exe_config, consts_out, optimize, target);
    }
}
