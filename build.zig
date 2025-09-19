const std = @import("std");

const ANDROID_TARGET_x86_64_QUERY: std.Target.Query = .{
    .cpu_arch = .x86_64,
    .abi = .android,
};

const ANDROID_TARGET_AARCH64_QUERY: std.Target.Query = .{
    .cpu_arch = .aarch64,
    .abi = .android,
};

fn build_consts(b: *std.Build) std.Build.LazyPath {
    // generate the magics at build time
    const consts = b.addExecutable(.{
        .name = "buildtime_consts_gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/buildtime_consts.zig"),
            .target = b.graph.host,
            // .optimize = b.optimize,
            .optimize = .ReleaseFast,
        }),
    });

    const consts_step = b.addRunArtifact(consts);
    return consts_step.addOutputFileArg("buildtime_consts.zig");
}

fn build_openings_builder(
    b: *std.Build,
    consts_out: std.Build.LazyPath,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
) void {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/opening_builder.zig"),
        .target = target,
        .optimize = optimize,
    });

    mod.addAnonymousImport("consts", .{
        .root_source_file = consts_out,
    });

    const exe = b.addExecutable(.{ .name = "openings", .root_module = mod });

    exe.linkLibC();
    exe.linkSystemLibrary("sqlite3");

    b.installArtifact(exe);
    const cmd = b.addRunArtifact(exe);
    cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        cmd.addArgs(args);
    }

    const step = b.step("openings", "build opening database, reading pgn notating from stdin");
    step.dependOn(&cmd.step);
}

const ExeConfig = struct {
    name: []const u8,
    root_src: []const u8,
    step: []const u8,
    desc: []const u8,
};

const exes = [_]ExeConfig{
    .{
        .name = "crig",
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
    const mod = b.createModule(.{
        .root_source_file = b.path(exe_config.root_src),
        .target = target,
        .optimize = optimize,
    });

    mod.addAnonymousImport("consts", .{
        .root_source_file = consts_out,
    });

    const exe = b.addExecutable(.{ .name = exe_config.name, .root_module = mod });
    b.installArtifact(exe);
    const cmd = b.addRunArtifact(exe);
    cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        cmd.addArgs(args);
    }

    const step = b.step(exe_config.step, exe_config.desc);
    step.dependOn(&cmd.step);
}

const LibConfig = struct {
    target: std.Build.ResolvedTarget,
    libc_file: std.Build.LazyPath,
};

fn build_app_libs(
    b: *std.Build,
    consts_out: std.Build.LazyPath,
    optimize: std.builtin.OptimizeMode,
) void {
    const ndk_sysroot = b.option([]const u8, "ndk_sysroot", "Path to NDK sysroot");
    const android_min_sdk = b.option(usize, "android_min_sdk", "Minimum target SDK for the android api");

    const libconfs = [_]LibConfig{ .{
        .target = b.resolveTargetQuery(ANDROID_TARGET_x86_64_QUERY),
        .libc_file = b.path("include/android_libc_x86_64.conf"),
    }, .{
        .target = b.resolveTargetQuery(ANDROID_TARGET_AARCH64_QUERY),
        .libc_file = b.path("include/android_libc_aarch64.conf"),
    } };

    const libapp_step = b.step("app", "Installs the android libraries");
    for (libconfs) |conf| {
        const install_step = add_app_lib(b, consts_out, optimize, ndk_sysroot, android_min_sdk, conf);
        libapp_step.dependOn(&install_step.step);
    }
}

fn add_app_lib(
    b: *std.Build,
    consts_out: std.Build.LazyPath,
    optimize: std.builtin.OptimizeMode,
    ndk_sysroot: ?[]const u8,
    min_sdk_ver: ?usize,
    conf: LibConfig,
) *std.Build.Step.InstallArtifact {
    const arch = @tagName(conf.target.result.cpu.arch);

    const libapp_root = b.createModule(.{
        .root_source_file = b.path("src/android.zig"),
        .target = conf.target,
        .optimize = optimize,
        // .single_threaded = true, ??
    });
    libapp_root.pic = true;
    libapp_root.addAnonymousImport("consts", .{ .root_source_file = consts_out });
    libapp_root.addIncludePath(b.path("include"));

    const libcrig = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "crig",
        .root_module = libapp_root,
    });
    libcrig.linkLibC();
    libcrig.setLibCFile(conf.libc_file);

    const ndk_lib_path = std.fmt.allocPrint(b.allocator, "{s}/usr/lib/{s}-linux-android/{d}/", .{
        ndk_sysroot orelse "",
        arch,
        min_sdk_ver orelse 0,
    }) catch |err| {
        std.process.fatal("could not alloc ndk lib path: {s}", .{@errorName(err)});
    };

    libcrig.addLibraryPath(.{ .cwd_relative = ndk_lib_path });
    libcrig.linkSystemLibrary2("log", .{ .needed = true });

    libcrig.addRPath(.{ .cwd_relative = "/system/lib64/" });

    const subpath = std.fmt.allocPrint(b.allocator, "{s}/libcrig.so", .{arch}) catch |err| {
        std.process.fatal("could not alloc subpath: {s}", .{@errorName(err)});
    };

    return b.addInstallArtifact(libcrig, .{ .dest_sub_path = subpath });
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

    const consts_out = build_consts(b);

    build_openings_builder(b, consts_out, optimize, target);

    for (exes) |exe_config| {
        add_runnable_exe(b, exe_config, consts_out, optimize, target);
    }

    build_app_libs(b, consts_out, optimize);
}
